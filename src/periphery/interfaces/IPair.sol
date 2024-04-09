// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

interface IPair {
    function fee() external view returns (uint24);
    function token0() external view returns (address);
    function token1() external view returns (address);
}
