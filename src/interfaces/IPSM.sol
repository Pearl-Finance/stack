// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IPSM {
    function mint(address to, uint256 amount, uint256 minAmountOut) external;
    function redeem(address to, uint256 amount, uint256 minAmountOut) external;
    function mintingAllowed() external view returns (bool);
    function maxRedeemAmount() external view returns (uint256);
    function redeemingAllowed() external view returns (bool);
}
