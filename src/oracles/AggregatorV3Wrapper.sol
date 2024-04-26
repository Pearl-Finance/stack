// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IOracle} from "../interfaces/IOracle.sol";
import {Constants} from "../libraries/Constants.sol";

/**
 * @title AggregatorV3Wrapper
 * @author SeaZarrgh LaBuoy
 *
 * @notice Wraps a Chainlink Aggregator V3 to conform to the IOracle interface, providing price data for a specific
 * token.
 *
 * @dev This contract acts as an adapter between the Chainlink Aggregator V3 interface and the IOracle interface,
 * allowing it to be used wherever IOracle price data is required. It handles differences in decimal precision
 * between the token and the aggregator, scaling prices as necessary.
 */
contract AggregatorV3Wrapper is IOracle {
    using Math for uint256;

    address public immutable token;
    address public immutable aggregator;

    bool private immutable _scaleUp;
    uint256 private immutable _scalePrecision;
    uint256 private immutable _tokenPrecision;

    /**
     * @notice Initializes a new AggregatorV3Wrapper contract for a specific token and Chainlink price feed.
     * @dev Sets up the contract by storing the addresses of the token and the Chainlink aggregator. It calculates and
     * stores scaling factors to reconcile differences in decimal precision between the token, the aggregator, and
     * the expected oracle precision.
     * @param _token The address of the ERC20 token for which this oracle provides price data.
     * @param _aggregator The address of the Chainlink Aggregator V3 contract providing price data for the token.
     */
    constructor(address _token, address _aggregator) {
        token = _token;
        aggregator = _aggregator;
        _tokenPrecision = 10 ** IERC20Metadata(_token).decimals();
        uint256 aggregatorPrecision = 10 ** AggregatorV3Interface(_aggregator).decimals();
        require(aggregatorPrecision <= Constants.ORACLE_PRICE_PRECISION, "AggregatorV3Wrapper: too many decimals");
        bool scaleUp = aggregatorPrecision < Constants.ORACLE_PRICE_PRECISION;
        _scaleUp = scaleUp;
        _scalePrecision = scaleUp ? Constants.ORACLE_PRICE_PRECISION / aggregatorPrecision : 1;
    }

    /**
     * @notice Calculates the amount of tokens equivalent to a given value in the oracle's pricing currency.
     * @dev Uses the latest price from the aggregator to convert a value in the pricing currency to an equivalent
     * amount of tokens. Scales the price as necessary to match the token's precision.
     * @param value The value in the oracle's pricing currency to convert to tokens.
     * @param rounding The rounding direction to use when converting (up or down).
     * @return amount The equivalent amount of tokens.
     */
    function amountOf(uint256 value, Math.Rounding rounding) external view returns (uint256 amount) {
        amount = value.mulDiv(_tokenPrecision, _latestPrice(), rounding);
    }

    /**
     * @notice Calculates the amount of tokens equivalent to a given value in the oracle's pricing currency, ensuring
     * the price data is not older than maxAge.
     * @param value The value in the oracle's pricing currency to convert to tokens.
     * @param maxAge The maximum age (in seconds) for valid price data.
     * @param rounding The rounding direction to use in the calculation.
     * @return amount The equivalent amount of tokens based on the current price, if it's not stale.
     */
    function amountOf(uint256 value, uint256 maxAge, Math.Rounding rounding) external view returns (uint256 amount) {
        uint256 price;
        uint256 age;
        (price, age) = _priceInfo();
        if (age > maxAge) {
            revert StalePrice(price, maxAge, age);
        }
        amount = value.mulDiv(_tokenPrecision, price, rounding);
    }

    /**
     * @notice Calculates the amount of tokens equivalent to a given value in the oracle's pricing currency at a
     * specific price.
     * @dev Converts a value in the pricing currency to an equivalent amount of tokens using the provided price, scaling
     * the calculation to match the token's precision.
     * @param value The value in the oracle's pricing currency to convert to tokens.
     * @param price The price of the token in the oracle's pricing currency to use for the conversion.
     * @param rounding The rounding direction to use in the calculation (up or down).
     * @return amount The equivalent amount of tokens at the specified price.
     */
    function amountOfAtPrice(uint256 value, uint256 price, Math.Rounding rounding)
        external
        view
        returns (uint256 amount)
    {
        amount = value.mulDiv(_tokenPrecision, price, rounding);
    }

    /**
     * @notice Retrieves the latest price of the token from the Chainlink aggregator.
     * @dev Returns the latest price, scaled as necessary to match the expected oracle precision. This version of the
     * function does not check the age of the price data.
     * @return price The latest price of the token.
     */
    function latestPrice() external view returns (uint256 price) {
        (price,) = _priceInfo();
    }

    /**
     * @notice Retrieves the latest price of the token from the Chainlink aggregator, ensuring it is not older than
     * maxAge.
     * @dev Returns the latest price, scaled to match the expected oracle precision. Reverts if the latest price data is
     * older than maxAge seconds.
     * @param maxAge The maximum age (in seconds) of the price data that is considered valid.
     * @return price The latest price of the token.
     */
    function latestPrice(uint256 maxAge) external view returns (uint256 price) {
        uint256 age;
        (price, age) = _priceInfo();
        if (maxAge < age) {
            revert StalePrice(price, maxAge, age);
        }
    }

    /**
     * @notice Calculates the value in the oracle's pricing currency of a given amount of tokens.
     * @dev Uses the latest price from the aggregator to convert an amount of tokens to an equivalent value in the
     * oracle's pricing currency, scaling the price as necessary.
     * @param amount The amount of tokens to convert to the oracle's pricing currency.
     * @param rounding The rounding direction to use in the calculation (up or down).
     * @return value The equivalent value in the oracle's pricing currency.
     */
    function valueOf(uint256 amount, Math.Rounding rounding) external view returns (uint256 value) {
        value = _valueOf(amount, _latestPrice(), rounding);
    }

    /**
     * @notice Calculates the value in the oracle's pricing currency of a given amount of tokens, ensuring the price
     * data is not older than maxAge.
     * @param amount The amount of tokens to convert to the oracle's pricing currency.
     * @param maxAge The maximum age (in seconds) for valid price data.
     * @param rounding The rounding direction to use in the calculation.
     * @return value The equivalent value in the oracle's pricing currency based on the current price, if it's not
     * stale.
     */
    function valueOf(uint256 amount, uint256 maxAge, Math.Rounding rounding) external view returns (uint256 value) {
        uint256 price;
        uint256 age;
        (price, age) = _priceInfo();
        if (age > maxAge) {
            revert StalePrice(price, maxAge, age);
        }
        value = _valueOf(amount, price, rounding);
    }

    /**
     * @notice Calculates the value in the oracle's pricing currency of a given amount of tokens at a specific price.
     * @dev Converts an amount of tokens to an equivalent value in the oracle's pricing currency using the provided
     * price, scaling the calculation to match the token's precision.
     * @param amount The amount of tokens to convert to the oracle's pricing currency.
     * @param price The price of the token in the oracle's pricing currency to use for the conversion.
     * @param rounding The rounding direction to use in the calculation (up or down).
     * @return value The equivalent value in the oracle's pricing currency at the specified price.
     */
    function valueOfAtPrice(uint256 amount, uint256 price, Math.Rounding rounding)
        external
        view
        returns (uint256 value)
    {
        value = _valueOf(amount, price, rounding);
    }

    /**
     * @dev Internal function to calculate the value in the oracle's pricing currency of a given amount of tokens at a
     * specific price. This function applies scaling to account for differences in decimal precision between the token
     * and the oracle's pricing currency.
     * @param amount The amount of tokens to convert to the oracle's pricing currency.
     * @param price The price of the token in the oracle's pricing currency to use for the conversion.
     * @param rounding The rounding direction to use in the calculation (up or down).
     * @return value The calculated value in the oracle's pricing currency.
     */
    function _valueOf(uint256 amount, uint256 price, Math.Rounding rounding) internal view returns (uint256 value) {
        value = amount.mulDiv(price, _tokenPrecision, rounding);
    }

    /**
     * @dev Internal function to retrieve the latest price of the token from the Chainlink aggregator.
     * Applies scaling as necessary to match the expected oracle precision. This function abstracts the retrieval and
     * scaling logic for the latest price, simplifying other functions that require the current price.
     * @return price The latest scaled price of the token.
     */
    function _latestPrice() internal view returns (uint256 price) {
        (price,) = _priceInfo();
    }

    /**
     * @dev Private function to fetch the latest price and its timestamp from the Chainlink aggregator and scale the
     * price. Returns both the scaled price and the age of the price data, allowing calling functions to perform
     * additional checks or calculations as necessary.
     * @return price The latest scaled price from the aggregator.
     * @return age The age of the latest price data in seconds.
     */
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
