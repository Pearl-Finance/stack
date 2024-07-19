// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {
    Test,
    Math,
    More,
    WETH9,
    IERC20,
    FeeMath,
    ERC4626,
    MockSwap,
    console2,
    IOracle,
    ERC20Mock,
    Constants,
    StackVault,
    ERC20Mock2,
    MoreMinter,
    CommonErrors,
    VaultFactory,
    ERC1967Proxy,
    VaultDeployer,
    YieldTokenMock,
    ERC20MockMinter,
    AggregatorV3Mock,
    StackVaultHandler,
    CappedPriceOracle,
    InterestAccrualMath,
    StackVaultTransfers,
    IERC3156FlashBorrower,
    InterestAccruingAmount,
    AggregatorV3WrapperMock,
    VaultImplementationDeployer
} from "./StackVaultHandler.sol";

/**
 * @title Stack Vault Invariant Test Cases
 * @author c-n-o-t-e
 * @dev Contract is used to test out Stack Vault Contract Invariants in a stateful way.
 *
 * Invariants Tested:
 *  - Total Borrowed Amount Is Correct.
 *  - Users Borrowed Amounts Are Correct.
 *  - Total Collateral Amount Is Correct.
 *  - Total Interest Accurred Is Correct.
 *  - Users Collateral Amounts Are Correct.
 *  - Total Penalty Fee Amount Collected Is Correct..
 */
contract StackVaultInvariantTest is Test {
    WETH9 weth;
    StackVault vault;
    More borrowToken;
    VaultFactory factory;
    ERC4626 collateralToken;
    IOracle borrowTokenOracle;
    StackVaultHandler public handler;
    ERC20MockMinter borrowTokenMinter;
    AggregatorV3Mock borrowTokenAggregator;
    InterestAccruingAmount totalBorrowAmount;
    AggregatorV3Mock collateralTokenAggregator;
    InterestAccruingAmount totalCollateralAmount;
    AggregatorV3WrapperMock collateralTokenOracle;

    function setUp() public {
        vm.warp(1 days);
        ERC20Mock underlying = new ERC20Mock(18);
        deal(address(underlying), address(this), 1_000_000e18);
        borrowTokenAggregator = new AggregatorV3Mock(6);
        collateralTokenAggregator = new AggregatorV3Mock(6);
        borrowTokenAggregator.setAnswer(1e6);
        collateralTokenAggregator.setAnswer(1e6);
        collateralToken = new YieldTokenMock(underlying);

        borrowToken = new More(address(9));
        bytes memory init = abi.encodeCall(borrowToken.initialize, (address(this)));

        ERC1967Proxy proxy = new ERC1967Proxy(address(borrowToken), init);
        borrowToken = More(address(proxy));

        borrowTokenOracle = new CappedPriceOracle(
            address(new AggregatorV3WrapperMock(address(borrowToken), address(borrowTokenAggregator))), 1e18
        );

        collateralTokenOracle =
            new AggregatorV3WrapperMock(address(collateralToken), address(collateralTokenAggregator));

        ERC20Mock(address(borrowToken)).mint(address(this), 1_000_000e18);
        weth = new WETH9();

        address factoryAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 7);
        MoreMinter moreMinter = new MoreMinter(address(borrowToken));

        init = abi.encodeCall(moreMinter.initialize, (address(this), factoryAddress));
        proxy = new ERC1967Proxy(address(moreMinter), init);

        moreMinter = MoreMinter(address(proxy));
        borrowToken.setMinter(address(moreMinter));

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

        MockSwap swap = new MockSwap(address(borrowToken), address(collateralToken));
        deal(address(collateralToken), address(swap), type(uint160).max);

        vault = StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));
        assert(factoryAddress == address(factory));

        factory.setMinimumBorrowAmount(payable(address(vault)), 50e18);
        factory.setTrustedSwapTarget(address(swap), true);
        factory.overrideBorrowInterestRate(0.02e18);

        borrowToken.approve(address(factory), type(uint120).max);
        deal(address(borrowToken), address(this), type(uint120).max);
        factory.setBorrowLimit(payable(address(vault)), type(uint120).max);

        collateralToken.approve(address(vault), 100e18);
        deal(address(collateralToken), address(this), 100e18);
        vault.depositCollateral(address(this), 100e18);

        handler = new StackVaultHandler(
            vault, collateralToken, collateralTokenOracle, swap, address(this), collateralTokenAggregator
        );

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = StackVaultHandler.depositCollateral.selector;
        selectors[1] = StackVaultHandler.withdrawCollateral.selector;
        selectors[2] = StackVaultHandler.borrow.selector;
        selectors[3] = StackVaultHandler.repay.selector;
        selectors[4] = StackVaultHandler.leverage.selector;
        selectors[5] = StackVaultHandler.deLeverage.selector;
        selectors[6] = StackVaultHandler.liquidate.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_usersCollateralAmountIsSame() external {
        (address[] memory actors, address[] memory leverageActors) = handler.actors();

        for (uint256 i; i < actors.length; ++i) {
            (uint256 collateralAmount,,,) = vault.userPositionInfo(actors[i]);
            assertEq(handler.usersCollateral(actors[i]), collateralAmount);
        }

        for (uint256 i; i < leverageActors.length; ++i) {
            (uint256 collateralAmount,,,) = vault.userPositionInfo(leverageActors[i]);
            assertEq(handler.usersCollateral(leverageActors[i]), collateralAmount);
        }
    }

    function invariant_usersBorrowedAmountsIsSame() external {
        (address[] memory actors, address[] memory leverageActors) = handler.actors();

        for (uint256 i; i < actors.length; ++i) {
            (,, uint256 borrowAmount,) = vault.userPositionInfo(actors[i]);
            assertEq(handler.getUserBorrowAmount(actors[i]), borrowAmount);
        }

        for (uint256 i; i < leverageActors.length; ++i) {
            (,, uint256 borrowAmount,) = vault.userPositionInfo(leverageActors[i]);
            assertEq(handler.getUserBorrowAmount(leverageActors[i]), borrowAmount);
        }
    }

    function invariant_totalBorrowAmountIsSame() external {
        (, uint256 total) = handler.totalBorrowAmount();
        assertEq(total, vault.totalBorrowAmount());
    }

    function invariant_totalCollateralAmountIsSame() external {
        (, uint256 total) = handler.totalCollateralAmount();
        assertEq(total, vault.totalCollateralAmount() - 100e18);
    }

    function invariant_totalInterestAccurredIsSame() external {
        assertEq(handler.totalAccruedAmount(), borrowToken.balanceOf(address(1)));
    }

    function invariant_totalPenaltyFeeAmountAccurredIsSame() external {
        assertEq(handler.totalPenaltyFeeAmount(), collateralToken.balanceOf(address(2)));
    }

    function invariant_callSummary() public view {
        handler.callSummary();
    }
}
