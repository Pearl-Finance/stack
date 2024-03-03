// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

/**
 * @title Common Errors Interface
 * @notice Defines custom error types to be used across the contract system for specific revert scenarios.
 * @dev This interface declares error types without implementing any logic. It serves as a centralized definition of
 *      common errors that can be inherited and used by other contracts. These errors provide clearer and more
 *      informative messages for revert scenarios, improving the debuggability and overall developer experience.
 * @author SeaZarrgh LaBuoy
 */
interface CommonErrors {
    /// @notice Error used to indicate an invalid fee value.
    error InvalidFee(uint256 min, uint256 max, uint256 actual);

    /// @notice Error used to indicate an invalid share value.
    error InvalidShare(uint256 min, uint256 max, uint256 actual);

    /// @notice Error used to indicate operations involving an invalid zero address.
    error InvalidZeroAddress();

    /// @notice Error used to indicate unauthorized access or call to a function.
    error UnauthorizedCaller();

    /// @notice Error used to indicate an operation where the value remains unchanged, hence the operation is redundant.
    error ValueUnchanged();
}
