// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title ERC4626 Router
 * @author SeaZarrgh LaBuoy
 * @dev This contract acts as a router for interacting with ERC4626 vaults, facilitating the minting, depositing,
 * withdrawing, and redeeming processes. It abstracts away the complexity of interacting directly with ERC4626 vault
 * contracts for users, providing a simplified interface for these operations.
 * The router handles the transfer of assets into the vault for minting or depositing, as well as managing the allowance
 * for the vault to access the user's tokens. Similarly, it manages the withdrawal and redemption of assets from the
 * vault, ensuring that users receive their tokens or shares directly.
 * It includes error handling to revert transactions that would result in undesirable states, such as insufficient
 * output amounts or shares, or exceeding specified maximum inputs.
 *
 * Error Codes:
 * - ERC4626RouterInsufficientAmount: Indicates an attempt to redeem shares for an amount lower than the minimum
 *                                    specified.
 * - ERC4626RouterInsufficientShares: Indicates an attempt to deposit an amount resulting in fewer shares than the
 *                                    minimum specified.
 * - ERC4626RouterMaxAmountExceeded: Indicates an attempt to mint shares requiring an asset amount higher than the
 *                                   maximum allowed.
 * - ERC4626RouterMaxSharesExceeded: Indicates an attempt to withdraw an amount resulting in more shares being used than
 *                                   the maximum allowed.
 */
contract ERC4626Router {
    using SafeERC20 for IERC20;

    error ERC4626RouterInsufficientAmount();
    error ERC4626RouterInsufficientShares();
    error ERC4626RouterMaxAmountExceeded();
    error ERC4626RouterMaxSharesExceeded();

    /**
     * @notice Mints shares in the specified ERC4626 vault and assigns them to the `to` address.
     *
     * @dev This function handles the asset transfer required for minting shares in the vault, ensuring the amount of
     * assets transferred does not exceed `maxAmountIn`.
     * It first calculates the amount of the vault's underlying asset needed to mint the specified `shares` by calling
     * `previewMint`. If this amount exceeds `maxAmountIn`, the transaction is reverted to prevent excessive asset
     * expenditure.
     * The function then transfers the calculated amount of assets from the caller to the router contract,
     * increases the allowance for the vault to spend the assets, and finally calls `mint` on the vault.
     * If the actual amount of assets used for minting is less than the amount transferred to the router,
     * the surplus is refunded to the caller.
     *
     * Requirements:
     * - The actual amount needed to mint `shares` must not exceed `maxAmountIn`.
     * - The caller must have a sufficient balance and have given the router contract enough allowance to transfer the
     *   required asset amount.
     *
     * @param vault The address of the ERC4626 vault where shares are to be minted.
     * @param to The address to which the minted shares will be assigned.
     * @param shares The amount of shares to mint in the vault.
     * @param maxAmountIn The maximum amount of the vault's underlying asset that the caller is willing to spend on
     *                    minting.
     * @return amountIn The actual amount of the vault's underlying asset used to mint the specified `shares`.
     */
    function mint(IERC4626 vault, address to, uint256 shares, uint256 maxAmountIn)
        external
        returns (uint256 amountIn)
    {
        amountIn = vault.previewMint(shares);
        if (amountIn > maxAmountIn) {
            revert ERC4626RouterMaxAmountExceeded();
        }
        IERC20 asset = IERC20(vault.asset());
        asset.safeTransferFrom(msg.sender, address(this), amountIn);
        asset.safeIncreaseAllowance(address(vault), amountIn);
        uint256 amount = vault.mint(shares, to);
        if (amount < amountIn) {
            asset.forceApprove(address(vault), 0);
            unchecked {
                asset.safeTransfer(msg.sender, amountIn - amount);
            }
        }
    }

    /**
     * @notice Deposits the specified amount of the vault's underlying asset into the vault in exchange for vault
     * shares, assigned to the `to` address.
     *
     * @dev This function facilitates the deposit of assets into the specified ERC4626 vault, converting the deposited
     * assets into vault shares.
     * It begins by estimating the number of shares `sharesOut` that will be received for the deposit using
     * `previewDeposit`. If the estimated shares are less than `minSharesOut`, the transaction is reverted to ensure the
     * depositor receives a minimum return.
     * The assets are then transferred from the caller to this router contract, and the allowance for the vault to spend
     * these assets is increased accordingly. The function then proceeds to deposit the assets into the vault, which in
     * turn mints the shares directly to the `to` address.
     * If the actual shares minted are less than `minSharesOut`, the operation is reverted to prevent a less favorable
     * exchange rate.
     *
     * Requirements:
     * - The deposit must result in at least `minSharesOut` shares being minted to the `to` address.
     * - The caller must have a sufficient balance and have granted the router contract enough allowance to transfer the
     *   specified amount of the asset.
     *
     * @param vault The address of the ERC4626 vault where the assets are to be deposited.
     * @param to The address that will receive the shares from the deposit.
     * @param amount The amount of the vault's underlying asset to be deposited.
     * @param minSharesOut The minimum number of shares the depositor expects to receive for their deposit.
     * @return sharesOut The actual number of shares minted to the `to` address as a result of the deposit.
     */
    function deposit(IERC4626 vault, address to, uint256 amount, uint256 minSharesOut)
        external
        returns (uint256 sharesOut)
    {
        sharesOut = vault.previewDeposit(amount);
        if (sharesOut < minSharesOut) {
            revert ERC4626RouterInsufficientShares();
        }
        IERC20 asset = IERC20(vault.asset());
        asset.safeTransferFrom(msg.sender, address(this), amount);
        asset.safeIncreaseAllowance(address(vault), amount);
        uint256 shares = vault.deposit(amount, to);
        if (shares < minSharesOut) {
            revert ERC4626RouterInsufficientShares();
        }
    }

    /**
     * @notice Withdraws a specified amount of the vault's underlying asset from the vault, using the caller's shares,
     * and sends the assets to the `to` address.
     *
     * @dev This function facilitates the withdrawal of assets from the specified ERC4626 vault in exchange for burning
     * a portion of the caller's shares in the vault.
     * It calculates the number of shares `sharesOut` needed to withdraw the specified `amount` of assets by calling the
     * vault's `withdraw` function directly, which also performs the actual withdrawal and share burning. If the number
     * of shares required exceeds `maxSharesOut`, the transaction is reverted to prevent the use of more
     * shares than the caller is willing to spend. This ensures that the caller does not inadvertently spend more shares
     * than intended for the withdrawal amount.
     *
     * Requirements:
     * - The withdrawal must not require more than `maxSharesOut` shares to be burned.
     * - The caller must have enough shares in the vault to cover the withdrawal and have granted the router contract
     *   enough allowance to transfer the specified amount of the asset.
     *
     * @param vault The address of the ERC4626 vault from which the assets are to be withdrawn.
     * @param to The address that will receive the withdrawn assets.
     * @param amount The amount of the vault's underlying asset to withdraw.
     * @param maxSharesOut The maximum number of shares the caller is willing to spend to perform the withdrawal.
     * @return sharesOut The actual number of shares burned in exchange for the withdrawn assets.
     */
    function withdraw(IERC4626 vault, address to, uint256 amount, uint256 maxSharesOut)
        external
        returns (uint256 sharesOut)
    {
        sharesOut = vault.withdraw(amount, to, msg.sender);
        if (sharesOut > maxSharesOut) {
            revert ERC4626RouterMaxSharesExceeded();
        }
    }

    /**
     * @notice Redeems a specified number of shares from the vault for its underlying asset, sending the asset to the
     * `to` address, and deducting the shares from the caller's balance.
     *
     * @dev This function allows the caller to exchange their shares in the specified ERC4626 vault for the vault's
     * underlying asset.
     * It performs the redemption by directly calling the vault's `redeem` function, which handles the exchange of
     * shares for assets and the transfer of assets to the `to` address.
     * This function ensures that the amount of assets received from redeeming the shares is not less than
     * `minAmountOut`, protecting the caller from receiving less than expected due to fluctuations in the value of the
     * shares or the underlying asset. If the actual amount of assets received is less than `minAmountOut`, the
     * transaction is reverted to prevent a redemption that does not meet the caller's expectations.
     *
     * Requirements:
     * - The redemption must result in receiving at least `minAmountOut` of the vault's underlying asset.
     * - The caller must have enough shares in the vault to cover the redemption and have granted the router contract
     *   enough allowance to transfer the specified amount of the shares.
     *
     * @param vault The address of the ERC4626 vault from which shares are to be redeemed.
     * @param to The address that will receive the vault's underlying asset as a result of the redemption.
     * @param shares The number of shares to be redeemed.
     * @param minAmountOut The minimum amount of the vault's underlying asset that the caller expects to receive for
     *                     their shares.
     * @return amountOut The actual amount of the vault's underlying asset received in exchange for the redeemed shares.
     */
    function redeem(IERC4626 vault, address to, uint256 shares, uint256 minAmountOut)
        external
        returns (uint256 amountOut)
    {
        amountOut = vault.redeem(shares, to, msg.sender);
        if (amountOut < minAmountOut) {
            revert ERC4626RouterInsufficientAmount();
        }
    }
}
