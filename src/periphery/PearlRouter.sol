// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {CommonErrors} from "../interfaces/CommonErrors.sol";

import {IQuoter} from "./interfaces/IQuoter.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {ITokenConverter} from "./interfaces/ITokenConverter.sol";

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
contract PearlRouter is MulticallUpgradeable, OwnableUpgradeable, UUPSUpgradeable, CommonErrors {
    using Address for address;
    using SafeERC20 for IERC20;

    error InsufficientOutputAmount();
    error InvalidPath();

    event QuoterUpdated(address indexed oldQuoter, address indexed newQuoter);
    event SwapRouterUpdated(address indexed oldSwapRouter, address indexed newSwapRouter);
    event TokenConverterUpdated(address indexed token, address indexed converter);

    /// @custom:storage-location erc7201:pearl.storage.PearlRouter
    struct PearlRouterStorage {
        address swapRouter;
        address quoter;
        mapping(address token => address) tokenConverter;
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
     * @notice Retrieves the address of the converter contract associated with a token.
     * @dev Returns the address of the converter contract associated with the specified token from the
     *      PearlRouterStorage.
     * @param token The address of the token to retrieve the converter for.
     */
    function getTokenConverter(address token) external view returns (address) {
        return _getPearlRouterStorage().tokenConverter[token];
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
     * @notice Associates a token with a converter contract.
     * @dev Stores a mapping between a token and its corresponding converter contract. The converter is used to
     *      facilitate token conversions that are not natively supported by the swap functionality. This enables
     *      the router to support a wider range of tokens by converting them to an intermediate token that is
     *      supported before proceeding with the swap. Only callable by the contract owner.
     * @param token The address of the token to associate with a converter.
     * @param converter The address of the converter contract.
     */
    function setTokenConverter(address token, address converter) external onlyOwner {
        PearlRouterStorage storage $ = _getPearlRouterStorage();
        $.tokenConverter[token] = converter;
        emit TokenConverterUpdated(token, converter);
    }

    /**
     * @notice Executes a token swap through the Uniswap V3 router, with optional support for fee-on-transfer tokens.
     * @dev Performs a token swap from `tokenIn` to `tokenOut` through the configured Uniswap V3 router. This
     *      function can accommodate tokens that have a transfer fee. If `feeOnTransfer` is true, it adjusts the
     *      swap logic to account for the fee taken during transfer, ensuring the correct amount of tokens is swapped.
     *      Requires the sender to have approved this contract to spend at least `amountIn` of `tokenIn`.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of `tokenIn` to swap.
     * @param minAmountOut The minimum amount of `tokenOut` to receive, to mitigate slippage.
     * @param fee The fee tier of the Uniswap V3 pool to be used for the swap.
     * @param feeOnTransfer Specifies whether `tokenIn` implements a transfer fee.
     * @return The amount of `tokenOut` received from the swap.
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24 fee,
        bool feeOnTransfer
    ) external returns (uint256) {
        amountIn = _pullToken(IERC20(tokenIn), msg.sender, amountIn, feeOnTransfer);
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

        bytes4 selector =
            feeOnTransfer ? IRouter.exactInputSingleFeeOnTransfer.selector : IRouter.exactInputSingle.selector;
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
        amountIn = _pullToken(IERC20(tokenIn), msg.sender, amountIn, feeOnTransfer);
        return _swap(path, amountIn, minAmountOut, feeOnTransfer, msg.sender);
    }

    /**
     * @notice Executes a token swap from `tokenIn` to `tokenOut` through a specified path, with support for initial and
     *         final token conversions.
     *
     * @dev This function enables swapping tokens that are not directly supported in the specified swap path by
     *      converting `tokenIn` to the first token in the `path` and/or the last token in the `path` to `tokenOut`, if
     *      necessary. It supports fee-on-transfer tokens by accounting for potential fees during the initial token pull
     *      and the final token conversion.
     *      The swap is executed through a specified path of intermediate tokens, potentially involving multiple Uniswap
     *      V3 pools. This function is designed to handle complex swap scenarios where direct paths are not available or
     *      optimal, allowing for greater flexibility in token swapping strategies.
     *      The caller must approve this contract to spend `tokenIn`, and the contract must have sufficient allowance to
     *      spend intermediate tokens on the caller's behalf.
     *
     * @param tokenIn The address of the input token to be swapped.
     * @param tokenOut The address of the output token to be received.
     * @param path The encoded path of intermediate tokens to swap through, not necessarily starting with `tokenIn` or
     *             ending with `tokenOut`.
     * @param amountIn The amount of `tokenIn` to be swapped.
     * @param minAmountOut The minimum amount of `tokenOut` to be received from the swap, accounting for slippage. This
     *                     parameter is enforced at the end of the swap execution.
     * @param feeOnTransfer Indicates whether `tokenIn` or any tokens involved in the swap are fee-on-transfer tokens.
     *                      This affects how the `amountIn` is calculated and potentially reduces the amount received
     *                      due to transfer fees.
     * @return amountOut The actual amount of `tokenOut` received from the swap, which may be less than `minAmountOut`
     *                   if market conditions change unfavorably.
     */
    function swap(
        address tokenIn,
        address tokenOut,
        bytes memory path,
        uint256 amountIn,
        uint256 minAmountOut,
        bool feeOnTransfer
    ) external returns (uint256 amountOut) {
        PearlRouterStorage storage $ = _getPearlRouterStorage();
        address pathTokenIn = _firstAddressInPath(path);

        amountIn = _pullToken(IERC20(tokenIn), msg.sender, amountIn, feeOnTransfer);

        if (tokenIn != pathTokenIn) {
            amountIn = _convertToken($, tokenIn, pathTokenIn, amountIn, address(this));
        }

        address pathTokenOut = _lastAddressInPath(path);

        if (tokenOut != pathTokenOut) {
            amountOut = _swap(path, amountIn, 0, feeOnTransfer, address(this));
            amountOut = _convertToken($, pathTokenOut, tokenOut, amountOut, msg.sender);
            if (amountOut < minAmountOut) {
                revert InsufficientOutputAmount();
            }
        } else {
            amountOut = _swap(path, amountIn, minAmountOut, feeOnTransfer, msg.sender);
        }
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
     * @notice Calculates the required input token amount for a specific output token amount through a defined swap
     *         path.
     * @dev Uses the Uniswap V3 quoter to estimate the amount of `tokenIn` required to receive a specific amount of
     *      `tokenOut` following the given `path`. Supports custom conversion scenarios where the path may require
     *      conversions outside of direct Uniswap V3 swaps.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param path The encoded path of tokens to be followed in the swap.
     * @param amountOut The desired amount of the output token.
     * @param sender The address initiating the request, used for permissions or validations.
     * @return amountIn The estimated amount of input tokens required.
     */
    function getAmountIn(address tokenIn, address tokenOut, bytes memory path, uint256 amountOut, address sender)
        public
        returns (uint256 amountIn)
    {
        PearlRouterStorage storage $ = _getPearlRouterStorage();
        address pathTokenIn = _firstAddressInPath(path);
        address pathTokenOut = _lastAddressInPath(path);

        if (tokenOut != pathTokenOut) {
            amountOut = _convertAmount($, tokenOut, pathTokenOut, amountOut, address(this));
        }

        (amountIn,,,) = IQuoter($.quoter).quoteExactInput(path, amountOut);

        if (tokenIn != pathTokenIn) {
            amountIn = _convertAmount($, pathTokenIn, tokenIn, amountIn, sender);
        }
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
    function getAmountOut(bytes memory path, uint256 amountIn) public returns (uint256 amountOut) {
        PearlRouterStorage storage $ = _getPearlRouterStorage();
        (amountOut,,,) = IQuoter($.quoter).quoteExactInput(path, amountIn);
    }

    /**
     * @notice Calculates the output token amount for a given input token amount through a defined swap path.
     * @dev Uses the Uniswap V3 quoter to estimate the amount of `tokenOut` obtainable for a specific amount of
     *      `tokenIn` following the given `path`. Supports custom conversion scenarios where the path may require
     *      conversions outside of direct Uniswap V3 swaps.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param path The encoded path of tokens to be followed in the swap.
     * @param amountIn The amount of the input token.
     * @param recipient The address that will receive the output tokens, used for permissions or validations.
     * @return amountOut The estimated amount of output tokens obtainable.
     */
    function getAmountOut(address tokenIn, address tokenOut, bytes memory path, uint256 amountIn, address recipient)
        public
        returns (uint256 amountOut)
    {
        PearlRouterStorage storage $ = _getPearlRouterStorage();
        address pathTokenIn = _firstAddressInPath(path);
        address pathTokenOut = _lastAddressInPath(path);

        if (tokenIn != pathTokenIn) {
            amountIn = _convertAmount($, tokenIn, pathTokenIn, amountIn, address(this));
        }

        (amountOut,,,) = IQuoter($.quoter).quoteExactInput(path, amountIn);

        if (tokenOut != pathTokenOut) {
            amountOut = _convertAmount($, pathTokenOut, tokenOut, amountOut, recipient);
        }
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
     * @notice Retrieves the address of the last token in a given path.
     * @param path The path of tokens to swap through.
     * @return lastAddress The address of the last token in the path.
     */
    function _lastAddressInPath(bytes memory path) internal pure returns (address lastAddress) {
        require(path.length >= 20, "OB");
        assembly {
            lastAddress := shr(96, mload(add(add(path, mload(path)), 12)))
        }
    }

    /**
     * @notice Converts a given amount of one token to another using a converter contract.
     * @dev Converts `amountIn` of `tokenIn` to `tokenOut` by invoking the previewConvert function of the associated
     *      converter. This function is typically used in the context of preparing for a swap where direct conversion
     *      paths are not available.
     * @param $ Reference to storage containing contract-wide settings and state.
     * @param tokenIn The address of the token to be converted from.
     * @param tokenOut The address of the token to be converted to.
     * @param amountIn The amount of `tokenIn` to be converted.
     * @param recipient The recipient address which will receive `tokenOut`.
     * @return The amount of `tokenOut` received from the conversion.
     */
    function _convertAmount(
        PearlRouterStorage storage $,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) internal view returns (uint256) {
        address converter = $.tokenConverter[tokenIn];
        if (converter == address(0)) {
            revert InvalidPath();
        }
        return ITokenConverter(converter).previewConvert(tokenIn, tokenOut, amountIn, recipient);
    }

    /**
     * @notice Converts an amount of `tokenIn` to `tokenOut` using a predefined converter contract.
     * @dev Calls a token converter contract to convert `tokenIn` to `tokenOut`. This function is utilized for swaps
     *      requiring conversions outside the main swap path, e.g., when `tokenIn` or `tokenOut` is not supported by
     *      the primary swap mechanism. It facilitates the use of custom conversion logic, potentially involving
     *      different protocols or swap mechanisms.
     *      Requires that a converter contract address for `tokenIn` is already set and that the converter contract
     *      can perform the conversion to `tokenOut`.
     * @param $ A reference to the contract's storage space used to access converter addresses.
     * @param tokenIn The address of the token to convert from.
     * @param tokenOut The address of the token to convert to.
     * @param amountIn The amount of `tokenIn` to convert.
     * @param recipient The address to receive `tokenOut`.
     * @return The amount of `tokenOut` received after conversion.
     */
    function _convertToken(
        PearlRouterStorage storage $,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) internal returns (uint256) {
        address converter = $.tokenConverter[tokenIn];
        if (converter == address(0)) {
            revert InvalidPath();
        }
        return abi.decode(
            Address.functionDelegateCall(
                converter, abi.encodeCall(ITokenConverter.convert, (tokenIn, tokenOut, amountIn, recipient))
            ),
            (uint256)
        );
    }

    /**
     * @notice Transfers the specified `amount` of `token` from `from` to this contract.
     * @dev This internal function transfers the specified `amount` of `token` from `from` to this contract and returns
     *      the actual amount transferred.
     * @param token The ERC20 token to be transferred.
     * @param from The address from which the tokens are to be transferred.
     * @param amount The amount of the token to be transferred.
     * @param feeOnTransfer A boolean indicating if the `token` includes a transfer fee.
     * @return The actual amount of `token` transferred.
     */
    function _pullToken(IERC20 token, address from, uint256 amount, bool feeOnTransfer) internal returns (uint256) {
        uint256 balanceBefore;
        if (feeOnTransfer) {
            balanceBefore = token.balanceOf(address(this));
        }
        token.safeTransferFrom(from, address(this), amount);
        if (feeOnTransfer) {
            return token.balanceOf(address(this)) - balanceBefore;
        }
        return amount;
    }

    /**
     * @notice Pulls the specified `amount` of `token` to this contract, approves the swap router to spend it, and
     *         executes a swap.
     *
     * @dev This internal function handles the transfer of tokens into the contract, sets the allowance for the swap
     *      router, and performs the token swap by calling the router with the provided `swapData`. It ensures the
     *      allowance is reset after the swap. This function abstracts the token transfer, approval, and swap execution
     *      steps to simplify swap operations.
     *
     * @param token The ERC20 token to be swapped.
     * @param amount The amount of the token to be swapped.
     * @param swapData The encoded data for the swap function call, including the swap parameters.
     * @return result The amount of output tokens received from the swap.
     */
    function _processTokenSwap(IERC20 token, uint256 amount, bytes memory swapData) internal returns (uint256 result) {
        PearlRouterStorage storage $ = _getPearlRouterStorage();
        address router = $.swapRouter;
        token.forceApprove(router, amount);
        result = abi.decode(router.functionCall(swapData), (uint256));
        token.forceApprove(router, 0);
    }

    /**
     * @notice Executes a swap operation through Uniswap V3 according to the specified path, amount, and recipient.
     * @dev This internal function performs a token swap operation via Uniswap V3, using the encoded `path` to dictate
     *      the swap route. It can accommodate single or multi-hop swaps and is capable of handling fee-on-transfer
     *      tokens if `feeOnTransfer` is true. This function is a lower-level utility used by public-facing swap
     *      functions to execute the actual swap logic.
     *      It ensures that the swap meets the specified `amountIn` and `minAmountOut` criteria, adjusting for
     *      fee-on-transfer tokens as necessary. The function delegates call to the Uniswap V3 router with the
     *      appropriate swap function based on the `feeOnTransfer` flag.
     * @param path The encoded swap path that specifies each token and fee tier to be used in the swap.
     * @param amountIn The amount of the input token to be swapped.
     * @param minAmountOut The minimum amount of the output token that must be received for the swap to succeed.
     * @param feeOnTransfer Indicates if the swap should account for tokens that deduct fees on transfer.
     * @param recipient The address that will receive the output token.
     * @return The amount of the output token received from the swap.
     */
    function _swap(bytes memory path, uint256 amountIn, uint256 minAmountOut, bool feeOnTransfer, address recipient)
        internal
        returns (uint256)
    {
        address tokenIn = _firstAddressInPath(path);
        IRouter.ExactInputParams memory params = IRouter.ExactInputParams({
            path: path,
            recipient: recipient,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut
        });

        bytes4 selector = feeOnTransfer ? IRouter.exactInputFeeOnTransfer.selector : IRouter.exactInput.selector;
        return _processTokenSwap(IERC20(tokenIn), amountIn, abi.encodeWithSelector(selector, (params)));
    }
}
