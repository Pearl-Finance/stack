// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {AggregatorV3Interface} from "@chainlink/interfaces/AggregatorV3Interface.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IOracle} from "../interfaces/IOracle.sol";
import {CommonErrors} from "../interfaces/CommonErrors.sol";
import {Constants} from "../libraries/Constants.sol";

/**
 * @title Capped Price Oracle Contract
 * @notice An Oracle implementation that wraps an existing oracle and caps its price to a maximum value.
 * @dev This contract implements the IOracle interface and uses another oracle for price data,
 *      but enforces a maximum cap on the price. It's useful in situations where extremely high
 *      asset price volatility needs to be mitigated.
 * @author SeaZarrgh LaBuoy
 */
contract CappedPriceOracle is IOracle, CommonErrors {
    using Math for uint256;

    address public immutable underlyingOracle;
    uint256 public immutable priceCap;

    /**
     * @notice Constructs the Capped Price Oracle contract.
     * @dev Initializes the contract with a reference to an underlying oracle and sets a price cap.
     * @param _underlyingOracle The address of the underlying oracle to fetch prices from.
     * @param _priceCap The maximum cap for the price, beyond which prices from the underlying oracle are not
     *                  considered.
     */
    constructor(address _underlyingOracle, uint256 _priceCap) {
        if (_underlyingOracle == address(0)) {
            revert InvalidZeroAddress();
        }
        underlyingOracle = _underlyingOracle;
        priceCap = _priceCap;
    }

    /**
     * @notice Converts a value in the oracle's quote currency to an amount of the token, using the capped price.
     * @dev Calculates the amount of token equivalent to the given value based on the capped price from the underlying
     *      oracle.
     * @param value The value to convert.
     * @param rounding The rounding direction (up or down).
     * @return amount The calculated amount of the token.
     */
    function amountOf(uint256 value, Math.Rounding rounding) external view returns (uint256 amount) {
        uint256 price = _capPrice(IOracle(underlyingOracle).latestPrice());
        amount = IOracle(underlyingOracle).amountOfAtPrice(value, price, rounding);
    }

    /**
     * @notice Converts a value in the oracle's quote currency to an amount in the oracle's asset, ensuring the price is
     * not older than the specified maximum age.
     * @dev Uses the underlying oracle to fetch the latest price and apply the capped value, then converts the given
     * value to the equivalent amount in the oracle's asset.
     * @param value The value to convert.
     * @param maxAge The maximum acceptable age for the price data.
     * @param rounding The rounding method (up, down, or closest).
     * @return amount The calculated amount in the oracle's asset.
     */
    function amountOf(uint256 value, uint256 maxAge, Math.Rounding rounding) external view returns (uint256 amount) {
        uint256 price = _capPrice(IOracle(underlyingOracle).latestPrice(maxAge));
        amount = IOracle(underlyingOracle).amountOfAtPrice(value, price, rounding);
    }

    /**
     * @notice Converts a value in the oracle's quote currency to an amount of the token at a specific (capped) price,
     *         applying a specified rounding method.
     * @dev Calculates the equivalent amount of the oracle's asset for a given value using the specified (and capped)
     *      price from the underlying oracle.
     * @param value The value in the base currency to be converted.
     * @param price The specific price to use for the conversion, subject to capping.
     * @param rounding The rounding method to be used (up, down, or closest).
     * @return amount The calculated amount in the oracle's asset at the specified (capped) price.
     */
    function amountOfAtPrice(uint256 value, uint256 price, Math.Rounding rounding)
        external
        view
        returns (uint256 amount)
    {
        amount = IOracle(underlyingOracle).amountOfAtPrice(value, _capPrice(price), rounding);
    }

    /**
     * @notice Retrieves the latest price from the underlying oracle, capped to a maximum value.
     * @dev Returns the latest price from the underlying oracle, but ensures it does not exceed the set price cap.
     * @return price The latest (capped) price of the token.
     */
    function latestPrice() external view returns (uint256 price) {
        price = _capPrice(IOracle(underlyingOracle).latestPrice());
    }

    /**
     * @notice Retrieves the latest price from the underlying oracle, ensuring it is not older than a specified maximum
     *         age and is capped to a maximum value.
     * @dev Returns the latest price from the underlying oracle, capped to the price cap, and ensures it is not older
     *      than `maxAge`.
     * @param maxAge The maximum age in seconds for the price to be considered valid.
     * @return price The latest (capped) price of the token.
     */
    function latestPrice(uint256 maxAge) external view returns (uint256 price) {
        price = _capPrice(IOracle(underlyingOracle).latestPrice(maxAge));
    }

    /**
     * @notice Calculates the value of a token amount in the oracle's quote currency, using the capped price.
     * @dev Computes the value based on the static price of the token from the underlying oracle, with a maximum cap
     *      applied.
     * @param amount The amount of the token.
     * @param rounding The rounding direction (up or down).
     * @return value The calculated value in the quote currency.
     */
    function valueOf(uint256 amount, Math.Rounding rounding) external view returns (uint256 value) {
        uint256 price = _capPrice(IOracle(underlyingOracle).latestPrice());
        value = IOracle(underlyingOracle).valueOfAtPrice(amount, price, rounding);
    }

    /**
     * @notice Converts an amount in the oracle's asset to a value in the base currency, ensuring the price data is not
     * older than a specified maximum age.
     * @dev Uses the capped price and ensures that the underlying oracle's latest price is not stale beyond the
     * specified maxAge.
     * @param amount The amount to convert.
     * @param maxAge The maximum age in seconds for the price data to be considered valid.
     * @param rounding The rounding method (up, down, or closest).
     * @return value The calculated value in the base currency.
     */
    function valueOf(uint256 amount, uint256 maxAge, Math.Rounding rounding) external view returns (uint256 value) {
        uint256 price = _capPrice(IOracle(underlyingOracle).latestPrice(maxAge));
        value = IOracle(underlyingOracle).valueOfAtPrice(amount, price, rounding);
    }

    /**
     * @notice Converts an amount in the oracle's asset to a value in the base currency at a specific (capped) price,
     *         applying a specified rounding method.
     * @dev Calculates the equivalent value in the base currency for a given amount of the oracle's asset using the
     *      specified (and capped) price from the underlying oracle.
     * @param amount The amount of the oracle's asset to be converted.
     * @param price The specific price to use for the conversion, subject to capping.
     * @param rounding The rounding method to be used (up, down, or closest).
     * @return value The calculated value in the base currency at the specified (capped) price.
     */
    function valueOfAtPrice(uint256 amount, uint256 price, Math.Rounding rounding)
        external
        view
        returns (uint256 value)
    {
        value = IOracle(underlyingOracle).valueOfAtPrice(amount, _capPrice(price), rounding);
    }

    /**
     * @notice Internal function to apply the price cap to a given price.
     * @dev Ensures that the returned price does not exceed the set price cap.
     * @param price The original price to be capped.
     * @return The capped price, which is the lesser of the original price or the price cap.
     */
    function _capPrice(uint256 price) internal view returns (uint256) {
        return price > priceCap ? priceCap : price;
    }
}
