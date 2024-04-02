// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {CommonErrors} from "../interfaces/CommonErrors.sol";
import {IVaultFactory} from "../interfaces/IVaultFactory.sol";
import {BorrowInterestRateAdjustmentMath} from "../libraries/BorrowInterestRateAdjustmentMath.sol";
import {Constants} from "../libraries/Constants.sol";

import {BorrowToken} from "../tokens/BorrowToken.sol";
import {StackVault} from "../vaults/StackVault.sol";
import {VaultFactoryBulkOperations} from "./VaultFactoryBulkOperations.sol";
import {VaultFactoryERC7201} from "./VaultFactoryERC7201.sol";

/**
 * @title Vault Factory Vault Management Contract
 * @notice Abstract contract for managing individual vaults in the Stack ecosystem, extending the VaultFactoryERC7201.
 * @dev This contract includes functions for retiring and reviving vaults, setting borrow interest multipliers, borrow
 *      limits, and various fees. It utilizes the storage structure defined in VaultFactoryERC7201 and integrates with
 *      the StackVault contract for specific vault operations. The contract ensures that only the owner can perform
 *      critical administrative tasks on vaults.
 *      It also includes utility functions to view all vaults and their specific details.
 * @author SeaZarrgh LaBuoy
 */
abstract contract VaultFactoryVaultManagement is
    CommonErrors,
    OwnableUpgradeable,
    VaultFactoryBulkOperations,
    VaultFactoryERC7201
{
    using BorrowInterestRateAdjustmentMath for uint256;
    using SafeERC20 for BorrowToken;
    using Math for uint256;

    uint256 public constant MIN_INTEREST_RATE_UPDATE_INTERVAL = 12 hours;

    error InterestRateUpdateTooFrequent(uint256 nextUpdateTimestamp);
    error NonexistentVault(address vault);

    /**
     * @notice Accrues interest across all vaults managed by the factory.
     * @dev Iterates through all vaults stored in `allVaults` and calls `accrueInterest` on each StackVault instance.
     *      This function ensures that interest is updated and accrued consistently across all vaults.
     *      Can be called by any actor in the system, allowing for flexible interest accrual triggers.
     */
    function accrueInterest() public virtual override(IVaultFactory, VaultFactoryBulkOperations) {
        VaultFactoryStorage storage $ = _getVaultFactoryStorage();
        for (uint256 i = $.allVaultsLength; i != 0;) {
            unchecked {
                --i;
            }
            StackVault(payable($.allVaults[i])).accrueInterest();
        }
    }

    /**
     * @notice Gets the total number of vaults managed by the factory.
     * @dev Returns the length of the `allVaults` array from the VaultFactoryStorage, representing the total number of
     *      vaults.
     *      This function provides a way to know how many vaults have been created and are managed by this factory.
     * @return length The total number of vaults managed by the factory.
     */
    function allVaultsLength() external view returns (uint256 length) {
        VaultFactoryStorage storage $ = _getVaultFactoryStorage();
        length = $.allVaultsLength;
    }

    /**
     * @notice Retrieves the address of a vault at a specific index in the factory's vault list.
     * @dev Returns the address of the vault located at the specified index in the `allVaults` array from the
     *      VaultFactoryStorage.
     *      This function allows for enumeration of all vaults managed by the factory, useful for off-chain queries and
     *      interfaces.
     * @param index The index in the list of all vaults.
     * @return vault The address of the vault at the given index.
     */
    function allVaults(uint256 index) external view returns (address vault) {
        VaultFactoryStorage storage $ = _getVaultFactoryStorage();
        vault = $.allVaults[index];
    }

    /**
     * @notice Retires a specific vault, disabling further interactions.
     * @dev Marks a vault as retired by calling the `retire` function on the StackVault contract.
     *      Retiring a vault prevents new borrowings and may affect other operations.
     *      This action can only be performed by the contract owner.
     *      Reverts if the vault is already retired (to prevent unnecessary transactions and gas usage).
     * @param vault The address of the vault to retire.
     */
    function retireVault(address payable vault) external onlyOwner {
        _requireVault(vault).retire();
    }

    /**
     * @notice Revives a retired vault, enabling further interactions.
     * @dev Marks a vault as active again by calling the `revive` function on the StackVault contract.
     *      Reviving a vault allows it to resume normal operations like borrowing.
     *      This action can only be performed by the contract owner.
     *      Reverts if the vault is already active (to prevent unnecessary transactions and gas usage).
     * @param vault The address of the vault to revive.
     */
    function reviveVault(address payable vault) external onlyOwner {
        _requireVault(vault).revive();
    }

    /**
     * @notice Sets a new liquidation threshold for a specific vault.
     * @dev Updates the liquidation threshold for a given vault by invoking the `setLiquidationThreshold` method on
     *      the StackVault contract.
     *      The liquidation threshold is applied when a position in this vault undergoes liquidation.
     *      Access to this function is restricted to the contract owner.
     *      Reverts if the new threshold is identical to the current threshold to avoid unnecessary transactions.
     * @param vault The address of the vault for which to set the new liquidation penalty fee.
     * @param newThreshold The new liquidation threshold to be set.
     */
    function setLiquidationThreshold(address payable vault, uint8 newThreshold) public onlyOwner {
        _requireVault(vault).setLiquidationThreshold(newThreshold);
    }

    /**
     * @notice Sets a new interest rate multiplier for a specific vault.
     * @dev Updates the interest rate multiplier of a given vault by calling the `setInterestRateMultiplier` function on
     *      the StackVault contract.
     *      This multiplier influences the calculation of the borrow interest rate for the vault.
     *      Can only be executed by the contract owner.
     *      Ensures the targeted vault exists by calling `_requireVault`.
     * @param vault The address of the vault for which to set the new interest rate multiplier.
     * @param multiplier The new interest rate multiplier to be set.
     */
    function setBorrowInterestMultiplier(address payable vault, uint256 multiplier) external onlyOwner {
        _requireVault(vault).setInterestRateMultiplier(multiplier);
    }

    /**
     * @notice Sets a new borrowing limit for a specific vault.
     * @dev Adjusts the borrow limit of a given vault. If the new limit is higher, it transfers the additional required
     *      tokens from the caller to the vault. If the new limit is lower, it reduces the vault's borrow limit.
     *      This action can only be performed by the contract owner.
     *      Reverts if the new borrow limit is the same as the current one to prevent unnecessary transactions.
     * @param vault The address of the vault for which to set the new borrow limit.
     * @param newBorrowLimit The new borrowing limit for the vault.
     */
    function setBorrowLimit(address payable vault, uint256 newBorrowLimit) external onlyOwner {
        uint256 currentBorrowLimit = StackVault(vault).borrowLimit();
        if (currentBorrowLimit < newBorrowLimit) {
            uint256 delta;
            unchecked {
                delta = newBorrowLimit - currentBorrowLimit;
            }
            BorrowToken(borrowToken).safeTransferFrom(msg.sender, address(this), delta);
            BorrowToken(borrowToken).forceApprove(vault, delta);
            StackVault(vault).increaseBorrowLimit(delta);
        } else if (currentBorrowLimit > newBorrowLimit) {
            uint256 delta;
            unchecked {
                delta = currentBorrowLimit - newBorrowLimit;
            }
            StackVault(vault).decreaseBorrowLimit(delta);
        } else {
            revert ValueUnchanged();
        }
    }

    /**
     * @notice Sets a new opening fee for borrowing from a specific vault.
     * @dev Updates the borrow opening fee for a given vault by calling the `setBorrowOpeningFee` function on the
     *      StackVault contract.
     *      The opening fee is charged when a borrowing operation is initiated.
     *      This action can only be performed by the contract owner.
     *      Reverts if the new fee is the same as the current one to prevent unnecessary transactions.
     * @param vault The address of the vault for which to set the new borrow opening fee.
     * @param newFee The new borrow opening fee to be set.
     */
    function setBorrowOpeningFee(address payable vault, uint256 newFee) public onlyOwner {
        _requireVault(vault).setBorrowOpeningFee(newFee);
    }

    /**
     * @notice Updates the oracle address used for borrow token price feeds for a specific vault.
     * @dev Sets a new oracle for obtaining borrow token price feeds, replacing the existing oracle address for the
     * specified vault. This function can only be called by the contract owner. It ensures that the new oracle address
     * differs from the current one to prevent unnecessary state changes. The oracle is critical for calculating the
     * collateralization ratio and managing loan security.
     * @param vault The address of the vault for which to update the borrow token oracle.
     * @param newOracle The address of the new oracle to be set for the borrow token price feeds.
     */
    function setBorrowTokenOracle(address payable vault, address newOracle) public onlyOwner {
        _requireVault(vault).setBorrowTokenOracle(newOracle);
    }

    /**
     * @notice Updates the oracle address used for collateral token price feeds for a specific vault.
     * @dev Sets a new oracle for obtaining collateral token price feeds, replacing the existing oracle address for the
     * specified vault. This function can only be called by the contract owner. It ensures that the new oracle address
     * differs from the current one to prevent unnecessary state changes. The oracle is critical for calculating the
     * collateralization ratio and managing loan security.
     * @param vault The address of the vault for which to update the collateral token oracle.
     * @param newOracle The address of the new oracle to be set for the collateral token price feeds.
     */
    function setCollateralTokenOracle(address payable vault, address newOracle) public onlyOwner {
        _requireVault(vault).setCollateralTokenOracle(newOracle);
    }

    /**
     * @notice Sets a new liquidation penalty fee for a specific vault.
     * @dev Updates the liquidation penalty fee for a given vault by invoking the `setLiquidationPenaltyFee` method on
     *      the StackVault contract.
     *      The liquidation penalty fee is applied when a position in this vault undergoes liquidation.
     *      Access to this function is restricted to the contract owner.
     *      Reverts if the new fee is identical to the current fee to avoid unnecessary transactions.
     * @param vault The address of the vault for which to set the new liquidation penalty fee.
     * @param newFee The new liquidation penalty fee to be set.
     */
    function setLiquidationPenaltyFee(address payable vault, uint256 newFee) public onlyOwner {
        _requireVault(vault).setLiquidationPenaltyFee(newFee);
    }

    /**
     * @notice Validates the existence of a vault and returns its StackVault instance.
     * @dev Checks if the given address corresponds to a valid vault by comparing it with the stored vaults in
     *      `VaultFactoryStorage`.
     *      Reverts with `NonexistentVault` error if the provided address does not match any existing vault.
     *      This function is used internally to ensure that operations are only performed on valid vaults.
     * @param vault The address of the vault to validate.
     * @return The StackVault instance corresponding to the provided vault address.
     */
    function _requireVault(address payable vault) internal view returns (StackVault) {
        VaultFactoryStorage storage $ = _getVaultFactoryStorage();
        uint256 vaultIndex = $.vaultIndex[vault];
        if ($.allVaults[vaultIndex] != vault) {
            revert NonexistentVault(vault);
        }
        return StackVault(vault);
    }
}
