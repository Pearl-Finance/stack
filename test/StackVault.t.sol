// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/interfaces/IERC3156.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "@layerzerolabs/contracts/lzApp/mocks/LZEndpointMock.sol";

import "src/factories/VaultFactory.sol";
import "src/factories/VaultImplementationDeployer.sol";
import "src/oracles/CappedPriceOracle.sol";
import "src/vaults/StackVault.sol";

import "./mocks/ERC20Mock.sol";
import "./mocks/ERC20MockMinter.sol";
import "./mocks/AggregatorV3Mock.sol";
import "./mocks/AggregatorV3WrapperMock.sol";
import "./mocks/YieldTokenMock.sol";
import "./mocks/WETH9.sol";

contract StackVaultTest is Test {
    VaultFactory factory;
    IERC20 borrowToken;
    ERC4626 collateralToken;
    ERC20MockMinter borrowTokenMinter;
    AggregatorV3Mock borrowTokenAggregator;
    AggregatorV3Mock collateralTokenAggregator;
    IOracle borrowTokenOracle;
    AggregatorV3WrapperMock collateralTokenOracle;
    StackVault vault;
    StackVault ethVault;
    WETH9 weth;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

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

        ERC20Mock(address(borrowToken)).mint(address(this), 1_000e18);

        underlying.approve(address(collateralToken), 100_000e18);
        collateralToken.deposit(100_000e18, address(this));

        collateralToken.transfer(alice, 10_000e18);
        collateralToken.transfer(bob, 10_000e18);

        weth = new WETH9();

        address factoryAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 4);

        VaultImplementationDeployer implementationDeployer = new VaultImplementationDeployer();
        VaultDeployer vaultDeployer = new VaultDeployer(address(weth), factoryAddress, address(implementationDeployer));
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

    function testDeposit() public {
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

    function testBorrow() public {
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

    function testRepay() public {
        collateralToken.approve(address(vault), 100e18);
        vault.depositCollateral(address(this), 100e18);

        vault.borrow(address(this), 85e18);
        uint256 amountWithFee = 85e18 * vault.borrowOpeningFee() / 1e18 + 85e18;

        borrowToken.approve(address(vault), 100e18);

        uint256 amount = vault.repay(address(this), 50e18);

        assertEq(amount, 50e18);

        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            vault.userPositionInfo(address(this));

        assertEq(collateralAmount, 100e18);
        assertEq(collateralValue, 100e18);
        assertEq(borrowAmount, amountWithFee - amount);
        assertEq(borrowValue, amountWithFee - amount);
    }
}
