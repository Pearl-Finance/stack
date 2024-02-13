// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "./mocks/ERC20Mock.sol";
import "./mocks/AggregatorV3Mock.sol";
import "./mocks/AggregatorV3WrapperMock.sol";

contract AggregatorV3WrapperTest is Test {
    ERC20Mock token2;
    ERC20Mock token6;
    ERC20Mock token9;
    ERC20Mock token18;
    AggregatorV3WrapperMock oracle2;
    AggregatorV3WrapperMock oracle6;
    AggregatorV3WrapperMock oracle9;
    AggregatorV3WrapperMock oracle18;

    function setUp() public {
        AggregatorV3Mock aggregator = new AggregatorV3Mock(6);
        aggregator.setAnswer(1337e6);
        token2 = new ERC20Mock(2);
        token6 = new ERC20Mock(6);
        token9 = new ERC20Mock(9);
        token18 = new ERC20Mock(18);
        oracle2 = new AggregatorV3WrapperMock(address(token2), address(aggregator));
        oracle6 = new AggregatorV3WrapperMock(address(token6), address(aggregator));
        oracle9 = new AggregatorV3WrapperMock(address(token9), address(aggregator));
        oracle18 = new AggregatorV3WrapperMock(address(token18), address(aggregator));
    }

    function testAmountOf() public {
        assertEq(oracle2.amountOf(1337e18, Math.Rounding.Trunc), 1e2);
        assertEq(oracle6.amountOf(1337e18, Math.Rounding.Trunc), 1e6);
        assertEq(oracle9.amountOf(1337e18, Math.Rounding.Trunc), 1e9);
        assertEq(oracle18.amountOf(1337e18, Math.Rounding.Trunc), 1e18);
    }

    function testValueOf() public {
        assertEq(oracle2.valueOf(1e2, Math.Rounding.Trunc), 1337e18);
        assertEq(oracle6.valueOf(1e6, Math.Rounding.Trunc), 1337e18);
        assertEq(oracle9.valueOf(1e9, Math.Rounding.Trunc), 1337e18);
        assertEq(oracle18.valueOf(1e18, Math.Rounding.Trunc), 1337e18);
    }
}
