// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

/**
 * @title Vault Factory Interface
 * @notice Interface for a factory contract managing the creation and administration of vaults.
 * @dev This interface defines functions for creating vaults, managing interest rates, borrowing limits, and fees,
 *      and handling collateral tokens and oracles. It also includes functions for fee collection and vault retirement
 *      or revival.
 * @author SeaZarrgh LaBuoy
 */
interface IVaultFactory {
    /**
     * @notice Accrues interest across all vaults.
     * @dev Function to perform a global interest accrual for all vaults managed by this factory.
     */
    function accrueInterest() external;

    /**
     * @notice Gets the current borrow interest rate.
     * @dev Function to view the current global borrow interest rate for vaults.
     * @return rate The current borrow interest rate.
     */
    function borrowInterestRate() external view returns (uint256 rate);

    /**
     * @notice Gets the address of the token that can be borrowed from the vaults.
     * @dev Function to view the address of the borrow token.
     * @return token The address of the borrow token.
     */
    function borrowToken() external view returns (address token);

    /**
     * @notice Gets the address of the oracle for the borrow token.
     * @dev Function to view the address of the oracle associated with the borrow token.
     * @return oracle The address of the borrow token oracle.
     */
    function borrowTokenOracle() external view returns (address oracle);

    /**
     * @notice Collects fees to a specified address.
     * @dev Function to collect accumulated fees in a specified token.
     * @param token The address of the token in which fees are collected.
     * @param amount The amount of fees to collect.
     */
    function collectFees(address token, uint256 amount) external;

    /**
     * @notice Creates a new vault with specified parameters.
     * @dev Function to create a new vault for a given collateral token and oracle, with specific liquidation threshold
     *      and interest rate multiplier.
     * @param collateralToken The address of the collateral token.
     * @param collateralTokenOracle The address of the oracle for the collateral token.
     * @param liquidationThreshold The liquidation threshold for the vault.
     * @param interestRateMultiplier The interest rate multiplier for the vault.
     * @return vault The address of the newly created vault.
     */
    function createVault(
        address collateralToken,
        address collateralTokenOracle,
        uint8 liquidationThreshold,
        uint256 interestRateMultiplier
    ) external returns (address payable vault);

    /**
     * @notice Gets the share of penalties allocated to the liquidator.
     * @dev Function to view the share of liquidation penalties that are allocated to the liquidator.
     * @return share The share of penalties allocated to the liquidator.
     */
    function liquidatorPenaltyShare() external view returns (uint256 share);

    /**
     * @notice Notifies the factory of the amount of interest accrued.
     * @dev Function used to inform the factory about the accrued interest, typically called by vaults.
     * @param amount The amount of accrued interest.
     */
    function notifyAccruedInterest(uint256 amount) external;

    /**
     * @notice Retires a vault, disabling further interactions.
     * @dev Function to retire a vault, marking it as inactive and preventing further operations.
     * @param vault The address of the vault to retire.
     */
    function retireVault(address payable vault) external;

    /**
     * @notice Revives a retired vault, enabling interactions.
     * @dev Function to revive a retired vault, marking it as active and allowing operations.
     * @param vault The address of the vault to revive.
     */
    function reviveVault(address payable vault) external;

    /**
     * @notice Sets a new borrow interest rate multiplier for a specific vault.
     * @dev Function to update the interest rate multiplier for a given vault.
     * @param vault The address of the vault for which to set the multiplier.
     * @param multiplier The new interest rate multiplier.
     */
    function setBorrowInterestMultiplier(address payable vault, uint256 multiplier) external;

    /**
     * @notice Sets a new borrowing limit for a specific vault.
     * @dev Function to update the borrowing limit for a given vault.
     * @param vault The address of the vault for which to set the new borrow limit.
     * @param newBorrowLimit The new borrowing limit.
     */
    function setBorrowLimit(address payable vault, uint256 newBorrowLimit) external;

    /**
     * @notice Sets the address of the debt collector.
     * @dev Function to update the address responsible for debt collection.
     * @param newDebtCollector The address of the new debt collector.
     */
    function setDebtCollector(address newDebtCollector) external;

    /**
     * @notice Sets the address where collected fees are sent.
     * @dev Function to update the address that receives collected fees.
     * @param feeReceiver The address of the new fee receiver.
     */
    function setFeeReceiver(address feeReceiver) external;

    /**
     * @notice Sets the share of penalties allocated to the liquidator.
     * @dev Function to update the share of liquidation penalties that are allocated to the liquidator.
     * @param share The new share of penalties allocated to the liquidator.
     */
    function setLiquidatorPenaltyShare(uint96 share) external;

    /**
     * @notice Sets a new borrowing opening fee for a specific vault.
     * @dev Function to update the opening fee for borrowing in a given vault.
     * @param vault The address of the vault for which to set the new fee.
     * @param newFee The new borrowing opening fee.
     */
    function setBorrowOpeningFee(address payable vault, uint256 newFee) external;

    /**
     * @notice Sets a new liquidation penalty fee for a specific vault.
     * @dev Function to update the liquidation penalty fee for a given vault.
     * @param vault The address of the vault for which to set the new fee.
     * @param newFee The new liquidation penalty fee.
     */
    function setLiquidationPenaltyFee(address payable vault, uint256 newFee) external;

    /**
     * @notice Checks if a given address is a trusted swap target.
     * @dev Function to verify if a given target address is considered trusted for swaps.
     * @param target The address to check.
     * @return A boolean indicating whether the address is a trusted swap target.
     */
    function isTrustedSwapTarget(address target) external view returns (bool);

    /**
     * @notice Gets the vault address for a specific collateral token.
     * @dev Function to retrieve the address of the vault associated with a given collateral token.
     * @param collateralToken The address of the collateral token.
     * @return vault The address of the associated vault.
     */
    function vaultForToken(address collateralToken) external view returns (address vault);

    /**
     * @notice Gets the address of the WETH token.
     */
    function WETH() external view returns (address);
}
