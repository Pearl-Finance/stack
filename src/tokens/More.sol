// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC3156FlashBorrower, IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20FlashMintUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20FlashMintUpgradeable.sol";

import {OFTUpgradeable} from "@tangible/contracts/layerzero/token/oft/v1/OFTUpgradeable.sol";
import {CrossChainToken} from "@tangible/contracts/tokens/CrossChainToken.sol";

import {IERC20Mintable} from "../interfaces/IERC20Mintable.sol";
import {BorrowToken} from "./BorrowToken.sol";

/**
 * @title More Token Contract
 * @notice An advanced ERC20 token supporting cross-chain transfers, flash minting, and custom minting.
 * @dev Inherits from:
 *      - `BorrowToken` for basic token functionalities including burn and flash mint.
 *      - `CrossChainToken` and `OFTUpgradeable` for cross-chain transfer capabilities.
 *      - `ReentrancyGuardUpgradeable` for protection against reentrancy attacks.
 *      - `UUPSUpgradeable` for upgradeability.
 *      The contract includes a custom minting function controlled by a designated minter or the contract owner.
 * @author SeaZarrgh LaBuoy
 */
contract More is BorrowToken, CrossChainToken, OFTUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    address public minter;

    /**
     * @notice Initializes the More contract.
     * @dev Sets up the contract with cross-chain token functionalities. Disables initializers to prevent
     *      reinitialization after an upgrade.
     * @param mainChainId The chain ID of the main chain for cross-chain functionality.
     * @param endpoint The LayerZero endpoint for cross-chain communication.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(uint256 mainChainId, address endpoint) CrossChainToken(mainChainId) OFTUpgradeable(endpoint) {
        _disableInitializers();
    }

    /**
     * @notice Authorizes an upgrade to a new contract implementation.
     * @dev Internal function to authorize upgrading the contract to a new implementation.
     *      Overrides the UUPSUpgradeable `_authorizeUpgrade` function.
     *      Restricted to the contract owner.
     * @param newImplementation The address of the new contract implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Initializes the More token with its minter.
     * @dev Sets up the token name, symbol, and the minter address. Initializes reentrancy guard.
     *      Can only be called once due to the `initializer` modifier.
     * @param _minter The address authorized to mint new tokens.
     */
    function initialize(address _minter) external initializer {
        __OFT_init(msg.sender, "MORE", "MORE");
        __ReentrancyGuard_init();
        setMinter(_minter);
    }

    /**
     * @notice Sets or updates the minter address.
     * @dev Updates the minter address. Only the contract owner can perform this operation.
     * @param _minter The new address authorized to mint new tokens.
     */
    function setMinter(address _minter) public onlyOwner {
        minter = _minter;
    }

    /**
     * @notice Mints new tokens to a specified address.
     * @dev Custom minting function restricted to the minter or the contract owner. Asserts that the contract is on the
     *      main chain.
     * @param to The address to receive the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external {
        assert(isMainChain);
        if (minter != msg.sender && owner() != msg.sender) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
        _mint(to, amount);
    }

    /**
     * @notice Internal function for debiting tokens during cross-chain transfers.
     * @dev Handles the token balance updates when tokens are debited for cross-chain transfer.
     *      Invoked by the OFT logic to transfer tokens out to another chain.
     *      Can be overridden for custom behavior.
     * @param from The address from which tokens are debited.
     * @param amount The amount of tokens to debit.
     * @return The actual amount of tokens debited.
     */
    function _debitFrom(address from, uint16, bytes memory, uint256 amount)
        internal
        virtual
        override
        returns (uint256)
    {
        if (from != msg.sender) {
            _spendAllowance(from, msg.sender, amount);
        }
        _update(from, address(0), amount);
        return amount;
    }

    /**
     * @notice Internal function for crediting tokens during cross-chain transfers.
     * @dev Handles the token balance updates when tokens are credited from a cross-chain transfer.
     *      Invoked by the OFT logic to receive tokens from another chain.
     *      Can be overridden for custom behavior.
     * @param toAddress The address on this chain to receive the tokens.
     * @param amount The amount of tokens to credit.
     * @return The actual amount of tokens credited.
     */
    function _creditTo(uint16, address toAddress, uint256 amount) internal virtual override returns (uint256) {
        _update(address(0), toAddress, amount);
        return amount;
    }
}
