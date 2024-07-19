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

contract StackVaultNativeTest is Test {
    VaultFactory factory;
    IERC20 borrowToken;
    ERC20MockMinter borrowTokenMinter;
    AggregatorV3Mock borrowTokenAggregator;
    AggregatorV3Mock collateralTokenAggregator;
    IOracle borrowTokenOracle;
    AggregatorV3WrapperMock collateralTokenOracle;
    StackVault vault;
    WETH9 weth;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    fallback() external payable {}
    receive() external payable {}

    function setUp() public {
        vm.warp(1 days);
        borrowTokenAggregator = new AggregatorV3Mock(6);
        collateralTokenAggregator = new AggregatorV3Mock(18);
        borrowTokenAggregator.setAnswer(1e6);
        collateralTokenAggregator.setAnswer(3_000e18);
        weth = new WETH9();
        borrowToken = new ERC20Mock(18);
        borrowTokenMinter = new ERC20MockMinter(address(borrowToken));
        borrowTokenOracle = new CappedPriceOracle(
            address(new AggregatorV3WrapperMock(address(borrowToken), address(borrowTokenAggregator))), 1e18
        );
        collateralTokenOracle = new AggregatorV3WrapperMock(address(weth), address(collateralTokenAggregator));

        ERC20Mock(address(borrowToken)).mint(address(this), 5_000e18);

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

        vault = StackVault(factory.createVault(Constants.ETH_ADDRESS, address(collateralTokenOracle), 80, 1e1));

        factory.overrideBorrowInterestRate(0.02e18);

        borrowToken.approve(address(factory), 5_000e18);
        factory.setBorrowLimit(payable(address(vault)), 5_000e18);

        vm.label(address(borrowToken), "BorrowToken");
        vm.label(address(weth), "WrappedCollateralToken");
        vm.label(address(borrowTokenOracle), "BorrowTokenOracle");
        vm.label(address(collateralTokenOracle), "CollateralTokenOracle");
        vm.label(address(vault), "Vault");
    }

    function testInitialState() public {
        assertEq(address(vault.collateralToken()), address(weth));
        assertEq(vault.collateralTokenOracle(), address(collateralTokenOracle));
        assertEq(address(vault.borrowToken()), address(borrowToken));
        assertEq(vault.liquidationThreshold(), 80);
        assertEq(vault.borrowOpeningFee(), 0.005e18);
        assertEq(vault.liquidationPenaltyFee(), 0.1e18);

        uint256 interestRate = vault.interestRatePerSecond() * 365 days;
        uint256 trimmedInterestRate = interestRate / 1e13 * 1e13;
        assertEq(trimmedInterestRate, 0.01999e18);
    }

    function testDeposit() public {
        uint256 share = vault.depositCollateral{value: 1 ether}(address(this), 1 ether);
        assertEq(share, 1 ether);
        assertEq(vault.userCollateralShare(address(this)), 1 ether);
        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            vault.userPositionInfo(address(this));
        assertEq(collateralAmount, 1 ether);
        assertEq(collateralValue, 3000e18);
        assertEq(borrowAmount, 0);
        assertEq(borrowValue, 0);
    }

    function testWithdraw() public {
        vault.depositCollateral{value: 1 ether}(address(this), 1 ether);

        uint256 balanceBefore = address(this).balance;
        uint256 balanceAfter;

        vault.withdrawCollateral(address(this), 0.5 ether);
        balanceAfter = address(this).balance;
        assertEq(balanceAfter - balanceBefore, 0.5 ether);

        vault.withdrawCollateral(address(this));
        balanceAfter = address(this).balance;
        assertEq(balanceAfter - balanceBefore, 1 ether);

        assertEq(vault.userCollateralShare(address(this)), 0);

        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            vault.userPositionInfo(address(this));

        assertEq(collateralAmount, 0);
        assertEq(collateralValue, 0);
        assertEq(borrowAmount, 0);
        assertEq(borrowValue, 0);
    }

    function testBorrow() public {
        vault.depositCollateral{value: 1 ether}(address(this), 1 ether);

        uint256 balanceBefore = borrowToken.balanceOf(address(this));
        uint256 amount = 2_000e18;
        uint256 share = vault.borrow(address(this), amount);
        uint256 balanceAfter = borrowToken.balanceOf(address(this));
        uint256 amountWithFee = amount * vault.borrowOpeningFee() / 1e18 + amount;

        assertEq(share, amountWithFee);
        assertEq(balanceAfter - balanceBefore, amount);

        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            vault.userPositionInfo(address(this));

        assertEq(collateralAmount, 1 ether);
        assertEq(collateralValue, 3_000e18);
        assertEq(borrowAmount, amountWithFee);
        assertEq(borrowValue, amountWithFee);
    }

    function testRepay() public {
        vault.depositCollateral{value: 1 ether}(address(this), 1 ether);

        uint256 amount = 2_000e18;
        vault.borrow(address(this), amount);
        uint256 amountWithFee = amount * vault.borrowOpeningFee() / 1e18 + amount;

        borrowToken.approve(address(vault), 2_050e18);

        uint256 share = vault.repay(address(this), 1_000e18);

        assertEq(share, 1_000e18); // share == amount

        (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
            vault.userPositionInfo(address(this));

        assertEq(collateralAmount, 1 ether);
        assertEq(collateralValue, 3_000e18);
        assertEq(borrowAmount, amountWithFee - share);
        assertEq(borrowValue, amountWithFee - share);
    }
}
