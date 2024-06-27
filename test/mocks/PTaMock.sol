// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PTaMock is ERC20 {
    using SafeERC20 for IERC20;

    uint8 public _decimals;
    IERC20 public usdt;

    constructor(uint8 decimals_, address _usdt) ERC20("PTaMock", "PTM") {
        usdt = IERC20(_usdt);
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function deposit(uint256 amount, address to) external returns (uint256) {
        usdt.safeTransferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
        return amount;
    }

    function redeem(uint256 amount, address to) external returns (uint256) {
        _burn(msg.sender, amount);
        usdt.safeTransfer(to, amount);
        return amount;
    }

    function previewDeposit(address to, uint256 amount) external view returns (uint256) {
        return amount;
    }

    function previewRedeem(address to, uint256 amount) external view returns (uint256) {
        return amount;
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function testExcludeContractForCoverage() external {}
}
