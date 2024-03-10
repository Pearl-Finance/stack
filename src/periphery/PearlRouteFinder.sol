pragma solidity =0.8.20;

import {PearlRouter} from "./PearlRouter.sol";

import {IPair} from "./interfaces/IPair.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";
import {IQuoter} from "./interfaces/IQuoter.sol";
import {IRouter} from "./interfaces/IRouter.sol";

/**
 * @title PearlRouteFinder Contract
 * @author SeaZarrgh LaBuoy
 * @notice This contract serves as an advanced route finder for token swaps on the Pearl decentralized exchange (DEX),
 * leveraging depth-first search (DFS) algorithms to identify the most efficient swap paths. It is designed to optimize
 * for the highest return amount by exploring all possible swap routes within a specified maximum path length.
 *
 * @dev The contract employs a combination of DFS strategy and caching mechanisms to efficiently determine the best path
 * for token swaps. It interfaces with the PearlRouter for swap executions and the IPairFactory for accessing pair
 * information. The main functionality is exposed through the `findBestSwapPath` function, which returns the optimal
 * swap route and expected output amount for a given input token, output token, and input amount. It also implements
 * error handling for scenarios such as no path found or zero path length.
 *
 * Key functionalities include:
 *  - Best Swap Path Finding: Utilizes a DFS algorithm to explore swap paths, aiming to maximize the output amount for
 *    the given input.
 *  - Pair Caching: Preloads and caches pair information from the IPairFactory to optimize path finding efficiency.
 *  - Error Handling: Provides clear custom errors for scenarios like no available path or invalid path lengths.
 *  - Gas Efficiency: Designed with gas efficiency in mind, minimizing on-chain computations and storage operations.
 */
contract PearlRouteFinder {
    struct CachedPair {
        address pair;
        address token0;
        address token1;
        uint24 fee;
    }

    struct SwapStep {
        address tokenIn;
        address tokenOut;
        address pair;
        uint24 fee;
        uint256 amountIn;
        uint256 amountOut;
    }

    error NoPathFound();
    error ZeroPathLength();

    IPairFactory public immutable factory;
    PearlRouter public immutable router;

    /**
     * @notice Initializes the PearlRouteFinder contract with the specified factory and router addresses.
     * @param _factory The address of the token pair factory.
     * @param _router The address of the router contract.
     */
    constructor(address _factory, address _router) {
        factory = IPairFactory(_factory);
        router = PearlRouter(_router);
    }

    /**
     * @dev This function performs a depth-first search to find the optimal swap path.
     * @notice Entry function to find the best swap path for a given token pair and amount.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of the input token to swap.
     * @param maxPathLength The maximum length of the swap path to consider.
     * @return bestAmountOut The best amount of the output token that can be received.
     * @return bestPath The swap path that gives the best return amount, encoded as bytes.
     */
    function findBestSwapPath(address tokenIn, address tokenOut, uint256 amountIn, uint256 maxPathLength)
        external
        returns (uint256 bestAmountOut, bytes memory bestPath)
    {
        if (maxPathLength == 0) {
            revert ZeroPathLength();
        }

        CachedPair[] memory cachedPairs = _cachePairs();
        SwapStep[] memory path = new SwapStep[](maxPathLength + 1);

        path[0].tokenIn = tokenIn;
        path[0].amountIn = amountIn;

        SwapStep[] memory bestSteps;

        (bestAmountOut, bestSteps) = _dfs(cachedPairs, tokenIn, tokenOut, amountIn, path, 1, maxPathLength);

        if (bestSteps.length == 0) {
            revert NoPathFound();
        }

        for (uint256 i = bestSteps.length; i != 0;) {
            unchecked {
                --i;
            }
            bestPath = abi.encodePacked(bestSteps[i].fee, bestSteps[i].tokenOut, bestPath);
        }
        bestPath = abi.encodePacked(tokenIn, bestPath);
    }

    /**
     * @dev This recursive function explores all possible paths to find the one that offers the best return.
     * @notice Internally used to perform a depth-first search (DFS) to find the optimal swap path.
     * @param pairs An array of cached pair information.
     * @param currentToken The current token address in the swap path.
     * @param targetToken The target token address for the swap.
     * @param amountIn The amount of the current token to swap.
     * @param path The current path being evaluated.
     * @param steps The current step count in the path.
     * @param maxPathLength The maximum allowed path length.
     * @return bestAmountOut The best amount out found during the search.
     * @return bestPath The best swap path found, as an array of SwapStep.
     */
    function _dfs(
        CachedPair[] memory pairs,
        address currentToken,
        address targetToken,
        uint256 amountIn,
        SwapStep[] memory path,
        uint256 steps,
        uint256 maxPathLength
    ) private returns (uint256 bestAmountOut, SwapStep[] memory bestPath) {
        if (steps > maxPathLength) {
            return (0, bestPath); // path too long, return invalid result
        }

        for (uint256 i = pairs.length; i != 0;) {
            unchecked {
                --i;
            }

            CachedPair memory pair = pairs[i];
            address nextToken;

            if (currentToken == pair.token0) {
                nextToken = pair.token1;
            } else if (currentToken == pair.token1) {
                nextToken = pair.token0;
            } else {
                continue;
            }

            if (_pathContainsPair(path, steps, pair.pair)) {
                // avoid loops
                continue;
            }

            SwapStep memory prev = path[steps - 1];
            SwapStep memory curr = path[steps];

            prev.pair = pair.pair;
            prev.fee = pair.fee;
            prev.tokenOut = nextToken;
            curr.tokenIn = nextToken;

            try router.getAmountOut(currentToken, nextToken, amountIn, pair.fee) returns (uint256 amountOut) {
                prev.amountOut = amountOut;
                curr.amountIn = amountOut;
            } catch {
                continue;
            }

            if (nextToken == targetToken) {
                // calculate output amount and update bestPath if better
                if (curr.amountIn > bestAmountOut) {
                    bestAmountOut = prev.amountOut;
                    // Copy path to bestPath
                    bestPath = _clonePath(path, steps);
                }
            } else {
                // recurse into next token
                (uint256 amountOut, SwapStep[] memory subPath) =
                    _dfs(pairs, nextToken, targetToken, curr.amountIn, path, steps + 1, maxPathLength);
                if (bestAmountOut < amountOut) {
                    bestAmountOut = amountOut;
                    bestPath = subPath;
                }
            }
        }

        return (bestAmountOut, bestPath);
    }

    /**
     * @dev Clones the given path up to the specified length.
     * @notice This is used to copy the current best path during the DFS search.
     * @param path The path to clone.
     * @param length The length of the path to clone.
     * @return A new array of SwapStep that is a clone of the given path up to the specified length.
     */
    function _clonePath(SwapStep[] memory path, uint256 length) private pure returns (SwapStep[] memory) {
        SwapStep[] memory clone = new SwapStep[](length);
        while (length != 0) {
            unchecked {
                --length;
            }
            clone[length] = _cloneStep(path[length]);
        }
        return clone;
    }

    /**
     * @dev Clones the given step.
     * @notice This is used to copy the current best step during the DFS search.
     * @param step The step to clone.
     * @return A new SwapStep that is a clone of the given step.
     */
    function _cloneStep(SwapStep memory step) private pure returns (SwapStep memory) {
        return SwapStep({
            tokenIn: step.tokenIn,
            tokenOut: step.tokenOut,
            pair: step.pair,
            fee: step.fee,
            amountIn: step.amountIn,
            amountOut: step.amountOut
        });
    }

    /**
     * @dev Checks if the given path already contains a specific pair.
     * @notice This is used to avoid loops in the path during the DFS search.
     * @param path The path to check.
     * @param steps The number of steps in the path to check.
     * @param pair The pair address to check for.
     * @return True if the pair is already in the path, false otherwise.
     */
    function _pathContainsPair(SwapStep[] memory path, uint256 steps, address pair) private pure returns (bool) {
        while (steps != 0) {
            unchecked {
                --steps;
            }
            if (path[steps].pair == pair) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Caches the pair information from the factory for all pairs.
     * @notice This function is used to preload pair information to optimize the DFS search.
     * @return cachedPairs An array of CachedPair containing information for all pairs from the factory.
     */
    function _cachePairs() private view returns (CachedPair[] memory cachedPairs) {
        uint256 poolCount = factory.allPairsLength();
        cachedPairs = new CachedPair[](poolCount);
        while (poolCount != 0) {
            unchecked {
                --poolCount;
            }
            address poolAddress = factory.allPairs(poolCount);
            IPair pool = IPair(poolAddress);
            cachedPairs[poolCount] =
                CachedPair({pair: poolAddress, token0: pool.token0(), token1: pool.token1(), fee: pool.fee()});
        }
    }
}
