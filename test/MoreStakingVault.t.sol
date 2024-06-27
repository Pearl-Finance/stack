// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {MockMoreStakingVault} from "./mocks/MockMoreStakingVault.sol";

import {More} from "src/tokens/More.sol";
import {MoreMinter} from "src/tokens/MoreMinter.sol";
import {ERC4626Router} from "src/periphery/ERC4626Router.sol";
import {MoreStakingVault} from "src/vaults/MoreStakingVault.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title Stack Vault Factory Test Cases
 * @author c-n-o-t-e
 * @dev Contract is used to test out Stack Vault Factory Contract in a stateless way.
 *
 * Functionalities Tested:
 *  - Mint
 *  - Redeem
 *  - Deposit
 *  - Withdraw
 *  - Failed Scenarios
 */

contract MoreStakingVaultTest is Test {
    More more;
    MoreMinter moreMinter;
    ERC4626Router erc4626Router;
    MoreStakingVault moreStakingVault;
    MockMoreStakingVault mockMoreStakingVault;

    function setUp() public {
        more = new More(address(9));
        bytes memory init = abi.encodeCall(more.initialize, (address(this)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(more), init);
        more = More(address(proxy));

        moreMinter = new MoreMinter(address(more));
        init = abi.encodeCall(moreMinter.initialize, (address(this), address(9)));
        proxy = new ERC1967Proxy(address(moreMinter), init);
        moreMinter = MoreMinter(address(proxy));

        moreStakingVault = new MoreStakingVault();
        init = abi.encodeCall(moreStakingVault.initialize, (address(more), "Local", "L"));
        proxy = new ERC1967Proxy(address(moreStakingVault), init);
        moreStakingVault = MoreStakingVault(address(proxy));

        mockMoreStakingVault = new MockMoreStakingVault();
        init = abi.encodeCall(mockMoreStakingVault.initialize, (address(more), "Local", "L"));
        proxy = new ERC1967Proxy(address(mockMoreStakingVault), init);
        mockMoreStakingVault = MockMoreStakingVault(address(proxy));

        erc4626Router = new ERC4626Router();
    }

    function testShouldMint() public {
        vm.expectRevert(abi.encodeWithSelector(ERC4626Router.ERC4626RouterMaxAmountExceeded.selector));
        erc4626Router.mint(moreStakingVault, address(this), 1 ether, 0.05 ether);
        deal(address(more), address(this), 10 ether);

        assertEq(more.balanceOf(address(this)), 10 ether);
        assertEq(moreStakingVault.balanceOf(address(this)), 0);

        more.approve(address(erc4626Router), 1 ether);
        erc4626Router.mint(moreStakingVault, address(this), 1 ether, 1 ether);

        assertEq(more.balanceOf(address(this)), 10 ether - 1e17);
        assertEq(moreStakingVault.balanceOf(address(this)), 1 ether);
    }

    function testShouldReturnAmountInNotUsed() public {
        deal(address(more), address(this), 10 ether);
        more.approve(address(erc4626Router), 1 ether);
        erc4626Router.mint(mockMoreStakingVault, address(this), 1 ether, 1 ether);
        assertEq(more.balanceOf(address(this)), 10 ether - 5e16);
    }

    function testShouldDeposit() public {
        deal(address(more), address(this), 10 ether);

        assertEq(more.balanceOf(address(this)), 10 ether);
        assertEq(moreStakingVault.balanceOf(address(this)), 0);

        more.approve(address(erc4626Router), 1 ether);
        erc4626Router.deposit(moreStakingVault, address(this), 1 ether, 1 ether);

        assertEq(more.balanceOf(address(this)), 9 ether);
        assertEq(moreStakingVault.balanceOf(address(this)), 10 ether);
    }

    function testShouldFailToDeposit() public {
        vm.expectRevert(abi.encodeWithSelector(ERC4626Router.ERC4626RouterInsufficientShares.selector));
        erc4626Router.deposit(moreStakingVault, address(this), 1 ether, 11 ether);

        deal(address(more), address(this), 10 ether);

        more.approve(address(erc4626Router), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(ERC4626Router.ERC4626RouterInsufficientShares.selector));
        erc4626Router.deposit(mockMoreStakingVault, address(this), 1 ether, 10 ether);
    }

    function testShouldRedeem() public {
        deal(address(more), address(this), 10 ether);

        more.approve(address(erc4626Router), 1 ether);
        erc4626Router.mint(moreStakingVault, address(this), 1 ether, 1 ether);

        assertEq(more.balanceOf(address(this)), 10 ether - 1e17);
        assertEq(moreStakingVault.balanceOf(address(this)), 1 ether);

        moreStakingVault.approve(address(erc4626Router), 10 ether);

        vm.expectRevert(abi.encodeWithSelector(ERC4626Router.ERC4626RouterInsufficientAmount.selector));
        erc4626Router.redeem(moreStakingVault, address(this), 1 ether, 1 ether);

        erc4626Router.redeem(moreStakingVault, address(this), 1 ether, 0.1 ether);
        assertEq(more.balanceOf(address(this)), 10 ether);
        assertEq(moreStakingVault.balanceOf(address(this)), 0);
    }

    function testShouldWithdraw() public {
        deal(address(more), address(this), 10 ether);

        more.approve(address(erc4626Router), 1 ether);
        erc4626Router.deposit(moreStakingVault, address(this), 1 ether, 1 ether);

        assertEq(more.balanceOf(address(this)), 9 ether);
        assertEq(moreStakingVault.balanceOf(address(this)), 10 ether);

        moreStakingVault.approve(address(erc4626Router), 10 ether);

        vm.expectRevert(abi.encodeWithSelector(ERC4626Router.ERC4626RouterMaxSharesExceeded.selector));
        erc4626Router.withdraw(moreStakingVault, address(this), 1 ether, 9 ether);

        erc4626Router.withdraw(moreStakingVault, address(this), 1 ether, 10 ether);

        assertEq(more.balanceOf(address(this)), 10 ether);
        assertEq(moreStakingVault.balanceOf(address(this)), 0);
    }
}
