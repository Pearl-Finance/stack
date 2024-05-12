// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @notice Struct representing an interest accruing amount with base and total values.
 */
struct InterestAccruingAmount {
    uint256 base;
    uint256 total;
}

/**
 * @title Interest Accrual Math Library
 * @notice Provides functions for managing interest accruing amounts, facilitating conversions between base and total
 *         amounts, and performing addition and subtraction operations on these amounts.
 * @dev This library uses a struct 'InterestAccruingAmount' to encapsulate base and total amounts, leveraging
 *      OpenZeppelin's Math library for safe arithmetic operations with support for different rounding methods. The
 *      functions handle edge cases like zero values gracefully to ensure correct calculations in all scenarios.
 * @author SeaZarrgh LaBuoy
 */
library InterestAccrualMath {
    using Math for uint256;

    /**
     * @dev Converts a total amount to a base amount based on the proportions in the 'InterestAccruingAmount' struct.
     * @param amount The 'InterestAccruingAmount' struct containing the current base and total amounts.
     * @param totalAmount The total amount to convert to base amount.
     * @param rounding The rounding method to be used (up, down, or closest).
     * @return baseAmount The calculated base amount.
     */
    function toBaseAmount(InterestAccruingAmount memory amount, uint256 totalAmount, Math.Rounding rounding)
        internal
        pure
        returns (uint256 baseAmount)
    {
        if (amount.base == 0) {
            baseAmount = totalAmount + amount.total;
        } else {
            baseAmount = totalAmount.mulDiv(amount.base, amount.total, rounding);
        }
    }

    /**
     * @dev Converts a base amount to a total amount based on the proportions in the 'InterestAccruingAmount' struct.
     * @param amount The 'InterestAccruingAmount' struct containing the current base and total amounts.
     * @param baseAmount The base amount to convert to total amount.
     * @param rounding The rounding method to be used (up, down, or closest).
     * @return totalAmount The calculated total amount.
     */
    function toTotalAmount(InterestAccruingAmount memory amount, uint256 baseAmount, Math.Rounding rounding)
        internal
        pure
        returns (uint256 totalAmount)
    {
        if (amount.base == 0) {
            totalAmount = baseAmount;
        } else {
            totalAmount = baseAmount.mulDiv(amount.total, amount.base, rounding);
        }
    }

    /**
     * @dev Adds a total amount to an 'InterestAccruingAmount', updating both base and total values.
     *      If the totalAmount is non-zero, it converts the totalAmount to the corresponding base amount and updates the
     *      struct accordingly.
     * @param amount The 'InterestAccruingAmount' struct to be updated.
     * @param totalAmount The total amount to be added.
     * @param rounding The rounding method to be used (up, down, or closest).
     * @return The updated 'InterestAccruingAmount' struct and the base amount corresponding to the added total amount.
     */
    function add(InterestAccruingAmount memory amount, uint256 totalAmount, Math.Rounding rounding)
        internal
        pure
        returns (InterestAccruingAmount memory, uint256 baseAmount)
    {
        if (totalAmount != 0) {
            baseAmount = toBaseAmount(amount, totalAmount, rounding);
            amount.base += baseAmount;
            amount.total += totalAmount;
        }
        return (amount, baseAmount);
    }

    /**
     * @dev Subtracts a total amount from an 'InterestAccruingAmount', updating both base and total values.
     *      Handles edge cases such as when the totalAmount equals the struct's total value.
     * @param amount The 'InterestAccruingAmount' struct to be updated.
     * @param totalAmount The total amount to be subtracted.
     * @param rounding The rounding method to be used (up, down, or closest).
     * @return The updated 'InterestAccruingAmount' struct and the base amount corresponding to the subtracted total
     *         amount.
     */
    function sub(InterestAccruingAmount memory amount, uint256 totalAmount, Math.Rounding rounding)
        internal
        pure
        returns (InterestAccruingAmount memory, uint256 baseAmount)
    {
        if (totalAmount != 0) {
            if (totalAmount == amount.total) {
                baseAmount = amount.base;
                amount.base = amount.total = 0;
            } else {
                baseAmount = toBaseAmount(amount, totalAmount, rounding);
                amount.base -= baseAmount;
                amount.total -= totalAmount;
            }
        }
        return (amount, baseAmount);
    }

    /**
     * @dev Subtracts a base amount from an 'InterestAccruingAmount', updating both base and total values.
     *      Handles edge cases such as when the baseAmount equals the struct's base value.
     * @param amount The 'InterestAccruingAmount' struct to be updated.
     * @param baseAmount The base amount to be subtracted.
     * @param rounding The rounding method to be used (up, down, or closest).
     * @return The updated 'InterestAccruingAmount' struct and the total amount corresponding to the subtracted base
     *         amount.
     */
    function subBase(InterestAccruingAmount memory amount, uint256 baseAmount, Math.Rounding rounding)
        internal
        pure
        returns (InterestAccruingAmount memory, uint256 totalAmount)
    {
        if (baseAmount != 0) {
            if (baseAmount == amount.base) {
                totalAmount = amount.total;
                amount.base = amount.total = 0;
            } else {
                totalAmount = toTotalAmount(amount, baseAmount, rounding);
                amount.base -= baseAmount;
                amount.total -= totalAmount;
            }
        }
        return (amount, totalAmount);
    }
}
