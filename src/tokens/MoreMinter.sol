// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IERC20Mintable} from "../interfaces/IERC20Mintable.sol";
import {IMinter} from "../interfaces/IMinter.sol";
import {CommonErrors} from "../interfaces/CommonErrors.sol";

/**
 * @title More Minter Contract
 * @notice Contract responsible for minting the 'More' tokens, managing related permissions and addresses.
 * @dev Inherits from OwnableUpgradeable and UUPSUpgradeable for ownership management and upgrade functionality.
 *      Implements IMinter for the minting of 'More' tokens.
 *      Utilizes ERC-7201 namespaced storage pattern for storing the team and vault factory addresses,
 *      ensuring collision-resistant storage.
 * @author SeaZarrgh LaBuoy
 */
contract MoreMinter is OwnableUpgradeable, UUPSUpgradeable, CommonErrors, IMinter {
    using EnumerableSet for EnumerableSet.AddressSet;

    address public immutable MORE;

    /// @custom:storage-location erc7201:pearl.storage.MoreMinter
    struct MoreMinterStorage {
        address team;
        address vaultFactory;
        address amo; // deprecated
        EnumerableSet.AddressSet amos;
    }

    // keccak256(abi.encode(uint256(keccak256("pearl.storage.MoreMinter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MoreMinterStorageLocation =
        0x45d65222210387cb7889272ba5bbc981dc1846db58d6c915bc27e17574273f00;

    function _getMoreMinterStorage() internal pure returns (MoreMinterStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := MoreMinterStorageLocation
        }
    }

    /**
     * @notice Initializes the MoreMinter contract.
     * @dev Sets the MORE token address and disables initializers to prevent reinitialization after an upgrade.
     * @param more The address of the MORE token.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address more) {
        _disableInitializers();
        if (more == address(0)) {
            revert InvalidZeroAddress();
        }
        MORE = more;
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
     * @notice Initializes the MoreMinter with team and vault factory addresses.
     * @dev Sets up the contract with initial team and vault factory addresses.
     *      Can only be called once due to the `initializer` modifier.
     * @param _team The address of the team responsible for minting.
     * @param _vaultFactory The address of the vault factory.
     */
    function initialize(address _team, address _vaultFactory) external initializer {
        __Ownable_init(_team);
        __UUPSUpgradeable_init();

        MoreMinterStorage storage $ = _getMoreMinterStorage();
        _setTeam($, _team);
        _setVaultFactory($, _vaultFactory);
    }

    /**
     * @notice Sets a new address for the team.
     * @dev Updates the team address in the MoreMinterStorage.
     *      Restricted to the contract owner.
     * @param _team The new address for the team.
     */
    function setTeam(address _team) external onlyOwner {
        MoreMinterStorage storage $ = _getMoreMinterStorage();
        if (_team == $.team) {
            revert ValueUnchanged();
        }
        _setTeam($, _team);
    }

    /**
     * @dev Internally sets a new address for the team. This function updates the team address stored in the
     * MoreMinterStorage.
     * It requires that the new team address is not the zero address, to ensure it points to a valid address.
     * @param $ The MoreMinterStorage instance to update.
     * @param _team The new address to be set for the team. It must be a valid address, not the zero address.
     */
    function _setTeam(MoreMinterStorage storage $, address _team) internal {
        if (_team == address(0)) {
            revert InvalidZeroAddress();
        }
        $.team = _team;
    }

    /**
     * @notice Sets a new address for the vault factory.
     * @dev Updates the vault factory address in the MoreMinterStorage.
     *      Restricted to the contract owner.
     * @param _vaultFactory The new address for the vault factory.
     */
    function setVaultFactory(address _vaultFactory) external onlyOwner {
        MoreMinterStorage storage $ = _getMoreMinterStorage();
        if (_vaultFactory == $.vaultFactory) {
            revert ValueUnchanged();
        }
        _setVaultFactory($, _vaultFactory);
    }

    /**
     * @dev Internally sets a new address for the vault factory. This function updates the vault factory address stored
     * in the MoreMinterStorage.
     * It validates that the new address is not the zero address, maintaining the integrity of the vault factory
     * address.
     * @param $ The MoreMinterStorage instance to update.
     * @param _vaultFactory The new address to be set for the vault factory. The address must be valid and not the zero
     * address.
     */
    function _setVaultFactory(MoreMinterStorage storage $, address _vaultFactory) internal {
        if (_vaultFactory == address(0)) {
            revert InvalidZeroAddress();
        }
        $.vaultFactory = _vaultFactory;
    }

    /**
     * @notice Returns all AMO addresses.
     * @dev Returns all addresses in the EnumerableSet of AMOs.
     * @return An array of AMO addresses.
     */
    function amos() external view returns (address[] memory) {
        return _getMoreMinterStorage().amos.values();
    }

    /**
     * @notice Adds a new AMO address to the set of approved AMOs.
     * @dev Adds a new address to the EnumerableSet of AMOs, checking for zero address and duplicates.
     * @param _amo The address to be added.
     */
    function addAMO(address _amo) external {
        MoreMinterStorage storage $ = _getMoreMinterStorage();
        if (msg.sender != owner() && msg.sender != $.team) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
        if ($.amos.contains(_amo)) {
            revert ValueUnchanged();
        }
        _addAMO($, _amo);
    }

    /**
     * @notice Removes an AMO address from the set of approved AMOs.
     * @dev Removes an address from the EnumerableSet of AMOs.
     * @param _amo The address to be removed.
     */
    function removeAMO(address _amo) external onlyOwner {
        MoreMinterStorage storage $ = _getMoreMinterStorage();
        if (msg.sender != owner() && msg.sender != $.team) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
        if (!$.amos.contains(_amo)) {
            revert ValueUnchanged();
        }
        _removeAMO($, _amo);
    }

    /**
     * @dev Internally adds a new AMO address to the set of approved AMOs.
     * This internal function encapsulates the logic for adding a new AMO address to the EnumerableSet,
     * ensuring that it is not a zero address and does not already exist in the set.
     * @param $ The MoreMinterStorage instance containing the EnumerableSet of AMOs.
     * @param _amo The AMO address to add. Must be non-zero and not already in the set.
     */
    function _addAMO(MoreMinterStorage storage $, address _amo) internal {
        if (_amo == address(0)) {
            revert InvalidZeroAddress();
        }
        $.amos.add(_amo);
    }

    /**
     * @dev Internally removes an AMO address from the set of approved AMOs.
     * This internal function handles the logic for removing an AMO address from the EnumerableSet.
     * It checks that the address is currently part of the set before removal.
     * @param $ The MoreMinterStorage instance containing the EnumerableSet of AMOs.
     * @param _amo The AMO address to remove. Must be present in the set.
     */
    function _removeAMO(MoreMinterStorage storage $, address _amo) internal {
        $.amos.remove(_amo);
    }

    /**
     * @notice Mints new MORE tokens to a specified address.
     * @dev Invokes the mint function of the MORE token. Can be called by authorized addresses.
     * @param to The address to receive the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external {
        MoreMinterStorage storage $ = _getMoreMinterStorage();
        if (msg.sender != $.team && msg.sender != $.vaultFactory && !$.amos.contains(msg.sender)) {
            revert UnauthorizedCaller();
        }
        IERC20Mintable(MORE).mint(to, amount);
    }

    /**
     * @notice Retrieves the address of the MORE token.
     * @dev Returns the MORE token address.
     * @return The address of the MORE token.
     */
    function token() external view returns (address) {
        return MORE;
    }

    /**
     * @notice Gets the address of the team.
     * @dev Returns the address of the team from the MoreMinterStorage.
     * @return The address of the team.
     */
    function team() external view returns (address) {
        return _getMoreMinterStorage().team;
    }

    /**
     * @notice Gets the address of the vault factory.
     * @dev Returns the address of the vault factory from the MoreMinterStorage.
     * @return The address of the vault factory.
     */
    function vaultFactory() external view returns (address) {
        return _getMoreMinterStorage().vaultFactory;
    }
}
