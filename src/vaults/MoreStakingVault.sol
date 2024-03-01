// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title More Staking Vault Contract
 * @notice Contract for staking MORE tokens, compliant with the ERC4626 standard for tokenized vaults.
 * @dev Inherits from:
 *      - `ERC4626Upgradeable` for standard vault functionalities.
 *      - `OwnableUpgradeable` and `UUPSUpgradeable` for ownership management and upgrade functionality.
 *      The contract provides a structured way for users to stake MORE tokens and potentially earn yield.
 * @author SeaZarrgh LaBuoy
 */
contract MoreStakingVault is ERC4626Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    /**
     * @notice Initializes the More Staking Vault with the MORE token and custom names.
     * @dev Sets up the staking vault with a specified MORE token address and custom token names.
     *      Initializes the contract as an ERC4626 tokenized vault.
     *      Can only be called once due to the `initializer` modifier.
     * @param more The address of the MORE token to be staked.
     * @param chainName The name of the chain to include in the vault's token name.
     * @param chainSymbol The symbol of the chain to include in the vault's token symbol.
     */
    function initialize(address more, string memory chainName, string memory chainSymbol) external initializer {
        string memory name = string.concat("Staked MORE (", chainName, ")");
        string memory symbol = string.concat("sMORE-", chainSymbol);
        __Ownable_init(msg.sender);
        __ERC20_init(name, symbol);
        __ERC4626_init(IERC20(more));
    }

    /**
     * @notice Authorizes an upgrade to a new contract implementation.
     * @dev Internal function to authorize upgrading the contract to a new implementation.
     *      Overrides the UUPSUpgradeable `_authorizeUpgrade` function.
     *      Restricted to the contract owner.
     * @param newImplementation The address of the new contract implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _decimalsOffset() internal view virtual override returns (uint8) {
        return 1;
    }
}
