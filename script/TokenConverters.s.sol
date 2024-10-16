// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {CaviarTokenConverter} from "src/periphery/converters/CaviarTokenConverter.sol";
import {PearlRouter} from "src/periphery/PearlRouter.sol";

contract DeployScript is Script {
    bytes32 private constant _SALT = keccak256("pearl.deployment-20240425");

    address private _deployer;

    function setUp() public {
        uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        _deployer = vm.addr(privateKey);

        setChain("unreal", ChainData("Unreal Chain", 18233, vm.rpcUrl("unreal")));
        setChain("real", ChainData("Real Chain", 111188, vm.rpcUrl("real")));

        vm.startBroadcast(privateKey);
    }

    function deployCaviarTokenConverter(PearlRouter router, address cscvr)
        public
        returns (address caviarTokenConverterAddress)
    {
        bytes32 initCodeHash = hashInitCode(type(CaviarTokenConverter).creationCode, abi.encode(cscvr));

        caviarTokenConverterAddress = vm.computeCreate2Address(_SALT, initCodeHash);

        if (!_isDeployed(caviarTokenConverterAddress)) {
            CaviarTokenConverter caviarTokenConverter = new CaviarTokenConverter{salt: _SALT}(cscvr);
            assert(address(caviarTokenConverter) == caviarTokenConverterAddress);
        }

        _saveDeploymentAddress("CaviarTokenConverter", caviarTokenConverterAddress);

        address scvr = IERC4626(cscvr).asset();
        address cvr = abi.decode(Address.functionStaticCall(scvr, abi.encodeWithSignature("underlying()")), (address));

        address[] memory tokens = new address[](3);
        tokens[0] = cscvr;
        tokens[1] = scvr;
        tokens[2] = cvr;

        for (uint256 i; i < tokens.length; i++) {
            if (router.owner() == _deployer) {
                if (router.getTokenConverter(tokens[i]) != caviarTokenConverterAddress) {
                    router.setTokenConverter(tokens[i], caviarTokenConverterAddress);
                }
            } else {
                console.log(
                    "Set token converter for token %s on PearlRouter (%s) to %s.",
                    tokens[i],
                    address(router),
                    caviarTokenConverterAddress
                );
            }
        }
    }

    function _saveDeploymentAddress(string memory name, address addr) internal {
        Chain memory _chain = getChain(block.chainid);
        string memory chainAlias = _chain.chainAlias;
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/", chainAlias, ".json");
        string memory json;
        string memory output;
        string[] memory keys;

        if (vm.exists(path)) {
            json = vm.readFile(path);
            keys = vm.parseJsonKeys(json, "$");
        } else {
            keys = new string[](0);
        }

        bool serialized;

        for (uint256 i; i < keys.length; i++) {
            if (keccak256(bytes(keys[i])) == keccak256(bytes(name))) {
                output = vm.serializeAddress(chainAlias, name, addr);
                serialized = true;
            } else {
                address value = vm.parseJsonAddress(json, string.concat(".", keys[i]));
                output = vm.serializeAddress(chainAlias, keys[i], value);
            }
        }

        if (!serialized) {
            output = vm.serializeAddress(chainAlias, name, addr);
        }

        vm.writeJson(output, path);
    }

    function _isDeployed(address contractAddress) internal view returns (bool isDeployed) {
        // slither-disable-next-line assembly
        assembly {
            let cs := extcodesize(contractAddress)
            if iszero(iszero(cs)) { isDeployed := true }
        }
    }
}
