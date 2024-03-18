// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {DeployAllBase} from "./base/DeployAllBase.sol";

// forge script ./script/DeployAllTestnet.s.sol --legacy --broadcast --gas-estimate-multiplier 200
contract DeployAll is DeployAllBase {
    function _getUSTBAddress() internal pure override returns (address) {
        return 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;
    }

    function _getSwapRouterAddress() internal pure override returns (address) {
        return 0x0a42599e0840aa292C76620dC6d4DAfF23DB5236;
    }

    function _getPearlFactoryAddress() internal pure override returns (address) {
        return 0xDfCD83D2F29cF1E05F267927C102c0e3Dc2BD725;
    }

    function _getQuoterAddress() internal pure override returns (address) {
        return 0x6B6dA57BA5E77Ed5504Fe778449056fbb18020D5;
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

    function _getDAI() internal override returns (address) {
        if (getChain("unreal").chainId == block.chainid) {
            return 0x3F93beBAd7BA4d7A5129eA8159A5829Eacb06497;
        }
        revert("DeployAll: DAI address not set");
    }

    function _getWETH9() internal override returns (address) {
        if (getChain("unreal").chainId == block.chainid) {
            return 0x0C68a3C11FB3550e50a4ed8403e873D367A8E361;
        } else if (getChain("sepolia").chainId == block.chainid) {
            return 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
        }
        revert("DeployAll: WETH9 address not set");
    }

    function _getDAIOracle() internal override returns (address) {
        if (getChain("unreal").chainId == block.chainid) {
            return 0x3A76b37D3dEAB120bC46E3a542C67386D83f0BbA;
        }
        revert("DeployAll: DAI oracle address not set");
    }

    function _getETHOracle() internal override returns (address) {
        if (getChain("unreal").chainId == block.chainid) {
            return 0xdE8215FEaFB3953cBDB0E2FB61De9752a1D86eF0;
        }
        revert("DeployAll: ETH oracle address not set");
    }

    function _getTangibleRevenueDistributor() internal pure override returns (address) {
        return 0x56843df02d5A230929B3A572ACEf5048d5dB76db;
    }

    function _getMOREOracle() internal override returns (address) {
        if (getChain("unreal").chainId == block.chainid) {
            return 0x3A76b37D3dEAB120bC46E3a542C67386D83f0BbA; // TODO: this is DAI
        }
        revert("DeployAll: MORE Oracle address not set");
    }

    function _getDeploymentChainAliases() internal pure override returns (string[] memory aliases) {
        aliases = new string[](1);
        aliases[0] = "unreal";
        //aliases[1] = "sepolia";
    }
}
