// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {DeployAllBase} from "./base/DeployAllBase.sol";

// forge script ./script/DeployAllTestnet.s.sol --legacy --sig "deployOnMainChain()" --rpc-url unreal --broadcast \
//     --sender 0x839aeea3537989ce05ea1b218ab0f25e54cc3b3f --verify \
//     --verifier blockscout --verifier-url "https://unreal.blockscout.com/api"
// forge script ./script/DeployAllTestnet.s.sol --legacy --sig "deployOnAllChains()" --broadcast
contract DeployAll is DeployAllBase {
    function _getMainChainAlias() internal pure override returns (string memory) {
        return "unreal";
    }

    function _getUSTBAddress() internal pure override returns (address) {
        return 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;
    }

    function _getSwapRouterAddress() internal pure override returns (address) {
        return 0xC1734f65345A162edc078edB6465853CF86100B7;
    }

    function _getQuoterAddress() internal pure override returns (address) {
        return 0xbA72f9Afb2759eC1882e5D51aa5f8c480Fe61Bd8;
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

    function _getDeploymentChainAliases() internal pure override returns (string[] memory aliases) {
        aliases = new string[](2);
        aliases[0] = "unreal";
        aliases[1] = "sepolia";
    }
}
