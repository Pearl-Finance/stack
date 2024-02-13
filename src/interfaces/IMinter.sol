// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

/**
 * @title Token Minter Interface
 * @notice Interface for contracts responsible for minting tokens.
 * @dev This interface defines functions for minting tokens and accessing the associated token contract.
 *      Implementations of this interface should ensure proper access control for the minting function.
 * @author SeaZarrgh LaBuoy
 */
interface IMinter {
    /**
     * @notice Mints new tokens and assigns them to the specified address.
     * @dev Function to mint new tokens. This function increases the total supply of the token and should be
     *      restricted to authorized roles to prevent unauthorized token creation.
     * @param to The address to which the minted tokens will be assigned.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Returns the address of the associated token contract.
     * @dev Function to get the address of the token contract this minter is associated with.
     * @return The address of the token contract.
     */
    function token() external view returns (address);
}
