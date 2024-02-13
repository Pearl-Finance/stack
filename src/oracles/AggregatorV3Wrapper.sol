// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {AggregatorV3Interface} from "@chainlink/interfaces/AggregatorV3Interface.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IOracle} from "../interfaces/IOracle.sol";
import {Constants} from "../libraries/Constants.sol";

contract AggregatorV3Wrapper is IOracle {
    using Math for uint256;

    address public immutable token;
    address public immutable aggregator;

    bool private immutable _scaleUp;
    uint256 private immutable _scalePrecision;
    uint256 private immutable _tokenPrecision;

    constructor(address _token, address _aggregator) {
        token = _token;
        aggregator = _aggregator;
        _tokenPrecision = 10 ** IERC20Metadata(_token).decimals();
        uint256 aggregatorPrecision = 10 ** AggregatorV3Interface(_aggregator).decimals();
        require(aggregatorPrecision <= Constants.ORACLE_PRICE_PRECISION, "OracleWrapper: too many decimals");
        bool scaleUp = aggregatorPrecision < Constants.ORACLE_PRICE_PRECISION;
        _scaleUp = scaleUp;
        _scalePrecision = scaleUp ? Constants.ORACLE_PRICE_PRECISION / aggregatorPrecision : 1;
    }

    function amountOf(uint256 value, Math.Rounding rounding) external view returns (uint256 amount) {
        amount = value.mulDiv(_tokenPrecision, _latestPrice(), rounding);
    }

    function amountOfAtPrice(uint256 value, uint256 price, Math.Rounding rounding)
        external
        view
        returns (uint256 amount)
    {
        amount = value.mulDiv(_tokenPrecision, price, rounding);
    }

    function latestPrice() external view returns (uint256 price) {
        (price,) = _priceInfo();
    }

    function latestPrice(uint256 maxAge) external view returns (uint256 price) {
        uint256 age;
        (price, age) = _priceInfo();
        if (maxAge < age) {
            revert StalePrice(price, maxAge, age);
        }
    }

    function valueOf(uint256 amount, Math.Rounding rounding) external view returns (uint256 value) {
        value = _valueOf(amount, _latestPrice(), rounding);
    }

    function valueOfAtPrice(uint256 amount, uint256 price, Math.Rounding rounding)
        external
        view
        returns (uint256 value)
    {
        value = _valueOf(amount, price, rounding);
    }

    function _valueOf(uint256 amount, uint256 price, Math.Rounding rounding) internal view returns (uint256 value) {
        value = amount.mulDiv(price, _tokenPrecision, rounding);
    }

    function _latestPrice() internal view returns (uint256 price) {
        (price,) = _priceInfo();
    }

    function _priceInfo() private view returns (uint256 price, uint256 age) {
        (
            /* uint80 roundID */
            ,
            int256 answer,
            /*uint startedAt*/
            ,
            uint256 timestamp,
            /*uint80 answeredInRound*/
        ) = AggregatorV3Interface(aggregator).latestRoundData();
        price = uint256(answer) * _scalePrecision;
        age = block.timestamp - timestamp;
    }
}
