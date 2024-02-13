// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Constants} from "../libraries/Constants.sol";

/**
 * @title FeeMath Library
 * @notice Provides functions for calculating fee amounts based on given parameters.
 * @dev This library uses the OpenZeppelin's Math library for safe mathematical operations and constants from the
 *      Constants library. It includes functions that calculate the fee amount using a specified fee rate, with support
 *      for different rounding methods.
 * @author SeaZarrgh LaBuoy
 */
library FeeMath {
    using Math for uint256;

    /**
     * @dev Calculates the fee amount for a given amount and fee rate.
     * @param amount The principal amount on which the fee is calculated.
     * @param fee The fee rate, scaled by the FEE_PRECISION constant from the Constants library.
     * @return feeAmount The calculated fee amount.
     */
    function calculateFeeAmount(uint256 amount, uint256 fee) internal pure returns (uint256 feeAmount) {
        feeAmount = amount.mulDiv(fee, Constants.FEE_PRECISION);
    }

    /**
     * @dev Calculates the fee amount for a given amount and fee rate, with a specified rounding method.
     * @param amount The principal amount on which the fee is calculated.
     * @param fee The fee rate, scaled by the FEE_PRECISION constant from the Constants library.
     * @param rounding The rounding method to be used (up, down, or closest).
     * @return feeAmount The calculated fee amount with the specified rounding method.
     */
    function calculateFeeAmount(uint256 amount, uint256 fee, Math.Rounding rounding)
        internal
        pure
        returns (uint256 feeAmount)
    {
        feeAmount = amount.mulDiv(fee, Constants.FEE_PRECISION, rounding);
    }
}
