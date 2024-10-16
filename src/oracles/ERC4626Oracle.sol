// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract ERC4626Oracle is AggregatorV3Interface {
    using SafeCast for uint256;

    uint8 public immutable decimals;
    uint256 public immutable version;

    string public description;

    IERC4626 private immutable _token;
    AggregatorV3Interface private immutable _underlyingTokenAggregator;
    uint256 private immutable _scale;

    function(uint256,uint256) internal pure returns (uint256) immutable _scaleFn;

    constructor(address token, address underlyingTokenAggregator, string memory _description) {
        _token = IERC4626(token);
        _underlyingTokenAggregator = AggregatorV3Interface(underlyingTokenAggregator);
        decimals = AggregatorV3Interface(underlyingTokenAggregator).decimals();
        description = _description;
        version = 1;

        int8 tokenDecimalDiff = int8(IERC20Metadata(_token.asset()).decimals()) - int8(_token.decimals());

        uint256 scale;
        function(uint256,uint256) internal pure returns (uint256) scaleFn;

        if (tokenDecimalDiff > 0) {
            // ERC4626 vault has more decimals than the underlying token
            scale = 10 ** uint8(tokenDecimalDiff);
            scaleFn = _scaleUp;
        } else if (tokenDecimalDiff < 0) {
            // ERC4626 vault has less decimals than the underlying token
            scale = 10 ** uint8(-tokenDecimalDiff);
            scaleFn = _scaleDown;
        } else {
            scaleFn = _noop;
        }
        _scale = scale;
        _scaleFn = scaleFn;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = _underlyingTokenAggregator.getRoundData(_roundId);
        answer = _convertPrice(answer);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = _underlyingTokenAggregator.latestRoundData();
        answer = _convertPrice(answer);
    }

    function _convertPrice(int256 price) internal view returns (int256) {
        if (price > 0) {
            uint256 scaledPrice = _scaleFn(uint256(price), _scale);
            return _token.convertToAssets(scaledPrice).toInt256();
        }
        return 0;
    }

    function _scaleUp(uint256 value, uint256 scale) internal pure returns (uint256) {
        return value * scale;
    }

    function _scaleDown(uint256 value, uint256 scale) internal pure returns (uint256) {
        return value / scale;
    }

    function _noop(uint256 value, uint256 /*scale*/ ) internal pure returns (uint256) {
        return value;
    }
}
