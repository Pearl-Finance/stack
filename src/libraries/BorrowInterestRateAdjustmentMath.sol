// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Constants} from "../libraries/Constants.sol";

/**
 * @title Borrow Interest Rate Adjustment Math Library
 * @notice Provides functions to adjust the borrow interest rate based on the token price in comparison to a preferred
 *         price.
 * @dev Utilizes a sigmoid function for the calculation of rate adjustments. Adjustments can be both additive and
 *      multiplicative, based on the deviation of the token price from the preferred price. The library leverages
 *      OpenZeppelin's Math library for safe mathematical operations and constants from the Constants library.
 * @author SeaZarrgh LaBuoy, Chad Farmer
 */
library BorrowInterestRateAdjustmentMath {
    uint256 private constant P = Constants.INTEREST_RATE_PRECISION;

    uint256 public constant MULTIPLICATIVE_ADJUSTMENT_RANGE = P / 5; // 20%
    uint256 public constant ADDITIVE_ADJUSTMENT_RANGE_ABOVE = P / 1000; // 0.1%
    uint256 public constant ADDITIVE_ADJUSTMENT_RANGE_BELOW = P / 100; // 1%

    /**
     * @notice Factor determining the steepness of the sigmoid curve below the preferred price.
     * @custom:formula (1/9^2 - 1/10^2) = (1/81 - 1/100) = (100/8100 - 81/8100) = (100 - 81)/8100 = 19/8100
     */
    uint256 public constant CURVE_STEEPNESS_FACTOR_BELOW = 19 * P * P / 8100;

    /**
     * @notice Factor determining the steepness of the sigmoid curve above the preferred price.
     * @custom:formula (1/90^2 - 1/100^2) = (1/8100 - 1/10000)
     *                                    = (100/810000 - 81/810000)
     *                                    = (100 - 81)/810000
     *                                    = 19/810000
     */
    uint256 public constant CURVE_STEEPNESS_FACTOR_ABOVE = 19 * P * P / 810_000;

    /**
     * @dev Adjusts the borrow interest rate based on the token price in relation to the preferred price.
     *      The adjustment can be either an increase or decrease in the rate, based on whether the token price
     *      is below or above the preferred price respectively.
     * @param currentRate The current borrow interest rate.
     * @param tokenPrice The current price of the token.
     * @param preferredPrice The preferred price of the token for optimal interest rate.
     * @return adjustedRate The adjusted borrow interest rate.
     */
    function adjustBorrowInterestRate(uint256 currentRate, uint256 tokenPrice, uint256 preferredPrice)
        internal
        pure
        returns (uint256 adjustedRate)
    {
        uint256 delta;
        uint256 steepness;
        uint256 additiveRange;
        if (tokenPrice < preferredPrice) {
            unchecked {
                delta = preferredPrice - tokenPrice;
                additiveRange = ADDITIVE_ADJUSTMENT_RANGE_BELOW;
                steepness = CURVE_STEEPNESS_FACTOR_BELOW;
            }
        } else {
            unchecked {
                delta = tokenPrice - preferredPrice;
                additiveRange = ADDITIVE_ADJUSTMENT_RANGE_ABOVE;
                steepness = CURVE_STEEPNESS_FACTOR_ABOVE;
            }
        }

        uint256 multiplicative = sigmoid(delta, MULTIPLICATIVE_ADJUSTMENT_RANGE, steepness);
        uint256 additive = sigmoid(delta, additiveRange, steepness);
        uint256 adjustment = Math.max(currentRate * multiplicative / P, additive);

        if (tokenPrice < preferredPrice) {
            adjustedRate = currentRate + adjustment;
        } else if (currentRate > adjustment) {
            unchecked {
                adjustedRate = currentRate - adjustment;
            }
        }
    }

    /**
     * @dev Private function implementing a sigmoid curve for calculating the adjustment factor.
     * @param x The delta between the token price and the preferred price.
     * @param a The range of the adjustment (additive or multiplicative).
     * @param s The steepness factor of the sigmoid curve.
     * @return The adjustment factor calculated using a sigmoid function.
     */
    function sigmoid(uint256 x, uint256 a, uint256 s) private pure returns (uint256) {
        // slither-disable-next-line divide-before-multiply
        return a * (x * P / Math.sqrt(s + x * x)) / P;
    }
}
