// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface ISpotPriceOracle {
    function currentPrice() external view returns (uint256, uint256);
}
