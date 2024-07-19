// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {DeployAllBase} from "./base/DeployAllBase.sol";

// forge script ./script/DeployAll.s.sol -vvvv | grep ExecuteOnMultisig
// forge script ./script/DeployAll.s.sol --legacy --gas-estimate-multiplier 600 --slow --broadcast
contract DeployAll is DeployAllBase {
    function _getUSTBAddress() internal pure override returns (address) {
        return 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;
    }

    function _getUKREAddress() internal pure override returns (address) {
        return 0x835d3E1C0aA079C6164AAd21DCb23E60eb71AF48;
    }

    function _getUSDaAddress() internal pure override returns (address) {
        return 0xAEC9e50e3397f9ddC635C6c429C8C7eca418a143;
    }

    function _getPTaAddress() internal pure override returns (address) {
        return 0xeAcFaA73D34343FcD57a1B3eB5B0D949df727712;
    }

    function _getSwapRouterAddress() internal pure override returns (address) {
        //return 0xa1F56f72b0320179b01A947A5F78678E8F96F8EC;
        return 0xcDA705F6EE1d3130f088f58D35fE4aC0C016059C;
    }

    function _getPearlFactoryAddress() internal pure override returns (address) {
        return 0xeF0b0a33815146b599A8D4d3215B18447F2A8101;
    }

    function _getQuoterAddress() internal pure override returns (address) {
        return 0xDe43aBe37aB3b5202c22422795A527151d65Eb18;
    }

    function _getGelatoMessageSender() internal pure override returns (address) {
        return 0xFe48C99fD8A7cbb8d3a5257E1dCcC69e9a991A48;
    }

    function _getTeamWallet() internal override returns (address) {
        if (getChain("real").chainId == block.chainid) {
            return 0xAC0926290232D07eD8b083F6BE3Ab040010f757F;
        }
        return 0x839AEeA3537989ce05EA1b218aB0F25E54cC3B3f;
    }

    function _getDAI() internal pure override returns (address) {
        return 0x75d0cBF342060b14c2fC756fd6E717dFeb5B1B70;
    }

    function _getWETH9() internal override returns (address) {
        if (getChain("real").chainId == block.chainid) {
            return 0x90c6E93849E06EC7478ba24522329d14A5954Df4;
        }
        if (getChain("bnb_smart_chain").chainId == block.chainid) {
            return 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        }
        if (getChain("scroll").chainId == block.chainid) {
            return 0x5300000000000000000000000000000000000004;
        }
        if (getChain("blast").chainId == block.chainid) {
            return 0x4300000000000000000000000000000000000004;
        }
        revert("DeployAll: WETH9 address not set");
    }

    function _getTangibleRevenueDistributor() internal pure override returns (address) {
        return 0x7a2E4F574C0c28D6641fE78197f1b460ce5E4f6C;
    }

    function _getDAIOracle() internal pure override returns (address) {
        return 0xc1BC91831d6e105b60D948193357C244F1964606;
    }

    function _getETHOracle() internal pure override returns (address) {
        return 0xCE7975662c7a530ab2E0f6cD8b580c5540Bb480d;
    }

    function _getMOREOracle() internal virtual override returns (address) {
        return 0x900D4F7a7509194e248BbA319AFA4AB9691885fE;
    }

    function _getUKREOracle() internal virtual override returns (address) {
        revert("DeployAll: UKRE Oracle address not set");
    }

    function _getUSDAOracle() internal virtual override returns (address) {
        return 0x79f0DfE944b75692526c528176f25065Ad869aC9;
    }

    function _getUSTBOracle() internal virtual override returns (address) {
        return 0x16b7ffD3DE49afC9f7c64c0a45b3111857717C88;
    }

    function _getDeploymentChainAliases() internal pure override returns (string[] memory aliases) {
        aliases = new string[](4);
        aliases[0] = "real";
        aliases[1] = "bnb_smart_chain";
        aliases[2] = "scroll";
        aliases[3] = "blast";
        /*
        aliases = new string[](5);
        aliases[0] = "real";
        aliases[1] = "polygon";
        aliases[2] = "base";
        aliases[3] = "optimism";
        aliases[4] = "bnb_smart_chain";
        */
    }
}
