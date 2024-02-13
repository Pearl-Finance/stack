// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {ERC20BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";

/**
 * @title FeeSplitter Contract
 * @author SeaZarrgh LaBuoy
 * @dev This contract is designed to distribute ERC20 tokens to a set of receivers based on predetermined split ratios.
 * The FeeSplitter contract allows for the addition, removal, and update of fee receivers and their respective split
 * percentages. It employs OpenZeppelin's OwnableUpgradeable and UUPSUpgradeable for secure ownership and
 * upgradeability. The contract uses a custom storage structure, leveraging EVM assembly for efficient data storage and
 * access. This design ensures scalability and gas efficiency, particularly in the context of managing a dynamic list of
 * fee receivers and handling token distributions.
 *
 * Key features include:
 *  - Token Distribution: Enables the distribution of ERC20 tokens held by the contract to the registered receivers
 *    based on their split ratios.
 *  - Receiver Management: Allows the contract owner to add, remove, or update the split percentage of fee receivers.
 *  - Upgradeability: Built with upgradeability in mind, utilizing OpenZeppelin's UUPSUpgradeable pattern.
 *  - Gas-Efficient Storage: Uses custom storage layout with EVM assembly, optimizing for gas efficiency and contract
 *    size.
 *  - Checkpointing: Implements a checkpoint system to track distributions over time, aiding in rate calculations.
 *
 * The contract is particularly suited for scenarios where ongoing and fair distribution of fees or revenues is
 * required.
 */
contract FeeSplitter is OwnableUpgradeable, UUPSUpgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant CHECKPOINT_INTERVAL = 1 days;
    uint256 private constant CHECKPOINT_HISTORY_LENGTH = 2;

    error InvalidSplitValue(uint96 value);
    error ReceiverAlreadyAdded(address receiver);
    error ReceiverNotFound(address receiver);

    struct FeeReceiver {
        address receiver;
        uint96 split;
    }

    struct Checkpoint {
        uint256 timestamp;
        uint256 totalDistributed;
    }

    /// @custom:storage-location erc7201:pearl.storage.FeeSplitter
    struct FeeSplitterStorage {
        address token;
        uint256 splitTotal;
        uint256 lastCheckpointIndex;
        uint256 totalDistributed;
        FeeReceiver[] feeReceivers;
        Checkpoint[CHECKPOINT_HISTORY_LENGTH] checkpoints;
        mapping(address => uint256) receiverPos;
    }

    // keccak256(abi.encode(uint256(keccak256("pearl.storage.FeeSplitter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FeeSplitterStorageLocation =
        0x7453fee3fcdfde6b0f86e0f5f8261a3a97848a6274f4ca0559ecb4c0e22cbf00;

    function _getFeeSplitterStorage() private pure returns (FeeSplitterStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := FeeSplitterStorageLocation
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Initializes the FeeSplitter contract with a specified token.
     * @param token The address of the ERC20 token that will be distributed by this contract.
     */
    function initialize(address token) external initializer {
        __Ownable_init(msg.sender);
        FeeSplitterStorage storage $ = _getFeeSplitterStorage();
        $.token = token;
    }

    /**
     * @notice Distributes the ERC20 tokens held by the contract to the registered fee receivers.
     * @dev This function calculates the distribution amount for each receiver based on their split ratio and the total
     * amount of tokens currently held by the contract. It iterates over the list of receivers in reverse order and
     * transfers the calculated token amount to each. This reverse iteration is performed for gas efficiency, as
     * comparing the loop counter against zero is cheaper than comparing two values. The function can be called by any
     * external actor, facilitating flexible distribution schedules.
     *
     * Key aspects of the distribution logic include:
     *  - Proportional Distribution: The split amount for each receiver is proportional to their registered split ratio.
     *  - Distribution History: Updates the checkpoints with the total amount distributed after each execution.
     *
     * Note: If there are no receivers or the total split ratio is 0, the function will not attempt distribution.
     */
    function distribute() external {
        FeeSplitterStorage storage $ = _getFeeSplitterStorage();
        address token = $.token;
        uint256 splitTotal = $.splitTotal;
        uint256 amount = IERC20($.token).balanceOf(address(this));
        uint256 totalDistributed = $.totalDistributed;
        if (splitTotal != 0) {
            FeeReceiver[] storage feeReceivers = $.feeReceivers;
            for (uint256 i = feeReceivers.length; i != 0;) {
                unchecked {
                    --i;
                }
                (address feeReceiver, uint96 split) = _unsafeFeeReceiverAccess(feeReceivers, i);
                uint256 splitAmount = amount.mulDiv(split, splitTotal, Math.Rounding.Floor);
                if (splitAmount != 0) {
                    totalDistributed += splitAmount;
                    IERC20(token).safeTransfer(feeReceiver, splitAmount);
                }
            }
        }
        _updateCheckpoints(totalDistributed);
    }

    /**
     * @notice Adds a new receiver with a specified split percentage for token distribution.
     * @dev This function allows the contract owner to add a new fee receiver. It performs checks to ensure that the
     * receiver is not already in the list and that the split value is valid. The split value combined with the existing
     * total should not exceed the maximum limit for a uint96.
     *
     * Steps in the function:
     *  - Check if the receiver is already added: Reverts if so to prevent duplication.
     *  - Validate the split value: Ensures it's a non-zero value and, when added to the current total, does not exceed
     *    the maximum uint96 value.
     *  - Update the total split percentage and add the receiver to the list.
     *
     * This function can only be called by the contract owner, ensuring controlled management of receivers.
     *
     * @param receiver The address of the new fee receiver to be added.
     * @param split The percentage of the total distribution that this receiver should receive.
     */
    function addReceiver(address receiver, uint96 split) external onlyOwner {
        FeeSplitterStorage storage $ = _getFeeSplitterStorage();
        if ($.receiverPos[receiver] != 0) {
            revert ReceiverAlreadyAdded(receiver);
        }
        _validateSplitValue(split, $.splitTotal);
        $.splitTotal += split;
        $.feeReceivers.push(FeeReceiver(receiver, split));
        $.receiverPos[receiver] = $.feeReceivers.length;
    }

    /**
     * @notice Removes a receiver from the token distribution list.
     * @dev This function allows the contract owner to remove a fee receiver from the distribution list. It ensures the
     * receiver exists in the list and reverts if not found. The function then removes the receiver and adjusts the
     * total split percentage.
     *
     * Key steps in the function:
     *  - Locate and validate the receiver: Checks the receiver's position in the list and reverts if not found.
     *  - Clear the receiver's position: Sets the receiver's position to 0 in the mapping.
     *  - Adjust the total split: Deducts the receiver's split percentage from the total split.
     *  - Rearrange the list: If the receiver is not the last one, it swaps the receiver with the last one in the list
     *    for efficient removal, and updates the position mapping. This ensures continuous array indexing and gas
     *    optimization.
     *  - Remove the last receiver: Pops the last element of the array, effectively removing the target receiver.
     *
     *  Only the contract owner can execute this function, ensuring controlled access to the distribution list.
     *
     * @param receiver The address of the fee receiver to be removed.
     */
    function removeReceiver(address receiver) external onlyOwner {
        FeeSplitterStorage storage $ = _getFeeSplitterStorage();
        uint256 pos = $.receiverPos[receiver];
        uint256 index;
        if (pos == 0) {
            revert ReceiverNotFound(receiver);
        }
        unchecked {
            index = pos - 1;
        }
        $.receiverPos[receiver] = 0;
        (, uint96 split) = _unsafeFeeReceiverAccess($.feeReceivers, index);
        $.splitTotal -= split;
        uint256 receiversLength = $.feeReceivers.length;
        uint256 lastIndex = receiversLength - 1;
        if (index != lastIndex) {
            (receiver,) = _unsafeFeeReceiverAccess($.feeReceivers, lastIndex);
            $.feeReceivers[index] = $.feeReceivers[lastIndex];
            $.receiverPos[receiver] = pos;
        }
        $.feeReceivers.pop();
    }

    /**
     * @notice Updates the split percentage for an existing receiver in the distribution list.
     * @dev This function allows the contract owner to update the split ratio for a specific fee receiver. It checks if
     * the receiver exists and reverts if not found. The function then validates the new split value and updates the
     * receiver's split percentage in the list, along with adjusting the total split percentage.
     *
     * Key steps in the function:
     *  - Validate the receiver: Ensures the receiver is currently in the distribution list.
     *  - Validate the new split value: Checks that the new split value, combined with the existing total (excluding the
     *    current receiver's split), is within the allowable range.
     *  - Update the receiver's split: Adjusts the receiver's split percentage in the list and updates the total split.
     *
     * This operation is owner-restricted, maintaining control over the distribution parameters.
     *
     * @param receiver The address of the fee receiver whose split percentage is to be updated.
     * @param split The new percentage of the total distribution that the receiver should receive.
     */
    function updateReceiver(address receiver, uint96 split) external onlyOwner {
        FeeSplitterStorage storage $ = _getFeeSplitterStorage();
        uint256 pos = $.receiverPos[receiver];
        if (pos == 0) {
            revert ReceiverNotFound(receiver);
        }
        (, uint96 currentSplit) = _unsafeFeeReceiverAccess($.feeReceivers, pos - 1);
        uint256 splitTotal;
        unchecked {
            splitTotal = $.splitTotal - currentSplit;
        }
        _validateSplitValue(split, splitTotal);
        unchecked {
            $.splitTotal = splitTotal + split;
        }
        uint256 receiversLength = $.feeReceivers.length;
        if (pos != receiversLength) {
            $.feeReceivers[pos - 1].split = split;
        }
    }

    /**
     * @notice Sets the entire list of receivers and their respective split percentages.
     * @dev This function allows the contract owner to replace the current set of fee receivers with a new list. It
     * ensures the lists of receivers and their corresponding splits are of equal length and resets the receiver list
     * based on the provided arrays. It validates each split value and calculates the new total split. Existing
     * receivers not included in the new list are removed, and new ones are added.
     *
     * Key steps in the function:
     *  - Validate input arrays: Ensures the length of both arrays (receivers and splits) are equal.
     *  - Reset the receiver list: Clears the current receiver list and mapping.
     *  - Process new receivers: Iterates through the new lists, adding each receiver with its split, ensuring the total
     *    split remains within valid bounds.
     *
     * This comprehensive update approach allows for batch updates to the receiver list, making it more efficient for
     * scenarios where multiple changes are needed.
     *
     * Only the contract owner can execute this function, ensuring controlled management of distribution parameters.
     *
     * @param receivers An array of addresses for the new set of fee receivers.
     * @param splits An array of split percentages corresponding to each receiver in the `receivers` array.
     */
    function setReceivers(address[] calldata receivers, uint96[] calldata splits) external onlyOwner {
        FeeSplitterStorage storage $ = _getFeeSplitterStorage();
        uint256 numReceivers = receivers.length;
        assert(numReceivers == splits.length);
        uint256 splitTotal;
        uint256 currentLength = $.feeReceivers.length;

        FeeReceiver[] storage feeReceivers = $.feeReceivers;
        mapping(address => uint256) storage receiverPos = $.receiverPos;

        while (currentLength > numReceivers) {
            unchecked {
                --currentLength;
            }
            (address receiver,) = _unsafeFeeReceiverAccess(feeReceivers, currentLength);
            receiverPos[receiver] = 0;
            feeReceivers.pop();
        }

        for (uint256 i = currentLength; i != 0;) {
            unchecked {
                --i;
            }
            (address receiver,) = _unsafeFeeReceiverAccess(feeReceivers, i);
            receiverPos[receiver] = 0;
        }

        for (uint256 i = numReceivers; i != 0;) {
            unchecked {
                --i;
            }
            address receiver = receivers[i];
            uint96 split = splits[i];
            _validateSplitValue(split, splitTotal);
            splitTotal += split;
            if (i < currentLength) {
                feeReceivers[i] = FeeReceiver(receiver, split);
                receiverPos[receiver] = i + 1;
            } else {
                feeReceivers.push(FeeReceiver(receiver, split));
                receiverPos[receiver] = feeReceivers.length;
            }
        }

        $.splitTotal = splitTotal;
    }

    /**
     * @notice Calculates the current rate of token distribution per second.
     * @dev This function computes the rate at which tokens are being distributed based on the historical distribution
     * data. It uses the checkpoint system to calculate the average distribution rate over the period from the oldest to
     * the latest checkpoint. If the current timestamp is before the oldest checkpoint, it returns 0, indicating no
     * distribution has occurred yet.
     *
     * Key steps in the function:
     *  - Retrieve checkpoints: Fetches the oldest and latest checkpoints from the storage.
     *  - Calculate time elapsed: Determines the time interval between the oldest and current timestamp.
     *  - Compute distribution rate: Calculates the average distribution rate per second over the elapsed time.
     *
     * This function provides valuable insights into the contract's distribution efficiency and is useful for analytics
     * and monitoring purposes.
     *
     * @return tokensPerSecond The average rate of token distribution per second, calculated over the checkpoint
     * interval.
     */
    function distributionRate() public view returns (uint256 tokensPerSecond) {
        FeeSplitterStorage storage $ = _getFeeSplitterStorage();
        uint256 lastCheckpointIndex = $.lastCheckpointIndex;
        Checkpoint memory oldestCheckpoint = $.checkpoints[(lastCheckpointIndex + 1) % CHECKPOINT_HISTORY_LENGTH];
        Checkpoint memory latestCheckpoint = $.checkpoints[lastCheckpointIndex];

        if (latestCheckpoint.timestamp <= oldestCheckpoint.timestamp) return 0;

        uint256 timeElapsed;

        unchecked {
            timeElapsed = latestCheckpoint.timestamp - oldestCheckpoint.timestamp;
        }

        if (latestCheckpoint.totalDistributed >= oldestCheckpoint.totalDistributed) {
            unchecked {
                tokensPerSecond = (latestCheckpoint.totalDistributed - oldestCheckpoint.totalDistributed) / timeElapsed;
            }
        }
    }

    /**
     * @notice Calculates the distribution rate per second for a specific fee receiver.
     * @dev This function extends the `distributionRate` function by determining the rate of token distribution for a
     * specific receiver. It calculates the receiver's share of the total distribution based on their split ratio. If
     * the receiver is not found or if there are no receivers, the function returns 0.
     *
     * Key steps in the function:
     *  - Validate receiver: Checks if the receiver is in the distribution list and has a non-zero split ratio.
     *  - Calculate receiver's rate: Determines the receiver's share of the total distribution rate, proportional to
     *    their split percentage.
     *
     * This function is useful for receivers to understand their individual share of the distribution and for tracking
     * individual receiver performance over time.
     *
     * @param feeReceiver The address of the fee receiver for whom the distribution rate is calculated.
     * @return tokensPerSecond The distribution rate per second for the specified fee receiver.
     */
    function distributionRateFor(address feeReceiver) external view returns (uint256 tokensPerSecond) {
        FeeSplitterStorage storage $ = _getFeeSplitterStorage();
        uint256 pos = $.receiverPos[feeReceiver];
        uint256 splitTotal = $.splitTotal;
        if (pos != 0 && splitTotal != 0) {
            tokensPerSecond = distributionRate() * $.feeReceivers[pos - 1].split / splitTotal;
        }
    }

    function checkpoint(uint256 index) external view returns (Checkpoint memory) {
        FeeSplitterStorage storage $ = _getFeeSplitterStorage();
        uint256 lastCheckpointIndex = $.lastCheckpointIndex;
        return $.checkpoints[(lastCheckpointIndex + index) % CHECKPOINT_HISTORY_LENGTH];
    }

    function allReceivers() external view returns (FeeReceiver[] memory) {
        FeeSplitterStorage storage $ = _getFeeSplitterStorage();
        return $.feeReceivers;
    }

    /**
     * @notice Validates the split value for a receiver in the distribution list.
     * @dev This internal function checks whether a given split value is valid within the context of the total split. It
     * ensures that the split value is non-zero and that the sum of this value and the existing total split does not
     * exceed the maximum allowed for a uint96. The function reverts with `InvalidSplitValue` if these conditions are
     * not met.
     *
     * This validation step is crucial in maintaining the integrity of the distribution ratios and preventing overflows
     * in split calculations.
     *
     * @param split The split percentage to validate.
     * @param splitTotal The current total split percentage against which the new value is to be validated.
     */
    function _validateSplitValue(uint96 split, uint256 splitTotal) internal pure {
        if (split == 0 || splitTotal + split > type(uint96).max) {
            revert InvalidSplitValue(split);
        }
    }

    /**
     * @notice Updates the distribution checkpoints.
     * @dev This private function manages the checkpoint system for tracking token distributions over time. It updates
     * the checkpoints array with the current timestamp and the total distributed amount. The function ensures
     * checkpoints are updated at regular intervals defined by `CHECKPOINT_INTERVAL`. If the current timestamp is
     * sufficiently after the last checkpoint, a new checkpoint is recorded.
     *
     * This checkpoint system is critical for calculating distribution rates and providing a historical view of
     * distributions.
     *
     * @param totalDistributed The total amount of tokens distributed up to this point.
     */
    function _updateCheckpoints(uint256 totalDistributed) private {
        FeeSplitterStorage storage $ = _getFeeSplitterStorage();
        uint256 currentIndex = $.lastCheckpointIndex;
        uint256 nextIndex = (currentIndex + 1) % CHECKPOINT_HISTORY_LENGTH;
        if (block.timestamp >= $.checkpoints[currentIndex].timestamp + CHECKPOINT_INTERVAL) {
            $.checkpoints[nextIndex] = Checkpoint(block.timestamp, totalDistributed);
            $.lastCheckpointIndex = nextIndex;
        }
        $.totalDistributed = totalDistributed;
    }

    /**
     * @notice Accesses a fee receiver from the storage using low-level assembly.
     * @dev This private function utilizes EVM assembly for direct storage access, bypassing Solidity's safety checks. It
     * is used to retrieve the address and split percentage of a fee receiver from the storage. This approach is more
     * gas-efficient but requires careful handling to avoid security issues.
     *
     * Important: This function should only be called with valid indexes, as it does not perform boundary checks.
     * Improper use can lead to undefined behavior or security vulnerabilities.
     *
     * @param arr The storage array of fee receivers.
     * @param pos The position of the fee receiver in the array.
     * @return feeReceiver The address of the fee receiver.
     * @return split The split percentage of the fee receiver.
     */
    function _unsafeFeeReceiverAccess(FeeReceiver[] storage arr, uint256 pos)
        private
        view
        returns (address feeReceiver, uint96 split)
    {
        // slither-disable-next-line assembly
        assembly {
            mstore(0, arr.slot)
            let slot := add(keccak256(0, 0x20), pos)
            let value := sload(slot)
            feeReceiver := and(value, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            split := shr(160, value)
        }
    }
}
