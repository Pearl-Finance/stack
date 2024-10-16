// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGauge is IERC20 {
    function TOKEN() external view returns (address);
    function rewardToken() external view returns (address);
    function getReward() external;
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
}
