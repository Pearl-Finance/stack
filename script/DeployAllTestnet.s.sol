// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {DeployAllBase} from "./base/DeployAllBase.sol";

// forge script ./script/DeployAllTestnet.s.sol --legacy --broadcast
contract DeployAll is DeployAllBase {
    function _getUSTBAddress() internal pure override returns (address) {
        return 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;
    }

    function _getSwapRouterAddress() internal pure override returns (address) {
        return 0x4b15F7725a6B0dbb51421220c445fE3f57Bfca8b;
    }

    function _getPearlFactoryAddress() internal pure override returns (address) {
        return 0x5A9aA74caceede5eAbBeDE2F425faEB85fdCE2f2;
    }

    function _getQuoterAddress() internal pure override returns (address) {
        return 0x96A3A276ACd970248c833E11a25c786e689cbaC9;
    }

    function _getGelatoMessageSender() internal pure override returns (address) {
        return 0xFe48C99fD8A7cbb8d3a5257E1dCcC69e9a991A48;
    }

    function _getTeamWallet() internal pure override returns (address) {
        return 0x839AEeA3537989ce05EA1b218aB0F25E54cC3B3f;
    }

    function _getAMO() internal pure override returns (address) {
        return 0x839AEeA3537989ce05EA1b218aB0F25E54cC3B3f;
    }

    function _getWETH9() internal pure override returns (address) {
        return 0x9801EEB848987c0A8d6443912827bD36C288F8FB;
    }

    function _getTangibleRevenueDistributor() internal pure override returns (address) {
        return 0x56843df02d5A230929B3A572ACEf5048d5dB76db;
    }

    function _getDeploymentChainAliases() internal pure override returns (string[] memory aliases) {
        aliases = new string[](2);
        aliases[0] = "unreal";
        aliases[1] = "sepolia";
    }
}
