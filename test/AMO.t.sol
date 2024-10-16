// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@layerzerolabs/contracts/lzApp/mocks/LZEndpointMock.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import "@openzeppelin/contracts/interfaces/IERC3156.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import "src/amo/AMO.sol";
import "src/amo/PSM.sol";
import "src/interfaces/ISpotPriceOracle.sol";

contract AMOTest is Test {
    AMO amo;
    PSM psm;

    address public constant MORE_USDC_POOL = 0x1733720f30EF013539Fa2EcEE00671A60B66243D;
    address public constant MORE_USDC_GAUGE = 0xEeEb242df68caaF38D9474196C8e222dB9F9B3F3;
    address public constant USDC = 0xc518A88c67CECA8B3f24c4562CB71deeB2AF86B7;
    address public constant MORE = 0x25ea98ac87A38142561eA70143fd44c4772A16b6;
    address public constant MORE_MINTER = 0xb311D3999ec9B77971d3Db6ef043E7bD54CE5218;
    address public constant SPOT_PRICE_ORACLE = 0xe96c09632bE2b3Dd1723B168E9c42958553c0690;
    address public constant TWAP_ORACLE = 0x5bd16F95dcE585E7FFE5578A011fF8664e4C1e9e;
    address public constant ROUTER = 0x7c5Df15989a317B9649933FE834835F3cB9fEe47;

    address public deployer = 0x839AEeA3537989ce05EA1b218aB0F25E54cC3B3f;
    address public multisig = 0xAC0926290232D07eD8b083F6BE3Ab040010f757F;
    address public keeper = makeAddr("keeper");
    address public user = makeAddr("user");

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("real"), 797200);
        vm.startPrank(deployer);

        PSM psmImpl = new PSM(USDC, MORE);
        bytes memory psmInit =
            abi.encodeCall(psmImpl.initialize, (deployer, MORE_MINTER, SPOT_PRICE_ORACLE, TWAP_ORACLE));
        ERC1967Proxy psmProxy = new ERC1967Proxy(address(psmImpl), psmInit);
        psm = PSM(address(psmProxy));

        address harvester = deployer;

        AMO amoImpl = new AMO(USDC, MORE, MORE_USDC_GAUGE);
        bytes memory amoInit = abi.encodeCall(
            amoImpl.initialize,
            (deployer, SPOT_PRICE_ORACLE, TWAP_ORACLE, MORE_MINTER, harvester, multisig, 0.999e8, 1.01e8)
        );
        ERC1967Proxy amoProxy = new ERC1967Proxy(address(amoImpl), amoInit);
        amo = AMO(address(amoProxy));

        psm.setAMO(address(amo));
        amo.setPSM(address(psm));

        vm.startPrank(multisig);

        Address.functionCall(
            MORE_MINTER, abi.encodeWithSignature("removeAMO(address)", 0x56743A08f09a39FBA40eE48f1C92974d849FC1e5)
        );
        Address.functionCall(MORE_MINTER, abi.encodeWithSignature("addAMO(address)", address(psm)));
        Address.functionCall(MORE_MINTER, abi.encodeWithSignature("addAMO(address)", address(amo)));

        deal(USDC, user, 1_000_000e6);
        deal(MORE, user, 1_000_000e18);

        vm.startPrank(user);
    }

    function test_psm_mint() public {
        _setOraclePrice(1.01e8);

        uint256 amount = 1_000e6;
        uint256 userBalanceBefore = IERC20(MORE).balanceOf(user);
        uint256 amoBalanceBefore = IERC20(USDC).balanceOf(address(amo));

        IERC20(USDC).approve(address(psm), amount);
        psm.mint(user, amount, 1);

        uint256 userBalanceAfter = IERC20(MORE).balanceOf(user);
        uint256 amoBalanceAfter = IERC20(USDC).balanceOf(address(amo));
        uint256 minted = userBalanceAfter - userBalanceBefore;
        uint256 amoBalanceChange = amoBalanceAfter - amoBalanceBefore;

        assertEq(minted, 1_000e18);
        assertEq(amoBalanceChange, 1_000e6);
    }

    function test_psm_mint_not_allowed() public {
        _setOraclePrice(1e8);
        uint256 amount = 1_000e6;
        IERC20(USDC).approve(address(psm), amount);
        vm.expectRevert(abi.encodeWithSelector(PSM.MintingNotAllowed.selector));
        psm.mint(user, amount, 1);
    }

    function test_psm_redeem() public {
        _setOraclePrice(1.01e8);
        deal(USDC, address(amo), 50_000e6);
        amo.mintAndAddLiquidity(50_000e6);

        vm.clearMockedCalls();

        IERC20(MORE).approve(address(psm), 5_000e18);
        psm.redeem(user, 5_000e18, 1);
    }

    function test_psm_redeem_not_allowed() public {
        _setOraclePrice(1e8);
        uint256 amount = 1_000e18;
        IERC20(MORE).approve(address(psm), amount);
        vm.expectRevert(abi.encodeWithSelector(PSM.RedeemingNotAllowed.selector));
        psm.redeem(user, amount, 1);
    }

    function test_psm_amo_mintAndAddLiquidity() public {
        _setOraclePrice(1.01e8);

        uint256 amount = 1_000e6;

        IERC20(USDC).approve(address(psm), amount);
        psm.mint(user, amount, 1);

        uint256 totalSupplyBefore = IERC20(MORE_USDC_GAUGE).totalSupply();

        bytes memory action = amo.determineNextAction();
        Address.functionCall(address(amo), action);

        uint256 totalSupplyAfter = IERC20(MORE_USDC_GAUGE).totalSupply();

        assertGt(totalSupplyAfter, totalSupplyBefore);
    }

    function test_amo_buyAndBurn() public {
        _setOraclePrice(1.01e8);
        deal(USDC, address(amo), 50_000e6);
        amo.mintAndAddLiquidity(50_000e6);

        vm.clearMockedCalls();

        _setOraclePrices(0, 0.99e8);
        _userSwap(MORE, USDC, 5_000e18);

        (, uint256 priceBefore) = ISpotPriceOracle(SPOT_PRICE_ORACLE).currentPrice();

        bytes memory action = amo.determineNextAction();
        Address.functionCall(address(amo), action);

        (, uint256 priceAfter) = ISpotPriceOracle(SPOT_PRICE_ORACLE).currentPrice();

        console.log("Price before: %d, price after: %d", priceBefore, priceAfter);

        assertGt(priceAfter, priceBefore);
    }

    function _setOraclePrice(uint256 price) internal {
        if (price == 0) {
            vm.clearMockedCalls();
        } else {
            _setOraclePrices(price, price);
        }
    }

    function _setOraclePrices(uint256 spot, uint256 twap) internal {
        if (spot != 0) {
            vm.mockCall(SPOT_PRICE_ORACLE, abi.encodeWithSignature("currentPrice()"), abi.encode(block.timestamp, spot));
        }
        if (twap != 0) {
            vm.mockCall(
                TWAP_ORACLE,
                abi.encodeWithSignature("latestRoundData()"),
                abi.encode(uint80(block.number), int256(twap), block.timestamp, block.timestamp, uint80(block.number))
            );
        }
    }

    function _userSwap(address from, address to, uint256 amount) internal {
        IERC20(from).approve(ROUTER, amount);
        Address.functionCall(
            ROUTER,
            abi.encodeWithSignature(
                "swapExactTokensForTokensSimple(uint256,uint256,address,address,bool,address,uint256)",
                amount,
                0,
                from,
                to,
                true,
                user,
                type(uint256).max
            )
        );
    }
}
