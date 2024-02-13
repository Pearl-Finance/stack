// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IMinter} from "../interfaces/IMinter.sol";
import {IVaultFactory} from "../interfaces/IVaultFactory.sol";

/**
 * @title Vault Factory ERC7201 Storage Contract
 * @notice Abstract contract for defining a structured and collision-resistant storage layout for vault management,
 *         in compliance with the ERC-7201 standard.
 * @dev Implements a namespaced storage pattern as per ERC-7201, ensuring isolated and structured storage
 *      for the contract's data. This contract is part of a larger system managing vaults in the STack ecosystem,
 *      and it primarily focuses on the secure and upgrade-safe storage structure. It defines the core storage layout
 *      used by other components of the vault management system. The contract is linked to a specific borrow token
 *      and its minter, but the primary emphasis is on implementing the ERC-7201 storage pattern.
 * @author SeaZarrgh LaBuoy
 */
abstract contract VaultFactoryERC7201 is IVaultFactory {
    address public immutable borrowTokenMinter;
    address public immutable borrowToken;

    /// @custom:storage-location erc7201:pearl.storage.VaultFactory
    struct VaultFactoryStorage {
        uint32 allVaultsLength;
        uint96 borrowInterestRate;
        uint96 liquidatorPenaltyShare;
        address vaultDeployer;
        address borrowTokenOracle;
        address debtCollector;
        address feeReceiver;
        address penaltyReceiver;
        address interestRateManager;
        address[] allVaults;
        mapping(address token => address payable) vaultForToken;
        mapping(address vault => uint256) vaultIndex;
        mapping(address vault => uint256) lastInterestRateUpdateTimestamp;
        mapping(address target => bool) trustedSwapTargets;
    }

    // keccak256(abi.encode(uint256(keccak256("pearl.storage.VaultFactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VaultFactoryStorageLocation =
        0x7e73b909798c3c9ebb8a04ddc27e32db02d4c781f37f96b8ff89750e1e716800;

    function _getVaultFactoryStorage() internal pure returns (VaultFactoryStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := VaultFactoryStorageLocation
        }
    }

    /**
     * @notice Creates a new instance of the VaultFactoryERC7201 contract.
     * @dev Initializes the contract by setting the borrow token minter. It also fetches and sets the address of the
     *      borrow token by interacting with the IMinter interface. This setup ensures that the borrow token is directly
     *      linked to its minter, which is crucial for the vault creation and management process.
     * @param _borrowTokenMinter The address of the minter contract for the borrow token. This minter is responsible for
     *                           creating new instances of the borrow token.
     */
    constructor(address _borrowTokenMinter) {
        borrowTokenMinter = _borrowTokenMinter;
        borrowToken = IMinter(_borrowTokenMinter).token();
    }
}
