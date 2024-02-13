// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

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
contract PearlRouter is OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

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
        _getPearlRouterStorage().swapRouter = swapRouter;
    }

    /**
     * @notice Sets a new address for the quoter.
     * @dev Updates the address of the quoter in the PearlRouterStorage.
     *      Access restricted to the contract owner.
     * @param quoter The new address for the quoter.
     */
    function setQuoter(address quoter) external onlyOwner {
        _getPearlRouterStorage().quoter = quoter;
    }

    /**
     * @notice Executes a token swap through the Uniswap V3 router.
     * @dev Swaps a specified amount of one token for another. Requires the tokenIn to be approved for transfer.
     *      The operation is executed via the Uniswap V3 router using the stored router address.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of the input token to swap.
     * @param minAmountOut The minimum amount of the output token to receive.
     * @param fee The pool fee for the swap.
     * @return The amount of the output token received.
     */
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, uint24 fee)
        external
        returns (uint256)
    {
        PearlRouterStorage storage $ = _getPearlRouterStorage();
        address router = $.swapRouter;
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).safeIncreaseAllowance(router, amountIn);
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

        return IRouter(router).exactInputSingle(params);
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
}
