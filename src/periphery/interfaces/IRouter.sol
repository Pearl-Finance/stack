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

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    /**
     * @notice Executes a single token swap with exact input parameters on Uniswap V3.
     * @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata.
     * @return amountOut The amount of output tokens received from the swap.
     */
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    /**
     * @notice Executes a single token swap with exact input parameters on Uniswap V3, specifically designed for tokens
     * that include transfer fees.
     * @dev This function is similar to `exactInputSingle` but is tailored for use with tokens that apply a transfer
     * fee. It takes into account the reduced amount of tokens received after transfer fees are deducted.
     * @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata. These
     * include the input and output token addresses, the fee tier, the recipient address, the deadline for the swap, the
     * input amount, the minimum output amount, and the price limit.
     * @return amountOut The amount of output tokens received from the swap, accounting for any transfer fees deducted
     * by the input token.
     */
    function exactInputSingleFeeOnTransfer(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);

    /**
     * @notice Executes a swap with exact input parameters on Uniswap V3.
     * @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata.
     * @return amountOut The amount of output tokens received from the swap.
     */
    function exactInput(ExactInputParams memory params) external payable returns (uint256 amountOut);

    /**
     * @notice Executes a swap with exact input parameters on Uniswap V3 for tokens that include transfer fees,
     * potentially involving multiple hops.
     * @dev Similar to `exactInput`, this function accommodates tokens with transfer fees during the swap process. It
     * considers the impact of transfer fees on the swap amount, ensuring the output meets or exceeds the specified
     * minimum after fees.
     * @param params The parameters for the swap, encoded as `ExactInputParams` in calldata. This includes the path for
     * multi-hop swaps, the recipient address, the deadline, the input amount, and the minimum amount of output tokens
     * expected from the swap.
     * @return amountOut The final amount of output tokens received, post-transfer fees.
     */
    function exactInputFeeOnTransfer(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}
