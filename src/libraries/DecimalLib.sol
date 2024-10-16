// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library DecimalLib {
    error RoundingModeRequired();

    function convertDecimals(uint256 amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals > toDecimals) {
            revert RoundingModeRequired();
        }
        return convertDecimals(amount, fromDecimals, toDecimals, Math.Rounding.Trunc);
    }

    function convertDecimals(uint256 amount, uint8 fromDecimals, uint8 toDecimals, Math.Rounding rounding)
        internal
        pure
        returns (uint256)
    {
        if (fromDecimals == toDecimals) {
            return amount;
        }

        uint256 scale;

        if (fromDecimals < toDecimals) {
            unchecked {
                scale = 10 ** (toDecimals - fromDecimals);
            }
            return amount * (10 ** (toDecimals - fromDecimals));
        }

        uint256 result;

        unchecked {
            scale = 10 ** (fromDecimals - toDecimals);
            result = amount / scale;
        }

        if (rounding == Math.Rounding.Trunc || rounding == Math.Rounding.Floor) {
            return result;
        }

        uint256 remainder;

        unchecked {
            remainder = amount % scale;
        }

        if (remainder != 0) {
            return result + 1;
        }

        return result;
    }
}
