// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RebaseTokenMath} from "@tangible/contracts/libraries/RebaseTokenMath.sol";

import {ITokenConverter} from "../interfaces/ITokenConverter.sol";

interface IPTa {
    function deposit(uint256 assets, address recipient) external returns (uint256 shares);
    function redeem(uint256 shares, address recipient) external returns (uint256 assets);
    function previewDeposit(address to, uint256 assets) external pure returns (uint256 shares);
    function previewRedeem(address from, uint256 shares) external view returns (uint256 assets);
}

/**
 * @title Arcana Token Converter
 * @dev Provides functionality to convert between USDa and PTa tokens. This contract handles the approvals and
 * calls to the deposit and redeem functions in the PTa contract, as well as previews of such conversions.
 * @author SeaZarrgh LaBuoy
 */
contract ArcanaTokenConverter is ITokenConverter {
    address public immutable USDA;
    address public immutable PTA;

    /**
     * @dev Initializes the contract with USDa and PTa token addresses.
     * @param usda The address of the USDa token.
     * @param pta The address of the PTa token.
     */
    constructor(address usda, address pta) {
        USDA = usda;
        PTA = pta;
    }

    /**
     * @notice Provides a preview of the conversion output for a given input token amount.
     * @dev Returns the estimated number of output tokens one would receive for converting a specific
     * amount of input tokens. Does not perform any state-changing operations.
     * @param tokenIn The token address to convert from.
     * @param tokenOut The token address to convert to.
     * @param amountIn The amount of the input token to convert.
     * @param receiver The address that would receive the output tokens. Used for calculating fees or limits that may
     * depend on the recipient.
     * @return amountOut The estimated amount of the output token that would be received.
     */
    function previewConvert(address tokenIn, address tokenOut, uint256 amountIn, address receiver)
        external
        view
        override
        returns (uint256 amountOut)
    {
        if (tokenIn == USDA && tokenOut == PTA) {
            amountOut = IPTa(PTA).previewDeposit(receiver, amountIn);
        } else if (tokenIn == PTA && tokenOut == USDA) {
            amountOut = IPTa(PTA).previewRedeem(receiver, amountIn);
        } else {
            revert InvalidConversionRequest();
        }
    }

    /**
     * @notice Converts an amount of one token (USDa or PTa) to the other.
     * @dev Approves the necessary amount of tokens and calls the deposit or redeem function on the PTa
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
        if (tokenIn == USDA && tokenOut == PTA) {
            IERC20(USDA).approve(PTA, amountIn);
            amountOut = IPTa(PTA).deposit(amountIn, receiver);
        } else if (tokenIn == PTA && tokenOut == USDA) {
            amountOut = IPTa(PTA).redeem(amountIn, receiver);
        } else {
            revert InvalidConversionRequest();
        }
    }
}
