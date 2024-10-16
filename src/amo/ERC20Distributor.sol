// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract ERC20Distributor is OwnableUpgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    struct ShareReceiver {
        address receiver;
        uint96 share;
    }

    ShareReceiver[] public shareReceivers;

    uint256 public shareReceiversLength;

    uint256 internal _leftoverAmount;
    uint256 private _totalShare;

    error InvalidShare(address receiver);

    function setShareReceivers(ShareReceiver[] memory newShareReceivers) external onlyOwner {
        uint256 totalShare;
        uint256 currentLength = shareReceiversLength;
        uint256 newLength = newShareReceivers.length;
        uint256 i;
        while (i < newLength) {
            uint256 share = newShareReceivers[i].share;
            if (share == 0) {
                revert InvalidShare(shareReceivers[i].receiver);
            }
            if (i < currentLength) {
                shareReceivers[i] = newShareReceivers[i];
            } else {
                shareReceivers.push(newShareReceivers[i]);
            }
            totalShare += share;
            unchecked {
                i++;
            }
        }
        while (i < currentLength) {
            shareReceivers.pop();
            unchecked {
                i++;
            }
        }
        _totalShare = totalShare;
        shareReceiversLength = newShareReceivers.length;
    }

    function _distributeTokens(IERC20 token, uint256 amount) internal {
        uint256 totalShare = _totalShare;
        uint256 numReceivers = shareReceiversLength;
        uint256 totalSent;

        amount += _leftoverAmount;

        for (uint256 i; i < numReceivers; i++) {
            uint256 share = shareReceivers[i].share;
            uint256 shareAmount = amount.mulDiv(share, totalShare);
            address receiver = shareReceivers[i].receiver;
            totalSent += shareAmount;
            token.safeTransfer(receiver, shareAmount);
        }

        unchecked {
            _leftoverAmount = amount - totalSent;
        }
    }
}
