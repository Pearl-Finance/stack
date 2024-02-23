// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PearlRouteFinder} from "src/periphery/PearlRouteFinder.sol";
import {PearlRouter} from "src/periphery/PearlRouter.sol";

contract PearlRouteFinderTest is Test {
    string UNREAL_RPC_URL = vm.envString("UNREAL_RPC_URL");

    PearlRouteFinder finder;

    function setUp() public {
        vm.createSelectFork(UNREAL_RPC_URL, 50675);

        address pearlFactory = 0xC46cDB77FF184562A834Ff684f0393b0cA57b5E5;
        address pearlRouter = 0x9e9A321968d5cA11f92947102313612615bae500;
        address pearlQuoter = 0x5aB061CAe88b7c125D6990648fA863390bf0cB7e;

        PearlRouter routerImplementation = new PearlRouter();
        ERC1967Proxy routerProxy = new ERC1967Proxy(
            address(routerImplementation), abi.encodeCall(routerImplementation.initialize, (pearlRouter, pearlQuoter))
        );

        finder = new PearlRouteFinder(pearlFactory, address(routerProxy));
    }

    function test_findBestSwapPath() public {
        address more = 0x3CD7AB62b0A96CC5c23490d0893084b58A98A1Dc;
        address ustb = 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;
        address pearl = 0xCE1581d7b4bA40176f0e219b2CaC30088Ad50C7A;

        bytes memory expectedPath = abi.encodePacked(more, uint24(100), ustb, uint24(3000), pearl);
        (uint256 amountOut, bytes memory path) = finder.findBestSwapPath(more, pearl, 10e18, 3);

        assertEq(keccak256(expectedPath), keccak256(path));
        assertGt(amountOut, 0);
    }
}
