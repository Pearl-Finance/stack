// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

/**
 * @title ERC20 Mintable Token Interface
 * @notice Interface for ERC20 tokens with a minting capability.
 * @dev This interface adds a 'mint' function to the standard ERC20 interface, allowing for the creation of new tokens.
 *      The 'mint' function should be implemented to control the supply of the token, typically by creating new tokens
 *      and assigning them to a specified address. It is essential to ensure that appropriate access controls are in
 *      place for the 'mint' function to prevent unauthorized token creation.
 * @author SeaZarrgh LaBuoy
 */
interface IERC20Mintable {
    /**
     * @notice Mints new tokens and assigns them to the specified address.
     * @dev Function to mint new tokens. It increases the total supply of the token and should be restricted to
     *      authorized roles.
     * @param to The address to which the minted tokens will be assigned.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external;
}
