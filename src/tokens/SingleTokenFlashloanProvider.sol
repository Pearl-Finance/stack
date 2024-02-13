// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC3156FlashBorrower, IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {Constants} from "../libraries/Constants.sol";

/**
 * @title Single Token Flashloan Provider Contract
 * @notice Abstract contract providing flash loan functionality for a single token, compliant with the ERC-3156
 *         standard.
 * @dev Implements the IERC3156FlashLender interface for single-token flash loans.
 *      Inherits from ReentrancyGuardUpgradeable for protection against reentrancy attacks.
 *      Utilizes ERC-7201 namespaced storage pattern for storing the flashloan fee.
 *      The contract must be extended and the abstract function `_flashloanFeeReceived` implemented.
 * @author SeaZarrgh LaBuoy
 */
abstract contract SingleTokenFlashloanProvider is IERC3156FlashLender, ReentrancyGuardUpgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    bytes32 constant FLASHLOAN_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /**
     * @dev The loan token is not valid.
     */
    error ERC3156UnsupportedToken(address token);

    /**
     * @dev The requested loan exceeds the max loan value for `token`.
     */
    error ERC3156ExceededMaxLoan(uint256 maxLoan);

    /**
     * @dev The receiver of a flashloan is not a valid {onFlashLoan} implementer.
     */
    error ERC3156InvalidReceiver(address receiver);

    /**
     * @dev The loan was not paid back (in full) by the end of the transaction.
     */
    error ERC3156RepayFailed();

    /// @custom:storage-location erc7201:pearl.storage.SingleTokenFlashloanProvider
    struct SingleTokenFlashloanProviderStorage {
        uint256 fee;
    }

    // keccak256(abi.encode(uint256(keccak256("pearl.storage.SingleTokenFlashloanProvider")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant SingleTokenFlashloanProviderStorageLocation =
        0x0e05a38410fdaa34fff17d0053c282ffaa6b9335ea6ad507753658ed52177500;

    address private immutable _token;

    function _getSingleTokenFlashloanProviderStorage()
        private
        pure
        returns (SingleTokenFlashloanProviderStorage storage $)
    {
        // slither-disable-next-line assembly
        assembly {
            $.slot := SingleTokenFlashloanProviderStorageLocation
        }
    }

    /**
     * @notice Initializes the SingleTokenFlashloanProvider contract.
     * @dev Sets the token for which flash loans are provided and disables initializers to prevent reinitialization
     *      after an upgrade.
     * @param token The address of the token for which flash loans are provided.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address token) {
        _disableInitializers();
        _token = token;
    }

    /**
     * @notice Initializes the flash loan provider with a specified fee.
     * @dev Sets up the initial flash loan fee and initializes the ReentrancyGuard.
     *      Can only be called once due to the `initializer` modifier.
     * @param fee The fee percentage for flash loans.
     */
    function __SingleTokenFlashloanProvider_init(uint256 fee) internal onlyInitializing {
        __SingleTokenFlashloanProvider_init_unchained(fee);
        __ReentrancyGuard_init();
    }

    /**
     * @notice Sets the initial fee for the flash loan provider.
     * @dev Configures the initial fee for flash loans, without initializing other components.
     * @param fee The fee percentage for flash loans.
     */
    function __SingleTokenFlashloanProvider_init_unchained(uint256 fee) internal onlyInitializing {
        SingleTokenFlashloanProviderStorage storage $ = _getSingleTokenFlashloanProviderStorage();
        $.fee = fee;
    }

    /**
     * @notice Returns the maximum amount available for a flash loan of a given token.
     * @dev Calculates the available amount of the specified token for flash loans.
     *      Returns zero for unsupported tokens.
     * @param token The address of the token to check.
     * @return _maxFlashLoan The maximum amount available for a flash loan.
     */
    function maxFlashLoan(address token) external view returns (uint256 _maxFlashLoan) {
        if (token == _token) {
            _maxFlashLoan = IERC20(token).balanceOf(address(this));
        }
    }

    /**
     * @notice Calculates the fee for a flash loan of a specific amount.
     * @dev Computes the flash loan fee based on the loan amount and stored fee percentage.
     *      Reverts if the token is not supported.
     * @param token The address of the loan token.
     * @param amount The amount of the loan.
     * @return The calculated flash loan fee.
     */
    function flashFee(address token, uint256 amount) external view returns (uint256) {
        SingleTokenFlashloanProviderStorage storage $ = _getSingleTokenFlashloanProviderStorage();
        if (token != _token) {
            revert ERC3156UnsupportedToken(token);
        }
        return amount.mulDiv($.fee, Constants.FEE_PRECISION);
    }

    /**
     * @notice Provides a flash loan to a receiver contract.
     * @dev Executes a flash loan transaction, ensuring repayment by the end of the transaction.
     *      Reverts if the receiver is invalid or if the loan is not repaid in full.
     * @param receiver The contract receiving the flash loan.
     * @param token The address of the loan token.
     * @param amount The amount of the loan.
     * @param data Arbitrary data passed to the receiver's `onFlashLoan` method.
     * @return True if the flash loan is executed successfully.
     */
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        nonReentrant
        returns (bool)
    {
        SingleTokenFlashloanProviderStorage storage $ = _getSingleTokenFlashloanProviderStorage();
        if (token != _token) {
            revert ERC3156UnsupportedToken(token);
        }

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        if (amount > balanceBefore) {
            revert ERC3156ExceededMaxLoan(balanceBefore);
        }

        uint256 fee = amount.mulDiv($.fee, Constants.FEE_PRECISION);
        uint256 minBalanceAfter = balanceBefore + fee;

        IERC20(token).safeTransfer(address(receiver), amount);

        if (receiver.onFlashLoan(msg.sender, token, amount, fee, data) != FLASHLOAN_SUCCESS) {
            revert ERC3156InvalidReceiver(address(receiver));
        }

        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        if (balanceAfter < minBalanceAfter) {
            revert ERC3156RepayFailed();
        }

        unchecked {
            _flashloanFeeReceived(balanceAfter - balanceBefore);
        }

        return true;
    }

    /**
     * @notice Sets a new flash loan fee.
     * @dev Internal function to update the fee percentage for flash loans.
     * @param fee The new fee percentage.
     */
    function _setFlashloanFee(uint256 fee) internal {
        SingleTokenFlashloanProviderStorage storage $ = _getSingleTokenFlashloanProviderStorage();
        $.fee = fee;
    }

    /**
     * @notice Abstract function to handle the received flash loan fee.
     * @dev Must be implemented by extending contracts to specify behavior upon receiving the flash loan fee.
     * @param fee The amount of fee received.
     */
    function _flashloanFeeReceived(uint256 fee) internal virtual;
}
