// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

interface ITokenConverter {
    error InvalidConversionRequest();

    function convert(address tokenIn, address tokenOut, uint256 amountIn, address receiver)
        external
        returns (uint256 amountOut);
}
