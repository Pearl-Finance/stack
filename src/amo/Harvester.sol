// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IGauge} from "src/interfaces/IGauge.sol";

abstract contract Harvester is OwnableUpgradeable {
    /// @custom:storage-location erc7201:pearl.storage.Harvester
    struct HarvesterStorage {
        address harvester;
        address rewardReceiver;
        uint256 lastHarvestTimestamp;
    }

    // keccak256(abi.encode(uint256(keccak256("pearl.storage.Harvester")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant HarvesterStorageLocation =
        0x70ce5f60a4dfa0c194c87f8a8f10618294596b11b6d132724e5a4f5a2007af00;

    function _getHarvesterStorage() internal pure returns (HarvesterStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := HarvesterStorageLocation
        }
    }

    IGauge public immutable gauge;

    event HarvesterUpdate(address indexed harvester);
    event RewardReceiverUpdate(address indexed rewardReceiver);

    error UnauthorizedHarvester();
    error ValueUnchanged();

    modifier onlyHarvester() {
        HarvesterStorage storage $ = _getHarvesterStorage();
        if (msg.sender != $.harvester && msg.sender != owner()) {
            revert UnauthorizedHarvester();
        }
        _;
    }

    constructor(address _gauge) {
        gauge = IGauge(_gauge);
    }

    function __Harvester_init(address initialOwner, address harvester_, address rewardReceiver_)
        internal
        onlyInitializing
    {
        __Ownable_init(initialOwner);
        __Harvester_init_unchained(harvester_, rewardReceiver_);
    }

    function __Harvester_init_unchained(address harvester_, address rewardReceiver_) internal onlyInitializing {
        HarvesterStorage storage $ = _getHarvesterStorage();
        $.harvester = harvester_;
        $.rewardReceiver = rewardReceiver_;
        $.lastHarvestTimestamp = block.timestamp;
    }

    function setHarvester(address _harvester) external onlyOwner {
        HarvesterStorage storage $ = _getHarvesterStorage();
        if ($.harvester == _harvester) {
            revert ValueUnchanged();
        }
        $.harvester = _harvester;
        emit HarvesterUpdate(_harvester);
    }

    function setRewardReceiver(address _rewardReceiver) external onlyOwner {
        HarvesterStorage storage $ = _getHarvesterStorage();
        if ($.rewardReceiver == _rewardReceiver) {
            revert ValueUnchanged();
        }
        $.rewardReceiver = _rewardReceiver;
        emit RewardReceiverUpdate(_rewardReceiver);
    }

    function harvestReward() external onlyHarvester {
        HarvesterStorage storage $ = _getHarvesterStorage();
        _harvestReward($);
    }

    function _harvestReward(HarvesterStorage storage $) internal {
        gauge.getReward();
        IERC20 rewardToken = IERC20(gauge.rewardToken());
        uint256 balanceReward = rewardToken.balanceOf(address(this));
        if (balanceReward != 0) {
            SafeERC20.safeTransfer(rewardToken, $.rewardReceiver, balanceReward);
        }
        $.lastHarvestTimestamp = block.timestamp;
    }

    function harvester() public view returns (address) {
        HarvesterStorage storage $ = _getHarvesterStorage();
        return $.harvester;
    }

    function rewardReceiver() public view returns (address) {
        HarvesterStorage storage $ = _getHarvesterStorage();
        return $.rewardReceiver;
    }

    function lastHarvestTimestamp() public view returns (uint256) {
        HarvesterStorage storage $ = _getHarvesterStorage();
        return $.lastHarvestTimestamp;
    }
}
