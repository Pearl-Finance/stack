// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {AggregatorV3Wrapper} from "src/oracles/AggregatorV3Wrapper.sol";
import {ERC4626Oracle} from "src/oracles/ERC4626Oracle.sol";
import {AMO} from "src/amo/AMO.sol";
import {PSM} from "src/amo/PSM.sol";

import {IPair} from "src/interfaces/IPair.sol";

import {EmptyUUPS} from "./utils/EmptyUUPS.sol";

contract DeployScript is Script {
    bytes32 internal constant PROXY_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    bytes32 private constant _SALT = keccak256("pearl.deployment-20240425");

    address private _deployer;

    event ExecuteOnMultisig(string chain, address target, bytes data, string description);

    function setUp() public {
        uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        _deployer = vm.addr(privateKey);

        setChain("unreal", ChainData("Unreal Chain", 18233, vm.rpcUrl("unreal")));
        setChain("real", ChainData("Real Chain", 111188, vm.rpcUrl("real")));

        vm.startBroadcast(privateKey);
    }

    function deployAMO(address usdc, address moreUsdcGauge, address harvester, address rewardReceiver)
        public
        returns (address amoAddress)
    {
        bytes memory bytecode = abi.encodePacked(type(AMO).creationCode);

        address psm = _loadDeploymentAddress("PSM");
        address more = _loadDeploymentAddress("MORE");
        address moreMinter = _loadDeploymentAddress("MoreMinter");
        address spotPriceOracle = _loadDeploymentAddress("MORESpotPriceOracle");
        address twapOracle = _loadDeploymentAddress("MORETWAPOracle");

        amoAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(bytecode, abi.encode(usdc, more, moreUsdcGauge)))
        );

        AMO amo;

        if (_isDeployed(amoAddress)) {
            console.log("AMO is already deployed to %s", amoAddress);
            amo = AMO(amoAddress);
        } else {
            amo = new AMO{salt: _SALT}(usdc, more, moreUsdcGauge);
            assert(amoAddress == address(amo));
            console.log("AMO deployed to %s", amoAddress);
        }

        address proxy = _deployProxy(
            "AMO",
            amoAddress,
            abi.encodeCall(
                AMO.initialize,
                (_deployer, spotPriceOracle, twapOracle, moreMinter, harvester, rewardReceiver, 0.999e8, 1.01e8)
            )
        );

        amo = AMO(proxy);

        if (amo.psm() != psm) {
            if (amo.owner() == _deployer) {
                amo.setPSM(psm);
            } else {
                console.log("AMO PSM not updated");
            }
        }

        if (amo.moreMinter() != moreMinter) {
            if (amo.owner() == _deployer) {
                amo.setMoreMinter(moreMinter);
            } else {
                console.log("AMO MORE Minter not updated");
            }
        }

        if (amo.spotPriceOracle() != spotPriceOracle) {
            if (amo.owner() == _deployer) {
                amo.setSpotPriceOracle(spotPriceOracle);
            } else {
                console.log("AMO Spot Price Oracle not updated");
            }
        }

        if (amo.twapOracle() != twapOracle) {
            if (amo.owner() == _deployer) {
                amo.setTWAPOracle(twapOracle);
            } else {
                console.log("AMO TWAP Oracle not updated");
            }
        }
    }

    function deployPSM(address usdc) public returns (address psmAddress) {
        bytes memory bytecode = abi.encodePacked(type(PSM).creationCode);

        address amo = _loadDeploymentAddress("AMO");
        address more = _loadDeploymentAddress("MORE");
        address moreMinter = _loadDeploymentAddress("MoreMinter");
        address spotPriceOracle = _loadDeploymentAddress("MORESpotPriceOracle");
        address twapOracle = _loadDeploymentAddress("MORETWAPOracle");

        psmAddress = vm.computeCreate2Address(_SALT, keccak256(abi.encodePacked(bytecode, abi.encode(usdc, more))));

        PSM psm;

        if (_isDeployed(psmAddress)) {
            console.log("PSM is already deployed to %s", psmAddress);
            psm = PSM(psmAddress);
        } else {
            psm = new PSM{salt: _SALT}(usdc, more);
            assert(psmAddress == address(psm));
            console.log("PSM deployed to %s", psmAddress);
        }

        address proxy = _deployProxy(
            "PSM", psmAddress, abi.encodeCall(PSM.initialize, (_deployer, moreMinter, spotPriceOracle, twapOracle))
        );

        psm = PSM(proxy);

        if (psm.amo() != amo) {
            if (psm.owner() == _deployer) {
                psm.setAMO(amo);
            } else {
                console.log("PSM AMO not updated");
            }
        }

        if (psm.moreMinter() != moreMinter) {
            if (psm.owner() == _deployer) {
                psm.setMoreMinter(moreMinter);
            } else {
                console.log("PSM MORE Minter not updated");
            }
        }

        if (psm.spotPriceOracle() != spotPriceOracle) {
            if (psm.owner() == _deployer) {
                psm.setSpotPriceOracle(spotPriceOracle);
            } else {
                console.log("PSM Spot Price Oracle not updated");
            }
        }

        if (psm.twapOracle() != twapOracle) {
            if (psm.owner() == _deployer) {
                psm.setTWAPOracle(twapOracle);
            } else {
                console.log("PSM TWAP Oracle not updated");
            }
        }
    }

    address internal _emptyUUPS;

    function _ensureEmptyUUPSIsDeployed() internal {
        bytes32 initCodeHash = hashInitCode(type(EmptyUUPS).creationCode, abi.encode(_deployer));
        _emptyUUPS = vm.computeCreate2Address(_SALT, initCodeHash);

        if (!_isDeployed(_emptyUUPS)) {
            EmptyUUPS emptyUUPS = new EmptyUUPS{salt: _SALT}(_deployer);
            assert(address(emptyUUPS) == _emptyUUPS);
            console.log("Empty UUPS implementation contract deployed to %s", _emptyUUPS);
        }
    }

    function _computeProxyAddress(string memory forContract)
        internal
        view
        returns (address proxyAddress, bytes32 salt)
    {
        bytes32 initCodeHash = hashInitCode(type(ERC1967Proxy).creationCode, abi.encode(_emptyUUPS, ""));
        salt = keccak256(abi.encodePacked(_SALT, forContract));
        proxyAddress = vm.computeCreate2Address(salt, initCodeHash);
    }

    function _deployProxy(string memory forContract, address implementation, bytes memory data)
        internal
        returns (address proxyAddress)
    {
        _ensureEmptyUUPSIsDeployed();

        bytes32 salt;
        (proxyAddress, salt) = _computeProxyAddress(forContract);

        if (_isDeployed(proxyAddress)) {
            ERC1967Proxy proxy = ERC1967Proxy(payable(proxyAddress));
            address _implementation = address(uint160(uint256(vm.load(address(proxy), PROXY_IMPLEMENTATION_SLOT))));
            if (_implementation != implementation) {
                if (Ownable(address(proxy)).owner() != _deployer) {
                    emit ExecuteOnMultisig(
                        getChain(block.chainid).chainAlias,
                        address(proxy),
                        abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (implementation, "")),
                        string.concat("Upgrade ", forContract, " proxy")
                    );
                } else {
                    UUPSUpgradeable(address(proxy)).upgradeToAndCall(implementation, "");
                    console.log("%s proxy at %s has been upgraded", forContract, proxyAddress);
                }
            } else {
                console.log("%s proxy at %s remains unchanged", forContract, proxyAddress);
            }
        } else {
            ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(_emptyUUPS, "");
            proxyAddress = address(proxy);
            UUPSUpgradeable(address(proxy)).upgradeToAndCall(implementation, data);
            console.log("%s proxy deployed to %s", forContract, proxyAddress);
            _saveDeploymentAddress(forContract, address(proxy));
        }
    }

    function _loadDeploymentAddress(string memory name) internal returns (address) {
        Chain memory _chain = getChain(block.chainid);
        string memory chainAlias = _chain.chainAlias;
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/", chainAlias, ".json");

        if (vm.exists(path)) {
            string memory json = vm.readFile(path);
            string[] memory keys = vm.parseJsonKeys(json, "$");
            for (uint256 i; i < keys.length; i++) {
                if (keccak256(bytes(keys[i])) == keccak256(bytes(name))) {
                    return vm.parseJsonAddress(json, string.concat(".", keys[i]));
                }
            }
        }

        return address(0);
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
