// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockSwap {
    using SafeERC20 for IERC20;

    address public token0;
    address public token1;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function swap(address _token0, address _token1, uint256 amount) external {
        IERC20(_token0).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(_token1).safeTransfer(msg.sender, amount);
    }

    function swapForLess(address _token0, address _token1, uint256 amount) external {
        IERC20(_token0).safeTransferFrom(msg.sender, address(this), amount / 2);
        IERC20(_token1).safeTransfer(msg.sender, amount / 2);
    }

    function testExcludeContractForCoverage() external {}
}
