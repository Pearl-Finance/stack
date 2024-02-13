// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {ERC20BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20FlashMintUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20FlashMintUpgradeable.sol";

import "../interfaces/IERC20Mintable.sol";

/**
 * @title Borrow Token Contract
 * @notice Abstract contract representing a borrowable token with burning, flash minting, and custom minting
 *         capabilities.
 * @dev Extends ERC20BurnableUpgradeable and ERC20FlashMintUpgradeable from OpenZeppelin to provide burn and flash mint
 *      functionalities.
 *      Implements IERC20Mintable to include custom minting logic specific to the Stack ecosystem.
 *      This token is used within the vault system for borrowing operations and other financial activities.
 * @author SeaZarrgh LaBuoy
 */
abstract contract BorrowToken is ERC20BurnableUpgradeable, ERC20FlashMintUpgradeable, IERC20Mintable {}
