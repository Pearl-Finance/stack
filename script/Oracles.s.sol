// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {AggregatorV3Wrapper} from "src/oracles/AggregatorV3Wrapper.sol";
import {ERC4626Oracle} from "src/oracles/ERC4626Oracle.sol";
import {SpotPriceOracle} from "src/oracles/SpotPriceOracle.sol";
import {TWAPOracle} from "src/oracles/TWAPOracle.sol";

import {IPair} from "src/interfaces/IPair.sol";

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

    function deployERC4626Oracle(string memory key, address token, address aggregatorV3, string memory description)
        public
        returns (address erc4626OracleAddress)
    {
        bytes32 initCodeHash =
            hashInitCode(type(ERC4626Oracle).creationCode, abi.encode(token, aggregatorV3, description));

        erc4626OracleAddress = vm.computeCreate2Address(_SALT, initCodeHash);

        ERC4626Oracle oracle;

        if (_isDeployed(erc4626OracleAddress)) {
            console.log("ERC4626 Oracle (%s) for %s is already deployed to %s", key, token, erc4626OracleAddress);
            oracle = ERC4626Oracle(erc4626OracleAddress);
        } else {
            oracle = new ERC4626Oracle{salt: _SALT}(token, aggregatorV3, description);
            assert(erc4626OracleAddress == address(oracle));
            console.log("ERC4626 Oracle (%s) for %s deployed to %s", key, token, erc4626OracleAddress);
        }

        _saveDeploymentAddress(key, address(oracle));
    }

    function deployOracleWrapper(string memory key, address token, address aggregatorV3)
        public
        returns (address wrappedOracleAddress)
    {
        bytes memory bytecode = abi.encodePacked(type(AggregatorV3Wrapper).creationCode);

        wrappedOracleAddress =
            vm.computeCreate2Address(_SALT, keccak256(abi.encodePacked(bytecode, abi.encode(token, aggregatorV3))));

        AggregatorV3Wrapper wrappedOracle;

        if (_isDeployed(wrappedOracleAddress)) {
            console.log("Wrapped oracle (%s) for %s is already deployed to %s", key, token, wrappedOracleAddress);
            wrappedOracle = AggregatorV3Wrapper(wrappedOracleAddress);
        } else {
            wrappedOracle = new AggregatorV3Wrapper{salt: _SALT}(token, aggregatorV3);
            assert(wrappedOracleAddress == address(wrappedOracle));
            console.log("Wrapped Oracle (%s) for %s deployed to %s", key, token, wrappedOracleAddress);
        }

        _saveDeploymentAddress(key, address(wrappedOracle));
    }

    function deploySpotPriceOracle(string memory key, address pair, address baseToken)
        public
        returns (address spotPriceOracleAddress)
    {
        bytes memory bytecode = abi.encodePacked(type(SpotPriceOracle).creationCode);

        address token0 = IPair(pair).token0();
        bool zeroInOne = token0 == baseToken;
        uint8 decimals = 8;

        spotPriceOracleAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(bytecode, abi.encode(pair, zeroInOne, decimals)))
        );

        SpotPriceOracle spotPriceOracle;

        if (_isDeployed(spotPriceOracleAddress)) {
            console.log(
                "Spot Price Oracle (%s) for %s is already deployed to %s", key, baseToken, spotPriceOracleAddress
            );
            spotPriceOracle = SpotPriceOracle(spotPriceOracleAddress);
        } else {
            spotPriceOracle = new SpotPriceOracle{salt: _SALT}(pair, zeroInOne, decimals);
            assert(spotPriceOracleAddress == address(spotPriceOracle));
            console.log("Spot Price Oracle (%s) for %s deployed to %s", key, baseToken, spotPriceOracleAddress);
        }

        _saveDeploymentAddress(key, address(spotPriceOracle));
    }

    function deployTWAPOracle(string memory key, string memory description, address keeper)
        public
        returns (address twapOracleAddress)
    {
        bytes memory bytecode = abi.encodePacked(type(TWAPOracle).creationCode);

        twapOracleAddress =
            vm.computeCreate2Address(_SALT, keccak256(abi.encodePacked(bytecode, abi.encode(description, _deployer))));

        TWAPOracle twapOracle;

        if (_isDeployed(twapOracleAddress)) {
            console.log("TWAPOracle (%s) is already deployed to %s", key, twapOracleAddress);
            twapOracle = TWAPOracle(twapOracleAddress);
        } else {
            twapOracle = new TWAPOracle{salt: _SALT}(description, _deployer);
            assert(twapOracleAddress == address(twapOracle));
            console.log("TWAPOracle (%s) deployed to %s", key, twapOracleAddress);
        }

        if (twapOracle.keeper() != keeper) {
            if (twapOracle.owner() == _deployer) {
                twapOracle.setKeeper(keeper);
            } else {
                console.log("TWAPOracle (%s) keeper not updated", key);
            }
        }

        _saveDeploymentAddress(key, address(twapOracle));
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
