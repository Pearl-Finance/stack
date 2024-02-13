// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

/**
 * @title Constants Library
 * @notice Provides a collection of constant values used across the contract system.
 * @dev This library defines constants with specific precision levels to ensure consistency and accuracy in
 *      calculations. These constants are internal and are utilized in various financial and computational contexts
 *      within the contract system.
 * @author SeaZarrgh LaBuoy
 */
library Constants {
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // Address used to represent
        // Ether (ETH).
    uint256 internal constant FEE_PRECISION = 1e18; // Precision for fee calculations.
    uint256 internal constant LTV_PRECISION = 1e2; // Precision for Loan-to-Value (LTV) ratio calculations.
    uint256 internal constant ORACLE_PRICE_PRECISION = 1e18; // Precision for oracle price values.
    uint256 internal constant INTEREST_RATE_PRECISION = 1e18; // Precision for interest rate calculations.
    uint256 internal constant INTEREST_RATE_MULTIPLIER_PRECISION = 1e1; // Precision for interest rate multipliers.
}
