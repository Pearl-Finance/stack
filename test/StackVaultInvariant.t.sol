// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/Base.sol";
import "forge-std/StdCheats.sol";
import "forge-std/StdUtils.sol";

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
import "./mocks/YieldTokenMock.sol";
import "./mocks/WETH9.sol";

interface Handler {}

contract StackVaultUserHandler is CommonBase, StdCheats, StdUtils, Handler {
    StackVault private vault;
    IERC20 private borrowToken;
    IERC20 private collateralToken;

    address[] private users;

    constructor(StackVault _vault, IERC20 _borrowToken, IERC20 _collateralToken) {
        vault = _vault;
        borrowToken = _borrowToken;
        collateralToken = _collateralToken;
    }

    function setUsers(address[] memory _users) external {
        users = _users;
    }

    function deposit(uint256 userIndex, uint256 amount) external {
        uint256 index = bound(userIndex, 0, users.length - 1);
        amount = bound(amount, 0, collateralToken.balanceOf(address(this)));
        if (amount != 0) {
            collateralToken.approve(address(vault), amount);
            vault.depositCollateral(users[index], amount);
        }
    }

    function withdraw(uint256 userIndex, uint256 amount) external {
        uint256 index = bound(userIndex, 0, users.length - 1);
        (uint256 collateralAmount,, uint256 borrowedAmount,) = vault.userPositionInfo(address(this));
        if (borrowedAmount == 0) {
            amount = bound(amount, 0, collateralAmount);
        } else {
            uint256 minimumBalance = borrowedAmount * 100 / 85;
            if (minimumBalance < collateralAmount) {
                amount = bound(amount, 0, collateralAmount - minimumBalance);
            } else {
                amount = 0;
            }
        }
        if (amount != 0) {
            vault.withdrawCollateral(users[index], amount);
        }
    }

    function borrow(uint256 userIndex, uint256 amount) external {
        uint256 index = bound(userIndex, 0, users.length - 1);
        (uint256 collateralAmount,, uint256 borrowedAmount,) = vault.userPositionInfo(address(this));
        uint256 maxBorrowAmount = collateralAmount * 85 / 100;
        if (borrowedAmount >= maxBorrowAmount) {
            maxBorrowAmount = 0;
        } else {
            maxBorrowAmount -= borrowedAmount;
        }
        amount = bound(amount, 0, maxBorrowAmount);
        if (amount != 0) {
            vault.borrow(users[index], amount);
        }
    }

    function repay(uint256 userIndex, uint256 amount) external {
        uint256 index = bound(userIndex, 0, users.length - 1);
        amount = bound(amount, 0, borrowToken.balanceOf(address(this)));
        (,, uint256 borrowAmount,) = vault.userPositionInfo(users[index]);
        amount = bound(amount, 0, borrowAmount);
        if (amount != 0) {
            borrowToken.approve(address(vault), amount);
            vault.repay(users[index], amount);
        }
    }
}

contract ActorManager is CommonBase, StdCheats, StdUtils {
    StackVaultUserHandler[] public users;

    modifier warp() {
        vm.warp(block.timestamp + 1 hours);
        _;
    }

    constructor(StackVaultUserHandler[] memory _users) {
        users = _users;
    }

    function deposit(uint256 handlerIndex, uint256 userIndex, uint256 amount) external warp {
        uint256 index = bound(handlerIndex, 0, users.length - 1);
        users[index].deposit(userIndex, amount);
    }

    function withdraw(uint256 handlerIndex, uint256 userIndex, uint256 amount) external warp {
        uint256 index = bound(handlerIndex, 0, users.length - 1);
        users[index].withdraw(userIndex, amount);
    }

    function borrow(uint256 handlerIndex, uint256 userIndex, uint256 amount) external warp {
        uint256 index = bound(handlerIndex, 0, users.length - 1);
        users[index].borrow(userIndex, amount);
    }

    function repay(uint256 handlerIndex, uint256 userIndex, uint256 amount) external warp {
        uint256 index = bound(handlerIndex, 0, users.length - 1);
        users[index].repay(userIndex, amount);
    }
}

contract StackVaultInvariantTest is Test {
    VaultFactory factory;
    IERC20 borrowToken;
    ERC4626 collateralToken;
    ERC20MockMinter borrowTokenMinter;
    AggregatorV3Mock borrowTokenAggregator;
    AggregatorV3Mock collateralTokenAggregator;
    AggregatorV3WrapperMock borrowTokenOracle;
    AggregatorV3WrapperMock collateralTokenOracle;
    StackVault vault;
    WETH9 weth;

    StackVaultUserHandler[] userHandlers;
    ActorManager manager;

    address feeReceiver = makeAddr("feeReceiver");

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
        borrowTokenOracle = new AggregatorV3WrapperMock(address(borrowToken), address(borrowTokenAggregator));
        collateralTokenOracle =
            new AggregatorV3WrapperMock(address(collateralToken), address(collateralTokenAggregator));

        ERC20Mock(address(borrowToken)).mint(address(this), 100_000e18);

        underlying.approve(address(collateralToken), 100_000e18);
        collateralToken.deposit(100_000e18, address(this));

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
        factory.updateBorrowInterestRate(0.95e18);

        assert(factoryAddress == address(factory));

        vault = StackVault(factory.createVault(address(collateralToken), address(collateralTokenOracle), 90, 1e1));

        borrowToken.approve(address(factory), 50_000e18);
        factory.setBorrowLimit(payable(address(vault)), 50_000e18);
        factory.setFeeReceiver(feeReceiver);

        vm.label(address(borrowToken), "BorrowToken");
        vm.label(address(collateralToken), "CollateralToken");
        vm.label(address(borrowTokenOracle), "BorrowTokenOracle");
        vm.label(address(collateralTokenOracle), "CollateralTokenOracle");
        vm.label(address(vault), "Vault");

        address[] memory users = new address[](3);
        for (uint256 i = 0; i < users.length; i++) {
            userHandlers.push(new StackVaultUserHandler(vault, borrowToken, collateralToken));
            users[i] = address(userHandlers[i]);
            collateralToken.transfer(users[i], 10_000e18);
        }

        for (uint256 i = 0; i < users.length; i++) {
            userHandlers[i].setUsers(users);
        }

        manager = new ActorManager(userHandlers);

        targetContract(address(manager));
    }

    /// forge-config: default.invariant.runs = 1000
    /// forge-config: default.invariant.depth = 10
    function invariant() public view {
        for (uint256 i = 0; i < userHandlers.length; i++) {
            console.log("user #%d:", i + 1);
            (uint256 collateralAmount, uint256 collateralValue, uint256 borrowAmount, uint256 borrowValue) =
                vault.userPositionInfo(address(userHandlers[i]));
            console.log("- collateral token balance: %d", collateralToken.balanceOf(address(userHandlers[i])));
            console.log("- borrow token balance:     %d", borrowToken.balanceOf(address(userHandlers[i])));
            console.log("- collateral token deposit: %d", collateralAmount);
            console.log("- collateral deposit value: %d", collateralValue);
            console.log("- borrowed:                 %d", borrowAmount);
            console.log("- borrowed value:           %d", borrowValue);
        }
        console.log("fee receiver balance: %d", borrowToken.balanceOf(feeReceiver));
    }
}
