// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC1967Utils, ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {EmptyUUPS} from "../utils/EmptyUUPS.sol";

/**
 * @title Deployment Script Base
 * @author SeaZarrgh
 * @notice This contract serves as a foundational element for deploying and upgrading UUPS proxies with deterministic
 * address generation using CREATE2. It leverages the EmptyUUPS contract as the initial implementation for each new
 * proxy.
 * @dev The contract extends the 'Script' contract from Forge Standard Library and includes functions for deploying
 * and upgrading proxies, ensuring a consistent and secure upgrade path.
 *
 * Key functionalities include:
 * - Loading private keys for transactions
 * - Setting up chain configurations
 * - Ensuring the deployment of EmptyUUPS implementation
 * - Computing proxy addresses for specific contracts
 * - Deploying or upgrading proxies with specified implementations
 * - Checking the deployment status of contracts
 *
 * The contract uses a private key stored in an environment variable for transaction signing and the EmptyUUPS contract
 * for initializing new proxies. It contains methods to compute the proxy address and salt for specific contracts,
 * deploy or upgrade proxies, and verify if a contract is deployed at a given address.
 */
abstract contract DeploymentScriptBase is Script {
    /// @notice Slot for the proxy's implementation address, based on EIP-1967.
    bytes32 internal constant PROXY_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice Salt used for generating CREATE2 addresses.
    bytes32 internal immutable _SALT;

    /// @notice Address of the deployer.
    address internal _deployer;

    /// @dev Private key used for broadcasting.
    uint256 internal _pk;

    /// @dev Address for the initial EmptyUUPS implementation.
    address private _emptyUUPS;

    /**
     * @dev Constructor for DeploymentScriptBase. It sets the immutable salt for CREATE2 address generation.
     * The salt is derived from the provided raw salt value, allowing for customizable yet consistent address
     * generation.
     * @param _salt The raw salt value to be hashed and used for CREATE2 address calculations. This parameter enables
     * customization of the deployment process, as different salts lead to different deterministic addresses.
     */
    constructor(bytes memory _salt) {
        _SALT = keccak256(_salt);
    }

    /**
     * @dev Loads the private key from an environment variable, setting up the deployer's address for transaction
     * signing. This function is crucial for ensuring that the deployer's identity is secured and transactions are
     * properly signed. The private key is loaded from an environment variable named 'DEPLOYER_PRIVATE_KEY'. This
     * approach centralizes and secures the management of the private key, ensuring it is not hardcoded in the contract.
     */
    function _loadPrivateKey() internal {
        _pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        _deployer = vm.addr(_pk);
    }

    /**
     * @dev Sets up the initial chain configurations and loads the deployer's private key for transaction signing.
     * This function is a part of the contract's initialization process, ensuring that the contract is ready for
     * deployment and upgrade operations.
     *
     * It performs two main tasks:
     * 1. Loads the deployer's private key using the `_loadPrivateKey` function, which is essential for secure and
     *    authenticated transactions.
     * 2. Configures two chains, "unreal" and "real", with their respective names, chain IDs, and RPC URLs. This setup
     *    allows the contract to interact with these specific chains, facilitating multi-chain deployment strategies.
     */
    function _setup() internal {
        _loadPrivateKey();
        setChain("unreal", ChainData("Unreal Chain", 18231, "https://rpc.unreal.gelato.digital"));
        setChain("real", ChainData("Real Chain", 111188, "https://rpc.real.gelato.digital"));
    }

    /**
     * @dev Ensures the deployment of the EmptyUUPS contract if it's not already deployed. This function is crucial for
     * setting up the initial proxy implementation.
     *
     * The process involves:
     * 1. Computing the expected address of the EmptyUUPS contract using CREATE2 with the provided deployer address.
     * 2. Checking if the contract is already deployed at the computed address.
     * 3. If not deployed, deploying the EmptyUUPS contract with the deployer address and the same salt used for
     *    computation.
     * 4. Logging the deployment to the console for tracking purposes.
     *
     * This function is called before any proxy deployment or upgrade to ensure that the initial implementation
     * (EmptyUUPS) is available and consistent across different deployments.
     */
    function _ensureEmptyUUPSIsDeployed() internal {
        bytes32 initCodeHash = hashInitCode(type(EmptyUUPS).creationCode, abi.encode(_deployer));
        _emptyUUPS = vm.computeCreate2Address(_SALT, initCodeHash);

        if (!_isDeployed(_emptyUUPS)) {
            EmptyUUPS emptyUUPS = new EmptyUUPS{salt: _SALT}(_deployer);
            assert(address(emptyUUPS) == _emptyUUPS);
            console.log("Empty UUPS implementation contract deployed to %s", _emptyUUPS);
        }
    }

    /**
     * @dev Computes the address and salt for a proxy corresponding to a specific contract. This is essential for
     * deploying or upgrading proxies in a deterministic manner.
     *
     * The function performs the following operations:
     * 1. Computes the hash of the ERC1967Proxy contract's creation code concatenated with the EmptyUUPS implementation
     *    address, serving as the init code hash.
     * 2. Generates a salt unique to the contract name by hashing the combination of the global salt and the contract
     *    name.
     * 3. Calculates the proxy's address using CREATE2 with the generated salt and init code hash.
     *
     * @param forContract The name of the contract for which the proxy address is being computed. This name influences
     * the unique salt generation, ensuring different contracts have different proxy addresses.
     * @return proxyAddress The computed address for the proxy.
     * @return salt The computed unique salt used in the CREATE2 address calculation.
     */
    function _computeProxyAddress(string memory forContract)
        internal
        view
        returns (address proxyAddress, bytes32 salt)
    {
        bytes32 initCodeHash = hashInitCode(type(ERC1967Proxy).creationCode, abi.encode(_emptyUUPS, ""));
        salt = keccak256(abi.encodePacked(_SALT, forContract));
        proxyAddress = vm.computeCreate2Address(salt, initCodeHash);
    }

    /**
     * @dev Deploys or upgrades a UUPS proxy for a specified contract with a given implementation and initialization
     * data. This function is central to the contract's functionality, handling both the initial deployment and
     * subsequent upgrades of proxies.
     *
     * The deployment process is as follows:
     * 1. Ensures that the EmptyUUPS implementation is deployed using `_ensureEmptyUUPSIsDeployed`.
     * 2. Computes the proxy address and salt specific to the contract using `_computeProxyAddress`.
     * 3. If the proxy is already deployed, checks whether the current implementation differs from the new one.
     *    - If different, upgrades the proxy to the new implementation using `upgradeToAndCall`.
     *    - Logs the upgrade process to the console.
     * 4. If the proxy is not yet deployed, deploys a new ERC1967Proxy with EmptyUUPS as the initial implementation and
     *    immediately upgrades it to the specified implementation.
     * 5. Logs the deployment process to the console.
     *
     * @param forContract The name of the contract for which the proxy is being deployed or upgraded.
     * @param implementation The address of the new implementation contract to set for the proxy.
     * @param data The initialization data to be used in the `upgradeToAndCall` function during proxy deployment or
     * upgrade.
     * @return proxyAddress The address of the deployed or upgraded proxy.
     */
    function _deployProxy(string memory forContract, address implementation, bytes memory data)
        internal
        returns (address proxyAddress)
    {
        _ensureEmptyUUPSIsDeployed();

        bytes32 salt;
        (proxyAddress, salt) = _computeProxyAddress(forContract);

        if (_isDeployed(proxyAddress)) {
            ERC1967Proxy proxy = ERC1967Proxy(payable(proxyAddress));
            address _implementation = address(uint160(uint256(vm.load(address(proxy), PROXY_IMPLEMENTATION_SLOT))));
            if (_implementation != implementation) {
                UUPSUpgradeable(address(proxy)).upgradeToAndCall(implementation, "");
                console.log("%s proxy at %s has been upgraded", forContract, proxyAddress);
            } else {
                console.log("%s proxy at %s remains unchanged", forContract, proxyAddress);
            }
        } else {
            ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(_emptyUUPS, "");
            assert(proxyAddress == address(proxy));
            UUPSUpgradeable(address(proxy)).upgradeToAndCall(implementation, data);
            console.log("%s proxy deployed to %s", forContract, proxyAddress);
        }
    }

    /**
     * @dev Checks whether a contract is deployed at a given address. This function is crucial for determining the
     * deployment status of contracts, particularly in the context of proxy deployment and upgrades.
     *
     * The check is performed using low-level assembly code to query the size of the code at the specified address:
     * 1. The 'extcodesize' opcode is used to obtain the size of the contract's bytecode at the given address.
     * 2. A non-zero size indicates that a contract is deployed at the address.
     *
     * @param contractAddress The address to check for the presence of a contract.
     * @return isDeployed A boolean indicating whether a contract is deployed at the specified address. Returns 'true'
     * if a contract is present, and 'false' otherwise.
     */
    function _isDeployed(address contractAddress) internal view returns (bool isDeployed) {
        // slither-disable-next-line assembly
        assembly {
            let cs := extcodesize(contractAddress)
            if iszero(iszero(cs)) { isDeployed := true }
        }
    }

    /**
     * @dev Saves the deployment address of a contract to the chain's deployment address JSON file. This function is
     * essential for
     * tracking the deployment of contracts and ensuring that the contract's address is stored for future
     * reference.
     * @param name The name of the contract for which the deployment address is being saved.
     * @param addr The address of the deployed contract.
     */
    function _saveDeploymentAddress(string memory name, address addr) internal {
        Chain memory _chain = getChain(block.chainid);
        string memory chainAlias = _chain.chainAlias;
        string[] memory commandInput = new string[](4);
        commandInput[0] = "store-deployment-address";
        commandInput[1] = chainAlias;
        commandInput[2] = name;
        commandInput[3] = vm.toString(addr);
        vm.ffi(commandInput);
    }
}
