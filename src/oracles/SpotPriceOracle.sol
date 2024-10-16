// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPair} from "src/interfaces/IPair.sol";
import {ISpotPriceOracle} from "src/interfaces/ISpotPriceOracle.sol";

contract SpotPriceOracle is ISpotPriceOracle {
    IPair public immutable pair;

    uint8 public immutable decimals;

    uint256 private immutable _token0Scale;
    uint256 private immutable _token1Scale;
    uint256 private immutable _precision;

    function () view returns (uint256, uint256) private immutable _getReserves;
    function () view returns (uint256) private immutable _calculatePrice;

    constructor(address _pair, bool zeroInOne, uint8 _decimals) {
        pair = IPair(_pair);
        decimals = _decimals;

        _token0Scale = 10 ** (18 - IERC20Metadata(pair.token0()).decimals());
        _token1Scale = 10 ** (18 - IERC20Metadata(pair.token1()).decimals());
        _precision = 10 ** _decimals;

        _getReserves = zeroInOne ? _getReserves01 : _getReserves10;
        _calculatePrice = pair.stable() ? _calculatePriceStable : _calculatePriceVolatile;
    }

    function currentPrice() external view returns (uint256 timestamp, uint256 price) {
        timestamp = block.timestamp;
        price = _calculatePrice();
    }

    function _getReserves01() private view returns (uint256 reserveA, uint256 reserveB) {
        (reserveA, reserveB,) = pair.getReserves();
        reserveA *= _token0Scale;
        reserveB *= _token1Scale;
    }

    function _getReserves10() private view returns (uint256 reserveA, uint256 reserveB) {
        (reserveB, reserveA,) = pair.getReserves();
        reserveA *= _token1Scale;
        reserveB *= _token0Scale;
    }

    function _calculatePriceStable() private view returns (uint256) {
        (uint256 reserveA, uint256 reserveB) = _getReserves();
        if (reserveA == 0 || reserveB == 0) {
            return 0;
        }
        return Math.mulDiv(
            Math.mulDiv(
                _precision,
                3 * reserveA ** 2 / 1e18 + reserveB ** 2 / 1e18,
                3 * reserveB ** 2 / 1e18 + reserveA ** 2 / 1e18
            ),
            reserveB,
            reserveA,
            Math.Rounding.Trunc
        );
    }

    function _calculatePriceVolatile() private view returns (uint256) {
        (uint256 reserveA, uint256 reserveB) = _getReserves();
        if (reserveA == 0 || reserveB == 0) {
            return 0;
        }
        return reserveB * _precision / reserveA;
    }
}
