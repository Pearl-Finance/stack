// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {PearlRouteFinder} from "src/periphery/PearlRouteFinder.sol";
import {PearlRouter} from "src/periphery/PearlRouter.sol";

contract PearlRouteFinderTest is Test {
    string UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    PearlRouter router;
    PearlRouteFinder finder;

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL, 56450);

        address pearlFactory = 0x5A9aA74caceede5eAbBeDE2F425faEB85fdCE2f2;
        address pearlRouter = 0x4b15F7725a6B0dbb51421220c445fE3f57Bfca8b;
        address pearlQuoter = 0x96A3A276ACd970248c833E11a25c786e689cbaC9;

        PearlRouter routerImplementation = new PearlRouter();
        ERC1967Proxy routerProxy = new ERC1967Proxy(
            address(routerImplementation), abi.encodeCall(routerImplementation.initialize, (pearlRouter, pearlQuoter))
        );

        router = PearlRouter(address(routerProxy));
        finder = new PearlRouteFinder(pearlFactory, address(router));
    }

    function test_findBestSwapPath() public {
        address more = 0x3CD7AB62b0A96CC5c23490d0893084b58A98A1Dc;
        address ustb = 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;
        address pearl = 0xCE1581d7b4bA40176f0e219b2CaC30088Ad50C7A;

        bytes memory expectedPath = abi.encodePacked(more, uint24(100), ustb, uint24(3000), pearl);
        (uint256 amountOut, bytes memory path) = finder.findBestSwapPath(more, pearl, 10e18, 3);

        assertEq(keccak256(expectedPath), keccak256(path));
        assertGt(amountOut, 0);

        deal(more, address(this), 0.1e18);

        IERC20(more).approve(address(router), 0.1e18);
        router.swap(path, 0.1e18, 0);
    }
}
