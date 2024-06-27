// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {AddressSet, LibAddressSet} from "./LibAddressSet.sol";

import "../StackVault.t.sol";

/**
 * @title Stack Vault Handler Contract
 * @author c-n-o-t-e
 * @dev Contract is used to expose Stack Vault functions for testing in a stateful way.
 *
 * Functionalities Exposed:
 *  - Repay()
 *  - Borrow()
 *  - Leveraged()
 *  - Liquidate()
 *  - Deleveraged()
 *  - AccrueInterest()
 *  - DepositCollateral()
 *  - WithdrawCollateral()
 */
contract StackVaultHandler is CommonBase, StdCheats, StdUtils {
    using Math for uint256;
    using LibAddressSet for AddressSet;
    using InterestAccrualMath for InterestAccruingAmount;

    MockSwap swap;
    StackVault vault;
    ERC4626 collateralToken;
    AddressSet internal _actors;
    AddressSet internal _leverageActors;
    AggregatorV3Mock collateralTokenAggregator;
    AggregatorV3WrapperMock collateralTokenOracle;
    InterestAccruingAmount public totalBorrowAmount;
    InterestAccruingAmount public totalCollateralAmount;

    address currentActor;
    address testContract;

    uint256 public totalAccruedAmount;
    uint256 public totalPenaltyFeeAmount;
    uint256 public minimumBorrowAmount = 50e18;

    mapping(bytes32 => uint256) public calls;
    mapping(address => bool) public blackList;
    mapping(address => uint256) public usersDebt;
    mapping(address => uint256) public usersDebtShare;
    mapping(address => uint256) public usersCollateral;

    constructor(
        StackVault _vault,
        ERC4626 _collateralToken,
        AggregatorV3WrapperMock _collateralTokenOracle,
        MockSwap _swap,
        address _testContract,
        AggregatorV3Mock _collateralTokenAggregator
    ) {
        swap = _swap;
        vault = _vault;
        testContract = _testContract;
        collateralToken = _collateralToken;
        collateralTokenOracle = _collateralTokenOracle;
        collateralTokenAggregator = _collateralTokenAggregator;

        blackList[address(1)] = true;
        blackList[address(2)] = true;
        blackList[address(swap)] = true;
        blackList[address(vault)] = true;
        blackList[_testContract] = true;
    }

    modifier createActor() {
        if (!blackList[msg.sender] && !_leverageActors.leverageSaved[msg.sender]) {
            currentActor = msg.sender;
            _actors.add(currentActor);
        } else {
            return;
        }
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actors.rand(actorIndexSeed);
        _;
    }

    modifier createLeverageActor() {
        if (!blackList[msg.sender] && !_actors.saved[msg.sender]) {
            currentActor = msg.sender;
            _leverageActors.addForLeverage(currentActor);
        } else {
            return;
        }
        _;
    }

    modifier useLeverageActor(uint256 actorIndexSeed) {
        currentActor = _leverageActors.randForLeverage(actorIndexSeed);
        _;
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    function depositCollateral(uint256 amount) external createActor countCall("Deposit") {
        if (currentActor != address(0)) {
            if (totalBorrowAmount.base > 0) {
                accrueInterest();
            }

            vm.startPrank(currentActor);
            amount = bound(amount, 500e18, 1000e18);
            deal(address(collateralToken), currentActor, amount);

            (InterestAccruingAmount memory totalCollateralAmount_, uint256 share_) =
                totalCollateralAmount.add(amount, Math.Rounding.Floor);
            uint256 cAmount = totalCollateralAmount.toTotalAmount(share_, Math.Rounding.Floor);

            collateralToken.approve(address(vault), amount);
            vault.depositCollateral(currentActor, amount);
            totalCollateralAmount = totalCollateralAmount_;

            (uint256 collateralAmount,,,) = vault.userPositionInfo(currentActor);
            usersCollateral[currentActor] = cAmount + usersCollateral[currentActor];
            vm.stopPrank();

            vm.roll(block.number + 10);
            vm.warp(block.timestamp + 10);
        }
    }

    function withdrawCollateral(uint256 amount, uint256 actorSeed) external useActor(actorSeed) countCall("Withdraw") {
        if (currentActor != address(0)) {
            vm.startPrank(currentActor);
            amount = bound(
                amount,
                0,
                usersCollateral[currentActor]
                    - (getUserBorrowAmount(currentActor) + (usersCollateral[currentActor] * 10) / 100)
            );

            if (amount != 0) {
                if (totalBorrowAmount.base > 0) {
                    accrueInterest();
                }

                (InterestAccruingAmount memory totalCollateralAmount_, uint256 share_) =
                    totalCollateralAmount.sub(amount, Math.Rounding.Ceil);

                uint256 cAmount = totalCollateralAmount.toTotalAmount(share_, Math.Rounding.Floor);
                vault.withdrawCollateral(currentActor, amount);
                totalCollateralAmount = totalCollateralAmount_;
                usersCollateral[currentActor] = usersCollateral[currentActor] - cAmount;

                vm.roll(block.number + 10);
                vm.warp(block.timestamp + 10);
            }
            vm.stopPrank();
        }
    }

    function borrow(uint256 amountToBorrow, uint256 actorSeed, uint256 threshold)
        external
        useActor(actorSeed)
        countCall("Borrow")
    {
        if (currentActor != address(0)) {
            if (usersDebtShare[currentActor] == 0) {
                vm.startPrank(currentActor);
                uint256 liquidityFreeRange = (usersCollateral[currentActor] * 80) / 100;
                uint256 liquidityFreee = (liquidityFreeRange * 80) / 100;

                if (liquidityFreee >= minimumBorrowAmount) {
                    amountToBorrow = bound(amountToBorrow, liquidityFreee, liquidityFreeRange);
                    uint256 fee = (amountToBorrow * vault.borrowOpeningFee()) / 1e18;
                    uint256 amountWithfee = fee + amountToBorrow;

                    if (totalBorrowAmount.total + amountWithfee < type(uint120).max) {
                        if (totalBorrowAmount.base > 0) {
                            accrueInterest();
                        }

                        totalAccruedAmount = totalAccruedAmount + fee;

                        deal(
                            address(vault.borrowToken()), currentActor, amountToBorrow * vault.borrowOpeningFee() / 1e18
                        );
                        (InterestAccruingAmount memory totalBorrowAmount_, uint256 share_) =
                            totalBorrowAmount.add(amountWithfee, Math.Rounding.Ceil);

                        vault.borrow(currentActor, amountToBorrow);
                        totalBorrowAmount = totalBorrowAmount_;

                        (,, uint256 borrowAmount,) = vault.userPositionInfo(currentActor);
                        usersDebtShare[currentActor] = usersDebtShare[currentActor] + share_;

                        vm.roll(block.number + 10);
                        vm.warp(block.timestamp + 10);
                    }
                }
                vm.stopPrank();
            }
        }
    }

    function getUserBorrowAmount(address addr) public returns (uint256 borrowAmount) {
        borrowAmount = totalBorrowAmount.toTotalAmount(usersDebtShare[addr], Math.Rounding.Ceil);
    }

    function repay(uint256 actorSeed) external useActor(actorSeed) countCall("Repay") {
        if (currentActor != address(0)) {
            if (usersDebtShare[currentActor] > 0) {
                vm.startPrank(currentActor);
                accrueInterest();

                (InterestAccruingAmount memory totalBorrowAmount_, uint256 borrowAmount) =
                    totalBorrowAmount.subBase(usersDebtShare[currentActor], Math.Rounding.Floor);

                deal(address(vault.borrowToken()), currentActor, borrowAmount);
                IERC20(address(vault.borrowToken())).approve(address(vault), borrowAmount);

                vault.repay(currentActor);
                vm.stopPrank();

                totalBorrowAmount = totalBorrowAmount_;
                usersDebtShare[currentActor] = 0;

                vm.roll(block.number + 10);
                vm.warp(block.timestamp + 10);
            }
        }
    }

    function leverage(uint256 amountToBorrow) external createLeverageActor countCall("Leverage") {
        if (currentActor != address(0)) {
            amountToBorrow = bound(amountToBorrow, 500e18, 1000e18);
            uint256 collateralAmount = (amountToBorrow * 20) / 100;

            deal(address(collateralToken), currentActor, collateralAmount);
            uint256 fee = (amountToBorrow * vault.borrowOpeningFee()) / 1e18;
            uint256 amountWithfee = fee + amountToBorrow;

            bytes memory data = abi.encodeWithSelector(
                bytes4(keccak256(bytes("swap(address,address,uint256)"))),
                address(vault.borrowToken()),
                address(collateralToken),
                amountToBorrow
            );

            if (amountToBorrow > IERC20(address(collateralToken)).balanceOf(address(swap))) {
                deal(address(collateralToken), address(swap), amountToBorrow);
            }

            if (totalBorrowAmount.total + amountWithfee < type(uint120).max) {
                if (totalBorrowAmount.base > 0) {
                    accrueInterest();
                }

                totalAccruedAmount = totalAccruedAmount + fee;

                (InterestAccruingAmount memory totalCollateralAmount_, uint256 share_) =
                    totalCollateralAmount.add(collateralAmount + amountToBorrow, Math.Rounding.Floor);

                uint256 cAmount = totalCollateralAmount.toTotalAmount(share_, Math.Rounding.Floor);

                (InterestAccruingAmount memory totalBorrowAmount_, uint256 bShare_) =
                    totalBorrowAmount.add(amountWithfee, Math.Rounding.Ceil);

                vm.startPrank(currentActor);
                collateralToken.approve(address(vault), collateralAmount);
                vault.leverage(collateralAmount, amountToBorrow, address(swap), data);
                vm.stopPrank();

                totalBorrowAmount = totalBorrowAmount_;
                totalCollateralAmount = totalCollateralAmount_;

                usersDebtShare[currentActor] = usersDebtShare[currentActor] + bShare_;
                usersCollateral[currentActor] = cAmount + usersCollateral[currentActor];

                vm.roll(block.number + 10);
                vm.warp(block.timestamp + 10);
            }
        }
    }

    function deLeverage(uint256 actorSeed) external useLeverageActor(actorSeed) countCall("Deleverage") {
        if (currentActor != address(0)) {
            uint256 cAmount = usersCollateral[currentActor];

            if (usersDebtShare[currentActor] > 0) {
                if (totalBorrowAmount.base > 0) {
                    accrueInterest();
                }

                uint256 borrowAmount = getUserBorrowAmount(currentActor);

                bytes memory data = abi.encodeWithSelector(
                    bytes4(keccak256(bytes("swap(address,address,uint256)"))),
                    address(collateralToken),
                    address(vault.borrowToken()),
                    borrowAmount
                );

                if (borrowAmount > IERC20(address(vault.borrowToken())).balanceOf(address(swap))) {
                    deal(address(vault.borrowToken()), address(swap), borrowAmount);
                }

                vm.startPrank(currentActor);
                vault.deleverage(borrowAmount, address(swap), data);
                vm.stopPrank();

                (InterestAccruingAmount memory totalCollateralAmount_,) =
                    totalCollateralAmount.sub(borrowAmount, Math.Rounding.Ceil);

                (InterestAccruingAmount memory totalBorrowAmount_,) =
                    totalBorrowAmount.sub(borrowAmount, Math.Rounding.Floor);

                usersDebtShare[currentActor] = 0;
                usersCollateral[currentActor] = cAmount - borrowAmount;

                totalBorrowAmount = totalBorrowAmount_;
                totalCollateralAmount = totalCollateralAmount_;

                vm.roll(block.number + 10);
                vm.warp(block.timestamp + 10);
            }
        }
    }

    function liquidate(uint256 actorSeed) external useActor(actorSeed) countCall("Liquidate") {
        if (currentActor != address(0) && getUserBorrowAmount(currentActor) > 0) {
            if (totalBorrowAmount.base > 0) {
                accrueInterest();
            }

            uint256 borrowAmount = getUserBorrowAmount(currentActor);
            uint256 borrowValue =
                IOracle(vault.borrowTokenOracle()).valueOf(borrowAmount, 24 hours, Math.Rounding.Floor);

            (uint256 collateralAmount, uint256 collateralValue,,) = vault.userPositionInfo(currentActor);

            uint256 g = (borrowValue * 100) / 94;
            uint256 p = (g * 1e6) / collateralAmount;

            collateralTokenAggregator.setAnswer(int256(p));
            deal(address(vault.borrowToken()), testContract, borrowAmount);
            uint256 collateralAmt = collateralTokenOracle.amountOf(borrowValue, Math.Rounding.Floor);

            uint256 fee = FeeMath.calculateFeeAmount(borrowAmount, 50000000000000000);
            uint256 feeValue = IOracle(vault.borrowTokenOracle()).valueOf(fee, Math.Rounding.Floor);

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

            uint256 liquidationBonus = penaltyFeeAmount / 2;
            uint256 collectedFee = penaltyFeeAmount - liquidationBonus;
            totalPenaltyFeeAmount = totalPenaltyFeeAmount + collectedFee;

            vm.startPrank(testContract);
            vault.borrowToken().approve(address(vault), borrowAmount);
            vault.liquidate(currentActor, borrowAmount, testContract);
            vm.stopPrank();

            collateralTokenAggregator.setAnswer(1e6);

            usersDebtShare[currentActor] = 0;
            usersCollateral[currentActor] = usersCollateral[currentActor] - totalCollateralRemoved;

            (InterestAccruingAmount memory totalCollateralAmount_,) =
                totalCollateralAmount.sub(totalCollateralRemoved, Math.Rounding.Ceil);

            (InterestAccruingAmount memory totalBorrowAmount_,) =
                totalBorrowAmount.sub(borrowAmount, Math.Rounding.Floor);

            totalBorrowAmount = totalBorrowAmount_;
            totalCollateralAmount = totalCollateralAmount_;

            vm.roll(block.number + 10);
            vm.warp(block.timestamp + 10);
        }
    }

    function accrueInterest() internal {
        uint256 interestPerElapsedTime = vault.interestRatePerSecond() * 10;
        uint256 accruedAmount = totalBorrowAmount.total.mulDiv(interestPerElapsedTime, 1e18);
        totalBorrowAmount.total = totalBorrowAmount.total + accruedAmount;
        totalAccruedAmount = totalAccruedAmount + accruedAmount;
    }

    function callSummary() external view {
        console2.log("-------------------");
        console2.log("  ");
        console2.log("Call summary:");
        console2.log("  ");

        console2.log("-------------------");
        console2.log("Call Count:");
        console2.log("-------------------");
        console2.log("Repay(s):", calls["Repay"]);
        console2.log("Borrow(s)", calls["Borrow"]);
        console2.log("Deposit(s)", calls["Deposit"]);
        console2.log("Withdraw(s)", calls["Withdraw"]);
        console2.log("Leverage(s):", calls["Leverage"]);
        console2.log("Liquidate(s):", calls["Liquidate"]);
        console2.log("Deleverage(s):", calls["Deleverage"]);
    }

    function actors() external view returns (address[] memory, address[] memory) {
        return (_actors.addrs, _leverageActors.leverageAddrs);
    }
}
