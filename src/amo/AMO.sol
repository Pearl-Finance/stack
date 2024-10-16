// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IAMO} from "src/interfaces/IAMO.sol";
import {IERC20Provider} from "src/interfaces/IERC20Provider.sol";
import {IGauge} from "src/interfaces/IGauge.sol";
import {IMinter} from "src/interfaces/IMinter.sol";
import {IPair} from "src/interfaces/IPair.sol";
import {ISpotPriceOracle} from "src/interfaces/ISpotPriceOracle.sol";
import {DecimalLib} from "src/libraries/DecimalLib.sol";

import {ERC20Holder} from "./ERC20Holder.sol";
import {Harvester} from "./Harvester.sol";
import {Simulator} from "./Simulator.sol";

contract AMO is
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ERC20Holder,
    Harvester,
    Simulator,
    IAMO,
    IERC20Provider
{
    using DecimalLib for uint256;
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:pearl.storage.AMO
    struct AMOStorage {
        address psm;
        address moreMinter;
        address spotPriceOracle;
        address twapOracle;
        uint256 floorPrice;
        uint256 capPrice;
    }

    // keccak256(abi.encode(uint256(keccak256("pearl.storage.AMO")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AMOStorageLocation = 0xb8e0a7b22759055fe781e967be12c31156252144c861e686e9d1f0650a6b3a00;

    function _getAMOStorage() internal pure returns (AMOStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := AMOStorageLocation
        }
    }

    uint256 public constant TARGET_PRICE = 1e8;

    IPair public immutable pair;
    IERC20 public immutable usdc;
    IERC20 public immutable more;

    uint8 private immutable _usdcDecimals;
    uint8 private immutable _moreDecimals;

    function(uint256, uint256) pure returns(uint256, uint256) private immutable _fromUsdcMore;
    function(uint256, uint256) pure returns(uint256, uint256) private immutable _toUsdcMore;

    event CapPriceUpdate(uint256 oldPrice, uint256 newPrice);
    event FloorPriceUpdate(uint256 oldPrice, uint256 newPrice);
    event MoreMinterUpdate(address indexed oldMinter, address indexed newMinter);
    event PSMUpdate(address indexed oldPSM, address indexed newPSM);
    event SpotPriceOracleUpdate(address indexed oldOracle, address indexed newOracle);
    event TWAPOracleUpdate(address indexed oldOracle, address indexed newOracle);

    error InsufficientFunds();
    error InvalidPair();
    error PreconditionNotMet();
    error PostconditionNotMet();
    error Unauthorized();

    constructor(address usdc_, address more_, address gauge_) Harvester(gauge_) {
        usdc = IERC20(usdc_);
        more = IERC20(more_);
        pair = IPair(gauge.TOKEN());

        _usdcDecimals = IERC20Metadata(usdc_).decimals();
        _moreDecimals = IERC20Metadata(more_).decimals();

        address token0 = pair.token0();
        address token1 = pair.token1();

        function(uint256, uint256) pure returns(uint256, uint256) fromUsdcMore;
        function(uint256, uint256) pure returns(uint256, uint256) toUsdcMore;

        if (token0 == address(usdc_)) {
            if (token1 != address(more_)) {
                revert InvalidPair();
            }
            fromUsdcMore = _fromKnownAmounts01; // USDC/MORE -> 01
            toUsdcMore = _toKnownAmounts01; // 01 -> USDC/MORE
        } else if (token0 == address(more_)) {
            if (token1 != address(usdc_)) {
                revert InvalidPair();
            }
            fromUsdcMore = _fromKnownAmounts10; // USDC/MORE -> 10
            toUsdcMore = _toKnownAmounts10; // 10 -> USDC/MORE
        } else {
            revert InvalidPair();
        }

        _fromUsdcMore = fromUsdcMore;
        _toUsdcMore = toUsdcMore;
    }

    function initialize(
        address initialOwner,
        address spotPriceOracle_,
        address twapOracle_,
        address minter,
        address harvester_,
        address rewardReceiver_,
        uint256 floorPrice_,
        uint256 capPrice_
    ) external initializer {
        __Harvester_init(initialOwner, harvester_, rewardReceiver_);
        __Pausable_init();
        __UUPSUpgradeable_init();

        AMOStorage storage $ = _getAMOStorage();
        $.spotPriceOracle = spotPriceOracle_;
        $.twapOracle = twapOracle_;
        $.moreMinter = minter;
        $.floorPrice = floorPrice_;
        $.capPrice = capPrice_;

        emit SpotPriceOracleUpdate(address(0), spotPriceOracle_);
        emit TWAPOracleUpdate(address(0), twapOracle_);
        emit MoreMinterUpdate(address(0), minter);
        emit FloorPriceUpdate(0, floorPrice_);
        emit CapPriceUpdate(0, capPrice_);
    }

    function setSpotPriceOracle(address oracle) external onlyOwner {
        AMOStorage storage $ = _getAMOStorage();
        address oldOracle = $.spotPriceOracle;
        if (oldOracle == oracle) {
            revert ValueUnchanged();
        }
        $.spotPriceOracle = oracle;
        emit SpotPriceOracleUpdate(oldOracle, oracle);
    }

    function setTWAPOracle(address oracle) external onlyOwner {
        AMOStorage storage $ = _getAMOStorage();
        address oldOracle = $.twapOracle;
        if (oldOracle == oracle) {
            revert ValueUnchanged();
        }
        $.twapOracle = oracle;
        emit TWAPOracleUpdate(oldOracle, oracle);
    }

    function setCapPrice(uint256 _capPrice) external onlyOwner {
        AMOStorage storage $ = _getAMOStorage();
        uint256 oldCapPrice = $.capPrice;
        if (oldCapPrice == _capPrice) {
            revert ValueUnchanged();
        }
        $.capPrice = _capPrice;
        emit CapPriceUpdate(oldCapPrice, _capPrice);
    }

    function setFloorPrice(uint256 _floorPrice) external onlyOwner {
        AMOStorage storage $ = _getAMOStorage();
        uint256 oldFloorPrice = $.floorPrice;
        if (oldFloorPrice == _floorPrice) {
            revert ValueUnchanged();
        }
        $.floorPrice = _floorPrice;
        emit CapPriceUpdate(oldFloorPrice, _floorPrice);
    }

    function setMoreMinter(address minter) external onlyOwner {
        AMOStorage storage $ = _getAMOStorage();
        address oldMinter = $.moreMinter;
        if (oldMinter == minter) {
            revert ValueUnchanged();
        }
        $.moreMinter = minter;
        emit MoreMinterUpdate(oldMinter, minter);
    }

    function setPSM(address _psm) external onlyOwner {
        AMOStorage storage $ = _getAMOStorage();
        address oldPSM = $.psm;
        if (oldPSM == _psm) {
            revert ValueUnchanged();
        }
        $.psm = _psm;
        emit PSMUpdate(oldPSM, _psm);
    }

    function addExternalLiquidity(uint256 amount) external onlyOwner {
        SafeERC20.safeTransferFrom(pair, msg.sender, address(this), amount);
        IERC20(pair).forceApprove(address(gauge), amount);
        gauge.deposit(amount);
    }

    function requestTokens(address token, uint256 amount) external override {
        AMOStorage storage $ = _getAMOStorage();
        if (msg.sender != $.psm) {
            revert Unauthorized();
        }
        _processTokenRequest(token, amount, msg.sender);
    }

    function requestTokensFor(address token, uint256 amount, address recipient) external override {
        AMOStorage storage $ = _getAMOStorage();
        if (msg.sender != $.psm) {
            revert Unauthorized();
        }
        _processTokenRequest(token, amount, recipient);
    }

    function determineNextAction() external returns (bytes memory) {
        if (!paused()) {
            AMOStorage storage $ = _getAMOStorage();
            (, uint256 currentSpotPrice) = _getMorePrice($);
            uint256 currentScore = _score(currentSpotPrice);
            if (_belowFloorPrice($)) {
                uint256 usdcBalance = usdc.balanceOf(address(this));
                if (usdcBalance != 0) {
                    (uint256 score, uint256 usdcAmount) = _optimizeFn(this.buyAndBurn, usdcBalance);
                    if (score < currentScore) {
                        return abi.encodeCall(this.buyAndBurn, (usdcAmount));
                    }
                }
                uint256 lpBalance = gauge.balanceOf(address(this));
                if (lpBalance != 0) {
                    (uint256 score, uint256 lpAmount) = _optimizeFn(this.withdrawBuyAndBurn, lpBalance);
                    if (score < currentScore) {
                        return abi.encodeCall(this.withdrawBuyAndBurn, (lpAmount));
                    }
                }
            } else if (_aboveCapPrice($)) {
                uint256 maxAmount = IERC20(usdc).balanceOf(address(pair)).convertDecimals(_usdcDecimals, _moreDecimals);
                (uint256 score, uint256 moreAmount) = _optimizeFn(this.mintAndSell, maxAmount);
                if (score < currentScore) {
                    return abi.encodeCall(this.mintAndSell, (moreAmount));
                }
            } else {
                uint256 usdcBalance = usdc.balanceOf(address(this));
                if (usdcBalance != 0) {
                    return abi.encodeCall(this.mintAndAddLiquidity, (usdcBalance));
                }
            }
        }
        if (lastHarvestTimestamp() + 24 hours <= block.timestamp) {
            return abi.encodeCall(this.harvestReward, ());
        }
        return "";
    }

    function buyAndBurn(uint256 amount) external whenNotPaused returns (uint256 newSpotPrice) {
        AMOStorage storage $ = _getAMOStorage();
        uint256 spot = _checkBelowFloorPrice($);
        uint256 usdcBalance = usdc.balanceOf(address(this));
        if (usdcBalance < amount) {
            revert PreconditionNotMet();
        }
        amount = _buyMore(amount);
        ERC20Burnable(address(more)).burn(amount);
        newSpotPrice = _checkHigherSpotPrice($, spot);
    }

    function withdrawBuyAndBurn(uint256 amount) external whenNotPaused returns (uint256 newSpotPrice) {
        AMOStorage storage $ = _getAMOStorage();
        uint256 spot = _checkBelowFloorPrice($);
        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 lpBalance = gauge.balanceOf(address(this));
        if (usdcBalance != 0 || lpBalance < amount) {
            revert PreconditionNotMet();
        }
        (uint256 usdcAmount, uint256 moreAmount) = _unstakeAndWithdrawLiquidity(amount);
        moreAmount += _buyMore(usdcAmount);
        ERC20Burnable(address(more)).burn(moreAmount);
        newSpotPrice = _checkHigherSpotPrice($, spot);
    }

    function mintAndSell(uint256 amount) external whenNotPaused returns (uint256 newSpotPrice) {
        AMOStorage storage $ = _getAMOStorage();
        uint256 spot = _checkAboveCapPrice($);
        IMinter($.moreMinter).mint(address(this), amount);
        _sellMore(amount);
        newSpotPrice = _checkLowerSpotPrice($, spot);
    }

    function mintAndAddLiquidity(uint256 amount) external whenNotPaused {
        AMOStorage storage $ = _getAMOStorage();
        (uint256 twap, uint256 spot) = _getMorePrice($);
        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 floor = $.floorPrice;
        if (twap < floor || spot < floor || usdcBalance < amount) {
            revert PreconditionNotMet();
        }
        uint256 mintAmount = _getRequiredMoreAmountForLiquidity(amount);
        IMinter($.moreMinter).mint(address(this), mintAmount);
        _addLiquidity(amount, mintAmount);
    }

    function psm() external view returns (address) {
        return _getAMOStorage().psm;
    }

    function moreMinter() external view returns (address) {
        return _getAMOStorage().moreMinter;
    }

    function spotPriceOracle() external view returns (address) {
        return _getAMOStorage().spotPriceOracle;
    }

    function twapOracle() external view returns (address) {
        return _getAMOStorage().twapOracle;
    }

    function capPrice() external view returns (uint256) {
        return _getAMOStorage().capPrice;
    }

    function floorPrice() external view returns (uint256) {
        return _getAMOStorage().floorPrice;
    }

    function liquidity() external view returns (uint256 usdcAmount, uint256 moreAmount) {
        uint256 balance = gauge.balanceOf(address(this)) + pair.balanceOf(address(this));
        uint256 total = pair.totalSupply();

        if (balance == 0 || total == 0) {
            return (0, 0);
        }

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        (uint256 usdcLiquidity, uint256 moreLiquidity) = _toUsdcMore(reserve0, reserve1);

        usdcAmount = Math.mulDiv(usdcLiquidity, balance, total);
        moreAmount = Math.mulDiv(moreLiquidity, balance, total);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _processTokenRequest(address token, uint256 amount, address recipient) internal {
        if (token == address(usdc)) {
            uint256 balance = usdc.balanceOf(address(this));

            if (balance >= amount) {
                SafeERC20.safeTransfer(usdc, recipient, amount);
                return;
            }

            uint256 lpBalance = gauge.balanceOf(address(this));

            if (lpBalance != 0) {
                (uint256 usdcAmount,) = _unstakeAndWithdrawLiquidity(lpBalance);
                unchecked {
                    balance += usdcAmount;
                }
                if (balance >= amount) {
                    unchecked {
                        balance -= amount;
                    }

                    SafeERC20.safeTransfer(usdc, recipient, amount);

                    if (balance != 0) {
                        uint256 moreAmount = _getRequiredMoreAmountForLiquidity(balance);
                        _addLiquidity(balance, moreAmount);
                        _burnExcessMore();
                    }
                    
                    return;
                }
            }
        }

        revert InsufficientFunds();
    }

    function _aboveCapPrice(AMOStorage storage $) private view returns (bool) {
        (uint256 twap, uint256 spot) = _getMorePrice($);
        uint256 capPrice_ = $.capPrice;
        return twap > capPrice_ && spot > capPrice_;
    }

    function _belowFloorPrice(AMOStorage storage $) private view returns (bool) {
        (uint256 twap, uint256 spot) = _getMorePrice($);
        uint256 floorPrice_ = $.floorPrice;
        return twap < floorPrice_ && spot < floorPrice_;
    }

    function _score(uint256 spotPrice) private pure returns (uint256) {
        unchecked {
            return spotPrice < TARGET_PRICE ? TARGET_PRICE - spotPrice : spotPrice - TARGET_PRICE;
        }
    }

    function _optimizeFn(function(uint256) external returns(uint256) fn, uint256 maxAmount)
        private
        returns (uint256 optimalScore, uint256 optimalAmount)
    {
        uint256 score;
        uint256 newSpotPrice;
        uint256 mid;
        uint256 low;
        uint256 high = maxAmount;

        // Check the boundary at maxAmount
        newSpotPrice = _simulateUint256Result(abi.encodeCall(fn, (maxAmount)));
        optimalScore = _score(newSpotPrice);
        optimalAmount = maxAmount;

        while (low <= high) {
            mid = (low + high) / 2;
            newSpotPrice = _simulateUint256Result(abi.encodeCall(fn, (mid)));
            score = _score(newSpotPrice);

            if (score < optimalScore) {
                optimalScore = score;
                optimalAmount = mid;
            }

            if (newSpotPrice > TARGET_PRICE) {
                high = mid - 1;
            } else {
                low = mid + 1;
            }
        }

        return (optimalScore, optimalAmount);
    }

    function _addLiquidity(uint256 usdcAmount, uint256 moreAmount) private {
        usdc.transfer(address(pair), usdcAmount);
        more.transfer(address(pair), moreAmount);
        uint256 liquidity_ = pair.mint(address(this));
        pair.approve(address(gauge), liquidity_);
        gauge.deposit(liquidity_);
    }

    function _burnExcessMore() private {
        uint256 balance = IERC20(more).balanceOf(address(this));
        if (balance != 0) {
            ERC20Burnable(address(more)).burn(balance);
        }
    }

    function _buyMore(uint256 usdcAmount) private returns (uint256 moreAmount) {
        moreAmount = pair.getAmountOut(usdcAmount, address(usdc));
        (uint256 amount0Out, uint256 amount1Out) = _fromUsdcMore(0, moreAmount);
        usdc.transfer(address(pair), usdcAmount);
        pair.swap(amount0Out, amount1Out, address(this), "");
    }

    function _sellMore(uint256 moreAmount) private returns (uint256 usdcAmount) {
        usdcAmount = pair.getAmountOut(moreAmount, address(more));
        (uint256 amount0Out, uint256 amount1Out) = _fromUsdcMore(usdcAmount, 0);
        more.transfer(address(pair), moreAmount);
        pair.swap(amount0Out, amount1Out, address(this), "");
    }

    function _unstake(uint256 amount) private {
        gauge.withdraw(amount);
    }

    function _unstakeAndWithdrawLiquidity(uint256 amount) private returns (uint256 usdcAmount, uint256 moreAmount) {
        _unstake(amount);
        amount = pair.balanceOf(address(this));
        pair.transfer(address(pair), amount);
        (uint256 amount0, uint256 amount1) = pair.burn(address(this));
        (usdcAmount, moreAmount) = _toUsdcMore(amount0, amount1);
    }

    function _checkAboveCapPrice(AMOStorage storage $) private view returns (uint256 spot) {
        uint256 _capPrice = $.capPrice;
        uint256 twap;
        (twap, spot) = _getMorePrice($);
        if (twap <= _capPrice || spot <= _capPrice) {
            revert PreconditionNotMet();
        }
    }

    function _checkBelowFloorPrice(AMOStorage storage $) private view returns (uint256 spot) {
        uint256 _floorPrice = $.floorPrice;
        uint256 twap;
        (twap, spot) = _getMorePrice($);
        if (twap >= _floorPrice || spot >= _floorPrice) {
            revert PreconditionNotMet();
        }
    }

    function _checkHigherSpotPrice(AMOStorage storage $, uint256 previousSpotPrice)
        private
        view
        returns (uint256 spot)
    {
        (, spot) = _getMorePrice($);
        if (spot <= previousSpotPrice || spot > $.capPrice) {
            revert PostconditionNotMet();
        }
    }

    function _checkLowerSpotPrice(AMOStorage storage $, uint256 previousSpotPrice)
        private
        view
        returns (uint256 spot)
    {
        (, spot) = _getMorePrice($);
        if (spot >= previousSpotPrice || spot < $.floorPrice) {
            revert PostconditionNotMet();
        }
    }

    function _getRequiredMoreAmountForLiquidity(uint256 usdcAmount) private view returns (uint256 moreAmount) {
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        (uint256 usdcReserve, uint256 moreReserve) = _toUsdcMore(reserve0, reserve1);
        moreAmount = (usdcAmount * moreReserve) / usdcReserve;
    }

    function _getMorePrice(AMOStorage storage $) private view returns (uint256 twap, uint256 spot) {
        (, spot) = ISpotPriceOracle($.spotPriceOracle).currentPrice();
        (, int256 twap_,,,) = AggregatorV3Interface($.twapOracle).latestRoundData();
        twap = twap_ <= 0 ? 0 : uint256(twap_);
    }

    function _fromKnownAmounts01(uint256 amountA, uint256 amountB)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = (amountA, amountB);
    }

    function _fromKnownAmounts10(uint256 amountA, uint256 amountB)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        (amount1, amount0) = (amountA, amountB);
    }

    function _toKnownAmounts01(uint256 amount0, uint256 amount1)
        internal
        pure
        returns (uint256 amountA, uint256 amountB)
    {
        (amountA, amountB) = (amount0, amount1);
    }

    function _toKnownAmounts10(uint256 amount0, uint256 amount1)
        internal
        pure
        returns (uint256 amountA, uint256 amountB)
    {
        (amountA, amountB) = (amount1, amount0);
    }
}
