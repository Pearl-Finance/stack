// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract TWAPOracle is AggregatorV3Interface, Ownable {
    using SafeCast for uint256;

    uint8 public immutable override decimals;
    uint256 public immutable override version;

    address public keeper;
    uint256 public lastPrice;
    string public override description;

    uint256 private _lastUpdateTimestamp;
    uint256 private _cumulativePrice;
    uint256 private _totalTime;

    event KeeperUpdated(address indexed keeper);

    error InvalidUpdate();
    error NotImplemented();
    error Unauthorized();
    error ValueUnchanged();
    error ZeroAddress();

    constructor(string memory _description, address initialOwner) Ownable(initialOwner) {
        decimals = 8;
        version = 0;
        description = _description;
        keeper = initialOwner;
        emit KeeperUpdated(initialOwner);
    }

    function setKeeper(address _keeper) external {
        if (msg.sender != keeper) {
            revert Unauthorized();
        }
        if (msg.sender == _keeper) {
            revert ValueUnchanged();
        }
        keeper = _keeper;
        emit KeeperUpdated(_keeper);
    }

    function setDescription(string memory _description) external onlyOwner {
        description = _description;
    }

    function update(uint256 _lastPrice, uint256 cumulativePrice, uint256 totalDuration) public {
        if (msg.sender != keeper) {
            revert Unauthorized();
        }

        if (block.timestamp <= _lastUpdateTimestamp) {
            revert InvalidUpdate();
        }

        lastPrice = _lastPrice;

        _lastUpdateTimestamp = block.timestamp;
        _cumulativePrice = cumulativePrice;
        _totalTime = totalDuration;
    }

    function getRoundData(uint80) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert NotImplemented();
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId_, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (_totalTime != 0) {
            updatedAt = _lastUpdateTimestamp;
            roundId_ = uint80(block.number);
            answer = _calculateTWAP().toInt256();
            startedAt = updatedAt - _totalTime;
            answeredInRound = roundId_;
        }
    }

    function _calculateTWAP() private view returns (uint256) {
        uint256 lastDuration = block.timestamp - _lastUpdateTimestamp;
        uint256 cumulativePrice = _cumulativePrice + lastPrice * lastDuration;
        uint256 totalTime = _totalTime + lastDuration;
        return cumulativePrice / totalTime;
    }
}
