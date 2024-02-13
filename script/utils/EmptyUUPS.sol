// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title EmptyUUPS
 * @author Caesar LaVey
 * @dev This contract serves as an initial implementation behind a UUPS proxy.
 * It is meant to be deployed once and used as the default implementation for multiple proxies.
 * This helps in generating deterministic addresses for these proxies across different chains using CREATE2.
 *
 * The contract ensures that only the deployer can authorize upgrades.
 */
contract EmptyUUPS is UUPSUpgradeable {
    using Address for address;

    /// @notice Address of the deployer who is authorized to perform upgrades.
    address public immutable deployer;

    /// @dev Custom error to show that the caller is not the deployer.
    error CallerIsNotDeployer(address caller, address deployer);

    /**
     * @dev Initializes the contract and sets the deployer address.
     * @param _deployer Address of the deployer to be stored as an immutable state variable.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address _deployer) {
        deployer = _deployer;
        _disableInitializers();
    }

    /**
     * @dev Overrides the _authorizeUpgrade from UUPSUpgradeable to add custom logic for authorizing upgrades.
     * Here, it checks that only the deployer can authorize an upgrade.
     */
    function _authorizeUpgrade(address) internal view override {
        address implementation = ERC1967Utils.getImplementation();
        address _deployer =
            abi.decode(implementation.functionStaticCall(abi.encodeWithSignature("deployer()")), (address));
        if (_deployer != msg.sender) {
            revert CallerIsNotDeployer(msg.sender, _deployer);
        }
    }
}
