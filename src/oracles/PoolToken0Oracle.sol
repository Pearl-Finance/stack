// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface IPair {
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1, uint256 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract PoolToken0Oracle is AggregatorV3Interface, Ownable {
    using SafeCast for int256;
    using SafeCast for uint128;
    using SafeCast for uint256;

    error NotImplemented();

    IPair public immutable pair;
    AggregatorV3Interface public immutable priceFeedToken1;

    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;

    uint256 private _value;
    string private _description;
    string private _pairKey;

    constructor(
        address initialOwner,
        string memory description_,
        string memory pairKey_,
        address pairAddress,
        address priceFeedAddress
    ) Ownable(initialOwner) {
        _description = description_;
        _pairKey = pairKey_;
        pair = IPair(pairAddress);
        priceFeedToken1 = AggregatorV3Interface(priceFeedAddress);
        token0Decimals = IERC20Metadata(pair.token0()).decimals();
        token1Decimals = IERC20Metadata(pair.token1()).decimals();
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

    function decimals() public pure override returns (uint8) {
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
        (uint128 priceToken0InUSD, uint128 timestamp) = getValue();

        roundId_ = uint80(block.number);
        answer = priceToken0InUSD.toInt256();
        startedAt = timestamp;
        updatedAt = timestamp;
        answeredInRound = uint80(block.number);
    }

    function getValue() public view returns (uint128, uint128) {
        // Fetch the latest price of token1 in USD and its decimals
        (, int256 priceToken1USD,,,) = priceFeedToken1.latestRoundData();
        uint8 token1PriceDecimals = priceFeedToken1.decimals();

        // Fetch reserves from the liquidity pool
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();

        // Normalize both reserves to 18 decimals
        uint256 adjustedReserve0 = reserve0 * (10 ** (18 - token0Decimals));
        uint256 adjustedReserve1 = reserve1 * (10 ** (18 - token1Decimals));

        // Calculate the price of token0 in terms of token1
        uint256 priceToken0InToken1 = (adjustedReserve1 * 1e18) / adjustedReserve0;

        // Convert to USD price adjusting down to 8 decimals
        uint256 priceToken0InUSD =
            (priceToken0InToken1 * uint256(priceToken1USD)) / (10 ** (18 - decimals() + token1PriceDecimals));

        return (priceToken0InUSD.toUint128(), block.timestamp.toUint128());
    }

    function getValueAndTimestamp() private view returns (int128, uint128) {
        (uint128 value, uint128 timestamp) = getValue();
        return (value.toInt256().toInt128(), timestamp);
    }

    function latestAnswer() external view returns (int256 answer) {
        (answer,) = getValueAndTimestamp();
        return (answer);
    }
}
