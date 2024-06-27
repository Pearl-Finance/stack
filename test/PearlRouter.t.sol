// // SPDX-License-Identifier: Unlicense
// pragma solidity ^0.8.13;

// import "forge-std/Test.sol";

// import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// import {PTaMock} from "./mocks/PTaMock.sol";

// import {PearlRouter, CommonErrors} from "src/periphery/PearlRouter.sol";
// import {ArcanaTokenConverter} from "src/periphery/converters/ArcanaTokenConverter.sol";

// contract PearlRouteTest is Test {
//     string UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

//     PTaMock ptaMock;
//     PearlRouter router;
//     ArcanaTokenConverter arcanaTokenConverter;

//     address more = 0x358404909b986A34Eb551d62178cDf72Cd1ca16f;
//     address ustb = 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;

//     address pearl = 0xCE1581d7b4bA40176f0e219b2CaC30088Ad50C7A;
//     address pearlRouter = 0x0a42599e0840aa292C76620dC6d4DAfF23DB5236;

//     address pearlQuoter = 0x6B6dA57BA5E77Ed5504Fe778449056fbb18020D5;
//     address pearlFactory = 0xDfCD83D2F29cF1E05F267927C102c0e3Dc2BD725;

//     function setUp() public {
//         vm.createSelectFork(UNREAL_RPC_URL, 8343);

//         PearlRouter routerImplementation = new PearlRouter();
//         ERC1967Proxy routerProxy = new ERC1967Proxy(
//             address(routerImplementation), abi.encodeCall(routerImplementation.initialize, (pearlRouter,
// pearlQuoter))
//         );
//         router = PearlRouter(address(routerProxy));

//         ptaMock = new PTaMock(18, pearl);
//         arcanaTokenConverter = new ArcanaTokenConverter(pearl, address(ptaMock));
//         router.setTokenConverter(pearl, address(arcanaTokenConverter));
//         router.setTokenConverter(address(ptaMock), address(arcanaTokenConverter));
//     }

//     function testShouldFailIfInvalidZeroAddress() public {
//         PearlRouter r = new PearlRouter();
//         vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
//         new ERC1967Proxy(address(r), abi.encodeCall(r.initialize, (address(0), address(0))));

//         vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
//         router.setQuoter(address(0));

//         vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
//         router.setSwapRouter(address(0));
//     }

//     function testShouldSetSwapRouter() external {
//         vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
//         router.setSwapRouter(pearlRouter);

//         assertEq(router.getSwapRouter(), pearlRouter);
//         router.setSwapRouter(address(1));
//         assertEq(router.getSwapRouter(), address(1));
//     }

//     function testShouldSetSwapQuoter() external {
//         vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
//         router.setQuoter(pearlQuoter);

//         assertEq(router.getQuoter(), pearlQuoter);
//         router.setQuoter(address(1));
//         assertEq(router.getQuoter(), address(1));
//     }

//     function testShouldSwap() external {
//         deal(more, address(this), 0.2e18);
//         uint256 amtOut = router.getAmountOut(more, ustb, 0.1e18, 100);

//         uint256 amtIn = router.getAmountIn(more, ustb, amtOut, 100);
//         assertEq(amtIn, 0.1e18);

//         IERC20(more).approve(address(router), 0.1e18);
//         uint256 amountOutWhenTrue = router.swap(more, ustb, 0.1e18, 0, 100, true);

//         uint256 amtOut0 = router.getAmountOut(more, ustb, 0.1e18, 100);
//         IERC20(more).approve(address(router), 0.1e18);
//         uint256 amountOutWhenFalse = router.swap(more, ustb, 0.1e18, 0, 100, false);

//         assertEq(amountOutWhenTrue, amtOut);
//         assertEq(amountOutWhenFalse, amtOut0);
//     }

//     function testShouldSwapWithPath() external {
//         deal(more, address(this), 1e18);
//         bytes memory expectedPath = abi.encodePacked(more, uint24(100), ustb, uint24(3000), pearl);

//         uint256 amountO = router.getAmountOut(expectedPath, 1e18);
//         uint256 slippage = (amountO * 5) / 1000;

//         IERC20(more).approve(address(router), 1e18);
//         uint256 amountOutWhenTrue = router.swap(more, pearl, expectedPath, 1e18, 0, true);
//         assertGe(amountOutWhenTrue, amountO - slippage);
//     }

//     function testShouldSwapWithPathAndConvertTokenIn() external {
//         deal(more, address(this), 1e18);
//         deal(pearl, address(ptaMock), 1e18);
//         deal(address(ptaMock), address(this), 1e18);

//         bytes memory expectedPath = abi.encodePacked(pearl, uint24(3000), ustb, uint24(100), more);
//         vm.expectRevert(abi.encodeWithSelector(PearlRouter.InvalidPath.selector));

//         router.getAmountOut(more, address(ptaMock), expectedPath, 1e18, address(this));
//         uint256 amountO = router.getAmountIn(address(ptaMock), more, expectedPath, 199414969009059257,
// address(this));
//         console2.log(amountO);

//         amountO = router.getAmountOut(address(ptaMock), more, expectedPath, 1e18, address(this));
//         console2.log(amountO);
//         uint256 slippage = (amountO * 5) / 1000;
//         IERC20(address(more)).approve(address(router), 1e18);
//         IERC20(address(ptaMock)).approve(address(router), 1e18);

//         vm.expectRevert(abi.encodeWithSelector(PearlRouter.InvalidPath.selector));
//         router.swap(more, address(ptaMock), expectedPath, 1e18, 0, false);

//         uint256 amountOut = router.swap(address(ptaMock), more, expectedPath, 1e18, 0, false);
//         assertGe(amountOut, amountO - slippage);
//     }

//     function testShouldSwapWithPathAndConvertTokenOut() external {
//         deal(address(more), address(this), 1e18);

//         bytes memory expectedPath = abi.encodePacked(more, uint24(100), ustb, uint24(3000), pearl);
//         uint256 amountO = router.getAmountOut(more, address(ptaMock), expectedPath, 1e18, address(this));

//         uint256 slippage = (amountO * 5) / 1000;
//         IERC20(address(more)).approve(address(router), 1e18);
//         uint256 contractPTaBalBeforeTx = ptaMock.balanceOf(address(this));

//         vm.expectRevert(abi.encodeWithSelector(PearlRouter.InsufficientOutputAmount.selector));
//         router.swap(more, address(ptaMock), expectedPath, 1e18, amountO, false);

//         uint256 amountOut = router.swap(more, address(ptaMock), expectedPath, 1e18, 0, false);
//         assertGe(amountOut, amountO - slippage);
//         assertGt(ptaMock.balanceOf(address(this)), contractPTaBalBeforeTx);
//     }
// }
