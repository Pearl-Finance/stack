// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {IMinter} from "../../src/interfaces/IMinter.sol";
import {ERC20Mock} from "./ERC20Mock.sol";

contract ERC20MockMinter is IMinter {
    address public immutable token;

    constructor(address mockToken) {
        token = mockToken;
    }

    function mint(address to, uint256 amount) external {
        ERC20Mock(token).mint(to, amount);
    }
}
