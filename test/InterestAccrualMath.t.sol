// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/libraries/InterestAccrualMath.sol";

contract InterestAccrualMathTest is Test {
    InterestAccruingAmount amount1;
    InterestAccruingAmount amount2;
    InterestAccruingAmount amount3;

    function setUp() public {
        amount1 = InterestAccruingAmount({base: 100, total: 100});
        amount2 = InterestAccruingAmount({base: 100, total: 200});
        amount3 = InterestAccruingAmount({base: 100, total: 50});
    }

    function testToBaseAmount() public {
        assertEq(InterestAccrualMath.toBaseAmount(amount1, 100, Math.Rounding.Trunc), 100);
        assertEq(InterestAccrualMath.toBaseAmount(amount2, 100, Math.Rounding.Trunc), 50);
        assertEq(InterestAccrualMath.toBaseAmount(amount3, 100, Math.Rounding.Trunc), 200);
    }

    function testToTotalAmount() public {
        assertEq(InterestAccrualMath.toTotalAmount(amount1, 100, Math.Rounding.Trunc), 100);
        assertEq(InterestAccrualMath.toTotalAmount(amount2, 100, Math.Rounding.Trunc), 200);
        assertEq(InterestAccrualMath.toTotalAmount(amount3, 100, Math.Rounding.Trunc), 50);
    }

    function testAdd() public {
        InterestAccruingAmount memory amount;
        uint256 baseAmount;

        (amount, baseAmount) = InterestAccrualMath.add(amount1, 10, Math.Rounding.Trunc);
        assertEq(amount.base, 110);
        assertEq(amount.total, 110);
        assertEq(baseAmount, 10);

        (amount, baseAmount) = InterestAccrualMath.add(amount2, 10, Math.Rounding.Trunc);
        assertEq(amount.base, 105);
        assertEq(amount.total, 210);
        assertEq(baseAmount, 5);

        (amount, baseAmount) = InterestAccrualMath.add(amount3, 10, Math.Rounding.Trunc);
        assertEq(amount.base, 120);
        assertEq(amount.total, 60);
        assertEq(baseAmount, 20);
    }

    function testSub() public {
        InterestAccruingAmount memory amount;
        uint256 baseAmount;

        (amount, baseAmount) = InterestAccrualMath.sub(amount1, 10, Math.Rounding.Trunc);
        assertEq(amount.base, 90);
        assertEq(amount.total, 90);
        assertEq(baseAmount, 10);

        (amount, baseAmount) = InterestAccrualMath.sub(amount2, 10, Math.Rounding.Trunc);
        assertEq(amount.base, 95);
        assertEq(amount.total, 190);
        assertEq(baseAmount, 5);

        (amount, baseAmount) = InterestAccrualMath.sub(amount3, 10, Math.Rounding.Trunc);
        assertEq(amount.base, 80);
        assertEq(amount.total, 40);
        assertEq(baseAmount, 20);
    }

    function testSubBase() public {
        InterestAccruingAmount memory amount;
        uint256 totalAmount;

        (amount, totalAmount) = InterestAccrualMath.subBase(amount1, 10, Math.Rounding.Trunc);
        assertEq(amount.base, 90);
        assertEq(amount.total, 90);
        assertEq(totalAmount, 10);

        (amount, totalAmount) = InterestAccrualMath.subBase(amount2, 10, Math.Rounding.Trunc);
        assertEq(amount.base, 90);
        assertEq(amount.total, 180);
        assertEq(totalAmount, 20);

        (amount, totalAmount) = InterestAccrualMath.subBase(amount3, 10, Math.Rounding.Trunc);
        assertEq(amount.base, 90);
        assertEq(amount.total, 45);
        assertEq(totalAmount, 5);
    }
}
