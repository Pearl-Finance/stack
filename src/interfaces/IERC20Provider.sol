// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IERC20Provider {
    function requestTokens(address token, uint256 amount) external;
    function requestTokensFor(address token, uint256 amount, address receiver) external;
}
