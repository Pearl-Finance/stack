// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {BorrowInterestRateAdjustmentMath as Math} from "src/libraries/BorrowInterestRateAdjustmentMath.sol";

contract BorrowInterestRateAdjustmentMathTest is Test {
    uint256 constant PREFERRED_PRICE = 1e18;

    function testFormula10PercentRate() public {
        uint256 currentRate = 0.1e18;
        assertEq(adjustAndTrim(currentRate, 0.5e18, PREFERRED_PRICE), 0.1199e18);
        assertEq(adjustAndTrim(currentRate, 0.9e18, PREFERRED_PRICE), 0.118e18);
        assertEq(adjustAndTrim(currentRate, 1.0e18, PREFERRED_PRICE), currentRate);
        assertEq(adjustAndTrim(currentRate, 1.005e18, PREFERRED_PRICE), 0.08563e18);
        assertEq(adjustAndTrim(currentRate, 1.01e18, PREFERRED_PRICE), 0.082e18);
    }

    function testFormula1PercentRate() public {
        uint256 currentRate = 0.01e18;
        assertEq(adjustAndTrim(currentRate, 0.5e18, PREFERRED_PRICE), 0.01995e18);
        assertEq(adjustAndTrim(currentRate, 0.9e18, PREFERRED_PRICE), 0.019e18);
        assertEq(adjustAndTrim(currentRate, 1.0e18, PREFERRED_PRICE), currentRate);
        assertEq(adjustAndTrim(currentRate, 1.005e18, PREFERRED_PRICE), 0.00856e18);
        assertEq(adjustAndTrim(currentRate, 1.01e18, PREFERRED_PRICE), 0.0082e18);
    }

    function testFormula0PercentRate() public {
        uint256 currentRate = 0;
        assertEq(adjustAndTrim(currentRate, 0.5e18, PREFERRED_PRICE), 0.00995e18);
        assertEq(adjustAndTrim(currentRate, 0.9e18, PREFERRED_PRICE), 0.009e18);
        assertEq(adjustAndTrim(currentRate, 1.0e18, PREFERRED_PRICE), currentRate);
        assertEq(adjustAndTrim(currentRate, 1.005e18, PREFERRED_PRICE), currentRate);
        assertEq(adjustAndTrim(currentRate, 1.01e18, PREFERRED_PRICE), currentRate);
    }

    function adjustAndTrim(uint256 currentRate, uint256 tokenPrice, uint256 preferredPrice)
        private
        pure
        returns (uint256)
    {
        return Math.adjustBorrowInterestRate(currentRate, tokenPrice, preferredPrice) / 1e13 * 1e13;
    }
}
