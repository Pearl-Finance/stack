// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {WETH9} from "./mocks/WETH9.sol";
import {MockMore} from "./mocks/MockMore.sol";
import {MockSwap} from "./mocks/MockSwap.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ERC20Mock2} from "./mocks/ERC20Mock2.sol";
import {ERC20MockMinter} from "./mocks/ERC20MockMinter.sol";
import {AggregatorV3Mock} from "./mocks/AggregatorV3Mock.sol";
import {YieldTokenMock, ERC4626} from "./mocks/YieldTokenMock.sol";
import {AggregatorV3WrapperMock} from "./mocks/AggregatorV3WrapperMock.sol";

import {Test, console2} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156.sol";

import {More} from "src/tokens/More.sol";
import {MoreMinter} from "src/tokens/MoreMinter.sol";
import {VaultImplementationDeployer} from "src/factories/VaultImplementationDeployer.sol";
import {CappedPriceOracle, IOracle, CommonErrors} from "src/oracles/CappedPriceOracle.sol";
import {IERC20, Math, Constants, VaultFactory, VaultDeployer} from "src/factories/VaultFactory.sol";
import {
    StackVault,
    StackVaultTransfers,
    InterestAccrualMath,
    InterestAccruingAmount,
    FeeMath
} from "src/vaults/StackVault.sol";

/**
 * @title Stack Vault Test Cases
 * @author c-n-o-t-e
 * @dev Contract is used to test out Stack Vault Contract in a stateless way.
 *
 * Functionalities Tested:
 *  - Debt Repayment
 *  - Failed Scenarios
 *  - Leveraged Operations
 *  - Position Liquidations
 *  - Deleveraged Operations
 *  - Closing Bad Debts Position
 *  - Collateral Deposits and Withdrawals.
 *  - Borrowing Against Collateral With Interest Accrual.
 */
contract StackVaultTest is Test {
    using InterestAccrualMath for InterestAccruingAmount;

    WETH9 weth;
    StackVault vault;
    More borrowToken0;
    IERC20 borrowToken;
    StackVault ethVault;
    VaultFactory factory;
    ERC4626 collateralToken;
    IOracle borrowTokenOracle;
    ERC20MockMinter borrowTokenMinter;
    AggregatorV3Mock borrowTokenAggregator;
    InterestAccruingAmount totalBorrowAmount;
    AggregatorV3Mock collateralTokenAggregator;
    InterestAccruingAmount totalCollateralAmount;
    AggregatorV3WrapperMock collateralTokenOracle;

    address bob = makeAddr("bob");
    address alice = makeAddr("alice");

    function setUp() public {
        vm.warp(1 days);
        ERC20Mock underlying = new ERC20Mock(18);
        deal(address(underlying), address(this), 1_000_000e18);
        borrowTokenAggregator = new AggregatorV3Mock(6);
        collateralTokenAggregator = new AggregatorV3Mock(6);
        borrowTokenAggregator.setAnswer(1e6);
        collateralTokenAggregator.setAnswer(1e6);
        borrowToken = new ERC20Mock(18);
        collateralToken = new YieldTokenMock(underlying);
        borrowTokenMinter = new ERC20MockMinter(address(borrowToken));
        borrowTokenOracle = new CappedPriceOracle(
            address(new AggregatorV3WrapperMock(address(borrowToken), address(borrowTokenAggregator))), 1e18
        );
        collateralTokenOracle =
            new AggregatorV3WrapperMock(address(collateralToken), address(collateralTokenAggregator));

        ERC20Mock(address(borrowToken)).mint(address(this), 10_000e18);

        underlying.approve(address(collateralToken), 100_000e18);
        collateralToken.deposit(100_000e18, address(this));

        collateralToken.transfer(alice, 10_000e18);
        collateralToken.transfer(bob, 10_000e18);

        weth = new WETH9();

        address factoryAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 5);

        VaultImplementationDeployer implementationDeployer = new VaultImplementationDeployer();
        StackVaultTransfers transferHelper = new StackVaultTransfers();
        VaultDeployer vaultDeployer =
            new VaultDeployer(address(weth), factoryAddress, address(implementationDeployer), address(transferHelper));
        bytes memory init = abi.encodeCall(vaultDeployer.initialize, ());
        ERC1967Proxy proxy = new ERC1967Proxy(address(vaultDeployer), init);

        VaultFactory vaultFactory = new VaultFactory(address(weth), address(borrowTokenMinter));
        init = abi.encodeCall(
            vaultFactory.initialize, (address(proxy), address(borrowTokenOracle), address(1), address(2))
        );
        proxy = new ERC1967Proxy(address(vaultFactory), init);
        factory = VaultFactory(address(proxy));

        assert(factoryAddress == address(factory));

        vault = StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));
        ethVault = StackVault(factory.createVault(Constants.ETH_ADDRESS, address(collateralTokenOracle), 80, 1e1));

        factory.setMinimumBorrowAmount(payable(address(vault)), 1e18);
        factory.setMinimumBorrowAmount(payable(address(ethVault)), 1e18);

        factory.overrideBorrowInterestRate(0.02e18);

        borrowToken.approve(address(factory), 1_000e18);
        factory.setBorrowLimit(payable(address(vault)), 1_000e18);

        vm.label(address(borrowToken), "BorrowToken");
        vm.label(address(collateralToken), "CollateralToken");
        vm.label(address(borrowTokenOracle), "BorrowTokenOracle");
        vm.label(address(collateralTokenOracle), "CollateralTokenOracle");
        vm.label(address(vault), "Vault");
    }

    function testInitialState() public {
        assertEq(address(vault.collateralToken()), address(collateralToken));
        assertEq(vault.collateralTokenOracle(), address(collateralTokenOracle));
        assertEq(address(vault.borrowToken()), address(borrowToken));
        assertEq(vault.liquidationThreshold(), 90);
        assertEq(vault.borrowOpeningFee(), 0.005e18);
        assertEq(vault.liquidationPenaltyFee(), 0.05e18);

        uint256 interestRate = vault.interestRatePerSecond() * 365 days;
        uint256 trimmedInterestRate = interestRate / 1e13 * 1e13;
        assertEq(trimmedInterestRate, 0.01999e18);
    }

    error OwnableUnauthorizedAccount(address account);

    function testDeposit() public {
        vm.startPrank(address(alice));
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(alice)));
        vault.depositCollateral(address(alice), 100e18);
        vm.stopPrank();

        vm.expectRevert("StackVault: Unexpected ETH value");
        vault.depositCollateral{value: 1 ether}(address(this), 100e18);

        collateralToken.approve(address(vault), 100e18);
        uint256 share = vault.depositCollateral(address(this), 100e18);

        assertEq(share, 100e18);
        assertEq(vault.userCollateralShare(address(this)), 100e18);

        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            vault.userPositionInfo(address(this));

        assertEq(collateralAmount, 100e18);
        assertEq(collateralValue, 100e18);

        assertEq(borrowAmount, 0);
        assertEq(borrowValue, 0);
    }

    function testDepositETH() public {
        vm.expectRevert("StackVault: Incorrect ETH value");
        ethVault.depositCollateral{value: 1 ether}(address(this), 100e18);

        ethVault.depositCollateral{value: 100e18}(address(this), 100e18);
        weth.deposit{value: 100e18}();

        // deposit weth
        weth.approve(address(ethVault), 100e18);
        ethVault.depositCollateral(address(this), 100e18);
    }

    function testWithdraw() public {
        collateralToken.approve(address(vault), 100e18);
        vault.depositCollateral(address(this), 100e18);

        uint256 balanceBefore = collateralToken.balanceOf(address(this));
        uint256 balanceAfter;

        vault.withdrawCollateral(address(this), 50e18);
        balanceAfter = collateralToken.balanceOf(address(this));
        assertEq(balanceAfter - balanceBefore, 50e18);

        vault.withdrawCollateral(address(this));
        balanceAfter = collateralToken.balanceOf(address(this));
        assertEq(balanceAfter - balanceBefore, 100e18);

        assertEq(vault.userCollateralShare(address(this)), 0);

        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            vault.userPositionInfo(address(this));

        assertEq(collateralAmount, 0);
        assertEq(collateralValue, 0);
        assertEq(borrowAmount, 0);
        assertEq(borrowValue, 0);
    }

    function testWithdrawETH() public {
        ethVault.transferOwnership(address(alice));

        vm.startPrank(address(alice));
        deal(address(alice), 100e18);

        uint256 balanceBefore = address(alice).balance;
        ethVault.depositCollateral{value: 100e18}(address(alice), 100e18);

        assertEq(balanceBefore - 100e18, address(alice).balance);
        ethVault.withdrawCollateral(address(alice));
        assertEq(balanceBefore, address(alice).balance);

        // deposit weth
        weth.deposit{value: 100e18}();
        balanceBefore = weth.balanceOf(address(alice));

        weth.approve(address(ethVault), 100e18);
        ethVault.depositCollateral(address(alice), 100e18);

        assertEq(balanceBefore - 100e18, weth.balanceOf(address(alice)));
        ethVault.withdrawCollateral(address(alice));

        assertEq(balanceBefore, address(alice).balance);
        vm.stopPrank();

        //withdraw weth
        vm.startPrank(address(alice));
        ethVault.transferOwnership(address(this));
        vm.stopPrank();
        ERC20Mock2 token = new ERC20Mock2(18, address(9));

        weth.deposit{value: 100e18}();
        balanceBefore = weth.balanceOf(address(this));

        weth.approve(address(ethVault), 100e18);
        ethVault.depositCollateral(address(this), 100e18);
        assertEq(weth.balanceOf(address(this)), balanceBefore - 100e18);

        ethVault.withdrawCollateral(address(token), 50e18);
        assertEq(weth.balanceOf(address(token)), 50e18);

        weth.blackListAddress(address(token));
        vm.expectRevert("StackVault: Failed to send ETH");
        ethVault.withdrawCollateral(address(token), 50e18);
    }

    function testShouldBorrow() public {
        collateralToken.approve(address(vault), 100e18);
        vault.depositCollateral(address(this), 100e18);

        uint256 amount = 65e18;
        uint256 balanceBefore = borrowToken.balanceOf(address(this));

        uint256 contractBalanceBefore = borrowToken.balanceOf(address(vault));
        uint256 feeReceieverBalanceBefore = borrowToken.balanceOf(address(1));
        uint256 userBorrowerSharesBefore = vault.userBorrowShare(address(this));

        uint256 share = vault.borrow(address(this), amount);

        uint256 fee = amount * vault.borrowOpeningFee() / 1e18;
        uint256 balanceAfter = borrowToken.balanceOf(address(this));
        uint256 amountWithFee = fee + amount;

        assertEq(share, amountWithFee);
        assertEq(balanceAfter - balanceBefore, amount);
        assertEq(contractBalanceBefore - amount, borrowToken.balanceOf(address(vault)));

        assertEq(fee + feeReceieverBalanceBefore, borrowToken.balanceOf(address(1)));
        assertEq(share + userBorrowerSharesBefore, vault.userBorrowShare(address(this)));

        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            vault.userPositionInfo(address(this));

        assertEq(collateralAmount, 100e18);
        assertEq(collateralValue, 100e18);

        assertEq(borrowAmount, amountWithFee);
        assertEq(borrowValue, amountWithFee);
    }

    function testViewFunctionsForCoverage() external view {
        vault.isRetired();
        vault.totalBorrowAmount();
        vault.mimimumBorrowAmount();
        vault.totalCollateralAmount();
        vault.interestRateMultiplier();
    }

    function testShouldAccrueInterestForFactory() external {
        collateralToken.approve(address(vault), 100e18);
        vault.depositCollateral(address(this), 100e18);
        assertEq(borrowToken.balanceOf(address(1)), 0);

        vault.borrow(address(this), 65e18);
        vm.roll(block.number + 1 hours);

        vm.startPrank(address(bob));
        collateralToken.approve(address(vault), 100e18);
        vault.depositCollateral(address(this), 100e18);
        vm.stopPrank();

        assertGt(borrowToken.balanceOf(address(1)), 0);

        vm.startPrank(address(factory));
        vault.retire();
        vm.stopPrank();

        vm.roll(block.number + 1 hours);
        // for coverage
        collateralToken.approve(address(vault), 100e18);
        vault.depositCollateral(address(this), 100e18);
    }

    function testShouldFailToBorrow() public {
        collateralToken.approve(address(vault), 100e18);
        vault.depositCollateral(address(this), 100e18);

        vm.expectRevert(abi.encodeWithSelector(StackVault.BorrowAmountTooLow.selector, 1.005e17, 1e18));
        vault.borrow(address(this), 1e17);

        vm.expectRevert(abi.encodeWithSelector(StackVault.Unhealthy.selector));
        vault.borrow(address(this), 92e18);

        factory.setBorrowLimit(payable(address(vault)), 70e18);
        uint256 amountWithFee = 71e18 * vault.borrowOpeningFee() / 1e18 + 71e18;

        vm.expectRevert(abi.encodeWithSelector(StackVault.BorrowLimitExceeded.selector, amountWithFee, 70e18));
        vault.borrow(address(this), 71e18);
    }

    function testBorrowUpsideDepeg() public {
        borrowTokenAggregator.setAnswer(1.5e6);

        collateralToken.approve(address(vault), 100e18);
        vault.depositCollateral(address(this), 100e18);

        uint256 balanceBefore = borrowToken.balanceOf(address(this));
        uint256 amount = 85e18;
        uint256 share = vault.borrow(address(this), amount);
        uint256 balanceAfter = borrowToken.balanceOf(address(this));
        uint256 amountWithFee = amount * vault.borrowOpeningFee() / 1e18 + amount;

        assertEq(share, amountWithFee);
        assertEq(balanceAfter - balanceBefore, amount);

        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            vault.userPositionInfo(address(this));

        assertEq(collateralAmount, 100e18);
        assertEq(collateralValue, 100e18);
        assertEq(borrowAmount, amountWithFee);
        assertEq(borrowValue, amountWithFee);
    }

    function testBorrowDownsideDepeg() public {
        borrowTokenAggregator.setAnswer(0.5e6);

        collateralToken.approve(address(vault), 100e18);
        vault.depositCollateral(address(this), 100e18);

        uint256 balanceBefore = borrowToken.balanceOf(address(this));
        uint256 amount = 170e18;
        uint256 share = vault.borrow(address(this), amount);
        uint256 balanceAfter = borrowToken.balanceOf(address(this));
        uint256 amountWithFee = amount * vault.borrowOpeningFee() / 1e18 + amount;

        assertEq(share, amountWithFee);
        assertEq(balanceAfter - balanceBefore, amount);

        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            vault.userPositionInfo(address(this));

        assertEq(collateralAmount, 100e18);
        assertEq(collateralValue, 100e18);
        assertEq(borrowAmount, amountWithFee);
        assertEq(borrowValue, amountWithFee / 2);
    }

    function testShouldRepayDebt() public {
        collateralToken.approve(address(vault), 100e18);
        vault.depositCollateral(address(this), 100e18);

        vault.borrow(address(this), 85e18);
        uint256 amountWithFee = 85e18 * vault.borrowOpeningFee() / 1e18 + 85e18;

        borrowToken.approve(address(vault), 100e18);

        vm.expectRevert(abi.encodeWithSelector(StackVault.BorrowAmountTooLow.selector, 0.9e18, 1e18));
        vault.repay(address(this), amountWithFee - 0.9e18);

        uint256 amount = vault.repay(address(this), 50e18);

        assertEq(amount, 50e18);

        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            vault.userPositionInfo(address(this));

        assertEq(collateralAmount, 100e18);
        assertEq(collateralValue, 100e18);
        assertEq(borrowAmount, amountWithFee - amount);
        assertEq(borrowValue, amountWithFee - amount);
    }

    function testShouldRepayFullDebt() public {
        collateralToken.approve(address(vault), 100e18);
        vault.depositCollateral(address(this), 100e18);
        vault.borrow(address(this), 85e18);

        borrowToken.approve(address(vault), 100e18);
        vault.repay(address(this));

        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            vault.userPositionInfo(address(this));

        assertEq(collateralAmount, 100e18);
        assertEq(collateralValue, 100e18);

        assertEq(borrowAmount, 0);
        assertEq(borrowValue, 0);
    }

    function testShouldFailToApplyLeverage() public {
        MockMore bToken = new MockMore(address(9));
        bytes memory init = abi.encodeCall(bToken.initialize, (address(this)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(bToken), init);
        bToken = MockMore(address(proxy));

        address factoryAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 7);
        MoreMinter moreMinter = new MoreMinter(address(bToken));

        init = abi.encodeCall(moreMinter.initialize, (address(this), factoryAddress));
        proxy = new ERC1967Proxy(address(moreMinter), init);
        moreMinter = MoreMinter(address(proxy));
        bToken.setMinter(address(moreMinter));

        VaultImplementationDeployer implementationDeployer = new VaultImplementationDeployer();
        StackVaultTransfers transferHelper = new StackVaultTransfers();
        VaultDeployer vaultDeployer =
            new VaultDeployer(address(weth), factoryAddress, address(implementationDeployer), address(transferHelper));

        init = abi.encodeCall(vaultDeployer.initialize, ());
        proxy = new ERC1967Proxy(address(vaultDeployer), init);

        VaultFactory vaultFactory = new VaultFactory(address(weth), address(moreMinter));
        init = abi.encodeCall(
            vaultFactory.initialize, (address(proxy), address(borrowTokenOracle), address(1), address(2))
        );

        proxy = new ERC1967Proxy(address(vaultFactory), init);
        factory = VaultFactory(address(proxy));

        StackVault va =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));

        collateralToken.approve(address(va), 200e18);
        vm.expectRevert(abi.encodeWithSelector(StackVault.LeverageFlashloanFailed.selector));
        va.leverage(20e18, 108e18, address(9), "0x0");
    }

    function testShouldLeverage() public {
        borrowToken0 = new More(address(9));
        bytes memory init = abi.encodeCall(borrowToken0.initialize, (address(this)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(borrowToken0), init);
        borrowToken0 = More(address(proxy));

        address factoryAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 7);
        MoreMinter moreMinter = new MoreMinter(address(borrowToken0));

        init = abi.encodeCall(moreMinter.initialize, (address(this), factoryAddress));
        proxy = new ERC1967Proxy(address(moreMinter), init);

        moreMinter = MoreMinter(address(proxy));
        borrowToken0.setMinter(address(moreMinter));

        VaultImplementationDeployer implementationDeployer = new VaultImplementationDeployer();
        StackVaultTransfers transferHelper = new StackVaultTransfers();
        VaultDeployer vaultDeployer =
            new VaultDeployer(address(weth), factoryAddress, address(implementationDeployer), address(transferHelper));

        init = abi.encodeCall(vaultDeployer.initialize, ());
        proxy = new ERC1967Proxy(address(vaultDeployer), init);

        VaultFactory vaultFactory = new VaultFactory(address(weth), address(moreMinter));

        init = abi.encodeCall(
            vaultFactory.initialize, (address(proxy), address(borrowTokenOracle), address(1), address(2))
        );

        proxy = new ERC1967Proxy(address(vaultFactory), init);
        factory = VaultFactory(address(proxy));

        MockSwap swap = new MockSwap(address(borrowToken0), address(collateralToken));
        deal(address(collateralToken), address(swap), 1000e18);

        StackVault va =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));

        IERC3156FlashBorrower flash = IERC3156FlashBorrower(address(va));
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.UnauthorizedCaller.selector));

        borrowToken0.flashLoan(flash, address(borrowToken0), 1 ether, "0x0");
        factory.setMinimumBorrowAmount(payable(address(va)), 1e18);

        deal(address(borrowToken0), address(this), 10_000e18);
        uint256 amountWithFee = 108e18 * vault.borrowOpeningFee() / 1e18 + 108e18;

        borrowToken0.approve(address(factory), 1_000e18);
        factory.setBorrowLimit(payable(address(va)), 1_000e18);

        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256(bytes("swap(address,address,uint256)"))),
            address(borrowToken0),
            address(collateralToken),
            108e18
        );

        collateralToken.approve(address(va), 200e18);
        vm.expectRevert(abi.encodeWithSelector(StackVault.UntrustedSwapTarget.selector, address(swap)));
        va.leverage(20e18, 108e18, address(swap), data);
        factory.setTrustedSwapTarget(address(swap), true);

        vm.startPrank(address(alice));
        collateralToken.approve(address(va), 200e18);
        va.leverage(20e18, 108e18, address(swap), data);
        vm.stopPrank();

        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            va.userPositionInfo(address(alice));

        assertEq(collateralAmount, 20e18 + 108e18);
        assertEq(collateralValue, 20e18 + 108e18);

        assertEq(borrowAmount, amountWithFee);
        assertEq(borrowValue, amountWithFee);
    }

    function testShouldAddBackCollateralSwapAmountIsLess() public {
        borrowToken0 = new More(address(9));
        bytes memory init = abi.encodeCall(borrowToken0.initialize, (address(this)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(borrowToken0), init);
        borrowToken0 = More(address(proxy));

        address factoryAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 7);
        MoreMinter moreMinter = new MoreMinter(address(borrowToken0));

        init = abi.encodeCall(moreMinter.initialize, (address(this), factoryAddress));
        proxy = new ERC1967Proxy(address(moreMinter), init);

        moreMinter = MoreMinter(address(proxy));
        borrowToken0.setMinter(address(moreMinter));

        VaultImplementationDeployer implementationDeployer = new VaultImplementationDeployer();
        StackVaultTransfers transferHelper = new StackVaultTransfers();
        VaultDeployer vaultDeployer =
            new VaultDeployer(address(weth), factoryAddress, address(implementationDeployer), address(transferHelper));

        init = abi.encodeCall(vaultDeployer.initialize, ());
        proxy = new ERC1967Proxy(address(vaultDeployer), init);

        VaultFactory vaultFactory = new VaultFactory(address(weth), address(moreMinter));
        init = abi.encodeCall(
            vaultFactory.initialize, (address(proxy), address(borrowTokenOracle), address(1), address(2))
        );

        proxy = new ERC1967Proxy(address(vaultFactory), init);
        factory = VaultFactory(address(proxy));

        MockSwap swap = new MockSwap(address(borrowToken0), address(collateralToken));
        deal(address(collateralToken), address(swap), 1000e18);

        deal(address(borrowToken0), address(swap), 1000e18);
        factory.setTrustedSwapTarget(address(swap), true);

        StackVault va =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));

        factory.setMinimumBorrowAmount(payable(address(va)), 1e18);
        deal(address(borrowToken0), address(this), 10_000e18);

        borrowToken0.approve(address(factory), 1_000e18);
        factory.setBorrowLimit(payable(address(va)), 1_000e18);

        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256(bytes("swap(address,address,uint256)"))),
            address(borrowToken0),
            address(collateralToken),
            108e18
        );

        uint256 amountWithFee = 108e18 * vault.borrowOpeningFee() / 1e18 + 108e18;

        bytes memory data0 = abi.encodeWithSelector(
            bytes4(keccak256(bytes("swapForLess(address,address,uint256)"))),
            address(collateralToken),
            address(borrowToken0),
            amountWithFee
        );

        vm.startPrank(address(alice));
        collateralToken.approve(address(va), 200e18);
        va.leverage(100e18, 108e18, address(swap), data);

        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            va.userPositionInfo(address(alice));

        assertEq(collateralAmount, 100e18 + 108e18);
        assertEq(collateralValue, 100e18 + 108e18);

        assertEq(borrowAmount, amountWithFee);
        assertEq(borrowValue, amountWithFee);

        va.deleverage(amountWithFee, address(swap), data0);
        vm.stopPrank();

        (uint256 cAmount, uint256 cValue, uint256 bAmount, uint256 bValue) = va.userPositionInfo(address(alice));

        assertEq(collateralAmount - (amountWithFee / 2), cAmount);
        assertEq(collateralValue - (amountWithFee / 2), cValue);

        assertEq(borrowAmount / 2, bAmount);
        assertEq(borrowValue / 2, bValue);
    }

    function testShouldDeleverage() public {
        borrowToken0 = new More(address(9));
        bytes memory init = abi.encodeCall(borrowToken0.initialize, (address(this)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(borrowToken0), init);
        borrowToken0 = More(address(proxy));

        address factoryAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 7);
        MoreMinter moreMinter = new MoreMinter(address(borrowToken0));

        init = abi.encodeCall(moreMinter.initialize, (address(this), factoryAddress));
        proxy = new ERC1967Proxy(address(moreMinter), init);

        moreMinter = MoreMinter(address(proxy));
        borrowToken0.setMinter(address(moreMinter));

        VaultImplementationDeployer implementationDeployer = new VaultImplementationDeployer();
        StackVaultTransfers transferHelper = new StackVaultTransfers();
        VaultDeployer vaultDeployer =
            new VaultDeployer(address(weth), factoryAddress, address(implementationDeployer), address(transferHelper));

        init = abi.encodeCall(vaultDeployer.initialize, ());
        proxy = new ERC1967Proxy(address(vaultDeployer), init);

        VaultFactory vaultFactory = new VaultFactory(address(weth), address(moreMinter));
        init = abi.encodeCall(
            vaultFactory.initialize, (address(proxy), address(borrowTokenOracle), address(1), address(2))
        );

        proxy = new ERC1967Proxy(address(vaultFactory), init);
        factory = VaultFactory(address(proxy));

        MockSwap swap = new MockSwap(address(borrowToken0), address(collateralToken));
        deal(address(collateralToken), address(swap), 1000e18);

        deal(address(borrowToken0), address(swap), 1000e18);
        factory.setTrustedSwapTarget(address(swap), true);

        StackVault va =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));

        factory.setMinimumBorrowAmount(payable(address(va)), 1e18);
        deal(address(borrowToken0), address(this), 10_000e18);

        borrowToken0.approve(address(factory), 1_000e18);
        factory.setBorrowLimit(payable(address(va)), 1_000e18);

        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256(bytes("swap(address,address,uint256)"))),
            address(borrowToken0),
            address(collateralToken),
            108e18
        );

        uint256 fee = 108e18 * vault.borrowOpeningFee() / 1e18;
        uint256 amountWithFee = fee + 108e18;

        bytes memory data0 = abi.encodeWithSelector(
            bytes4(keccak256(bytes("swap(address,address,uint256)"))),
            address(collateralToken),
            address(borrowToken0),
            amountWithFee
        );

        vm.startPrank(address(alice));
        collateralToken.approve(address(va), 200e18);
        va.leverage(20e18, 108e18, address(swap), data);

        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            va.userPositionInfo(address(alice));

        assertEq(collateralAmount, 108e18 + 20e18);
        assertEq(collateralValue, 108e18 + 20e18);

        assertEq(borrowAmount, amountWithFee);
        assertEq(borrowValue, amountWithFee);

        va.deleverage(amountWithFee, address(swap), data0);
        vm.stopPrank();

        (uint256 cAmount, uint256 cValue, uint256 bAmount, uint256 bValue) = va.userPositionInfo(address(alice));

        assertEq(cAmount, 20e18 - fee);
        assertEq(cValue, 20e18 - fee);

        assertEq(bAmount, 0);
        assertEq(bValue, 0);
    }

    function testShouldLiquidateUserEntireFunds() public {
        collateralToken.approve(address(vault), 10000e18);
        vault.depositCollateral(address(this), 1000e18);

        vault.borrow(address(this), 850e18);
        (uint256 collateralAmount,, uint256 borrowAmount, uint256 borrowValue) = vault.userPositionInfo(address(this));

        vm.expectRevert(abi.encodeWithSelector(StackVault.LiquidationFailed.selector, address(this), address(this)));
        vault.liquidate(address(this), 1_000e18, address(bob));

        collateralTokenAggregator.setAnswer(0.86e6);
        deal(address(borrowToken), address(bob), 100_000e18);

        assertEq(borrowToken.balanceOf(address(bob)), 100_000e18);
        uint256 collateralAmt = collateralTokenOracle.amountOf(borrowValue, Math.Rounding.Floor);

        uint256 fee = FeeMath.calculateFeeAmount(borrowAmount, 50000000000000000);
        uint256 feeValue = borrowTokenOracle.valueOf(fee, Math.Rounding.Floor);

        uint256 penaltyFeeAmount = collateralTokenOracle.amountOf(feeValue, Math.Rounding.Floor);
        uint256 totalCollateralRemoved = collateralAmt + penaltyFeeAmount;

        if (totalCollateralRemoved > collateralAmount) {
            totalCollateralRemoved = collateralAmount;
            if (totalCollateralRemoved > collateralAmt) {
                penaltyFeeAmount = totalCollateralRemoved - collateralAmt;
            } else {
                penaltyFeeAmount = 0;
            }
        }

        uint256 factoryFee = penaltyFeeAmount / 2;
        uint256 collateralRecieved = totalCollateralRemoved - factoryFee;

        uint256 userCollateralBalanceBeforeTx = collateralToken.balanceOf(address(bob));
        uint256 factoryCollateralBalanceBeforeTx = collateralToken.balanceOf(address(factory));

        vm.startPrank(address(bob));
        borrowToken.approve(address(vault), 1_00000e18);
        vault.liquidate(address(this), 1_000e18, address(bob));
        vm.stopPrank();

        (uint256 cAmount,, uint256 bAmount,) = vault.userPositionInfo(address(this));

        assertEq(bAmount, 0);
        assertEq(cAmount, collateralAmount - totalCollateralRemoved);
        assertEq(borrowToken.balanceOf(address(bob)), 100_000e18 - borrowAmount);

        assertApproxEqAbs(collateralToken.balanceOf(address(2)), factoryCollateralBalanceBeforeTx + factoryFee, 1);
        assertApproxEqAbs(
            collateralToken.balanceOf(address(bob)), userCollateralBalanceBeforeTx + collateralRecieved, 1
        );
    }

    function testShouldFailToSetLiquidationThreshold() external {
        collateralToken.approve(address(vault), 10000e18);
        vault.depositCollateral(address(this), 1000e18);
        vault.borrow(address(this), 850e18);

        vm.startPrank(address(factory));
        vm.expectRevert(abi.encodeWithSelector(StackVault.InvalidLiquidationThreshold.selector, 90, 99, 70));
        vault.setLiquidationThreshold(70);
    }

    function testShouldFailToSetMinimumBorrowAmount() external {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ValueUnchanged.selector));
        factory.setMinimumBorrowAmount(payable(address(vault)), 1e18);
    }

    function testShouldLiquidatePartOfUserFunds() public {
        collateralToken.approve(address(vault), 10000e18);
        vault.depositCollateral(address(this), 1000e18);

        vault.borrow(address(this), 850e18);
        (uint256 collateralAmount,, uint256 borrowAmount,) = vault.userPositionInfo(address(this));

        collateralTokenAggregator.setAnswer(0.86e6);
        deal(address(borrowToken), address(bob), 100_000e18);

        assertEq(borrowToken.balanceOf(address(bob)), 100_000e18);
        uint256 borrowVal = borrowTokenOracle.valueOf(borrowAmount / 2, Math.Rounding.Floor);
        uint256 collateralAmt = collateralTokenOracle.amountOf(borrowVal, Math.Rounding.Floor);

        uint256 fee = FeeMath.calculateFeeAmount(borrowAmount / 2, 50000000000000000);
        uint256 feeValue = borrowTokenOracle.valueOf(fee, Math.Rounding.Floor);

        uint256 penaltyFeeAmount = collateralTokenOracle.amountOf(feeValue, Math.Rounding.Floor);
        uint256 totalCollateralRemoved = collateralAmt + penaltyFeeAmount;

        if (totalCollateralRemoved > collateralAmount) {
            totalCollateralRemoved = collateralAmount;
            if (totalCollateralRemoved > collateralAmt) {
                penaltyFeeAmount = totalCollateralRemoved - collateralAmt;
            } else {
                penaltyFeeAmount = 0;
            }
        }

        uint256 factoryFee = penaltyFeeAmount / 2;
        uint256 collateralRecieved = totalCollateralRemoved - factoryFee;

        uint256 userCollateralBalanceBeforeTx = collateralToken.balanceOf(address(bob));
        uint256 factoryCollateralBalanceBeforeTx = collateralToken.balanceOf(address(factory));

        vm.startPrank(address(bob));
        borrowToken.approve(address(vault), 1_00000e18);
        vault.liquidate(address(this), borrowAmount / 2, address(bob));
        vm.stopPrank();

        (uint256 cAmount,, uint256 bAmount,) = vault.userPositionInfo(address(this));

        assertEq(borrowAmount / 2, bAmount);
        assertEq(collateralAmount - totalCollateralRemoved, cAmount);

        assertEq(borrowToken.balanceOf(address(bob)), 100_000e18 - (borrowAmount / 2));
        assertApproxEqAbs(collateralToken.balanceOf(address(2)), factoryCollateralBalanceBeforeTx + factoryFee, 1);

        assertApproxEqAbs(
            collateralToken.balanceOf(address(bob)), userCollateralBalanceBeforeTx + collateralRecieved, 1
        );
    }

    function testShouldCloseBadDebtPosition() public {
        collateralToken.approve(address(vault), 100e18);
        vault.depositCollateral(address(this), 100e18);

        vm.startPrank(address(4));
        deal(address(collateralToken), address(4), 10000e18);
        collateralToken.approve(address(vault), 100e18);
        vault.depositCollateral(address(4), 100e18);
        vault.borrow(address(4), 50e18);
        vm.stopPrank();

        vault.borrow(address(this), 89e18);
        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            vault.userPositionInfo(address(this));

        vm.expectRevert(abi.encodeWithSelector(StackVault.NoBadDebt.selector, address(this)));
        vault.closeBadDebtPosition(address(this), address(bob));

        collateralTokenAggregator.setAnswer(0.1e6);
        uint256 fee = FeeMath.calculateFeeAmount(borrowAmount, 50000000000000000);

        uint256 feeValue = borrowTokenOracle.valueOf(fee, Math.Rounding.Floor);
        uint256 penaltyFeeAmount = collateralTokenOracle.amountOf(feeValue, Math.Rounding.Floor);

        if (penaltyFeeAmount > collateralAmount) {
            penaltyFeeAmount = collateralAmount;
        }

        uint256 partFee = penaltyFeeAmount / 2;
        uint256 amountToOwner = collateralAmount - penaltyFeeAmount;

        uint256 userCollateralBalanceBeforeTx = collateralToken.balanceOf(address(bob));
        uint256 factoryCollateralBalanceBeforeTx = collateralToken.balanceOf(address(factory));
        uint256 factoryOwnerCollateralBalanceBeforeTx = collateralToken.balanceOf(factory.owner());

        vm.startPrank(address(bob));
        vault.closeBadDebtPosition(address(this), address(bob));
        vm.stopPrank();

        (collateralAmount, collateralValue, borrowAmount, borrowValue) = vault.userPositionInfo(address(this));

        assertEq(collateralAmount, 0);
        assertEq(collateralValue, 0);

        assertEq(borrowAmount, 0);
        assertEq(borrowValue, 0);

        assertEq(collateralToken.balanceOf(address(bob)), userCollateralBalanceBeforeTx + partFee);
        assertEq(collateralToken.balanceOf(address(2)), factoryCollateralBalanceBeforeTx + partFee);
        assertEq(collateralToken.balanceOf(factory.owner()), factoryOwnerCollateralBalanceBeforeTx + amountToOwner);
    }

    function testShouldCloseBadDebtPositionWithPenaltyFeeAsCollateral() public {
        collateralToken.approve(address(vault), 10e18);
        vault.depositCollateral(address(this), 10e18);

        vault.borrow(address(this), 8.9e18);
        (uint256 collateralAmount,, uint256 borrowAmount,) = vault.userPositionInfo(address(this));

        vm.expectRevert(abi.encodeWithSelector(StackVault.NoBadDebt.selector, address(this)));
        vault.closeBadDebtPosition(address(this), address(bob));

        vm.startPrank(address(factory));
        vault.setLiquidationPenaltyFee(1000000000000000000);
        vm.stopPrank();

        collateralTokenAggregator.setAnswer(0.5e6);
        uint256 fee = FeeMath.calculateFeeAmount(borrowAmount, 1000000000000000000);

        uint256 feeValue = borrowTokenOracle.valueOf(fee, Math.Rounding.Floor);
        uint256 penaltyFeeAmount = collateralTokenOracle.amountOf(feeValue, Math.Rounding.Floor);

        if (penaltyFeeAmount > collateralAmount) {
            penaltyFeeAmount = collateralAmount;
        }

        uint256 amountToOwner = collateralAmount - penaltyFeeAmount;
        uint256 factoryOwnerCollateralBalanceBeforeTx = collateralToken.balanceOf(factory.owner());

        vm.startPrank(address(bob));
        vault.closeBadDebtPosition(address(this), address(bob));
        vm.stopPrank();

        assertEq(0, amountToOwner);
        assertEq(collateralToken.balanceOf(factory.owner()), factoryOwnerCollateralBalanceBeforeTx);
    }
}
