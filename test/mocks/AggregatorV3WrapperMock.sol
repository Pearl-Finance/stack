// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/oracles/AggregatorV3Wrapper.sol";

contract AggregatorV3WrapperMock is AggregatorV3Wrapper {
    constructor(address _token, address _aggregator) AggregatorV3Wrapper(_token, _aggregator) {}
}
