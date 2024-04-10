// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RebaseTokenMath} from "@tangible/contracts/libraries/RebaseTokenMath.sol";

import {ITokenConverter} from "../interfaces/ITokenConverter.sol";

interface IDJPT {
    function deposit(uint256 assets, address recipient) external returns (uint256 shares);
    function redeem(uint256 shares, address recipient) external returns (uint256 assets);
}

/**
 * @title DJUSD Token Converter
 * @dev Provides functionality to convert between djUSD and djPT tokens. This contract handles the approval and
 * calling of the deposit and redeem functions in the DJPointsToken contract.
 * @author SeaZarrgh LaBuoy
 */
contract DJUSDTokenConverter is ITokenConverter {
    address public immutable DJUSD;
    address public immutable DJPT;

    /**
     * @dev Initializes the contract with djUSD and djPT token addresses.
     * @param djusd The address of the djUSD token.
     * @param djpt The address of the djPT token.
     */
    constructor(address djusd, address djpt) {
        DJUSD = djusd;
        DJPT = djpt;
    }

    /**
     * @notice Converts an amount of one token (djUSD or djPT) to the other.
     * @dev Approves the necessary amount of tokens and calls the deposit or redeem function on the DJPointsToken
     * contract, depending on the conversion direction.
     * @param tokenIn The token address to convert from.
     * @param tokenOut The token address to convert to.
     * @param amountIn The amount of the input token to convert.
     * @param receiver The address that will receive the output tokens.
     * @return amountOut The amount of the output token received after conversion.
     */
    function convert(address tokenIn, address tokenOut, uint256 amountIn, address receiver)
        external
        override
        returns (uint256 amountOut)
    {
        if (tokenIn == DJUSD && tokenOut == DJPT) {
            IERC20(DJUSD).approve(DJPT, amountIn);
            amountOut = IDJPT(DJPT).deposit(amountIn, receiver);
        } else if (tokenIn == DJPT && tokenOut == DJUSD) {
            amountOut = IDJPT(DJPT).redeem(amountIn, receiver);
        } else {
            revert InvalidConversionRequest();
        }
    }
}
