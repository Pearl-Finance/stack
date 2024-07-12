// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract StackOracle is AggregatorV3Interface, Ownable {
    using SafeCast for int256;
    using SafeCast for uint128;

    event OracleUpdate(string key, uint128 value, uint128 timestamp);
    event HeartbeatSenderAddressChange(address newSender);
    event UpdaterAddressChange(address newUpdater);

    error NotImplemented();

    address public heartbeatSender;
    address public oracleUpdater;

    uint256 private _value;
    string private _description;
    string private _pairKey;

    constructor(address initialOwner, uint256 initialPrice, string memory description_, string memory pairKey_)
        Ownable(initialOwner)
    {
        _description = description_;
        _pairKey = pairKey_;
        _value = (((uint256)(initialPrice)) << 128) + block.timestamp;
    }

    function pairKey() external view returns (string memory) {
        return _pairKey;
    }

    function setPairKey(string memory newPairKey) external onlyOwner {
        _pairKey = newPairKey;
    }

    function version() external pure override returns (uint256) {
        return 0;
    }

    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function setDescription(string memory newDescription) external onlyOwner {
        _description = newDescription;
    }

    function getRoundData(uint80 /*_roundId*/ )
        external
        pure
        returns (
            uint80, /*roundId*/
            int256, /*answer*/
            uint256, /*startedAt*/
            uint256, /*updatedAt*/
            uint80 /*answeredInRound*/
        )
    {
        revert NotImplemented();
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId_, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (int128 value, uint128 timestamp) = getValueAndTimestamp();

        roundId_ = uint80(block.number);
        answer = value;
        startedAt = timestamp;
        updatedAt = timestamp;
        answeredInRound = uint80(block.number);
    }

    function getValue() private view returns (uint128, uint128) {
        uint256 cValue = _value;
        uint128 timestamp = (uint128)(cValue % 2 ** 128);
        uint128 value = (uint128)(cValue >> 128);
        return (value, timestamp);
    }

    function setValue(uint128 value, uint128 timestamp) external {
        uint256 currentValue = (uint128)(_value >> 128);
        if (value == currentValue) {
            require(msg.sender == heartbeatSender || msg.sender == oracleUpdater);
        } else {
            require(msg.sender == oracleUpdater);
        }
        _value = (((uint256)(value)) << 128) + timestamp;
        emit OracleUpdate(_pairKey, value, timestamp);
    }

    function getValueAndTimestamp() private view returns (int128, uint128) {
        (uint128 value, uint128 timestamp) = getValue();
        return (value.toInt256().toInt128(), timestamp);
    }

    function latestAnswer() external view returns (int256 answer) {
        (answer,) = getValueAndTimestamp();
        return (answer);
    }

    function updateHeartbeatSenderAddress(address newHeartbeatSenderAddress) external onlyOwner {
        heartbeatSender = newHeartbeatSenderAddress;
        emit HeartbeatSenderAddressChange(newHeartbeatSenderAddress);
    }

    function updateOracleUpdaterAddress(address newOracleUpdaterAddress) external onlyOwner {
        oracleUpdater = newOracleUpdaterAddress;
        emit UpdaterAddressChange(newOracleUpdaterAddress);
    }
}
