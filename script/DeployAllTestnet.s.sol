// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {DeployAllBase} from "./base/DeployAllBase.sol";

// forge script ./script/DeployAllTestnet.s.sol --legacy --slow --broadcast --gas-estimate-multiplier 200
contract DeployAll is DeployAllBase {
    function _getUSTBAddress() internal pure override returns (address) {
        return 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;
    }

    function _getUKREAddress() internal override returns (address) {
        if (getChain("unreal").chainId == block.chainid) {
            return 0x2B8640bb46bc882bBbDE8c48D4D4503971c8DFc2;
        }
        revert("DeployAll: UKRE address not set");
    }

    function _getUSDaAddress() internal pure override returns (address) {
        return 0x902Fd8A51ED809C505F37405120A1E4c4b2c2F6c;
    }

    function _getPTaAddress() internal pure override returns (address) {
        return 0x5Cfe47AB9d98A1a00246B576240866F439c1F956;
    }

    function _getSwapRouterAddress() internal pure override returns (address) {
        return 0xa752C9Cd89FE0F9D07c8dC79A7564b45F904b344;
    }

    function _getPearlFactoryAddress() internal pure override returns (address) {
        return 0x579485AC5737c0A729908d5EA19D1054d275393F;
    }

    function _getQuoterAddress() internal pure override returns (address) {
        return 0x97Fdf90f153628b74aA9EB19BD617adB32987caF;
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

    function _getMOREOracle() internal override returns (address) {
        if (getChain("unreal").chainId == block.chainid) {
            return 0x05357De52458f6dC968c7d5A5Dc75b3Cb0bEdd49;
        }
        revert("DeployAll: MORE oracle address not set");
    }

    function _getUKREOracle() internal override returns (address) {
        if (getChain("unreal").chainId == block.chainid) {
            return 0x84278F7Bac767453f46Ccb1CF71aF5414b9b6543;
        }
        revert("DeployAll: UKRE oracle address not set");
    }

    function _getUSTBOracle() internal override returns (address) {
        if (getChain("unreal").chainId == block.chainid) {
            return 0x83a6daA1d07178D26a19Ca0FE28e424A80349Be8;
        }
        revert("DeployAll: USTB oracle address not set");
    }

    function _getTangibleRevenueDistributor() internal pure override returns (address) {
        return 0x48027bfdc9923642F44aa5c199C7eF9f07B3d5D2;
    }

    function _getDeploymentChainAliases() internal pure override returns (string[] memory aliases) {
        aliases = new string[](2);
        aliases[0] = "unreal";
        aliases[1] = "sepolia";
    }
}
