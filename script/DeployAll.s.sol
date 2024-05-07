// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {DeployAllBase} from "./base/DeployAllBase.sol";

// forge script ./script/DeployAll.s.sol --legacy --broadcast
contract DeployAll is DeployAllBase {
    function _getUSTBAddress() internal pure override returns (address) {
        revert("DeployAll: USTB address not set");
    }

    function _getUKREAddress() internal override returns (address) {
        revert("DeployAll: UKRE address not set");
    }

    function _getUSDaAddress() internal override returns (address) {
        revert("DeployAll: USDa address not set");
    }

    function _getPTaAddress() internal override returns (address) {
        revert("DeployAll: PTa address not set");
    }

    function _getSwapRouterAddress() internal pure override returns (address) {
        revert("DeployAll: Swap Router address not set");
    }

    function _getPearlFactoryAddress() internal pure override returns (address) {
        revert("DeployAll: Pearl factory address not set");
    }

    function _getQuoterAddress() internal pure override returns (address) {
        revert("DeployAll: Quoter address not set");
    }

    function _getGelatoMessageSender() internal pure override returns (address) {
        revert("DeployAll: Gelato Message Sender not set");
    }

    function _getTeamWallet() internal pure override returns (address) {
        revert("DeployAll: Team wallet address not set");
    }

    function _getAMO() internal pure override returns (address) {
        revert("DeployAll: AMO address not set");
    }

    function _getDAI() internal pure override returns (address) {
        revert("DeployAll: DAI address not set");
    }

    function _getWETH9() internal pure override returns (address) {
        revert("DeployAll: WETH9 address not set");
    }

    function _getTangibleRevenueDistributor() internal pure override returns (address) {
        revert("DeployAll: Tangible Revenue Distributor address not set");
    }

    function _getDAIOracle() internal override returns (address) {
        revert("DeployAll: DAI oracle address not set");
    }

    function _getETHOracle() internal override returns (address) {
        revert("DeployAll: ETH oracle address not set");
    }

    function _getMOREOracle() internal virtual override returns (address) {
        revert("DeployAll: MORE Oracle address not set");
    }

    function _getUKREOracle() internal virtual override returns (address) {
        revert("DeployAll: UKRE Oracle address not set");
    }

    function _getUSDAOracle() internal virtual override returns (address) {
        revert("DeployAll: USDA Oracle address not set");
    }

    function _getUSTBOracle() internal virtual override returns (address) {
        revert("DeployAll: USTB Oracle address not set");
    }

    function _getDeploymentChainAliases() internal pure override returns (string[] memory aliases) {
        aliases = new string[](4);
        aliases[0] = "real";
        aliases[1] = "polygon";
        aliases[2] = "base";
        aliases[3] = "optimism";
    }
}
