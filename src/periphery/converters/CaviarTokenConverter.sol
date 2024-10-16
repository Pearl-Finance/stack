// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {ITokenConverter} from "../interfaces/ITokenConverter.sol";

interface IStakedCaviar {
    function stake(uint256 amount, address recipient) external returns (uint256);
    function unstake(uint256 amount, address recipient) external returns (uint256);
    function underlying() external view returns (address);
}

/**
 * @title Caviar Token Converter
 * @dev Provides functionality to convert between CVR, sCVR, and csCVR tokens by interacting with their respective
 * contracts. Handles the necessary token approvals and calls the stake, unstake, deposit, and redeem functions
 * appropriately.
 * @author SeaZarrgh LaBuoy
 */
contract CaviarTokenConverter is ITokenConverter {
    address public immutable CVR;
    address public immutable sCVR;
    address public immutable csCVR;

    /**
     * @dev Initializes the converter with the addresses of the CVR, sCVR, and csCVR tokens.
     * @param cscvr Address of the csCVR token contract.
     */
    constructor(address cscvr) {
        address scvr = IERC4626(cscvr).asset();
        address cvr = IStakedCaviar(scvr).underlying();
        CVR = cvr;
        sCVR = scvr;
        csCVR = cscvr;
    }

    /**
     * @notice Provides a preview of the output amount for a given conversion request without changing the state.
     * @dev Calculates the amount of tokens one would receive for a given input amount during a token conversion.
     * This function only simulates the conversion and does not perform any actual token transfers.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of the input token to convert.
     * @return amountOut The estimated amount of the output token that would be received.
     */
    function previewConvert(address tokenIn, address tokenOut, uint256 amountIn, address /*receiver*/ )
        external
        view
        override
        returns (uint256 amountOut)
    {
        if (tokenIn == CVR) {
            if (tokenOut == sCVR) {
                amountOut = amountIn;
            } else if (tokenOut == csCVR) {
                amountOut = IERC4626(csCVR).previewDeposit(amountIn);
            } else {
                revert InvalidConversionRequest();
            }
        } else if (tokenIn == sCVR) {
            if (tokenOut == CVR) {
                amountOut = amountIn;
            } else if (tokenOut == csCVR) {
                amountOut = IERC4626(csCVR).previewDeposit(amountIn);
            } else {
                revert InvalidConversionRequest();
            }
        } else if (tokenIn == csCVR) {
            if (tokenOut == CVR || tokenOut == sCVR) {
                amountOut = IERC4626(csCVR).previewRedeem(amountIn);
            } else {
                revert InvalidConversionRequest();
            }
        } else {
            revert InvalidConversionRequest();
        }
    }

    /**
     * @notice Converts an amount of one token (CVR, sCVR, or csCVR) to another.
     * @dev Handles the token conversion by performing necessary token approvals and calling the appropriate stake,
     * unstake, deposit, or redeem functions.
     * @param tokenIn The address of the token to convert from.
     * @param tokenOut The address of the token to convert to.
     * @param amountIn The amount of the token to convert.
     * @param receiver The address that will receive the output token.
     * @return amountOut The actual amount of the output token received after the conversion.
     */
    function convert(address tokenIn, address tokenOut, uint256 amountIn, address receiver)
        external
        override
        returns (uint256 amountOut)
    {
        if (tokenIn == CVR) {
            if (tokenOut == sCVR) {
                IERC20(CVR).approve(sCVR, amountIn);
                amountOut = IStakedCaviar(sCVR).stake(amountIn, receiver);
            } else if (tokenOut == csCVR) {
                IERC20(CVR).approve(sCVR, amountIn);
                amountOut = IStakedCaviar(sCVR).stake(amountIn, address(this));
                IERC20(sCVR).approve(csCVR, amountOut);
                amountOut = IERC4626(csCVR).deposit(amountIn, receiver);
            } else {
                revert InvalidConversionRequest();
            }
        } else if (tokenIn == sCVR) {
            if (tokenOut == CVR) {
                amountOut = IStakedCaviar(sCVR).unstake(amountIn, receiver);
            } else if (tokenOut == csCVR) {
                IERC20(sCVR).approve(csCVR, amountIn);
                amountOut = IERC4626(csCVR).deposit(amountIn, receiver);
            } else {
                revert InvalidConversionRequest();
            }
        } else if (tokenIn == csCVR) {
            if (tokenOut == CVR) {
                amountOut = IERC4626(csCVR).redeem(amountIn, address(this), address(this));
                amountOut = IStakedCaviar(sCVR).unstake(amountIn, receiver);
            } else if (tokenOut == sCVR) {
                amountOut = IERC4626(csCVR).redeem(amountIn, receiver, address(this));
            } else {
                revert InvalidConversionRequest();
            }
        } else {
            revert InvalidConversionRequest();
        }
    }
}
