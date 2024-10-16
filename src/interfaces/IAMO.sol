// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IAMO {
    function liquidity() external view returns (uint256, uint256);
}
