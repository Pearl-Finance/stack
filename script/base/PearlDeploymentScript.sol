// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {DeploymentScriptBase} from "./DeploymentScriptBase.sol";

/**
 * @title Pearl Deployment Script
 * @notice This abstract contract extends DeploymentScriptBase for the Pearl ecosystem, using a specific salt
 * ('pearl.deployer') for CREATE2 address calculations. This salt ensures deterministic address generation for
 * contracts deployed within the Pearl ecosystem.
 * @dev The contract inherits DeploymentScriptBase's functionality, tailoring it to the Pearl ecosystem's deployment
 * needs. It uses the 'pearl.deployer' salt for all CREATE2 address calculations, providing consistency and
 * predictability in contract addresses.
 *
 * Key Features:
 * - Inherits the robust deployment and proxy management system of DeploymentScriptBase.
 * - Uses a specific salt ('pearl.deployer') to ensure deterministic and consistent CREATE2 address generation.
 * - Sets the stage for deploying various components of the Pearl ecosystem with predictable addresses.
 *
 * As an abstract contract, it forms the base for concrete deployment scripts within the Pearl ecosystem, requiring
 * further customization for deploying specific contracts.
 */
abstract contract PearlDeploymentScript is DeploymentScriptBase {
    constructor() DeploymentScriptBase("pearl.deployer") {}
}
