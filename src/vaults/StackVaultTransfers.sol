// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH9} from "../periphery/interfaces/IWETH9.sol";

/**
 * @title Stack Vault Transfer Helper
 * @notice Helper contract to facilitate transfers of collateral in and out of vaults.
 * @dev This contract is used by StackVaults to transfer collateral in and out of the vault.
 * @author SeaZarrgh LaBuoy
 */
contract StackVaultTransfers {
    using SafeERC20 for IERC20;

    /**
     * @dev Function to transfer collateral into a vault. Should be called via delegatecall from a StackVault.
     * @param from The address from which to transfer the collateral.
     * @param amount The amount of collateral to transfer.
     */
    function transferCollateralIn(bool isNative, IWETH9 weth, IERC20 collateralToken, address from, uint256 amount)
        external
        payable
        returns (uint256 received)
    {
        if (isNative) {
            received = _transferNativeIn(weth, from, amount);
        } else {
            require(msg.value == 0, "StackVault: Unexpected ETH value");
            address to = address(this);
            uint256 balanceBefore = collateralToken.balanceOf(to);
            collateralToken.safeTransferFrom(from, to, amount);
            received = collateralToken.balanceOf(to) - balanceBefore;
        }
    }

    /**
     * @dev Function to transfer collateral out of a vault. Should be called via delegatecall from a StackVault.
     * @param to The address to which to transfer the collateral.
     * @param amount The amount of collateral to transfer.
     */
    function transferCollateralOut(bool isNative, IWETH9 weth, IERC20 collateralToken, address to, uint256 amount)
        external
        returns (uint256 sent)
    {
        if (isNative) {
            sent = _transferNativeOut(weth, to, amount);
        } else {
            address from = address(this);
            uint256 balanceBefore = collateralToken.balanceOf(from);
            collateralToken.safeTransfer(to, amount);
            sent = balanceBefore - collateralToken.balanceOf(from);
        }
    }

    /**
     * @dev Internal function to transfer ETH (or WETH) into the vault.
     * @param from The address from which to transfer the ETH.
     * @param amount The amount of ETH to transfer.
     */
    function _transferNativeIn(IWETH9 weth, address from, uint256 amount) internal returns (uint256 received) {
        if (msg.value == 0) {
            weth.transferFrom(from, address(this), amount);
        } else {
            require(msg.value == amount, "StackVault: Incorrect ETH value");
            weth.deposit{value: amount}();
        }
        received = amount;
    }

    /**
     * @dev Internal function to transfer ETH (or WETH) out of the vault.
     * @param to The address to which to transfer the ETH.
     * @param amount The amount of ETH to transfer.
     */
    function _transferNativeOut(IWETH9 weth, address to, uint256 amount) internal returns (uint256 sent) {
        weth.withdraw(amount);
        (bool success,) = to.call{value: amount}("");
        if (!success) {
            weth.deposit{value: amount}();
            success = weth.transfer(to, amount);
        }
        require(success, "StackVault: Failed to send ETH");
        sent = amount;
    }
}
