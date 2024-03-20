// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IWETH9} from "../periphery/interfaces/IWETH9.sol";
import {BorrowToken} from "../tokens/BorrowToken.sol";

import {CommonErrors} from "../interfaces/CommonErrors.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IVaultFactory} from "../interfaces/IVaultFactory.sol";

import {Constants} from "../libraries/Constants.sol";
import {FeeMath} from "../libraries/FeeMath.sol";
import {InterestAccrualMath, InterestAccruingAmount} from "../libraries/InterestAccrualMath.sol";

/**
 * @title Stack Vault Contract
 * @notice A multifunctional vault contract for collateral management, borrowing, and flash loan operations.
 * @dev Integrates functionalities for:
 *      - Collateral deposits and withdrawals.
 *      - Borrowing against collateral with interest accrual.
 *      - Leveraged operations and liquidations.
 *      Inherits from various OpenZeppelin contracts for upgradeability, ownership management, and reentrancy
 *      protection.
 *      Uses ERC-7201 namespaced storage pattern for robust and collision-resistant storage structure.
 *      Emits various events for tracking operations like deposits, withdrawals, borrowing, etc.
 * @author SeaZarrgh LaBuoy
 */
contract StackVault is
    CommonErrors,
    IERC3156FlashBorrower,
    MulticallUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using Address for address;
    using InterestAccrualMath for InterestAccruingAmount;
    using FeeMath for uint256;
    using Math for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for BorrowToken;

    uint256 public constant DEFAULT_BORROW_OPENING_FEE = 0.005e18;
    uint256 public constant DEFAULT_LIQUIDATION_PENALTY_FEE = 0.03e18;
    uint256 public constant DEFAULT_FLASHLOAN_FEE = 0.005e18;

    struct AccrualInfo {
        uint128 lastAccrualBlock;
        uint128 lastAccrualTimestamp;
        uint256 feesEarned;
    }

    event CollateralDeposited(address indexed from, address indexed to, uint256 amount, uint256 share);
    event CollateralWithdrawn(address indexed from, address indexed to, uint256 amount, uint256 share);
    event Borrowed(address indexed borrower, address indexed to, uint256 amount, uint256 share);
    event Repaid(address indexed borrower, address indexed to, uint256 amount, uint256 share);
    event Leveraged(address indexed borrower, uint256 depositamount, uint256 borrowAmount);
    event Deleveraged(address indexed borrower, uint256 withdrawalAmount, uint256 repayAmount);
    event Liquidated(
        address indexed liquidator,
        address indexed borrower,
        uint256 collateralSeized,
        uint256 penaltyFee,
        uint256 borrowAmountReducedBy
    );
    event BorrowInterestRateUpdated(uint256 oldRate, uint256 newRate);
    event BorrowLimitUpdated(uint256 oldBorrowLimit, uint256 newBorrowLimit);
    event InterestAccrued(uint256 amount);
    event Swap(address indexed initiator, address indexed swapTarget, bytes swapData, bytes swapResult);
    event VaultRetired();
    event VaultRevived();

    event CollateralTokenOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event BorrowOpeningFeeUpdated(uint256 oldFee, uint256 newFee);
    event LiquidationPenaltyFeeUpdated(uint256 oldFee, uint256 newFee);
    event LiquidationThresholdUpdated(uint8 oldThreshold, uint8 newThreshold);
    event InterestRateMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier);

    error BorrowLimitExceeded(uint256 totalAmountBorrowed, uint256 borrowLimit);
    error InvalidLiquidationThreshold(uint8 min, uint8 max, uint8 actual);
    error LeverageFlashloanFailed();
    error LiquidationFailed(address liquidator, address account);
    error RebaseDetected();
    error Unhealthy();
    error UntrustedSwapTarget(address target);

    /// @custom:storage-location erc7201:pearl.storage.StackVault
    struct StackVaultStorage {
        bool isRetired;
        address borrowTokenOracle;
        address collateralTokenOracle;
        uint256 borrowLimit;
        uint256 liquidationThreshold;
        uint256 liquidationPenaltyFee;
        uint256 borrowOpeningFee;
        uint256 interestRateMultiplier;
        InterestAccruingAmount totalBorrowAmount;
        InterestAccruingAmount totalCollateralAmount;
        AccrualInfo accrualInfo;
        mapping(address => uint256) userCollateralShare;
        mapping(address => uint256) userBorrowShare;
        mapping(address => uint256) userBorrowAmount;
    }

    // keccak256(abi.encode(uint256(keccak256("pearl.storage.StackVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant StackVaultStorageLocation =
        0x9019847cfee11e1d0d9d3e939b66f1e818d096cb391b50c50eaa48e2c99e9800;

    function _getStackVaultStorage() private pure returns (StackVaultStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := StackVaultStorageLocation
        }
    }

    bool private immutable _isNativeCollateralToken;
    IVaultFactory private immutable _factory;
    IWETH9 private immutable _WETH;
    BorrowToken public immutable borrowToken;
    IERC20 public immutable collateralToken;

    /**
     * @notice Ensures that the operation leaves the user's position in a healthy state.
     * @dev Modifier to check the health of a user's position after an operation.
     *      Reverts if the operation would make the user's position unhealthy.
     */
    modifier healthcheck() {
        _;
        _healthcheck(msg.sender);
    }

    modifier onlyFactory() {
        StackVaultStorage storage $ = _getStackVaultStorage();
        if (msg.sender != address(_factory)) {
            revert UnauthorizedCaller();
        }
        _;
    }

    modifier readOnlyNonReentrant() {
        if (_reentrancyGuardEntered()) {
            revert ReentrancyGuardReentrantCall();
        }
        _;
    }

    modifier noRebase() {
        uint256 _totalSupply = collateralToken.totalSupply();
        _;
        if (_totalSupply < collateralToken.totalSupply()) {
            revert RebaseDetected();
        }
    }

    receive() external payable {
        require(msg.sender == address(_WETH), "StackVault: cannot receive ETH");
    }

    /**
     * @notice Initializes the StackVault contract.
     * @dev Sets the borrow and collateral token addresses and disables initializers to prevent reinitialization after
     *      an upgrade.
     * @param factory The address of the vault factory.
     * @param _borrowToken The address of the borrow token.
     * @param _collateralToken The address of the collateral token.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address factory, address _borrowToken, address _collateralToken) {
        _disableInitializers();
        address weth = IVaultFactory(factory).WETH();
        _isNativeCollateralToken = _collateralToken == Constants.ETH_ADDRESS || _collateralToken == weth;
        _factory = IVaultFactory(factory);
        _WETH = IWETH9(weth);
        borrowToken = BorrowToken(_borrowToken);
        collateralToken = IERC20(_isNativeCollateralToken ? weth : _collateralToken);
    }

    /**
     * @notice Initializes the StackVault with necessary parameters.
     * @dev Sets up the vault with factory, collateral token oracle, liquidation threshold, and interest rate
     *      multiplier.
     *      Initializes multicall and reentrancy guard functionalities.
     *      Can only be called once due to the `initializer` modifier.
     * @param _owner The address of the initial owner of the vault.
     * @param _collateralTokenOracle The address of the oracle for the collateral token.
     * @param _liquidationThreshold The liquidation threshold value.
     * @param _interestRateMultiplier The interest rate multiplier.
     */
    function initialize(
        address _owner,
        address _collateralTokenOracle,
        uint8 _liquidationThreshold,
        uint256 _interestRateMultiplier
    ) external initializer {
        __Multicall_init();
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        StackVaultStorage storage $ = _getStackVaultStorage();
        _updateLiquidationThreshold($, 0, _liquidationThreshold);
        _updateCollateralTokenOracle($, address(0), _collateralTokenOracle);
        _updateBorrowOpeningFee($, 0, DEFAULT_BORROW_OPENING_FEE);
        _updateLiquidationPenaltyFee($, 0, DEFAULT_LIQUIDATION_PENALTY_FEE);
        _updateInterestRateMultiplier($, 0, _interestRateMultiplier);
    }

    /**
     * @dev Internal function to update the liquidation threshold in the StackVaultStorage.
     * Validates the new threshold against system constraints, updates the storage, and emits a
     * `LiquidationThresholdUpdated` event. This function is expected to be called by public or external setter
     * functions that perform additional checks and access control.
     * @param $ The reference to the StackVaultStorage structure.
     * @param oldThreshold The previous liquidation threshold.
     * @param newThreshold The new liquidation threshold to be set.
     */
    function _updateLiquidationThreshold(StackVaultStorage storage $, uint8 oldThreshold, uint8 newThreshold)
        internal
    {
        uint8 minLiquidationThreshold = SafeCast.toUint8(Constants.LTV_PRECISION / 100); // 1%
        if (newThreshold < minLiquidationThreshold || newThreshold > Constants.LTV_PRECISION) {
            revert InvalidLiquidationThreshold(1, SafeCast.toUint8(Constants.LTV_PRECISION), newThreshold);
        }
        $.liquidationThreshold = newThreshold;
        emit LiquidationThresholdUpdated(oldThreshold, newThreshold);
    }

    /**
     * @notice Authorizes an upgrade to a new contract implementation.
     * @dev Internal function to authorize upgrading the contract to a new implementation.
     *      Overrides the UUPSUpgradeable `_authorizeUpgrade` function.
     *      Restricted to the contract owner.
     * @param newImplementation The address of the new contract implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Sets the oracle address for the borrow token. This overrides the default oracle set in the factory. If
     * the new oracle is set to the zero address, the default oracle is used.
     * @dev Updates the oracle used for pricing the borrow token. Only callable by the factory.
     * @param newOracle The new oracle address for the borrow token.
     */
    function setBorrowTokenOracle(address newOracle) public onlyFactory {
        StackVaultStorage storage $ = _getStackVaultStorage();
        address oldOracle = $.borrowTokenOracle;
        if (oldOracle == newOracle) {
            revert ValueUnchanged();
        }
        $.borrowTokenOracle = newOracle;
        emit CollateralTokenOracleUpdated(oldOracle, newOracle);
    }

    /**
     * @notice Sets the oracle address for the collateral token.
     * @dev Updates the oracle used for pricing the collateral token. Only callable by the factory.
     * @param newOracle The new oracle address for the collateral token.
     */
    function setCollateralTokenOracle(address newOracle) public onlyFactory {
        StackVaultStorage storage $ = _getStackVaultStorage();
        address oldOracle = $.collateralTokenOracle;
        if (oldOracle == newOracle) {
            revert ValueUnchanged();
        }
        _updateCollateralTokenOracle($, oldOracle, newOracle);
    }

    /**
     * @dev Internal function to update the collateral token oracle address in StackVaultStorage.
     * Validates the new oracle address, updates the storage, and emits a `CollateralTokenOracleUpdated` event. This
     * function is designed to be called by higher-level functions that include authorization checks and ensure the new
     * address's validity.
     * @param $ The reference to the StackVaultStorage structure.
     * @param oldOracle The address of the previous collateral token oracle.
     * @param newOracle The address of the new collateral token oracle.
     */
    function _updateCollateralTokenOracle(StackVaultStorage storage $, address oldOracle, address newOracle) internal {
        if (newOracle == address(0)) {
            revert InvalidZeroAddress();
        }
        $.collateralTokenOracle = newOracle;
        emit CollateralTokenOracleUpdated(oldOracle, newOracle);
    }

    /**
     * @notice Sets the fee percentage for opening a borrow position.
     * @dev Updates the borrow opening fee. Only callable by the factory.
     * @param _borrowOpeningFee The new borrow opening fee as a percentage.
     */
    function setBorrowOpeningFee(uint256 _borrowOpeningFee) public onlyFactory {
        StackVaultStorage storage $ = _getStackVaultStorage();
        uint256 oldFee = $.borrowOpeningFee;
        if (oldFee == _borrowOpeningFee) {
            revert ValueUnchanged();
        }
        _updateBorrowOpeningFee($, oldFee, _borrowOpeningFee);
    }

    /**
     * @dev Internal function to update the borrow opening fee in StackVaultStorage.
     * Checks that the new fee is within system limits, updates the storage, and emits a `BorrowOpeningFeeUpdated`
     * event. It is intended for use by functions like `setBorrowOpeningFee`, which manage access control and validation
     * of the new fee.
     * @param $ The reference to the StackVaultStorage structure.
     * @param oldFee The previous borrow opening fee.
     * @param newFee The new borrow opening fee to be set.
     */
    function _updateBorrowOpeningFee(StackVaultStorage storage $, uint256 oldFee, uint256 newFee) internal {
        if (newFee > Constants.FEE_PRECISION) {
            revert InvalidFee(0, Constants.FEE_PRECISION, newFee);
        }
        $.borrowOpeningFee = newFee;
        emit BorrowOpeningFeeUpdated(oldFee, newFee);
    }

    /**
     * @notice Sets the liquidation penalty fee.
     * @dev Updates the fee charged when a position is liquidated. Only callable by the factory.
     * @param _liquidationPenaltyFee The new liquidation penalty fee as a percentage.
     */
    function setLiquidationPenaltyFee(uint256 _liquidationPenaltyFee) public onlyFactory {
        StackVaultStorage storage $ = _getStackVaultStorage();
        uint256 oldFee = $.liquidationPenaltyFee;
        if (oldFee == _liquidationPenaltyFee) {
            revert ValueUnchanged();
        }
        _updateLiquidationPenaltyFee($, oldFee, _liquidationPenaltyFee);
    }

    /**
     * @dev Internal function to update the liquidation penalty fee in StackVaultStorage.
     * Validates the new fee against the system's constraints, updates the storage, and emits a
     * `LiquidationPenaltyFeeUpdated` event. This function is expected to be invoked by external or public functions
     * with appropriate authorization and validation checks.
     * @param $ The reference to the StackVaultStorage structure.
     * @param oldFee The previous liquidation penalty fee.
     * @param newFee The new liquidation penalty fee to be updated.
     */
    function _updateLiquidationPenaltyFee(StackVaultStorage storage $, uint256 oldFee, uint256 newFee) internal {
        if (newFee > Constants.FEE_PRECISION) {
            revert InvalidFee(0, Constants.FEE_PRECISION, newFee);
        }
        $.liquidationPenaltyFee = newFee;
        emit LiquidationPenaltyFeeUpdated(oldFee, newFee);
    }

    /**
     * @notice Sets the interest rate multiplier for borrow rates.
     * @dev Updates the multiplier affecting the interest rate on borrows. Only callable by the factory.
     *      Accrues interest before updating the multiplier.
     * @param _interestRateMultiplier The new interest rate multiplier.
     */
    function setInterestRateMultiplier(uint256 _interestRateMultiplier) public onlyFactory {
        accrueInterest();
        StackVaultStorage storage $ = _getStackVaultStorage();
        uint256 oldMultiplier = $.interestRateMultiplier;
        _updateInterestRateMultiplier($, oldMultiplier, _interestRateMultiplier);
    }

    /**
     * @dev Internal function to update the interest rate multiplier in StackVaultStorage.
     * Checks the new multiplier for validity, updates the storage, and emits an `InterestRateMultiplierUpdated` event.
     * Aimed to be used by setter functions like `setInterestRateMultiplier` that perform necessary checks and
     * authorization.
     * @param $ The reference to the StackVaultStorage structure.
     * @param oldMultiplier The previous interest rate multiplier.
     * @param newMultiplier The new interest rate multiplier to be set.
     */
    function _updateInterestRateMultiplier(StackVaultStorage storage $, uint256 oldMultiplier, uint256 newMultiplier)
        internal
    {
        $.interestRateMultiplier = newMultiplier;
        emit InterestRateMultiplierUpdated(oldMultiplier, newMultiplier);
    }

    /**
     * @notice Retires the vault, disabling new borrows.
     * @dev Marks the vault as retired. Only callable by the factory.
     */
    function retire() external onlyFactory {
        StackVaultStorage storage $ = _getStackVaultStorage();
        if ($.isRetired) {
            revert ValueUnchanged();
        }
        $.isRetired = true;
        emit VaultRetired();
    }

    /**
     * @notice Revives the vault, enabling new borrows.
     * @dev Marks the vault as active. Only callable by the factory.
     */
    function revive() external onlyFactory {
        StackVaultStorage storage $ = _getStackVaultStorage();
        if (!$.isRetired) {
            revert ValueUnchanged();
        }
        $.isRetired = false;
        emit VaultRevived();
    }

    /**
     * @notice Calculates the current interest rate per second.
     * @dev Returns the interest rate based on the vault factory's rate and the interest rate multiplier.
     * @return rate The current interest rate per second.
     */
    function interestRatePerSecond() public view returns (uint256 rate) {
        StackVaultStorage storage $ = _getStackVaultStorage();
        rate = _factory.borrowInterestRate() * $.interestRateMultiplier
            / (Constants.INTEREST_RATE_MULTIPLIER_PRECISION * 365 days);
    }

    /**
     * @notice Retrieves the interest rate multiplier for borrow rates.
     * @dev returns the multiplier affecting the interest rate on borrows.
     * @return multiplier The current interest rate multiplier.
     */
    function interestRateMultiplier() external view returns (uint256 multiplier) {
        return _getStackVaultStorage().interestRateMultiplier;
    }

    /**
     * @notice Increases the vault's borrow limit.
     * @dev Increases the maximum amount that can be borrowed from the vault. Only callable by the factory.
     * @param delta The amount by which to increase the borrow limit.
     */
    function increaseBorrowLimit(uint256 delta) external onlyFactory {
        StackVaultStorage storage $ = _getStackVaultStorage();
        uint256 currentBorrowLimit = $.borrowLimit;
        uint256 newBorrowLimit = currentBorrowLimit + delta;
        $.borrowLimit = newBorrowLimit;
        emit BorrowLimitUpdated(currentBorrowLimit, newBorrowLimit);
        borrowToken.safeTransferFrom(msg.sender, address(this), delta);
    }

    /**
     * @notice Decreases the vault's borrow limit.
     * @dev Decreases the maximum amount that can be borrowed from the vault. Only callable by the factory.
     *      Burns the excess borrow tokens if the current balance exceeds the new limit.
     * @param delta The amount by which to decrease the borrow limit.
     */
    function decreaseBorrowLimit(uint256 delta) external onlyFactory {
        StackVaultStorage storage $ = _getStackVaultStorage();
        uint256 currentBorrowLimit = $.borrowLimit;
        uint256 newBorrowLimit = currentBorrowLimit - delta;
        $.borrowLimit = newBorrowLimit;
        emit BorrowLimitUpdated(currentBorrowLimit, newBorrowLimit);
        borrowToken.burn(delta);
    }

    /**
     * @notice Accrues interest on borrowed amounts.
     * @dev Updates the total borrow amount with accrued interest. Should be called periodically to keep interest
     *      calculations up-to-date.
     */
    function accrueInterest() public {
        StackVaultStorage storage $ = _getStackVaultStorage();
        AccrualInfo memory accrual = $.accrualInfo;
        uint256 elapsedTime = block.timestamp - accrual.lastAccrualTimestamp;
        if (block.number == accrual.lastAccrualBlock) {
            return;
        }
        accrual.lastAccrualBlock = block.number.toUint128();
        accrual.lastAccrualTimestamp = block.timestamp.toUint128();

        InterestAccruingAmount memory totalBorrow = $.totalBorrowAmount;

        if (totalBorrow.base != 0) {
            uint256 interestPerElapsedTime = interestRatePerSecond() * elapsedTime;
            uint256 accruedAmount = totalBorrow.total.mulDiv(interestPerElapsedTime, 1e18);
            totalBorrow.total += accruedAmount;

            accrual.feesEarned += accruedAmount;
            $.totalBorrowAmount = totalBorrow;

            emit InterestAccrued(accruedAmount);

            uint256 burnAmount;

            if ($.isRetired) {
                uint256 _borrowLimit = $.borrowLimit;
                if (totalBorrow.total < _borrowLimit) {
                    unchecked {
                        burnAmount = _borrowLimit - totalBorrow.total;
                    }
                    $.borrowLimit = totalBorrow.total;
                    emit BorrowLimitUpdated(_borrowLimit, totalBorrow.total);
                }
            }

            _factory.notifyAccruedInterest(accruedAmount);

            if (burnAmount != 0) {
                borrowToken.burn(burnAmount);
            }
        }

        $.totalCollateralAmount.total = collateralToken.balanceOf(address(this));
        $.accrualInfo = accrual;
    }

    /// DEPOSITS

    /**
     * @notice Deposits collateral into the vault.
     * @dev Transfers the specified amount of collateral from the depositor to the vault.
     *      Updates the user's collateral share and the total collateral amount in the vault.
     *      Emits a `CollateralDeposited` event upon successful deposit.
     * @param to The address to credit with the deposit share.
     * @param amount The amount of collateral to deposit.
     * @return share The amount of share credited to the depositor.
     */
    function depositCollateral(address to, uint256 amount) external payable nonReentrant returns (uint256 share) {
        accrueInterest();
        amount = _transferCollateralIn(msg.sender, amount);
        share = _addAmountToCollateral(to, amount);
        emit CollateralDeposited(msg.sender, to, amount, share);
    }

    /// WITHDRAWALS

    /**
     * @notice Withdraws a specified amount of collateral from the vault.
     * @dev Subtracts the specified amount of collateral from the user's balance and transfers it.
     *      Performs a health check to ensure the vault remains healthy after withdrawal.
     *      Emits a `CollateralWithdrawn` event upon successful withdrawal.
     * @param to The address to receive the withdrawn collateral.
     * @param amount The amount of collateral to withdraw.
     * @return share The amount of share subtracted from the user's balance.
     */
    function withdrawCollateral(address to, uint256 amount) external healthcheck nonReentrant returns (uint256 share) {
        accrueInterest();
        share = _subtractAmountFromCollateral(msg.sender, amount);
        amount = _transferCollateralOut(to, amount);
        emit CollateralWithdrawn(msg.sender, to, amount, share);
    }

    /**
     * @notice Withdraws the entire collateral balance of the caller from the vault.
     * @dev Subtracts the total collateral share of the caller and transfers the corresponding amount.
     *      Performs a health check to ensure the vault remains healthy after withdrawal.
     *      Emits a `CollateralWithdrawn` event upon successful withdrawal.
     * @param to The address to receive the withdrawn collateral.
     * @return amount The total amount of collateral withdrawn.
     */
    function withdrawCollateral(address to) external healthcheck nonReentrant returns (uint256 amount) {
        accrueInterest();

        StackVaultStorage storage $ = _getStackVaultStorage();
        uint256 share = $.userCollateralShare[msg.sender];

        amount = _subtractShareFromCollateral(msg.sender, share);
        amount = _transferCollateralOut(to, amount);

        emit CollateralWithdrawn(msg.sender, to, amount, share);
    }

    /// BORROWING

    /**
     * @notice Allows a user to borrow against their collateral.
     * @dev Adds the specified borrow amount to the user's debt and transfers the borrowed tokens.
     *      Performs a health check to ensure the user's position remains healthy after borrowing.
     *      Emits a `Borrowed` event upon successful borrowing.
     * @param to The address to receive the borrowed tokens.
     * @param amount The amount of tokens to borrow.
     * @return share The amount of share added to the user's debt.
     */
    function borrow(address to, uint256 amount) external healthcheck nonReentrant returns (uint256 share) {
        accrueInterest();
        share = _addAmountToDebt(msg.sender, amount);
        borrowToken.safeTransfer(to, amount);
        emit Borrowed(msg.sender, to, amount, share);
    }

    /// REPAYMENTS

    /**
     * @notice Repays a specified amount of borrowed tokens.
     * @dev Subtracts the specified amount from the user's debt and transfers the tokens from the borrower to the vault.
     *      Burns any excess borrow tokens to match the vault's borrow limit.
     *      Emits a `Repaid` event upon successful repayment.
     * @param to The address whose debt is being repaid.
     * @param amount The amount of tokens to repay.
     * @return share The amount of share subtracted from the user's debt.
     */
    function repay(address to, uint256 amount) external nonReentrant returns (uint256 share) {
        accrueInterest();
        borrowToken.safeTransferFrom(msg.sender, address(this), amount);
        share = _subtractAmountFromDebt(to, amount);
        _burnExcessBorrowTokens();
        emit Repaid(msg.sender, to, amount, share);
    }

    /**
     * @notice Repays the entire borrowed amount of a user.
     * @dev Subtracts the total debt share of the specified user and transfers the corresponding amount of tokens.
     *      Burns any excess borrow tokens to match the vault's borrow limit.
     *      Emits a `Repaid` event upon successful repayment.
     * @param to The address whose entire debt is being repaid.
     * @return amount The total amount of tokens repaid.
     */
    function repay(address to) external nonReentrant returns (uint256 amount) {
        accrueInterest();

        StackVaultStorage storage $ = _getStackVaultStorage();
        uint256 share = $.userBorrowShare[to];

        amount = _subtractShareFromDebt(to, share);
        borrowToken.safeTransferFrom(msg.sender, address(this), amount);
        _burnExcessBorrowTokens();

        emit Repaid(msg.sender, to, amount, share);
    }

    // LEVERAGE

    /**
     * @notice Performs a leveraged operation by depositing collateral and borrowing simultaneously.
     * @dev Deposits collateral, borrows against it, and performs a swap using the borrowed amount.
     *      The swap is intended to convert the borrowed tokens back into collateral.
     *      Emits a `Leveraged` event upon successful leveraging.
     * @param depositAmount The amount of collateral to deposit.
     * @param borrowAmount The amount of tokens to borrow.
     * @param swapTarget The address of the swap target contract.
     * @param swapData The calldata for the swap operation.
     */
    function leverage(uint256 depositAmount, uint256 borrowAmount, address swapTarget, bytes memory swapData)
        external
        payable
        healthcheck
        nonReentrant
        noRebase
    {
        accrueInterest();

        // transfer user-provided collateral and deposit total collateral
        depositAmount = _transferCollateralIn(msg.sender, depositAmount);

        // flash-mint borrow token and finalize leverage in callback function
        bytes memory data = abi.encode(msg.sender, depositAmount, swapTarget, swapData);
        if (!borrowToken.flashLoan(this, address(borrowToken), borrowAmount, data)) {
            revert LeverageFlashloanFailed();
        }

        emit Leveraged(msg.sender, depositAmount, borrowAmount);
    }

    /**
     * @notice Reduces leverage by withdrawing collateral and repaying part of the borrowed amount.
     * @dev Withdraws collateral and uses it to repay the borrow. The withdrawn collateral is swapped for the borrow
     *      token.
     *      Emits a `Deleveraged` event upon successful deleveraging.
     * @param withdrawalAmount The amount of collateral to withdraw and use for repayment.
     * @param swapTarget The address of the swap target contract.
     * @param swapData The calldata for the swap operation.
     */
    function deleverage(uint256 withdrawalAmount, address swapTarget, bytes memory swapData)
        external
        healthcheck
        nonReentrant
        noRebase
    {
        accrueInterest();

        _checkSwapTarget(swapTarget);

        address account = msg.sender;

        _subtractAmountFromCollateral(account, withdrawalAmount);

        (uint256 swapAmountIn, uint256 swapAmountOut) =
            _safeSwap(collateralToken, borrowToken, withdrawalAmount, swapTarget, swapData);

        _subtractAmountFromDebt(account, swapAmountOut);

        if (swapAmountIn < withdrawalAmount) {
            unchecked {
                _addAmountToCollateral(account, withdrawalAmount - swapAmountIn);
            }
            collateralToken.forceApprove(swapTarget, 0);
        }

        emit Deleveraged(account, withdrawalAmount, swapAmountOut);
    }

    /**
     * @notice Handles the receipt of a flash loan.
     * @dev Implements the IERC3156FlashBorrower interface. It is called by the flash loan provider and is expected to
     *      repay the loan by the end of the transaction.
     *      This function is used primarily in the `leverage` operation to swap the borrowed tokens for additional
     *      collateral.
     * @param initiator The initiator of the loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param fee The additional amount of tokens to repay.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     * @return The keccak256 hash of "ERC3156FlashBorrower.onFlashLoan".
     */
    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        returns (bytes32)
    {
        if (msg.sender != address(borrowToken) || initiator != address(this)) {
            revert UnauthorizedCaller();
        }

        assert(token == address(borrowToken));

        {
            // swap borrow token for collateral token
            uint256 depositAmount;
            address swapTarget;
            bytes memory swapData;

            (initiator, depositAmount, swapTarget, swapData) = abi.decode(data, (address, uint256, address, bytes));

            (uint256 swapAmountIn, uint256 swapAmountOut) =
                _safeSwap(borrowToken, collateralToken, amount, swapTarget, swapData);

            depositAmount += swapAmountOut;
            uint256 share = _addAmountToCollateral(initiator, depositAmount);
            emit CollateralDeposited(initiator, initiator, depositAmount, share);

            // borrow against collateral to repay flashloan
            swapAmountIn += fee;
            share = _addAmountToDebt(initiator, swapAmountIn);
            emit Borrowed(initiator, initiator, swapAmountIn, share);
        }

        // repay flashloan
        borrowToken.forceApprove(address(borrowToken), amount + fee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /// LIQUIDATIONS

    /**
     * @notice Liquidates an unhealthy account by repaying part of its debt and seizing collateral.
     * @dev Repays part of the borrower's debt and seizes a portion of their collateral.
     *      A penalty fee is applied to the seized collateral, part of which is paid to the liquidator.
     *      Emits a `Liquidated` event upon successful liquidation.
     * @param account The address of the borrower to be liquidated.
     * @param repayAmount The amount of debt to be repaid as part of the liquidation.
     * @param to The address receiving the liquidation reward.
     */
    function liquidate(address account, uint256 repayAmount, address to) external nonReentrant {
        accrueInterest();

        StackVaultStorage storage $ = _getStackVaultStorage();

        uint256 collateralAmount;
        uint256 collateralValue;
        uint256 borrowValue;

        {
            uint256 borrowAmount;

            (collateralAmount, collateralValue, borrowAmount, borrowValue) = _userPositionInfo(account);

            if (repayAmount > borrowAmount) {
                repayAmount = borrowAmount;
            }

            if (_isHealthy(collateralValue, borrowValue)) {
                revert LiquidationFailed(msg.sender, account);
            }
        }

        borrowToken.safeTransferFrom(msg.sender, address(this), repayAmount);

        address _borrowTokenOracle = borrowTokenOracle();
        address _collateralTokenOracle = $.collateralTokenOracle;

        uint256 repaidCollateralAmount =
            _convertTokenAmount(repayAmount, _borrowTokenOracle, _collateralTokenOracle, Math.Rounding.Floor);
        uint256 penaltyFeeAmount = _convertTokenAmount(
            repayAmount.calculateFeeAmount($.liquidationPenaltyFee),
            _borrowTokenOracle,
            _collateralTokenOracle,
            Math.Rounding.Floor
        );
        uint256 totalCollateralRemoved = repaidCollateralAmount + penaltyFeeAmount;

        if (totalCollateralRemoved > collateralAmount) {
            totalCollateralRemoved = collateralAmount;
            unchecked {
                penaltyFeeAmount = totalCollateralRemoved - repaidCollateralAmount;
            }
        }

        _subtractAmountFromDebt(account, repayAmount);
        _subtractAmountFromCollateral(account, totalCollateralRemoved);

        uint256 liquidationBonus = penaltyFeeAmount / 2;
        uint256 collectedFee = penaltyFeeAmount - liquidationBonus;

        collateralToken.forceApprove(address(_factory), collectedFee);
        _factory.collectFees(address(collateralToken), collectedFee);

        _transferCollateralOut(to, totalCollateralRemoved - collectedFee);

        emit Liquidated(msg.sender, account, totalCollateralRemoved, penaltyFeeAmount, repayAmount);
    }

    /**
     * @notice Checks if the vault is retired.
     * @dev Returns true if the vault has been retired, indicating that no new deposits or borrows are allowed.
     * @return _retired Boolean indicating whether the vault is retired.
     */
    function isRetired() external view returns (bool _retired) {
        _retired = _getStackVaultStorage().isRetired;
    }

    /**
     * @notice Gets the address of the borrow token oracle.
     * @dev Returns the oracle address used for obtaining the price of the borrow token.
     * @return _borrowTokenOracle The address of the borrow token oracle.
     */
    function borrowTokenOracle() public view returns (address _borrowTokenOracle) {
        _borrowTokenOracle = _getStackVaultStorage().borrowTokenOracle;
        if (_borrowTokenOracle == address(0)) {
            _borrowTokenOracle = _factory.borrowTokenOracle();
        }
    }

    /**
     * @notice Gets the address of the collateral token oracle.
     * @dev Returns the oracle address used for obtaining the price of the collateral token.
     * @return _collateralTokenOracle The address of the collateral token oracle.
     */
    function collateralTokenOracle() external view returns (address _collateralTokenOracle) {
        _collateralTokenOracle = _getStackVaultStorage().collateralTokenOracle;
    }

    /**
     * @notice Retrieves the current borrow limit of the vault.
     * @dev Returns the maximum amount of tokens that can be borrowed from the vault.
     * @return _borrowLimit The current borrow limit in tokens.
     */
    function borrowLimit() external view readOnlyNonReentrant returns (uint256 _borrowLimit) {
        _borrowLimit = _getStackVaultStorage().borrowLimit;
    }

    /**
     * @notice Gets the liquidation threshold for the vault.
     * @dev Returns the threshold value that determines when a position becomes subject to liquidation.
     * @return _threshold The liquidation threshold as a percentage.
     */
    function liquidationThreshold() external view returns (uint256 _threshold) {
        _threshold = _getStackVaultStorage().liquidationThreshold;
    }

    /**
     * @notice Retrieves the liquidation penalty fee of the vault.
     * @dev Returns the fee percentage charged on liquidated collateral.
     * @return _fee The liquidation penalty fee as a percentage.
     */
    function liquidationPenaltyFee() external view returns (uint256 _fee) {
        _fee = _getStackVaultStorage().liquidationPenaltyFee;
    }

    /**
     * @notice Gets the borrow opening fee of the vault.
     * @dev Returns the fee charged when a new borrow position is opened.
     * @return _fee The borrow opening fee as a percentage.
     */
    function borrowOpeningFee() external view returns (uint256 _fee) {
        _fee = _getStackVaultStorage().borrowOpeningFee;
    }

    /**
     * @notice Retrieves the total amount of tokens borrowed from the vault.
     * @dev Returns the sum of all outstanding borrows in the vault.
     *      Note: Since this is a view function, the returned value could be stale.
     * @return _totalBorrowAmount The total amount of borrowed tokens.
     */
    function totalBorrowAmount() external view readOnlyNonReentrant returns (uint256 _totalBorrowAmount) {
        // NOTE: Since we can't call `accrueInterest()` in a view function, the return value of this function must be
        // considered stale. Clients should use a static multicall, `accrueInterest()` followed by
        // `totalBorrowAmount()`.
        _totalBorrowAmount = _getStackVaultStorage().totalBorrowAmount.total;
    }

    /**
     * @notice Retrieves the total amount of collateral deposited in the vault.
     * @dev Returns the sum of all collateral currently held in the vault.
     *      Note: Since this is a view function, the returned value could be stale.
     * @return _totalCollateralAmount The total amount of collateral in the vault.
     */
    function totalCollateralAmount() external view readOnlyNonReentrant returns (uint256 _totalCollateralAmount) {
        // NOTE: Since we can't call `accrueInterest()` in a view function, the return value of this function must be
        // considered stale. Clients should use a static multicall, `accrueInterest()` followed by
        // `totalCollateralAmount()`.
        _totalCollateralAmount = _getStackVaultStorage().totalCollateralAmount.total;
    }

    /**
     * @notice Gets the borrow share of a specific user.
     * @dev Returns the share of the total borrow amount that a specific user is responsible for.
     * @param account The address of the user.
     * @return share The user's borrow share.
     */
    function userBorrowShare(address account) external view readOnlyNonReentrant returns (uint256 share) {
        share = _getStackVaultStorage().userBorrowShare[account];
    }

    /**
     * @notice Gets the collateral share of a specific user.
     * @dev Returns the share of the total collateral amount that a specific user has deposited.
     * @param account The address of the user.
     * @return share The user's collateral share.
     */
    function userCollateralShare(address account) external view readOnlyNonReentrant returns (uint256 share) {
        share = _getStackVaultStorage().userCollateralShare[account];
    }

    /**
     * @notice Provides detailed information about a user's position in the vault.
     * @dev Returns the amounts and values of the user's collateral and borrow. This function has a
     * `readOnlyNonReentrant` modifier attached to prevent reentrancy attacks even in read-only operations, ensuring
     * that the function is not called in the middle of another state-changing operation.
     * @param account The address of the user.
     * @return collateralAmount The amount of collateral deposited by the user.
     * @return collateralValue The value of the user's collateral.
     * @return borrowAmount The amount of tokens borrowed by the user.
     * @return borrowValue The value of the user's borrow.
     */
    function userPositionInfo(address account)
        external
        view
        readOnlyNonReentrant
        returns (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue)
    {
        (collateralAmount, collateralValue, borrowAmount, borrowValue) = _userPositionInfo(account);
    }

    /**
     * @notice Provides detailed information about a user's position in the vault.
     * @dev Returns the amounts and values of the user's collateral and borrow.
     * @param account The address of the user.
     * @return collateralAmount The amount of collateral deposited by the user.
     * @return collateralValue The value of the user's collateral.
     * @return borrowAmount The amount of tokens borrowed by the user.
     * @return borrowValue The value of the user's borrow.
     */
    function _userPositionInfo(address account)
        internal
        view
        returns (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue)
    {
        StackVaultStorage storage $ = _getStackVaultStorage();

        uint256 collateralShare = $.userCollateralShare[account];
        uint256 borrowShare = $.userBorrowShare[account];

        if (collateralShare != 0) {
            collateralAmount = $.totalCollateralAmount.toTotalAmount(collateralShare, Math.Rounding.Floor);
            collateralValue = IOracle($.collateralTokenOracle).valueOf(collateralAmount, Math.Rounding.Floor);
        }

        if (borrowShare != 0) {
            address oracle = borrowTokenOracle();
            borrowAmount = $.totalBorrowAmount.toTotalAmount(borrowShare, Math.Rounding.Ceil);
            borrowValue = IOracle(oracle).valueOf(borrowAmount, Math.Rounding.Floor);
        }
    }

    /**
     * @notice Adds a specified amount of collateral to a user's balance.
     * @dev Internal function to increase a user's collateral share based on the deposited amount.
     * @param account The user's address.
     * @param amount The amount of collateral to add.
     * @return share The amount of share added to the user's collateral.
     */
    function _addAmountToCollateral(address account, uint256 amount) internal returns (uint256 share) {
        StackVaultStorage storage $ = _getStackVaultStorage();
        ($.totalCollateralAmount, share) = $.totalCollateralAmount.add(amount, Math.Rounding.Floor);
        $.userCollateralShare[account] += share;
    }

    /**
     * @notice Subtracts a specified amount of collateral from a user's balance.
     * @dev Internal function to decrease a user's collateral share based on the withdrawn amount.
     * @param account The user's address.
     * @param amount The amount of collateral to subtract.
     * @return share The amount of share subtracted from the user's collateral.
     */
    function _subtractAmountFromCollateral(address account, uint256 amount) internal returns (uint256 share) {
        StackVaultStorage storage $ = _getStackVaultStorage();
        ($.totalCollateralAmount, share) = $.totalCollateralAmount.sub(amount, Math.Rounding.Ceil);
        $.userCollateralShare[account] -= share;
    }

    /**
     * @notice Subtracts a specified share of collateral from a user's balance.
     * @dev Internal function to decrease a user's collateral by a specific share.
     * @param account The user's address.
     * @param share The share of collateral to subtract.
     * @return amount The equivalent amount of collateral subtracted.
     */
    function _subtractShareFromCollateral(address account, uint256 share) internal returns (uint256 amount) {
        StackVaultStorage storage $ = _getStackVaultStorage();
        ($.totalCollateralAmount, amount) = $.totalCollateralAmount.subBase(share, Math.Rounding.Ceil);
        $.userCollateralShare[account] -= share;
    }

    /**
     * @notice Adds a specified amount of debt to a user's balance.
     * @dev Internal function to increase a user's debt share based on the borrowed amount.
     * @param account The user's address.
     * @param amount The amount of debt to add.
     * @return share The amount of share added to the user's debt.
     */
    function _addAmountToDebt(address account, uint256 amount) internal returns (uint256 share) {
        StackVaultStorage storage $ = _getStackVaultStorage();
        uint256 feeAmount = amount.mulDiv($.borrowOpeningFee, Constants.FEE_PRECISION);

        amount += feeAmount;

        ($.totalBorrowAmount, share) = $.totalBorrowAmount.add(amount, Math.Rounding.Ceil);
        $.userBorrowShare[account] += share;
        $.userBorrowAmount[account] += amount;
        $.accrualInfo.feesEarned += feeAmount;

        _factory.notifyAccruedInterest(feeAmount);
    }

    /**
     * @notice Subtracts a specified amount of debt from a user's balance.
     * @dev Internal function to decrease a user's debt share based on the repaid amount.
     * @param account The user's address.
     * @param amount The amount of debt to subtract.
     * @return share The amount of share subtracted from the user's debt.
     */
    function _subtractAmountFromDebt(address account, uint256 amount) internal returns (uint256 share) {
        StackVaultStorage storage $ = _getStackVaultStorage();
        ($.totalBorrowAmount, share) = $.totalBorrowAmount.sub(amount, Math.Rounding.Floor);
        $.userBorrowShare[account] -= share;
        _decreaseUserBorrowAmount($.userBorrowAmount, account, amount);
    }

    /**
     * @notice Subtracts a specified share of debt from a user's balance.
     * @dev Internal function to decrease a user's debt by a specific share.
     * @param account The user's address.
     * @param share The share of debt to subtract.
     * @return amount The equivalent amount of debt subtracted.
     */
    function _subtractShareFromDebt(address account, uint256 share) internal returns (uint256 amount) {
        StackVaultStorage storage $ = _getStackVaultStorage();
        ($.totalBorrowAmount, amount) = $.totalBorrowAmount.subBase(share, Math.Rounding.Floor);
        $.userBorrowShare[account] -= share;
        _decreaseUserBorrowAmount($.userBorrowAmount, account, amount);
    }

    /**
     * @notice Decreases the borrow amount of a user.
     * @dev Internal function to reduce the total borrow amount recorded for a user.
     * @param userBorrowAmount The mapping of user addresses to their borrow amounts.
     * @param account The user's address.
     * @param amount The amount to decrease the user's borrow amount by.
     */
    function _decreaseUserBorrowAmount(
        mapping(address => uint256) storage userBorrowAmount,
        address account,
        uint256 amount
    ) internal {
        uint256 borrowAmount = userBorrowAmount[account];
        if (borrowAmount <= amount) {
            userBorrowAmount[account] = 0;
        } else {
            unchecked {
                userBorrowAmount[account] = borrowAmount - amount;
            }
        }
    }

    /**
     * @notice Burns excess borrow tokens to align with the vault's borrow limit.
     * @dev Internal function to burn any borrow tokens that exceed the vault's current borrow limit.
     */
    function _burnExcessBorrowTokens() internal {
        StackVaultStorage storage $ = _getStackVaultStorage();
        uint256 _borrowLimit = $.borrowLimit;
        uint256 balance = borrowToken.balanceOf(address(this));
        if (balance > _borrowLimit) {
            unchecked {
                borrowToken.burn(balance - _borrowLimit);
            }
        }
    }

    /**
     * @notice Converts an amount of one token to the equivalent amount in another token based on their respective
     *         oracle values.
     * @dev Uses oracles to find the equivalent value of an amount from one token in terms of another.
     * @param amount The amount of the token to be converted.
     * @param fromOracle The oracle for the token being converted from.
     * @param toOracle The oracle for the token being converted to.
     * @param rounding The rounding mechanism to use (Floor or Ceil).
     * @return The equivalent amount in the target token.
     */
    function _convertTokenAmount(uint256 amount, address fromOracle, address toOracle, Math.Rounding rounding)
        internal
        view
        returns (uint256)
    {
        uint256 fromValue = IOracle(fromOracle).valueOf(amount, rounding);
        return IOracle(toOracle).amountOf(fromValue, rounding);
    }

    /**
     * @dev Internal function to transfer collateral into the vault.
     * @param from The address from which to transfer the collateral.
     * @param amount The amount of collateral to transfer.
     */
    function _transferCollateralIn(address from, uint256 amount) internal returns (uint256 received) {
        if (_isNativeCollateralToken) {
            received = _transferNativeIn(from, amount);
        } else {
            require(msg.value == 0, "StackVault: Unexpected ETH value");
            address to = address(this);
            uint256 balanceBefore = collateralToken.balanceOf(to);
            collateralToken.safeTransferFrom(from, to, amount);
            received = collateralToken.balanceOf(to) - balanceBefore;
        }
    }

    /**
     * @dev Internal function to transfer collateral out of the vault.
     * @param to The address to which to transfer the collateral.
     * @param amount The amount of collateral to transfer.
     */
    function _transferCollateralOut(address to, uint256 amount) internal returns (uint256 sent) {
        if (_isNativeCollateralToken) {
            sent = _transferNativeOut(to, amount);
        } else {
            address from = address(this);
            uint256 balanceBefore = collateralToken.balanceOf(from);
            collateralToken.safeTransfer(to, amount);
            sent = balanceBefore - collateralToken.balanceOf(from);
        }
    }

    /**
     * @dev Internal function to transfer ETH (or WETH) into the vault.
     * @param from The address from which to transfer the ETH.
     * @param amount The amount of ETH to transfer.
     */
    function _transferNativeIn(address from, uint256 amount) internal returns (uint256 received) {
        if (msg.value == 0) {
            _WETH.transferFrom(from, address(this), amount);
        } else {
            require(msg.value == amount, "StackVault: Incorrect ETH value");
            _WETH.deposit{value: amount}();
        }
        received = amount;
    }

    /**
     * @dev Internal function to transfer ETH (or WETH) out of the vault.
     * @param to The address to which to transfer the ETH.
     * @param amount The amount of ETH to transfer.
     */
    function _transferNativeOut(address to, uint256 amount) internal returns (uint256 sent) {
        _WETH.withdraw(amount);
        (bool success,) = to.call{value: amount}("");
        if (!success) {
            _WETH.deposit{value: amount}();
            success = _WETH.transfer(to, amount);
        }
        require(success, "StackVault: Failed to send ETH");
        sent = amount;
    }

    /**
     * @dev Performs a token swap by calling an external contract, ensuring the swap does not exceed the specified input
     * amount. This internal function is used to execute a swap operation from one token to another, utilizing a
     * specified swap target contract.
     *
     * The function checks the balance of the `fromToken` before and after the swap to calculate the actual input amount
     * (`swapAmountIn`), and similarly, it checks the balance of the `toToken` to determine the output amount
     * (`swapAmountOut`). It ensures that the swap target is a trusted contract as defined by the vault factory. The
     * function emits a `Swap` event containing details of the swap operation.
     *
     * @param fromToken The token being swapped from.
     * @param toToken The token being swapped to.
     * @param amount The maximum amount of `fromToken` to be swapped. The actual amount swapped may be less.
     * @param swapTarget The address of the contract executing the swap.
     * @param swapData The calldata to be sent to `swapTarget` to execute the swap.
     * @return swapAmountIn The actual amount of `fromToken` that was swapped.
     * @return swapAmountOut The amount of `toToken` received from the swap.
     */
    function _safeSwap(IERC20 fromToken, IERC20 toToken, uint256 amount, address swapTarget, bytes memory swapData)
        private
        returns (uint256 swapAmountIn, uint256 swapAmountOut)
    {
        _checkSwapTarget(swapTarget);

        uint256 fromTokenBalanceBefore = fromToken.balanceOf(address(this));
        uint256 toTokenBalanceBefore = toToken.balanceOf(address(this));

        fromToken.forceApprove(swapTarget, amount);

        bytes memory swapResult = swapTarget.functionCall(swapData);
        emit Swap(msg.sender, swapTarget, swapData, swapResult);

        uint256 fromTokenBalanceAfter = fromToken.balanceOf(address(this));
        uint256 toTokenBalanceAfter = toToken.balanceOf(address(this));

        swapAmountIn = fromTokenBalanceBefore - fromTokenBalanceAfter;
        swapAmountOut = toTokenBalanceAfter - toTokenBalanceBefore;

        if (swapAmountOut < amount) {
            fromToken.forceApprove(swapTarget, 0);
        }
    }

    /**
     * @notice Checks if a user's position is healthy, i.e., not subject to liquidation.
     * @dev Determines the health of a user's position based on their collateral value and borrow value.
     * @param collateralValue The value of the user's collateral.
     * @param borrowValue The value of the user's borrow.
     * @return A boolean indicating whether the user's position is healthy.
     */
    function _isHealthy(uint256 collateralValue, uint256 borrowValue) internal view returns (bool) {
        StackVaultStorage storage $ = _getStackVaultStorage();

        if (collateralValue == 0 || borrowValue == 0) return borrowValue == 0;

        uint256 scaledLTV = borrowValue.mulDiv(Constants.ORACLE_PRICE_PRECISION, collateralValue);
        return scaledLTV < $.liquidationThreshold * Constants.ORACLE_PRICE_PRECISION / Constants.LTV_PRECISION;
    }

    /**
     * @notice Performs a health check on a user's position in the vault.
     * @dev Verifies that the user's position is healthy by comparing their collateral value to their borrow value.
     *      Reverts if the user's position is unhealthy, meaning it's at risk of liquidation.
     * @param account The address of the user whose position is being checked.
     */
    function _healthcheck(address account) internal view {
        (, uint256 collateralValue,, uint256 borrowValue) = _userPositionInfo(account);
        if (!_isHealthy(collateralValue, borrowValue)) {
            revert Unhealthy();
        }
    }

    /**
     * @notice Validates a swap target to ensure it is trusted.
     * @dev Internal function to check if a given swap target address is marked as trusted in the vault factory.
     * @param swapTarget The address of the swap target to validate.
     */
    function _checkSwapTarget(address swapTarget) internal view {
        if (!_factory.isTrustedSwapTarget(swapTarget)) {
            revert UntrustedSwapTarget(swapTarget);
        }
    }
}
