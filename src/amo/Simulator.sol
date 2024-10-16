// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

abstract contract Simulator {
    function callAndRevert(bytes calldata data) external {
        (bool success, bytes memory result) = address(this).delegatecall(data);
        if (success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        } else {
            assembly {
                revert(0, 0)
            }
        }
    }

    function _simulateUint256Result(bytes memory callData) internal returns (uint256 _result) {
        try this.callAndRevert(callData) {
            // This block won't be executed as any call will revert
        } catch (bytes memory result) {
            if (result.length == 32) {
                // Ensure we have a valid uint256 encoded result
                _result = abi.decode(result, (uint256));
            }
        }
    }
}
