// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/interfaces/IERC3156.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@layerzerolabs/contracts/lzApp/mocks/LZEndpointMock.sol";

import "src/factories/VaultFactory.sol";
import "src/factories/VaultImplementationDeployer.sol";
import "src/vaults/StackVault.sol";

import "./mocks/ERC20Mock.sol";
import "./mocks/ERC20MockMinter.sol";
import "./mocks/AggregatorV3Mock.sol";
import "./mocks/AggregatorV3WrapperMock.sol";
import "./mocks/WETH9.sol";

contract VaultFactoryTest is Test {
    VaultFactory factory;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
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
        VaultDeployer vaultDeployer = new VaultDeployer(address(weth), factoryAddress, address(implementationDeployer));
        bytes memory init = abi.encodeCall(vaultDeployer.initialize, ());
        ERC1967Proxy proxy = new ERC1967Proxy(address(vaultDeployer), init);

        VaultFactory impl = new VaultFactory(address(weth), address(borrowTokenMinter));
        init = abi.encodeCall(impl.initialize, (address(vaultDeployer), address(borrowTokenOracle), address(1)));
        proxy = new ERC1967Proxy(address(impl), init);
        factory = VaultFactory(address(proxy));

        assert(factoryAddress == address(factory));

        vm.label(address(borrowToken), "BorrowToken");
        vm.label(address(collateralToken), "CollateralToken");
        vm.label(address(borrowTokenOracle), "BorrowTokenOracle");
        vm.label(address(collateralTokenOracle), "CollateralTokenOracle");
        vm.warp(1 days);
    }

    function testInitialState() public {
        assertEq(factory.borrowToken(), address(borrowToken));
        assertEq(factory.borrowTokenOracle(), address(borrowTokenOracle));
        assertEq(factory.borrowInterestRate(), 0);
    }

    function testCreateVault() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));
        assertEq(address(vault.collateralToken()), address(collateralToken));
        assertEq(vault.collateralTokenOracle(), address(collateralTokenOracle));
        assertEq(address(vault.borrowToken()), address(borrowToken));
        assertEq(vault.liquidationThreshold(), 90);
    }

    function testUpdateBorrowInterestRate() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));
        uint256 referencePrice = 0.9e18;
        vm.expectCall(address(vault), abi.encodeWithSelector(StackVault.accrueInterest.selector));
        factory.updateBorrowInterestRate(referencePrice);
        assertGt(vault.interestRatePerSecond(), 0);
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
    }

    function testVaultForToken() public {
        StackVault vault =
            StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));
        assertEq(factory.vaultForToken(address(collateralToken)), address(vault));
        assertEq(factory.vaultForToken(address(borrowToken)), address(0));
    }
}
