// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {CommonErrors} from "../interfaces/CommonErrors.sol";
import {Constants} from "../libraries/Constants.sol";
import {StackVault} from "../vaults/StackVault.sol";
import {VaultImplementationDeployer} from "./VaultImplementationDeployer.sol";

/**
 * @title Vault Deployer Contract
 * @notice Contract responsible for deploying and upgrading individual vaults in the Stack ecosystem.
 * @dev Utilizes the OpenZeppelin ERC1967 proxy pattern for deploying upgradable vaults using the StackVault contract.
 *      The deployer is linked to a factory contract and ensures that only the factory can deploy or upgrade vaults.
 *      Inherits from OwnableUpgradeable and UUPSUpgradeable for ownership management and upgrade functionality.
 * @author SeaZarrgh LaBuoy
 */
contract VaultDeployer is CommonErrors, OwnableUpgradeable, UUPSUpgradeable {
    using Address for address;

    address public immutable WETH;
    address public immutable factory;
    address public immutable implementationDeployer;
    address public immutable transferHelper;

    /**
     * @notice Initializes the VaultDeployer contract.
     * @dev Sets the factory address and disables initializers to ensure the contract is only initialized once.
     * @param weth The address of the WETH token for the ecosystem.
     * @param _factory The address of the factory contract that controls the deployment and upgrade of vaults.
     * @param _implementationDeployer The address of the contract responsible for deploying the vault implementation.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address weth, address _factory, address _implementationDeployer, address _transferHelper) {
        _disableInitializers();
        if (weth == address(0) || _factory == address(0) || _implementationDeployer == address(0)) {
            revert InvalidZeroAddress();
        }
        WETH = weth;
        factory = _factory;
        implementationDeployer = _implementationDeployer;
        transferHelper = _transferHelper;
    }

    /**
     * @notice Initializes the VaultDeployer contract.
     * @dev Sets the contract owner to the caller of this function.
     *      Can only be called once due to the `initializer` modifier.
     */
    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
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
     * @notice Deploys a new vault with specified parameters.
     * @dev Deploys a new vault using a proxy pattern. Initializes the vault with the provided parameters.
     *      Can only be called by the factory contract.
     *      Reverts if the caller is not the factory.
     * @param borrowToken The address of the borrow token for the new vault.
     * @param collateralToken The address of the collateral token for the new vault.
     * @param collateralTokenOracle The address of the oracle for the collateral token.
     * @param liquidationThreshold The liquidation threshold for the new vault.
     * @param interestRateMultiplier The interest rate multiplier for the new vault.
     * @return vault The address of the newly deployed vault.
     */
    function deployVault(
        address borrowToken,
        address collateralToken,
        address collateralTokenOracle,
        uint256 liquidationThreshold,
        uint256 interestRateMultiplier
    ) external returns (address payable vault) {
        if (msg.sender != factory) {
            revert UnauthorizedCaller();
        }
        bytes memory init = abi.encodeWithSelector(
            StackVault.initialize.selector,
            OwnableUpgradeable(factory).owner(),
            collateralTokenOracle,
            liquidationThreshold,
            interestRateMultiplier
        );

        StackVault _vault = _deployImplementation(borrowToken, collateralToken);
        ERC1967Proxy proxy = new ERC1967Proxy(address(_vault), init);
        vault = payable(address(proxy));
    }

    /**
     * @notice Upgrades an existing vault to a new implementation.
     * @dev Deploys a new vault implementation and upgrades the specified proxy to this new implementation.
     *      Transfers ownership of the upgraded vault to the specified address.
     *      Can only be called by the factory contract.
     *      Reverts if the caller is not the factory.
     * @param proxy The address of the proxy representing the vault to be upgraded.
     * @param transferOwnershipTo The address to transfer ownership of the upgraded vault.
     */
    function upgradeVault(address payable proxy, address transferOwnershipTo) external {
        if (msg.sender != factory) {
            revert UnauthorizedCaller();
        }

        address borrowToken = address(StackVault(proxy).borrowToken());
        address collateralToken = address(StackVault(proxy).collateralToken());

        if (collateralToken == WETH) {
            collateralToken = Constants.ETH_ADDRESS;
        }

        StackVault _vault = _deployImplementation(borrowToken, collateralToken);
        UUPSUpgradeable(proxy).upgradeToAndCall(address(_vault), "");
        OwnableUpgradeable(proxy).transferOwnership(transferOwnershipTo);
    }

    function _deployImplementation(address borrowToken, address collateralToken) internal returns (StackVault) {
        bytes memory result = implementationDeployer.functionDelegateCall(
            abi.encodeCall(VaultImplementationDeployer.deploy, (factory, borrowToken, collateralToken, transferHelper))
        );
        address vaultAddress = abi.decode(result, (address));
        return StackVault(payable(vaultAddress));
    }
}
