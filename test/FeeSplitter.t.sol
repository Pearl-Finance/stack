// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {MockMoreStakingVault} from "./mocks/MockMoreStakingVault.sol";

import {More} from "../src/tokens/More.sol";
import {MoreMinter} from "../src/tokens/MoreMinter.sol";
import {MoreStakingVault} from "../src/vaults/MoreStakingVault.sol";
import {FeeSplitter, CommonErrors} from "../src/periphery/FeeSplitter.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title Stack Vault Factory Test Cases
 * @author c-n-o-t-e
 * @dev Contract is used to test out Stack Vault Factory Contract in a stateless way.
 *
 * Functionalities Tested:
 * - AddReceivers
 * - SetReceivers
 * - UpdateReceiver
 * - RemoveReceiver
 * - SetDistributor
 * - Failed Scenarios
 * - DistributionRate
 * - DistributionRateForFeeReceiver
 * - UpdateFeeReceiversWithSetOfReceivers
 */
contract FeeSplitterTest is Test {
    More more;
    MoreMinter moreMinter;
    FeeSplitter feeSplitter;
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

        feeSplitter = new FeeSplitter(address(more));
        init = abi.encodeCall(feeSplitter.initialize, ());
        proxy = new ERC1967Proxy(address(feeSplitter), init);
        feeSplitter = FeeSplitter(address(proxy));
    }

    function testShouldSetDistributor() public {
        assertEq(feeSplitter.distributor(), address(0));
        feeSplitter.setDistributor(address(1));
        assertEq(feeSplitter.distributor(), address(1));
    }

    function testShouldDistribute() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.UnauthorizedCaller.selector));
        feeSplitter.distribute();

        vm.warp(3 days);
        feeSplitter.addReceiver(address(1), 100);

        deal(address(more), address(feeSplitter), 1 ether);
        feeSplitter.setDistributor(address(this));

        assertEq(more.balanceOf(address(1)), 0);
        assertEq(more.balanceOf(address(feeSplitter)), 1 ether);

        feeSplitter.distribute();

        assertEq(more.balanceOf(address(1)), 1 ether);
        assertEq(more.balanceOf(address(feeSplitter)), 0);

        vm.warp(block.timestamp + 3 days);
        deal(address(more), address(feeSplitter), 2 ether);
        feeSplitter.distribute();

        FeeSplitter.Checkpoint memory f = feeSplitter.checkpoint(0);
        assertEq(f.timestamp, block.timestamp);
        assertEq(f.totalDistributed, 3 ether);

        f = feeSplitter.checkpoint(1);
        assertEq(f.timestamp, 3 days);
        assertEq(f.totalDistributed, 1 ether);
    }

    function testShouldCheckDistributionRate() public {
        vm.warp(3 days);
        feeSplitter.addReceiver(address(1), 100);

        deal(address(more), address(feeSplitter), 1 ether);
        feeSplitter.setDistributor(address(this));

        feeSplitter.distribute();

        vm.warp(block.timestamp + 3 days);
        deal(address(more), address(feeSplitter), 1 ether);
        feeSplitter.distribute();

        uint256 rate = feeSplitter.distributionRate();
        assertEq(rate, uint256(1 ether) / 3 days);
    }

    function testShouldCheckDistributionRateForFeeReceiver() public {
        vm.warp(3 days);
        feeSplitter.addReceiver(address(1), 50);
        feeSplitter.addReceiver(address(2), 30);
        feeSplitter.addReceiver(address(3), 20);

        deal(address(more), address(feeSplitter), 1 ether);
        feeSplitter.setDistributor(address(this));

        feeSplitter.distribute();

        vm.warp(block.timestamp + 3 days);
        deal(address(more), address(feeSplitter), 1 ether);
        feeSplitter.distribute();

        uint256 rate = feeSplitter.distributionRate();

        uint256 feeReceiverRate = feeSplitter.distributionRateFor(address(1));
        assertEq((rate * 50) / 100, feeReceiverRate);

        feeReceiverRate = feeSplitter.distributionRateFor(address(2));
        assertEq((rate * 30) / 100, feeReceiverRate);

        feeReceiverRate = feeSplitter.distributionRateFor(address(3));
        assertEq((rate * 20) / 100, feeReceiverRate);
    }

    function testShouldIfInvalidSplitValue() public {
        vm.expectRevert(abi.encodeWithSelector(FeeSplitter.InvalidSplitValue.selector, 0));
        feeSplitter.addReceiver(address(1), 0);

        feeSplitter.addReceiver(address(1), 1);

        vm.expectRevert(abi.encodeWithSelector(FeeSplitter.InvalidSplitValue.selector, type(uint96).max));
        feeSplitter.addReceiver(address(2), type(uint96).max);
    }

    function testShouldAddReceivers() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
        feeSplitter.addReceiver(address(0), 100);

        assertEq(feeSplitter.allReceivers().length, 0);
        feeSplitter.addReceiver(address(1), 100);
        assertEq(feeSplitter.allReceivers().length, 1);

        deal(address(more), address(feeSplitter), 1 ether);
        feeSplitter.setDistributor(address(this));

        assertEq(more.balanceOf(address(1)), 0);
        assertEq(more.balanceOf(address(feeSplitter)), 1 ether);

        feeSplitter.distribute();

        assertEq(more.balanceOf(address(1)), 1 ether);
        assertEq(more.balanceOf(address(feeSplitter)), 0);

        vm.expectRevert(abi.encodeWithSelector(FeeSplitter.ReceiverAlreadyAdded.selector, address(1)));
        feeSplitter.addReceiver(address(1), 100);
    }

    function testShouldUpdateReceiver() public {
        feeSplitter.addReceiver(address(1), 70);
        feeSplitter.addReceiver(address(2), 30);

        feeSplitter.setDistributor(address(this));
        deal(address(more), address(feeSplitter), 1 ether);
        feeSplitter.distribute();

        assertEq(more.balanceOf(address(1)), 0.7 ether);
        assertEq(more.balanceOf(address(2)), 0.3 ether);

        feeSplitter.updateReceiver(address(1), 50);
        feeSplitter.updateReceiver(address(2), 50);

        deal(address(more), address(feeSplitter), 1 ether);
        feeSplitter.distribute();

        assertEq(more.balanceOf(address(1)), 1.2 ether);
        assertEq(more.balanceOf(address(2)), 0.8 ether);

        vm.expectRevert(abi.encodeWithSelector(FeeSplitter.ReceiverNotFound.selector, address(3)));
        feeSplitter.updateReceiver(address(3), 50);
    }

    function testShouldRemoveReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(FeeSplitter.ReceiverNotFound.selector, address(1)));
        feeSplitter.removeReceiver(address(1));

        feeSplitter.addReceiver(address(1), 50);
        feeSplitter.addReceiver(address(2), 50);
        assertEq(feeSplitter.allReceivers().length, 2);

        feeSplitter.setDistributor(address(this));

        feeSplitter.removeReceiver(address(1));
        assertEq(feeSplitter.allReceivers().length, 1);
    }

    function testShouldSetReceivers() public {
        address[] memory receivers = new address[](2);
        uint96[] memory splits = new uint96[](receivers.length);
        uint96 split = 100 / uint96(receivers.length);

        receivers[0] = address(more);
        receivers[1] = address(1);

        splits[0] = split;
        splits[1] = split;

        assertEq(feeSplitter.allReceivers().length, 0);

        feeSplitter.setReceivers(receivers, splits);
        assertEq(feeSplitter.allReceivers().length, 2);

        receivers[0] = address(0);
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
        feeSplitter.setReceivers(receivers, splits);
    }

    function testShouldUpdateFeeReceiversWithSetOfReceivers() public {
        feeSplitter.addReceiver(address(8), 40);
        feeSplitter.addReceiver(address(3), 40);
        feeSplitter.addReceiver(address(6), 20);

        address[] memory receivers = new address[](2);
        uint96[] memory splits = new uint96[](receivers.length);
        uint96 split = 100 / uint96(receivers.length);

        receivers[0] = address(1);
        receivers[1] = address(2);

        splits[0] = split;
        splits[1] = split;

        assertEq(feeSplitter.allReceivers().length, 3);

        feeSplitter.setReceivers(receivers, splits);
        assertEq(feeSplitter.allReceivers().length, 2);

        deal(address(more), address(feeSplitter), 1 ether);
        feeSplitter.setDistributor(address(this));

        assertEq(more.balanceOf(address(1)), 0);
        assertEq(more.balanceOf(address(2)), 0);
        assertEq(more.balanceOf(address(feeSplitter)), 1 ether);

        feeSplitter.distribute();

        assertEq(more.balanceOf(address(1)), 0.5 ether);
        assertEq(more.balanceOf(address(2)), 0.5 ether);
        assertEq(more.balanceOf(address(feeSplitter)), 0);
    }
}
