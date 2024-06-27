// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock2 is ERC20 {
    uint8 public _decimals;
    address receiver;

    constructor(uint8 decimals_, address _receiver) ERC20("Mock", "MOCK") {
        _decimals = decimals_;
        receiver = _receiver;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    receive() external payable {
        require(msg.sender == receiver);
    }

    function testExcludeContractForCoverage() external {}
}
