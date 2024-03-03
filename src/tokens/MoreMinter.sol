// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

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
    address public immutable MORE;

    /// @custom:storage-location erc7201:pearl.storage.MoreMinter
    struct MoreMinterStorage {
        address team;
        address vaultFactory;
        address amo;
    }

    // keccak256(abi.encode(uint256(keccak256("pearl.storage.MoreMinter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MoreMinterStorageLocation =
        0x7e73b909798c3c9ebb8a04ddc27e32db02d4c781f37f96b8ff89750e1e716800;

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
     * @param _amo The address of the Algorithmic Market Operations Controller (AMO).
     */
    function initialize(address _team, address _vaultFactory, address _amo) external initializer {
        __Ownable_init(_team);
        __UUPSUpgradeable_init();

        MoreMinterStorage storage $ = _getMoreMinterStorage();
        $.team = _team;
        $.vaultFactory = _vaultFactory;
        $.amo = _amo;
    }

    /**
     * @notice Sets a new address for the team.
     * @dev Updates the team address in the MoreMinterStorage.
     *      Restricted to the contract owner.
     * @param _team The new address for the team.
     */
    function setTeam(address _team) external onlyOwner {
        MoreMinterStorage storage $ = _getMoreMinterStorage();
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
        $.vaultFactory = _vaultFactory;
    }

    /**
     * @notice Sets a new address for the AMO.
     * @dev Updates the AMO address in the MoreMinterStorage.
     *      Restricted to the contract owner.
     * @param _amo The new address for the AMO.
     */
    function setAMO(address _amo) external {
        MoreMinterStorage storage $ = _getMoreMinterStorage();
        if (msg.sender != owner() && msg.sender != $.team) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
        $.amo = _amo;
    }

    /**
     * @notice Mints new MORE tokens to a specified address.
     * @dev Invokes the mint function of the MORE token. Can be called by authorized addresses.
     * @param to The address to receive the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external {
        MoreMinterStorage storage $ = _getMoreMinterStorage();
        if (msg.sender != $.team && msg.sender != $.vaultFactory && msg.sender != $.amo) {
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

    /**
     * @notice Gets the address of the AMO.
     * @dev Returns the address of the AMO from the MoreMinterStorage.
     * @return The address of the AMO.
     */
    function amo() external view returns (address) {
        return _getMoreMinterStorage().amo;
    }
}
