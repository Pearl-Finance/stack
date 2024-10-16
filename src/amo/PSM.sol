// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {DecimalLib} from "src/libraries/DecimalLib.sol";
import {IAMO} from "src/interfaces/IAMO.sol";
import {IERC20Mintable} from "src/interfaces/IERC20Mintable.sol";
import {IERC20Provider} from "src/interfaces/IERC20Provider.sol";
import {IMinter} from "src/interfaces/IMinter.sol";
import {ISpotPriceOracle} from "src/interfaces/ISpotPriceOracle.sol";
import {IPSM} from "src/interfaces/IPSM.sol";
import {ERC20Distributor} from "./ERC20Distributor.sol";
import {ERC20Holder} from "./ERC20Holder.sol";

contract PSM is OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable, ERC20Distributor, ERC20Holder, IPSM {
    using DecimalLib for uint256;
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:pearl.storage.PSM
    struct PSMStorage {
        uint16 mintingFee;
        uint16 redeemingFee;
        address amo;
        address moreMinter;
        address spotPriceOracle;
        address twapOracle;
        uint256 minMintPrice;
        uint256 maxRedeemPrice;
    }

    // keccak256(abi.encode(uint256(keccak256("pearl.storage.PSM")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PSMStorageLocation = 0xdf877f2eb62ce2b3e079824e62d796b8c25ad74eb8c1744e98bd67046547d000;

    function _getPSMStorage() internal pure returns (PSMStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := PSMStorageLocation
        }
    }

    uint256 public constant FEE_PRECISION = 1e2;

    uint8 private immutable _usdcDecimals;
    uint8 private immutable _moreDecimals;

    address public immutable usdc;
    address public immutable more;

    event AMOUpdate(address amo);
    event MinMintPriceUpdate(uint256 minMintPrice);
    event MaxRedeemPriceUpdate(uint256 maxRedeemPrice);
    event Mint(address indexed account, address indexed to, uint256 amountIn, uint256 amountOut, bool indexed unbacked);
    event MintingFeeUpdate(uint16 mintingFee);
    event MoreMinterUpdate(address minter);
    event Redeem(address indexed account, address indexed to, uint256 amountIn, uint256 amountOut);
    event RedeemingFeeUpdate(uint16 redeemingFee);
    event SpotPriceOracleUpdate(address oracle);
    event TWAPOracleUpdate(address oracle);

    error InsufficientFunds();
    error InsufficientOutputAmount();
    error InvalidValue();
    error MintingNotAllowed();
    error RedeemingNotAllowed();
    error UnbackedMintingNotAllowed();
    error NotSupported();
    error ValueUnchanged();

    /**
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address usdc_, address more_) {
        _disableInitializers();
        usdc = usdc_;
        more = more_;
        _usdcDecimals = IERC20Metadata(usdc_).decimals();
        _moreDecimals = IERC20Metadata(more_).decimals();
    }

    function initialize(address initialOwner, address moreMinter_, address spotPriceOracle_, address twapOracle_)
        external
        initializer
    {
        __Ownable_init(initialOwner);
        __Pausable_init();
        __UUPSUpgradeable_init();

        PSMStorage storage $ = _getPSMStorage();
        $.moreMinter = moreMinter_;
        $.spotPriceOracle = spotPriceOracle_;
        $.twapOracle = twapOracle_;
        $.minMintPrice = 1e8 + 1;
        $.maxRedeemPrice = 1e8 - 1;

        emit MoreMinterUpdate(moreMinter_);
        emit SpotPriceOracleUpdate(spotPriceOracle_);
        emit TWAPOracleUpdate(twapOracle_);
        emit MinMintPriceUpdate($.minMintPrice);
        emit MaxRedeemPriceUpdate($.maxRedeemPrice);
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function setAMO(address _amo) external onlyOwner {
        PSMStorage storage $ = _getPSMStorage();
        if ($.amo == _amo) {
            revert ValueUnchanged();
        }
        $.amo = _amo;
        emit AMOUpdate(_amo);
    }

    function setMinMintPrice(uint256 _minMintPrice) external onlyOwner {
        PSMStorage storage $ = _getPSMStorage();
        if ($.minMintPrice == _minMintPrice) {
            revert ValueUnchanged();
        }
        $.minMintPrice = _minMintPrice;
        emit MinMintPriceUpdate(_minMintPrice);
    }

    function setMintingFee(uint16 _mintingFee) external onlyOwner {
        if (_mintingFee > 100 * FEE_PRECISION) {
            revert InvalidValue();
        }
        PSMStorage storage $ = _getPSMStorage();
        if ($.mintingFee == _mintingFee) {
            revert ValueUnchanged();
        }
        $.mintingFee = _mintingFee;
        emit MintingFeeUpdate(_mintingFee);
    }

    function setMaxRedeemPrice(uint256 _maxRedeemPrice) external onlyOwner {
        PSMStorage storage $ = _getPSMStorage();
        if ($.maxRedeemPrice == _maxRedeemPrice) {
            revert ValueUnchanged();
        }
        $.maxRedeemPrice = _maxRedeemPrice;
        emit MaxRedeemPriceUpdate(_maxRedeemPrice);
    }

    function setRedeemingFee(uint16 _redeemingFee) external onlyOwner {
        if (_redeemingFee > 100 * FEE_PRECISION) {
            revert InvalidValue();
        }
        PSMStorage storage $ = _getPSMStorage();
        if ($.redeemingFee == _redeemingFee) {
            revert ValueUnchanged();
        }
        $.redeemingFee = _redeemingFee;
        emit RedeemingFeeUpdate(_redeemingFee);
    }

    function setMoreMinter(address _minter) external onlyOwner {
        PSMStorage storage $ = _getPSMStorage();
        if ($.moreMinter == _minter) {
            revert ValueUnchanged();
        }
        $.moreMinter = _minter;
        emit MoreMinterUpdate(_minter);
    }

    function setSpotPriceOracle(address oracle) external onlyOwner {
        PSMStorage storage $ = _getPSMStorage();
        if ($.spotPriceOracle == oracle) {
            revert ValueUnchanged();
        }
        $.spotPriceOracle = oracle;
        emit SpotPriceOracleUpdate(oracle);
    }

    function setTWAPOracle(address oracle) external onlyOwner {
        PSMStorage storage $ = _getPSMStorage();
        if ($.twapOracle == oracle) {
            revert ValueUnchanged();
        }
        $.spotPriceOracle = oracle;
        emit TWAPOracleUpdate(oracle);
    }

    function mint(address to, uint256 amount, uint256 minAmountOut) external whenNotPaused {
        if (!mintingAllowed()) {
            revert MintingNotAllowed();
        }

        PSMStorage storage $ = _getPSMStorage();

        IERC20(usdc).safeTransferFrom(msg.sender, $.amo, amount);
        uint256 amountOut = amount.convertDecimals(_usdcDecimals, _moreDecimals);
        uint256 fee = amountOut.mulDiv($.mintingFee, 100 * FEE_PRECISION);
        unchecked {
            amountOut -= fee;
        }
        if (amountOut < minAmountOut) {
            revert InsufficientOutputAmount();
        }

        IMinter($.moreMinter).mint(to, amountOut);

        emit Mint(msg.sender, to, amount, amountOut, false);
    }

    function redeem(address to, uint256 amount, uint256 minAmountOut) external whenNotPaused {
        if (!redeemingAllowed()) {
            revert RedeemingNotAllowed();
        }

        ERC20Burnable(address(more)).burnFrom(msg.sender, amount);

        PSMStorage storage $ = _getPSMStorage();

        uint256 amountOut = amount.convertDecimals(_moreDecimals, _usdcDecimals, Math.Rounding.Trunc);
        uint256 fee = amountOut.mulDiv($.redeemingFee, 100 * FEE_PRECISION);

        unchecked {
            amountOut -= fee;
        }

        if (amountOut < minAmountOut) {
            revert InsufficientOutputAmount();
        }

        IERC20Provider($.amo).requestTokensFor(usdc, amountOut, to);

        emit Redeem(msg.sender, to, amount, amountOut);
    }

    function amo() external view returns (address) {
        return _getPSMStorage().amo;
    }

    function mintingFee() external view returns (uint16) {
        return _getPSMStorage().mintingFee;
    }

    function redeemingFee() external view returns (uint16) {
        return _getPSMStorage().redeemingFee;
    }

    function moreMinter() external view returns (address) {
        return _getPSMStorage().moreMinter;
    }

    function spotPriceOracle() external view returns (address) {
        return _getPSMStorage().spotPriceOracle;
    }

    function twapOracle() external view returns (address) {
        return _getPSMStorage().twapOracle;
    }

    function minMintPrice() external view returns (uint256) {
        return _getPSMStorage().minMintPrice;
    }

    function maxRedeemPrice() external view returns (uint256) {
        return _getPSMStorage().maxRedeemPrice;
    }

    function mintingAllowed() public view returns (bool) {
        if (paused()) return false;

        PSMStorage storage $ = _getPSMStorage();

        if ($.amo == address(0)) return false;

        (, uint256 spot) = ISpotPriceOracle($.spotPriceOracle).currentPrice();
        (, int256 twap,,,) = AggregatorV3Interface($.twapOracle).latestRoundData();

        uint256 minPrice = $.minMintPrice;

        return spot >= minPrice && twap > 0 && uint256(twap) >= minPrice;
    }

    function maxRedeemAmount() public view returns (uint256) {
        PSMStorage storage $ = _getPSMStorage();
        (uint256 usdcAmount,) = IAMO($.amo).liquidity();
        return usdcAmount + IERC20(usdc).balanceOf($.amo);
    }

    function redeemingAllowed() public view returns (bool) {
        if (paused()) return false;

        PSMStorage storage $ = _getPSMStorage();

        if ($.amo == address(0)) return false;

        (, uint256 spot) = ISpotPriceOracle($.spotPriceOracle).currentPrice();
        (, int256 twap,,,) = AggregatorV3Interface($.twapOracle).latestRoundData();

        uint256 maxPrice = $.maxRedeemPrice;

        return spot <= maxPrice && twap > 0 && uint256(twap) <= maxPrice;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
