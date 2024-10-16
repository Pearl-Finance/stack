// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract ERC20Holder is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    function rescueERC20(address token) external onlyOwner {
        IERC20 _token = IERC20(token);
        _rescueERC20(_token, msg.sender, _token.balanceOf(address(this)));
    }

    function rescueERC20(address token, uint256 amount) external onlyOwner {
        _rescueERC20(IERC20(token), msg.sender, amount);
    }

    function _rescueERC20(IERC20 token, address to, uint256 amount) private {
        token.safeTransfer(to, amount);
    }
}
