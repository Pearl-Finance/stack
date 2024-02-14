// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

/**
 * @title Uniswap V3 Quoter Interface
 * @notice Interface for the Uniswap V3 Quoter, providing functionality for fetching quotes for trades on Uniswap V3.
 * @dev This interface defines methods for getting quotes for both exact input and exact output single token swaps.
 */
interface IQuoter {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    struct QuoteExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountOut;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    /**
     * @notice Fetches a quote for a swap with an exact input amount.
     * @param params Struct containing parameters such as token addresses, input amount, fee, and other details.
     * @return amountOut The amount of output tokens that can be received for the given input.
     * @return sqrtPriceX96After The square root price after the swap.
     * @return initializedTicksCrossed The number of ticks initialized as a result of the swap.
     * @return gasEstimate An estimate of the gas cost for the swap.
     */
    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);

    /**
     * @notice Fetches a quote for a swap with an exact input amount.
     * @param path The path of the tokens to be swapped.
     * @param amountIn The amount of input tokens to be swapped.
     * @return amountOut The amount of output tokens that can be received for the given input.
     * @return sqrtPriceX96AfterList The square root prices along the path after the swap.
     * @return initializedTicksCrossedList The number of ticks initialized along the path as a result of the swap.
     * @return gasEstimate An estimate of the gas cost for the swap.
     */
    function quoteExactInput(bytes memory path, uint256 amountIn)
        external
        returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        );

    /**
     * @notice Fetches a quote for a swap with an exact output amount.
     * @param params Struct containing parameters such as token addresses, output amount, fee, and other details.
     * @return amountIn The amount of input tokens required to receive the given output.
     * @return sqrtPriceX96After The square root price after the swap.
     * @return initializedTicksCrossed The number of ticks initialized as a result of the swap.
     * @return gasEstimate An estimate of the gas cost for the swap.
     */
    function quoteExactOutputSingle(QuoteExactOutputSingleParams memory params)
        external
        returns (uint256 amountIn, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);

    /**
     * @notice Fetches a quote for a swap with an exact output amount.
     * @param path The path of the tokens to be swapped.
     * @param amountOut The amount of output tokens to be received.
     * @return amountIn The amount of input tokens required to receive the given output.
     * @return sqrtPriceX96AfterList The square root prices along the path after the swap.
     * @return initializedTicksCrossedList The number of ticks initialized along the path as a result of the swap.
     * @return gasEstimate An estimate of the gas cost for the swap.
     */
    function quoteExactOutput(bytes memory path, uint256 amountOut)
        external
        returns (
            uint256 amountIn,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        );
}
