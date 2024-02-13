// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract YieldTokenMock is ERC4626 {
    constructor(IERC20 underlying) ERC4626(underlying) ERC20("Yield Token", "YIELD") {}
}
