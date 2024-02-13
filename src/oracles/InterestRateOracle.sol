// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {CommonErrors} from "../interfaces/CommonErrors.sol";

/**
 * @title Interest Rate Oracle Contract
 * @notice Oracle for providing the Annual Percentage Rate (APR) for collateral tokens in the Stack ecosystem.
 * @dev The APR is maintained off-chain and can be updated by an authorized manager. It is intended to be used
 *      for calculating interest rates on supplied assets.
 * @author SeaZarrgh LaBuoy
 */
contract InterestRateOracle is Ownable, CommonErrors {
    address public immutable token;

    address public manager;
    uint256 public apr;
    uint256 public updateInterval;

    uint256 private _lastUpdateTimestamp;

    event ManagerUpdated(address manager);
    event APRUpdated(uint256 apr);

    /**
     * @notice Constructs the Interest Rate Oracle contract.
     * @dev Initializes the contract with the token address, owner, manager, and initial APR.
     * @param _token The address of the token for which the APR is provided.
     * @param _owner The owner address with the authority to change the manager.
     * @param _manager The manager address with the authority to update the APR.
     * @param initialAPR The initial APR for the token.
     */
    constructor(address _token, address _owner, address _manager, uint256 initialAPR) Ownable(_owner) {
        token = _token;
        manager = _manager;
        apr = initialAPR;
    }

    /**
     * @notice Sets or updates the manager address.
     * @dev Allows the owner to change the manager responsible for updating the APR.
     *      Emits a `ManagerUpdated` event upon successful update.
     * @param _manager The new manager's address.
     */
    function setManager(address _manager) external onlyOwner {
        if (manager == _manager) {
            revert ValueUnchanged();
        }
        manager = _manager;
        emit ManagerUpdated(_manager);
    }

    /**
     * @notice Updates the APR for the token.
     * @dev Can only be called by the manager. Updates the APR and the interval since the last update.
     *      Emits an `APRUpdated` event upon successful update.
     * @param _apr The new APR value.
     */
    function setAPR(uint256 _apr) external {
        if (msg.sender != manager) {
            revert UnauthorizedCaller();
        }
        updateInterval = block.timestamp - _lastUpdateTimestamp;
        _lastUpdateTimestamp = block.timestamp;
        apr = _apr;
        emit APRUpdated(_apr);
    }
}
