// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {BorrowInterestRateAdjustmentMath} from "../libraries/BorrowInterestRateAdjustmentMath.sol";
import {IERC20Mintable} from "../interfaces/IERC20Mintable.sol";
import {IMinter} from "../interfaces/IMinter.sol";
import {Constants} from "../libraries/Constants.sol";
import {StackVault} from "../vaults/StackVault.sol";

import {VaultDeployer} from "./VaultDeployer.sol";
import {VaultFactoryConfiguration} from "./VaultFactoryConfiguration.sol";
import {VaultFactoryVaultManagement} from "./VaultFactoryVaultManagement.sol";

/**
 * @title Vault Factory Contract
 * @notice Main contract for creating and managing vaults in the Stack ecosystem.
 * @dev Inherits from VaultFactoryConfiguration and VaultFactoryVaultManagement to combine their functionalities.
 *      This contract encapsulates the entire logic for vault management, including creation, upgrade, fee collection,
 *      and interest accrual. It integrates with the VaultDeployer for deploying individual vault contracts and
 *      manages the system-wide settings such as interest rates and oracle addresses.
 *      It also supports UUPS (Universal Upgradeable Proxy Standard) for upgradability and Multicall for batched calls.
 *      The contract uses a series of events for tracking actions like vault creation and fee collection.
 * @author SeaZarrgh LaBuoy
 */
contract VaultFactory is
    VaultFactoryConfiguration,
    VaultFactoryVaultManagement,
    UUPSUpgradeable,
    MulticallUpgradeable
{
    using BorrowInterestRateAdjustmentMath for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint96 public constant DEFAULT_LIQUIDATOR_PENALTY_SHARE = uint96(6 * Constants.FEE_PRECISION / 10);

    address public immutable WETH;

    event VaultCreated(address indexed collateralToken, uint8 liquidationThreshold, address vault);
    event FeesCollected(address indexed vault, address indexed token, uint256 amount);

    error VaultAlreadyExists(address collateralToken, address vault);

    modifier onlyVault() {
        VaultFactoryStorage storage $ = _getVaultFactoryStorage();
        uint256 vaultIndex = $.vaultIndex[msg.sender];
        if ($.allVaults[vaultIndex] != msg.sender) {
            revert UnauthorizedCaller();
        }
        _;
    }

    /**
     * @notice Initializes the VaultFactory contract.
     * @dev Calls the constructor of VaultFactoryConfiguration with the borrow token minter address.
     *      Disables initializers to ensure the contract is only initialized once and to prevent reinitialization after
     *      an upgrade.
     * @param weth The address of the WETH token.
     * @param _borrowTokenMinter The address of the borrow token minter.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address weth, address _borrowTokenMinter) VaultFactoryConfiguration(_borrowTokenMinter) {
        _disableInitializers();
        if (weth == address(0)) {
            revert InvalidZeroAddress();
        }
        WETH = weth;
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
     * @notice Initializes the VaultFactory contract with necessary configuration.
     * @dev Sets up the contract with initial configuration values, including the vault deployer, borrow token oracle,
     *      and fee receiver.
     *      It marks the contract as initialized to prevent reinitialization.
     *      This function can only be called once due to the `initializer` modifier from OpenZeppelin's upgradeable
     *      contracts library.
     * @param _vaultDeployer The address of the vault deployer.
     * @param _borrowTokenOracle The address of the oracle for the borrow token.
     * @param _feeReceiver The address where collected fees will be sent.
     */
    function initialize(address _vaultDeployer, address _borrowTokenOracle, address _feeReceiver)
        external
        initializer
    {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __Multicall_init();
        if (_feeReceiver == address(0)) {
            revert InvalidZeroAddress();
        }
        VaultFactoryStorage storage $ = _getVaultFactoryStorage();
        $.interestRateManager = msg.sender;
        setDebtCollector(msg.sender);
        setLiquidatorPenaltyShare(DEFAULT_LIQUIDATOR_PENALTY_SHARE);
        setVaultDeployer(_vaultDeployer);
        setBorrowTokenOracle(_borrowTokenOracle);
        setFeeReceiver(_feeReceiver);
    }

    /**
     * @notice Creates a new vault for a given collateral token.
     * @dev Deploys a new vault using the VaultDeployer. The new vault is configured with specified parameters.
     *      Adds the deployed vault to the system's records in VaultFactoryStorage.
     *      Emits a `VaultCreated` event upon successful creation.
     *      Reverts if a vault for the specified collateral token already exists.
     *      Access restricted to the contract owner.
     * @param collateralToken The address of the collateral token for the new vault.
     * @param collateralTokenOracle The address of the oracle for the collateral token.
     * @param liquidationThreshold The liquidation threshold for the new vault.
     * @param interestRateMultiplier The interest rate multiplier for the new vault.
     * @return vault The address of the newly created vault.
     */
    function createVault(
        address collateralToken,
        address collateralTokenOracle,
        uint8 liquidationThreshold,
        uint256 interestRateMultiplier
    ) external onlyOwner returns (address payable vault) {
        VaultFactoryStorage storage $ = _getVaultFactoryStorage();

        if (collateralToken == WETH) {
            collateralToken = Constants.ETH_ADDRESS;
        }

        if ($.vaultForToken[collateralToken] != address(0)) {
            revert VaultAlreadyExists(collateralToken, $.vaultForToken[collateralToken]);
        }

        vault = VaultDeployer($.vaultDeployer).deployVault(
            borrowToken, collateralToken, collateralTokenOracle, liquidationThreshold, interestRateMultiplier
        );

        uint32 numVaults = uint32($.allVaults.length);
        $.allVaults.push(vault);
        $.allVaultsLength = numVaults + 1;
        $.vaultForToken[collateralToken] = vault;
        $.vaultIndex[vault] = numVaults;
        emit VaultCreated(collateralToken, liquidationThreshold, vault);
    }

    /**
     * @notice Upgrades the implementation of a specified vault.
     * @dev Transfers ownership of the vault to the vault deployer, performs the upgrade, and then transfers ownership
     *      back to the Vault Factory owner.
     *      Before calling this function, the current owner of the vault must transfer the ownership to the Vault
     *      Factory.
     *      After the upgrade, the vault deployer transfers the ownership back to the current owner of the Vault
     *      Factory.
     *      Ensures that only existing, valid vaults are upgraded.
     *      Restricted to the contract owner.
     * @param vault The address of the vault to be upgraded.
     */
    function upgradeVaultImplementation(address payable vault) external onlyOwner {
        _requireVault(vault);
        VaultFactoryStorage storage $ = _getVaultFactoryStorage();
        OwnableUpgradeable(vault).transferOwnership($.vaultDeployer);
        VaultDeployer($.vaultDeployer).upgradeVault(vault, owner());
    }

    /**
     * @notice Collects fees from a specific vault.
     * @dev Transfers the specified amount of fees from the calling vault to the penalty receiver.
     *      Can only be called by a vault, verified through the `onlyVault` modifier.
     *      Emits a `FeesCollected` event upon successful fee collection.
     * @param token The address of the token in which fees are collected.
     * @param amount The amount of fees to be collected.
     */
    function collectFees(address token, uint256 amount) external onlyVault {
        VaultFactoryStorage storage $ = _getVaultFactoryStorage();
        address to = $.penaltyReceiver;
        uint256 balanceBefore = IERC20(token).balanceOf(to);
        IERC20(token).safeTransferFrom(msg.sender, to, amount);
        emit FeesCollected(msg.sender, token, IERC20(token).balanceOf(to) - balanceBefore);
    }

    /**
     * @notice Notifies the factory of accrued interest from a vault and mints tokens to the fee receiver.
     * @dev Mints the specified amount of the borrow token to the fee receiver as accrued interest.
     *      Can only be called by a vault, enforced by the `onlyVault` modifier.
     *      The minting is done through the borrow token minter, which is linked to the borrow token used in the vaults.
     * @param amount The amount of interest that has been accrued.
     */
    function notifyAccruedInterest(uint256 amount) external onlyVault {
        VaultFactoryStorage storage $ = _getVaultFactoryStorage();
        IMinter(borrowTokenMinter).mint($.feeReceiver, amount);
    }

    /**
     * @notice Retrieves the vault address associated with a specific collateral token.
     * @dev Returns the address of the vault corresponding to the given collateral token from the VaultFactoryStorage.
     *      This function is useful for finding the specific vault managing a particular type of collateral.
     * @param collateralToken The address of the collateral token.
     * @return vault The address of the vault associated with the given collateral token.
     */
    function vaultForToken(address collateralToken) external view returns (address vault) {
        VaultFactoryStorage storage $ = _getVaultFactoryStorage();
        if (collateralToken == WETH) {
            collateralToken = Constants.ETH_ADDRESS;
        }
        vault = $.vaultForToken[collateralToken];
    }
}
