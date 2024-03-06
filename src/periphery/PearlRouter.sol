// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {CommonErrors} from "../interfaces/CommonErrors.sol";

import {IQuoter} from "./interfaces/IQuoter.sol";
import {IRouter} from "./interfaces/IRouter.sol";

/**
 * @title Pearl Router Contract
 * @notice Contract facilitating interactions with Uniswap V3 pools, specifically for token swapping and price quoting
 *         on the Pearl platform.
 * @dev Implements functionalities to perform token swaps, and query input or output amounts for given trade parameters.
 *      It uses Uniswap V3's router and quoter interfaces for these operations. The contract's state, including
 *      addresses for the swap router and quoter, is managed using ERC-7201 namespaced storage pattern for
 *      collision-resistant storage.
 *      Inherits from OwnableUpgradeable and UUPSUpgradeable for ownership management and upgrade functionality.
 * @author SeaZarrgh LaBuoy
 */
contract PearlRouter is OwnableUpgradeable, UUPSUpgradeable, CommonErrors {
    using Address for address;
    using SafeERC20 for IERC20;

    event SwapRouterUpdated(address indexed oldSwapRouter, address indexed newSwapRouter);
    event QuoterUpdated(address indexed oldQuoter, address indexed newQuoter);

    /// @custom:storage-location erc7201:pearl.storage.PearlRouter
    struct PearlRouterStorage {
        address swapRouter;
        address quoter;
    }

    // keccak256(abi.encode(uint256(keccak256("pearl.storage.PearlRouter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PearlRouterStorageLocation =
        0xa8dfd4e0c95dbd38786246a52143f048ed2b0cdc00819129d811269a87ec2700;

    function _getPearlRouterStorage() private pure returns (PearlRouterStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := PearlRouterStorageLocation
        }
    }

    /**
     * @notice Initializes the PearlRouter contract.
     * @dev Disables initializers to ensure the contract is only initialized once and to prevent reinitialization after
     *      an upgrade.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Authorizes an upgrade to a new contract implementation.
     * @dev Internal function to authorize upgrading the contract to a new implementation.
     *      Overrides the UUPSUpgradeable `_authorizeUpgrade` function.
     *      Restricted to the contract owner.
     * @param newImplementation The address of the new contract implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Initializes the PearlRouter with the swap router and quoter addresses.
     * @dev Sets up the contract with initial configuration values for swap router and quoter.
     *      Can only be called once due to the `initializer` modifier.
     * @param swapRouter The address of the Uniswap V3 swap router.
     * @param quoter The address of the Uniswap V3 quoter.
     */
    function initialize(address swapRouter, address quoter) external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        if (swapRouter == address(0) || quoter == address(0)) {
            revert InvalidZeroAddress();
        }
        PearlRouterStorage storage $ = _getPearlRouterStorage();
        $.swapRouter = swapRouter;
        $.quoter = quoter;
    }

    /**
     * @notice Retrieves the address of the swap router.
     * @dev Returns the address of the Uniswap V3 swap router from the PearlRouterStorage.
     * @return The address of the swap router.
     */
    function getSwapRouter() external view returns (address) {
        return _getPearlRouterStorage().swapRouter;
    }

    /**
     * @notice Retrieves the address of the quoter.
     * @dev Returns the address of the Uniswap V3 quoter from the PearlRouterStorage.
     * @return The address of the quoter.
     */
    function getQuoter() external view returns (address) {
        return _getPearlRouterStorage().quoter;
    }

    /**
     * @notice Sets a new address for the swap router.
     * @dev Updates the address of the swap router in the PearlRouterStorage.
     *      Access restricted to the contract owner.
     * @param swapRouter The new address for the swap router.
     */
    function setSwapRouter(address swapRouter) external onlyOwner {
        PearlRouterStorage storage $ = _getPearlRouterStorage();
        if (swapRouter == address(0)) {
            revert InvalidZeroAddress();
        }
        address currentSwapRouter = $.swapRouter;
        if (swapRouter == currentSwapRouter) {
            revert ValueUnchanged();
        }
        $.swapRouter = swapRouter;
        emit SwapRouterUpdated(currentSwapRouter, swapRouter);
    }

    /**
     * @notice Sets a new address for the quoter.
     * @dev Updates the address of the quoter in the PearlRouterStorage.
     *      Access restricted to the contract owner.
     * @param quoter The new address for the quoter.
     */
    function setQuoter(address quoter) external onlyOwner {
        PearlRouterStorage storage $ = _getPearlRouterStorage();
        if (quoter == address(0)) {
            revert InvalidZeroAddress();
        }
        address currentQuoter = $.quoter;
        if (quoter == currentQuoter) {
            revert ValueUnchanged();
        }
        $.quoter = quoter;
        emit QuoterUpdated(currentQuoter, quoter);
    }

    /**
     * @notice Executes a token swap through the Uniswap V3 router, optionally accounting for tokens with transfer fees.
     * @dev Swaps a specified amount of one token for another. Requires the `tokenIn` to be approved for transfer.
     *      The function includes a `feeOnTransfer` parameter to accommodate tokens that deduct fees on transfer,
     *      affecting the swap's input amount. When `feeOnTransfer` is true, the function accounts for the input token's
     *      transfer fee, potentially altering the effective swap amount.
     *      The operation is executed via the Uniswap V3 router using the stored router address.
     *
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of the input token to swap.
     * @param minAmountOut The minimum amount of the output token to receive, accounting for slippage.
     * @param fee The pool fee tier for the swap.
     * @param feeOnTransfer A boolean indicating if the `tokenIn` includes a transfer fee.
     * @return The amount of the output token received, which may vary based on `feeOnTransfer` calculations.
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24 fee,
        bool feeOnTransfer
    ) external returns (uint256) {
        IRouter.ExactInputSingleParams memory params = IRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });

        bytes4 selector = feeOnTransfer ? IRouter.exactInputFeeOnTransfer.selector : IRouter.exactInput.selector;
        return _processTokenSwap(IERC20(tokenIn), amountIn, abi.encodeWithSelector(selector, (params)));
    }

    /**
     * @notice Executes a token swap through the Uniswap V3 router with multiple hops, optionally accounting for tokens
     *         with transfer fees.
     *
     * @dev Swaps a specified amount of one token for another via a defined path of tokens, possibly involving multiple
     *      hops. Requires the `tokenIn` to be approved for transfer.
     *      The function includes a `feeOnTransfer` parameter to support tokens that implement transfer fees, which can
     *      affect the amount of tokens actually transferred during the swap. When `feeOnTransfer` is set to true, it
     *      indicates that the input token deducts a fee on transfer, and the function adjusts the swap process
     *      accordingly.
     *      The operation is executed via the Uniswap V3 router using the stored router address.
     *
     * @param path An encoded path of tokens to swap through, starting with the input token and ending with the output
     *             token.
     * @param amountIn The amount of the input token to swap.
     * @param minAmountOut The minimum amount of the output token to receive, considering potential slippage.
     * @param feeOnTransfer A boolean indicating if the `tokenIn` or any token in the path includes a transfer fee.
     * @return The amount of the output token received, adjusted for any transfer fees if `feeOnTransfer` is true.
     */
    function swap(bytes memory path, uint256 amountIn, uint256 minAmountOut, bool feeOnTransfer)
        external
        returns (uint256)
    {
        address tokenIn = _firstAddressInPath(path);
        IRouter.ExactInputParams memory params = IRouter.ExactInputParams({
            path: path,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut
        });

        bytes4 selector = feeOnTransfer ? IRouter.exactInputFeeOnTransfer.selector : IRouter.exactInput.selector;
        return _processTokenSwap(IERC20(tokenIn), amountIn, abi.encodeWithSelector(selector, (params)));
    }

    /**
     * @notice Retrieves the required input amount for a given output amount in a swap.
     * @dev Uses the Uniswap V3 quoter to estimate the input amount required for a swap.
     *      The operation is executed via the Uniswap V3 quoter using the stored quoter address.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountOut The amount of the output token.
     * @param fee The pool fee for the swap.
     * @return amountIn The estimated amount of the input token required.
     */
    function getAmountIn(address tokenIn, address tokenOut, uint256 amountOut, uint24 fee)
        external
        returns (uint256 amountIn)
    {
        PearlRouterStorage storage $ = _getPearlRouterStorage();
        (amountIn,,,) = IQuoter($.quoter).quoteExactOutputSingle(
            IQuoter.QuoteExactOutputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountOut: amountOut,
                fee: fee,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /**
     * @notice Retrieves the required input amount for a given output amount in a swap.
     * @dev Uses the Uniswap V3 quoter to estimate the input amount required for a swap via multi-hop.
     *      The operation is executed via the Uniswap V3 quoter using the stored quoter address.
     * @param path The path of tokens to swap through.
     * @param amountOut The amount of the output token.
     * @return amountIn The estimated amount of the input token required.
     */
    function getAmountIn(bytes memory path, uint256 amountOut) external returns (uint256 amountIn) {
        PearlRouterStorage storage $ = _getPearlRouterStorage();
        (amountIn,,,) = IQuoter($.quoter).quoteExactOutput(path, amountOut);
    }

    /**
     * @notice Retrieves the output amount for a given input amount in a swap.
     * @dev Uses the Uniswap V3 quoter to estimate the output amount required for a swap.
     *      The operation is executed via the Uniswap V3 quoter using the stored quoter address.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of the input token.
     * @param fee The pool fee for the swap.
     * @return amountOut The estimated amount of the output token.
     */
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn, uint24 fee)
        external
        returns (uint256 amountOut)
    {
        PearlRouterStorage storage $ = _getPearlRouterStorage();
        (amountOut,,,) = IQuoter($.quoter).quoteExactInputSingle(
            IQuoter.QuoteExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                fee: fee,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /**
     * @notice Retrieves the output amount for a given input amount in a swap.
     * @dev Uses the Uniswap V3 quoter to estimate the output amount required for a swap via multi-hop.
     *      The operation is executed via the Uniswap V3 quoter using the stored quoter address.
     * @param path The path of tokens to swap through.
     * @param amountIn The amount of the input token.
     * @return amountOut The estimated amount of the output token.
     */
    function getAmountOut(bytes memory path, uint256 amountIn) external returns (uint256 amountOut) {
        PearlRouterStorage storage $ = _getPearlRouterStorage();
        (amountOut,,,) = IQuoter($.quoter).quoteExactInput(path, amountIn);
    }

    /**
     * @notice Retrieves the address of the first token in a given path.
     * @param path The path of tokens to swap through.
     * @return firstAddress The address of the first token in the path.
     */
    function _firstAddressInPath(bytes memory path) internal pure returns (address firstAddress) {
        require(path.length >= 20, "OB");
        assembly {
            firstAddress := shr(96, mload(add(path, 0x20)))
        }
    }

    /**
     * @notice Pulls the specified `amount` of `token` to this contract, approves the swap router to spend it, and
     * executes a swap.
     *
     * @dev This internal function handles the transfer of tokens into the contract, sets the allowance for the swap
     * router, and performs the token swap by calling the router with the provided `swapData`. It ensures the allowance
     * is reset after the swap. This function abstracts the token transfer, approval, and swap execution steps to
     * simplify swap operations.
     *
     * @param token The ERC20 token to be swapped.
     * @param amount The amount of the token to be swapped.
     * @param swapData The encoded data for the swap function call, including the swap parameters.
     * @return result The amount of output tokens received from the swap.
     */
    function _processTokenSwap(IERC20 token, uint256 amount, bytes memory swapData) internal returns (uint256 result) {
        PearlRouterStorage storage $ = _getPearlRouterStorage();
        address router = $.swapRouter;
        token.safeTransferFrom(msg.sender, address(this), amount);
        token.forceApprove(router, amount);
        result = abi.decode(router.functionCall(swapData), (uint256));
        token.forceApprove(router, 0);
    }
}
