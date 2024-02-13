// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

/**
 * @title Uniswap V3 Router Interface
 * @notice Interface for the Uniswap V3 Router, providing functionality for executing trades on Uniswap V3.
 * @dev This interface defines methods for single input token swaps with exact parameters.
 */
interface IRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /**
     * @notice Executes a single token swap with exact input parameters on Uniswap V3.
     * @param params Struct containing swap parameters such as token addresses, fee, amounts, and other trade details.
     * @return amountOut The amount of output tokens received from the swap.
     */
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}
