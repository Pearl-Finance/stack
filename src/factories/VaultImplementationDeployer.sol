// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {StackVault} from "../vaults/StackVault.sol";

/**
 * @title Vault Implementation Deployer Contract
 * @dev This contract is used by the VaultDeployer contract to deploy new StackVault contracts.
 * @notice Provides a function to deploy a new StackVault implementation contract.
 *         The sole reason for having this in a separate contract is to reduce the VaultDeployer contract size.
 * @author SeaZarrgh LaBuoy
 */
contract VaultImplementationDeployer {
    function deploy(address factory, address borrowToken, address collateralToken, address transferHelper)
        external
        returns (StackVault vault)
    {
        vault = new StackVault(factory, borrowToken, collateralToken, transferHelper);
    }
}
