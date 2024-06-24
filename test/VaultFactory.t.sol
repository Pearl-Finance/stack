// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";

import {WETH9} from "./mocks/WETH9.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ERC20MockMinter} from "./mocks/ERC20MockMinter.sol";
import {AggregatorV3Mock} from "./mocks/AggregatorV3Mock.sol";
import {AggregatorV3WrapperMock} from "./mocks/AggregatorV3WrapperMock.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {MockStackVault} from "./mocks/MockStackVault.sol";
import {MockVaultDeployer} from "./mocks/MockVaultDeployer.sol";
import {MockVaultImplementationDeployer} from "./mocks/MockVaultImplementationDeployer.sol";

import {StackVault} from "src/vaults/StackVault.sol";
import {CommonErrors} from "src/interfaces/CommonErrors.sol";
import {VaultImplementationDeployer} from "src/factories/VaultImplementationDeployer.sol";
import {VaultFactory, VaultDeployer, VaultFactoryVaultManagement} from "src/factories/VaultFactory.sol";

/**
 * @title Stack Vault Factory Test Cases
 * @author c-n-o-t-e
 * @dev Contract is used to test out Stack Vault Factory Contract in a stateless way.
 *
 * Functionalities Tested:
 *  - Vault Revival
 *  - Vault Creation
 *  - Fees Collection
 *  - Vault Retirement
 *  - Failed Scenarios
 *  - Position Liquidations
 *  - Accrual Interest Collection
 *  - Upgrade Vault Implementation
 *  - Setter and Updating Functions
 */
contract VaultFactoryTest is Test {
    VaultFactory factory;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    VaultDeployer vaultDeployer;
    ERC20MockMinter borrowTokenMinter;
    AggregatorV3Mock borrowTokenAggregator;
    AggregatorV3Mock collateralTokenAggregator;
    AggregatorV3WrapperMock borrowTokenOracle;
    AggregatorV3WrapperMock collateralTokenOracle;
    WETH9 weth;

    function setUp() public {
        borrowTokenAggregator = new AggregatorV3Mock(6);
        collateralTokenAggregator = new AggregatorV3Mock(6);
        borrowTokenAggregator.setAnswer(1e6);
        collateralTokenAggregator.setAnswer(1e6);
        borrowToken = new ERC20Mock(18);
        collateralToken = new ERC20Mock(18);
        borrowTokenMinter = new ERC20MockMinter(address(borrowToken));
        borrowTokenOracle = new AggregatorV3WrapperMock(address(borrowToken), address(borrowTokenAggregator));
        collateralTokenOracle =
            new AggregatorV3WrapperMock(address(collateralToken), address(collateralTokenAggregator));

        weth = new WETH9();

        address factoryAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 4);

        VaultImplementationDeployer implementationDeployer = new VaultImplementationDeployer();
        vaultDeployer = new VaultDeployer(address(weth), factoryAddress, address(implementationDeployer));
        bytes memory init = abi.encodeCall(vaultDeployer.initialize, ());
        ERC1967Proxy proxy = new ERC1967Proxy(address(vaultDeployer), init);

        VaultFactory impl = new VaultFactory(address(weth), address(borrowTokenMinter));
        init = abi.encodeCall(
            impl.initialize, (address(vaultDeployer), address(borrowTokenOracle), address(1), address(2))
        );
        proxy = new ERC1967Proxy(address(impl), init);
        factory = VaultFactory(address(proxy));

        assert(factoryAddress == address(factory));

        vm.label(address(borrowToken), "BorrowToken");
        vm.label(address(collateralToken), "CollateralToken");
        vm.label(address(borrowTokenOracle), "BorrowTokenOracle");
        vm.label(address(collateralTokenOracle), "CollateralTokenOracle");
        vm.warp(1 days);
    }

    function testShouldFailIfAddressZero() public {
        VaultImplementationDeployer implementationDeployer = new VaultImplementationDeployer();
        address factoryAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vaultDeployer = new VaultDeployer(address(weth), factoryAddress, address(implementationDeployer));

        bytes memory init = abi.encodeCall(vaultDeployer.initialize, ());
        ERC1967Proxy proxy = new ERC1967Proxy(address(vaultDeployer), init);

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
        new VaultFactory(address(0), address(borrowTokenMinter));

        VaultFactory impl = new VaultFactory(address(weth), address(borrowTokenMinter));
        init = abi.encodeCall(impl.initialize, (address(1), address(1), address(0), address(2)));

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
        proxy = new ERC1967Proxy(address(impl), init);

        init = abi.encodeCall(impl.initialize, (address(vaultDeployer), address(0), address(1), address(2)));
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
        proxy = new ERC1967Proxy(address(impl), init);

        init = abi.encodeCall(impl.initialize, (address(1), address(1), address(1), address(0)));
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
        proxy = new ERC1967Proxy(address(impl), init);
    }

    function testInitialState() public {
        assertEq(factory.WETH(), address(weth));
        assertEq(factory.borrowToken(), address(borrowToken));
        assertEq(factory.borrowTokenOracle(), address(borrowTokenOracle));
        assertEq(factory.borrowInterestRate(), 0);
    }

    function testCreateVault() public {
        assertEq(factory.allVaultsLength(), 0);
        assertEq(address(factory.vaultForToken(address(collateralToken))), address(0));

        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));

        assertEq(factory.allVaultsLength(), 1);
        assertEq(factory.allVaults(0), address(vault));

        assertEq(address(vault.collateralToken()), address(collateralToken));
        assertEq(vault.collateralTokenOracle(), address(collateralTokenOracle));

        assertEq(address(vault.borrowToken()), address(borrowToken));
        assertEq(vault.liquidationThreshold(), 90);
        assertEq(address(factory.vaultForToken(address(collateralToken))), address(vault));

        vm.expectRevert(
            abi.encodeWithSelector(VaultFactory.VaultAlreadyExists.selector, collateralToken, address(vault))
        );

        factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1);

        // for coverage
        vault = StackVault(factory.createVault(address(weth), address(collateralTokenOracle), 90, 1e1));
        assertEq(address(factory.vaultForToken(address(weth))), address(vault));
    }

    function testUpdateBorrowInterestRate() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));
        uint256 referencePrice = 0.9e18;
        vm.expectCall(address(vault), abi.encodeWithSelector(StackVault.accrueInterest.selector));
        factory.updateBorrowInterestRate(referencePrice);
        assertGt(vault.interestRatePerSecond(), 0);
    }

    function testSetBorrowTokenOracle() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setBorrowTokenOracle(address(borrowTokenOracle));

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
        factory.setBorrowTokenOracle(address(0));

        assertEq(factory.borrowTokenOracle(), address(borrowTokenOracle));
        factory.setBorrowTokenOracle(address(1));
        assertEq(factory.borrowTokenOracle(), address(1));
    }

    function testSetBorrowTokenOracleForVault() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setBorrowTokenOracle(payable(address(vault)), address(0));

        assertEq(vault.borrowTokenOracle(), address(borrowTokenOracle));
        factory.setBorrowTokenOracle(payable(address(vault)), address(1));
        assertEq(vault.borrowTokenOracle(), address(1));
    }

    function testSetBorrowTokenOracleMaxPriceAge() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setBorrowTokenOracleMaxPriceAge(payable(address(vault)), 24 hours);
        factory.setBorrowTokenOracleMaxPriceAge(payable(address(vault)), 10 hours);
    }

    function testSetCollateralTokenOracleMaxPriceAge() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setCollateralTokenOracleMaxPriceAge(payable(address(vault)), 24 hours);
        factory.setCollateralTokenOracleMaxPriceAge(payable(address(vault)), 10 hours);
    }

    function testSetInterestRateManager() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setInterestRateManager(address(this));

        assertEq(factory.interestRateManager(), address(this));
        factory.setInterestRateManager(address(1));
        assertEq(factory.interestRateManager(), address(1));
    }

    function testSetTrustedSwapTarget() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setTrustedSwapTarget(address(this), false);

        assertEq(factory.isTrustedSwapTarget(address(this)), false);
        factory.setTrustedSwapTarget(address(this), true);
        assertEq(factory.isTrustedSwapTarget(address(this)), true);
    }

    function testSetDebtCollector() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setDebtCollector(address(this));

        assertEq(factory.debtCollector(), address(this));
        factory.setDebtCollector(address(1));
        assertEq(factory.debtCollector(), address(1));
    }

    function testSetFeeReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setFeeReceiver(address(1));

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
        factory.setFeeReceiver(address(0));

        assertEq(factory.feeReceiver(), address(1));
        factory.setFeeReceiver(address(this));
        assertEq(factory.feeReceiver(), address(this));
    }

    function testSetPenaltyReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setPenaltyReceiver(address(2));

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
        factory.setPenaltyReceiver(address(0));

        assertEq(factory.penaltyReceiver(), address(2));
        factory.setPenaltyReceiver(address(this));
        assertEq(factory.penaltyReceiver(), address(this));
    }

    function testSetBorrowOpeningFee() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setBorrowOpeningFee(payable(address(vault)), 0.005e18);

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidFee.selector, 0, 1 ether, 1.1 ether));
        factory.setBorrowOpeningFee(payable(address(vault)), 1.1 ether);

        factory.setBorrowOpeningFee(payable(address(vault)), 0.7 ether);
    }

    function testSetLiquidationPenaltyFee() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setLiquidationPenaltyFee(payable(address(vault)), 0.05e18);

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidFee.selector, 0, 1 ether, 1.1 ether));
        factory.setLiquidationPenaltyFee(payable(address(vault)), 1.1 ether);

        vm.expectRevert(abi.encodeWithSelector(VaultFactoryVaultManagement.NonexistentVault.selector, address(1)));
        factory.setLiquidationPenaltyFee(payable(address(1)), 0.7 ether);

        factory.setLiquidationPenaltyFee(payable(address(vault)), 0.7 ether);
    }

    function testSetLiquidatorPenaltyShare() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setLiquidatorPenaltyShare(0.6 ether);

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidShare.selector, 0, 1 ether, 1.1 ether));
        factory.setLiquidatorPenaltyShare(1.1 ether);

        factory.setLiquidatorPenaltyShare(0.7 ether);
    }

    function testSetCollateralTokenOracle() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setCollateralTokenOracle(payable(address(vault)), address(collateralTokenOracle));

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
        factory.setCollateralTokenOracle(payable(address(vault)), address(0));

        factory.setCollateralTokenOracle(payable(address(vault)), address(1));
    }

    function testRetireVault() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));

        factory.retireVault(payable(address(vault)));
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.retireVault(payable(address(vault)));
    }

    function testReviveVault() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));
        factory.retireVault(payable(address(vault)));

        factory.reviveVault(payable(address(vault)));
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.reviveVault(payable(address(vault)));
    }

    function testSetLiquidationThreshold() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setLiquidationThreshold(payable(address(vault)), 90);

        vm.expectRevert(abi.encodeWithSelector(StackVault.InvalidLiquidationThreshold.selector, 1, 99, 0));
        factory.setLiquidationThreshold(payable(address(vault)), 0);

        vm.expectRevert(abi.encodeWithSelector(StackVault.InvalidLiquidationThreshold.selector, 1, 99, 100));
        factory.setLiquidationThreshold(payable(address(vault)), 100);

        factory.setLiquidationThreshold(payable(address(vault)), 70);
    }

    function testSetBorrowInterestMultiplier() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setBorrowInterestMultiplier(payable(address(vault)), 1e1);
        factory.setBorrowInterestMultiplier(payable(address(vault)), 2e1);
    }

    function testCollectFees() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));

        assertEq(borrowToken.balanceOf(factory.penaltyReceiver()), 0);
        borrowToken.mint(address(vault), 1 ether);

        vm.startPrank(address(vault));
        borrowToken.approve(address(factory), 1 ether);
        factory.collectFees(address(borrowToken), 1 ether);

        assertEq(borrowToken.balanceOf(factory.penaltyReceiver()), 1 ether);
        vm.stopPrank();
    }

    function testViewFunctionForCoverage() public {
        factory.liquidatorPenaltyShare();
    }

    function testSetVaultDeployer() public {
        address j = factory.vaultDeployer();
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setVaultDeployer(j);

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.InvalidZeroAddress.selector));
        factory.setVaultDeployer(address(0));

        factory.setVaultDeployer(address(this));
        assertEq(factory.vaultDeployer(), address(this));
    }

    function testShouldFailToUpdateBorrowInterestRate() public {
        vm.startPrank(address(1));
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.UnauthorizedCaller.selector));
        factory.updateBorrowInterestRate(0.5e18);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.updateBorrowInterestRate(1 ether);
    }

    function testShouldFailToCallVaultDeployerFunctions() public {
        vm.startPrank(address(1));
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.UnauthorizedCaller.selector));
        vaultDeployer.deployVault(address(1), address(1), address(1), 1, 1);

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.UnauthorizedCaller.selector));
        vaultDeployer.upgradeVault(payable(address(1)), address(1));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.updateBorrowInterestRate(1 ether);
    }

    function testOverrideBorrowInterestRate() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.overrideBorrowInterestRate(0);

        assertEq(factory.borrowInterestRate(), 0);
        factory.overrideBorrowInterestRate(1 ether);
        assertEq(factory.borrowInterestRate(), 1 ether);
    }

    function testUpdateDebtCeiling() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));
        assertEq(vault.borrowLimit(), 0);

        uint256 debtCeiling = 1_000e18;
        borrowToken.mint(address(this), debtCeiling);
        borrowToken.approve(address(factory), debtCeiling);

        factory.setBorrowLimit(payable(address(vault)), debtCeiling);
        assertEq(vault.borrowLimit(), debtCeiling);
        assertEq(borrowToken.balanceOf(address(this)), 0);
        assertEq(borrowToken.balanceOf(address(vault)), debtCeiling);

        factory.setBorrowLimit(payable(address(vault)), debtCeiling / 2);
        assertEq(vault.borrowLimit(), debtCeiling / 2);
        //assertEq(borrowToken.balanceOf(address(this)), 0);
        assertEq(borrowToken.balanceOf(address(vault)), debtCeiling / 2);

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setBorrowLimit(payable(address(vault)), debtCeiling / 2);
    }

    function testNotifyAccruedInterest() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));
        assertEq(borrowToken.balanceOf(address(1)), 0);

        vm.startPrank(address(vault));
        factory.notifyAccruedInterest(1 ether);

        vm.stopPrank();
        assertEq(borrowToken.balanceOf(address(1)), 1 ether);
    }

    function testUpgradeVaultImplementation() public {
        MockVaultImplementationDeployer implementationDeployer = new MockVaultImplementationDeployer();
        MockVaultDeployer vaultD =
            new MockVaultDeployer(address(weth), address(factory), address(implementationDeployer));

        bytes memory init = abi.encodeCall(MockVaultDeployer.initialize, ());
        ERC1967Proxy proxy = new ERC1967Proxy(address(vaultD), init);
        vaultD = MockVaultDeployer(address(proxy));

        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));

        // just for coverage
        StackVault v0 = StackVault(factory.createVault(address(weth), address(collateralTokenOracle), 90, 1e1));
        v0.transferOwnership(address(factory));
        factory.upgradeVaultImplementation(payable(address(v0)));

        // actual upgrade
        factory.setVaultDeployer(address(vaultD));
        vault.transferOwnership(address(factory));

        assertEq(vault.owner(), address(factory));
        factory.upgradeVaultImplementation(payable(address(vault)));

        assertEq(vault.owner(), factory.owner());
        MockStackVault v = MockStackVault(payable(factory.vaultForToken(address(collateralToken))));
        assertEq(v.newFunction(), 1);
    }
}
