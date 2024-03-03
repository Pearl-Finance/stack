// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {console} from "forge-std/Script.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {PearlDeploymentScript} from "./PearlDeploymentScript.sol";

import {More} from "../../src/tokens/More.sol";
import {MoreMinter} from "../../src/tokens/MoreMinter.sol";
import {MoreStakingVault} from "../../src/vaults/MoreStakingVault.sol";
import {FeeSplitter} from "../../src/periphery/FeeSplitter.sol";
import {VaultDeployer} from "../../src/factories/VaultDeployer.sol";
import {VaultImplementationDeployer} from "../../src/factories/VaultImplementationDeployer.sol";
import {VaultFactory} from "../../src/factories/VaultFactory.sol";
import {StaticPriceOracle} from "../../src/oracles/StaticPriceOracle.sol";
import {StackVault} from "../../src/vaults/StackVault.sol";
import {AggregatorV3Wrapper} from "../../src/oracles/AggregatorV3Wrapper.sol";
import {PearlRouter} from "../../src/periphery/PearlRouter.sol";
import {PearlRouteFinder} from "../../src/periphery/PearlRouteFinder.sol";
import {ERC4626Router} from "../../src/periphery/ERC4626Router.sol";

abstract contract DeployAllBase is PearlDeploymentScript {
    string private constant VAULT_FACTORY_KEY = "VaultFactory-v5";

    function run() public {
        _setup();

        string[] memory deploymentChainAliases = _getDeploymentChainAliases();

        for (uint256 i = 0; i < deploymentChainAliases.length; i++) {
            Chain memory _chain = getChain(getChain(deploymentChainAliases[i]).chainId);
            console.log("---------------------------------");
            console.log("CHAIN: %s", deploymentChainAliases[i]);
            console.log("---");
            vm.createSelectFork(deploymentChainAliases[i]);
            vm.startBroadcast(_pk);
            address moreAddress = _deployMore();
            More more = More(moreAddress);
            address moreStakingVault = _deployMoreStakingVault(address(more), _chain.name, _chain.chainAlias);
            (address vaultFactoryAddress,) = _computeProxyAddress(VAULT_FACTORY_KEY);
            address moreMinter = _deployMoreMinter(address(more), vaultFactoryAddress);
            if (more.minter() != moreMinter) {
                more.setMinter(moreMinter);
            }
            address[] memory feeReceivers;
            if (_chain.chainId == 18231) {
                feeReceivers = new address[](1);
                feeReceivers[0] = _getTangibleRevenueDistributor();
            } else {
                feeReceivers = new address[](1);
                feeReceivers[0] = _getGelatoMessageSender();
            }
            address feeSplitter = _deployFeeSplitter(address(more), moreStakingVault, feeReceivers);
            address moreOracle = _deployMoreOracle(address(more));
            address ustbOracle = _deployUSTBOracle(address(_getUSTBAddress()));
            if (_chain.chainId == 18231) {
                _deployOracleWrapper(
                    "DAIOracleWrapper",
                    0x665D4921fe931C0eA1390Ca4e0C422ba34d26169,
                    0xDC8Dd6e991cB1d9F2B4137294ee3EFE6D990d917
                );
                _deployOracleWrapper("ETHOracleWrapper", _getWETH9(), 0xde2b7274F5248DF7D90Fc634501eE31406FeDAe6);
            }
            address implementationDeployer = _deployVaultImplementationDeployer();
            address vaultDeployer = _deployVaultDeployer(vaultFactoryAddress, implementationDeployer);
            address vaultFactory = _deployVaultFactory(moreMinter, moreOracle, vaultDeployer, feeSplitter);
            address pearlRouter = _deployPearlRouter();
            assert(vaultFactoryAddress == vaultFactory);
            if (!VaultFactory(vaultFactory).isTrustedSwapTarget(pearlRouter)) {
                VaultFactory(vaultFactory).setTrustedSwapTarget(pearlRouter, true);
            }
            for (uint256 j = 0; j < deploymentChainAliases.length; j++) {
                if (i != j) {
                    if (
                        !more.isTrustedRemote(
                            _getLzChainId(deploymentChainAliases[j]), abi.encodePacked(moreAddress, moreAddress)
                        )
                    ) {
                        more.setTrustedRemoteAddress(
                            _getLzChainId(deploymentChainAliases[j]), abi.encodePacked(moreAddress)
                        );
                    }
                }
            }
            _deployERC4626Router();
            vm.stopBroadcast();
        }
    }

    function _getUSTBAddress() internal pure virtual returns (address);

    function _getSwapRouterAddress() internal pure virtual returns (address);

    function _getPearlFactoryAddress() internal pure virtual returns (address);

    function _getQuoterAddress() internal pure virtual returns (address);

    function _getGelatoMessageSender() internal pure virtual returns (address);

    function _getTeamWallet() internal pure virtual returns (address);

    function _getAMO() internal pure virtual returns (address);

    function _getWETH9() internal pure virtual returns (address);

    function _getTangibleRevenueDistributor() internal pure virtual returns (address);

    /**
     * @dev Virtual function to be overridden in derived contracts to provide an array of chain aliases where the MORE
     * token will be deployed. This list is essential for ensuring the deployment and configuration of MORE across
     * multiple networks.
     *
     * Implementations in derived contracts should return an array of strings, each representing a chain alias for
     * deploying the MORE token.
     *
     * @return aliases An array of strings representing the aliases of chains for deployment.
     */
    function _getDeploymentChainAliases() internal pure virtual returns (string[] memory aliases);

    function _deployMore() private returns (address moreProxy) {
        address lzEndpoint = _getLzEndpoint();
        bytes memory bytecode = abi.encodePacked(type(More).creationCode);

        address moreAddress =
            vm.computeCreate2Address(_SALT, keccak256(abi.encodePacked(bytecode, abi.encode(lzEndpoint))));

        More more;

        if (_isDeployed(moreAddress)) {
            console.log("MORE is already deployed to %s", moreAddress);
            more = More(moreAddress);
        } else {
            more = new More{salt: _SALT}(lzEndpoint);
            assert(moreAddress == address(more));
            console.log("MORE deployed to %s", moreAddress);
        }

        bytes memory init = abi.encodeWithSelector(
            More.initialize.selector,
            _deployer // initial minter
        );

        moreProxy = _deployProxy("More", address(more), init);
        _saveDeploymentAddress("MORE", address(moreProxy));
    }

    function _deployMoreStakingVault(address more, string memory chainName, string memory chainSymbol)
        private
        returns (address proxy)
    {
        bytes memory bytecode = abi.encodePacked(type(MoreStakingVault).creationCode);

        address vaultAddress = vm.computeCreate2Address(_SALT, keccak256(abi.encodePacked(bytecode)));

        MoreStakingVault vault;

        if (_isDeployed(vaultAddress)) {
            console.log("sMORE is already deployed to %s", vaultAddress);
            vault = MoreStakingVault(vaultAddress);
        } else {
            vault = new MoreStakingVault{salt: _SALT}();
            assert(vaultAddress == address(vault));
            console.log("sMORE deployed to %s", vaultAddress);
        }

        bytes memory init = abi.encodeWithSelector(MoreStakingVault.initialize.selector, more, chainName, chainSymbol);

        proxy = _deployProxy("MoreStakingVault", address(vault), init);
        _saveDeploymentAddress("sMORE", address(proxy));
    }

    function _deployMoreMinter(address more, address vaultFactoryAddress) private returns (address moreMinterProxy) {
        bytes memory bytecode = abi.encodePacked(type(MoreMinter).creationCode, abi.encode(more));

        address moreMinterAddress = vm.computeCreate2Address(_SALT, keccak256(abi.encodePacked(bytecode)));

        MoreMinter minter;

        if (_isDeployed(moreMinterAddress)) {
            console.log("MORE Minter is already deployed to %s", moreMinterAddress);
            minter = MoreMinter(moreMinterAddress);
        } else {
            minter = new MoreMinter{salt: _SALT}(more);
            assert(moreMinterAddress == address(minter));
            console.log("MORE Minter deployed to %s", moreMinterAddress);
        }

        address amo = _getAMO();
        address team = _getTeamWallet();
        bytes memory init = abi.encodeWithSelector(MoreMinter.initialize.selector, team, vaultFactoryAddress, amo);

        moreMinterProxy = _deployProxy("MoreMinter", address(minter), init);

        minter = MoreMinter(moreMinterProxy);

        if (minter.team() != team) {
            minter.setTeam(team);
        }

        if (minter.vaultFactory() != vaultFactoryAddress) {
            minter.setVaultFactory(vaultFactoryAddress);
        }

        if (minter.amo() != amo) {
            minter.setAMO(amo);
        }

        _saveDeploymentAddress("MoreMinter", address(moreMinterProxy));
    }

    function _deployFeeSplitter(address token, address moreStakingVaultAddress, address[] memory feeReceivers)
        private
        returns (address feeSplitterProxy)
    {
        bytes memory bytecode = abi.encodePacked(type(FeeSplitter).creationCode, abi.encode(token));

        address feeSplitterAddress = vm.computeCreate2Address(_SALT, keccak256(abi.encodePacked(bytecode)));

        FeeSplitter feeSplitter;

        if (_isDeployed(feeSplitterAddress)) {
            console.log("Fee Splitter is already deployed to %s", feeSplitterAddress);
            feeSplitter = FeeSplitter(feeSplitterAddress);
        } else {
            feeSplitter = new FeeSplitter{salt: _SALT}(token);
            assert(feeSplitterAddress == address(feeSplitter));
            console.log("Fee Splitter deployed to %s", feeSplitterAddress);
        }

        bytes memory init = abi.encodeCall(feeSplitter.initialize, ());

        feeSplitterProxy = _deployProxy("FeeSplitter-v2", address(feeSplitter), init);
        _saveDeploymentAddress("FeeSplitter", address(feeSplitterProxy));

        address[] memory receivers = new address[](1 + feeReceivers.length);
        uint96[] memory splits = new uint96[](receivers.length);
        uint96 split = 100 / uint96(receivers.length);

        receivers[0] = moreStakingVaultAddress;
        splits[0] = split;

        for (uint256 i = 0; i < feeReceivers.length; i++) {
            receivers[i + 1] = feeReceivers[i];
            splits[i + 1] = split;
        }

        feeSplitter = FeeSplitter(feeSplitterProxy);

        address distributor = _getGelatoMessageSender();

        if (feeSplitter.distributor() != distributor) {
            feeSplitter.setDistributor(distributor);
        }

        FeeSplitter.FeeReceiver[] memory currentReceivers = feeSplitter.allReceivers();

        bool shouldUpdate = false;
        if (currentReceivers.length != receivers.length) {
            shouldUpdate = true;
        } else {
            for (uint256 i = currentReceivers.length; i != 0;) {
                unchecked {
                    --i;
                }
                if (currentReceivers[i].receiver != receivers[i] || currentReceivers[i].split != splits[i]) {
                    shouldUpdate = true;
                    break;
                }
            }
        }

        if (shouldUpdate) {
            feeSplitter.setReceivers(receivers, splits);
        }
    }

    function _deployMoreOracle(address more) private returns (address moreOracleAddress) {
        bytes memory bytecode = abi.encodePacked(type(StaticPriceOracle).creationCode);

        moreOracleAddress =
            vm.computeCreate2Address(_SALT, keccak256(abi.encodePacked(bytecode, abi.encode(more, 1e18, 18))));

        StaticPriceOracle moreOracle;

        if (_isDeployed(moreOracleAddress)) {
            console.log("MORE Oracle is already deployed to %s", moreOracleAddress);
            moreOracle = StaticPriceOracle(moreOracleAddress);
        } else {
            moreOracle = new StaticPriceOracle{salt: _SALT}(more, 1e18, 18);
            assert(moreOracleAddress == address(moreOracle));
            console.log("MORE Oracle deployed to %s", moreOracleAddress);
        }

        _saveDeploymentAddress("MoreOracle", address(moreOracle));
    }

    function _deployUSTBOracle(address ustb) private returns (address ustbOracleAddress) {
        bytes memory bytecode = abi.encodePacked(type(StaticPriceOracle).creationCode);

        ustbOracleAddress =
            vm.computeCreate2Address(_SALT, keccak256(abi.encodePacked(bytecode, abi.encode(ustb, 1e18, 18))));

        StaticPriceOracle ustbOracle;

        if (_isDeployed(ustbOracleAddress)) {
            console.log("USTB Oracle is already deployed to %s", ustbOracleAddress);
            ustbOracle = StaticPriceOracle(ustbOracleAddress);
        } else {
            ustbOracle = new StaticPriceOracle{salt: _SALT}(ustb, 1e18, 18);
            assert(ustbOracleAddress == address(ustbOracle));
            console.log("USTB Oracle deployed to %s", ustbOracleAddress);
        }

        _saveDeploymentAddress("USTBOracle", address(ustbOracle));
    }

    function _deployOracleWrapper(string memory key, address token, address aggregatorV3)
        private
        returns (address wrappedOracleAddress)
    {
        bytes memory bytecode = abi.encodePacked(type(AggregatorV3Wrapper).creationCode);

        wrappedOracleAddress =
            vm.computeCreate2Address(_SALT, keccak256(abi.encodePacked(bytecode, abi.encode(token, aggregatorV3))));

        AggregatorV3Wrapper wrappedOracle;

        if (_isDeployed(wrappedOracleAddress)) {
            console.log("Wrapped oracle for %s is already deployed to %s", token, wrappedOracleAddress);
            wrappedOracle = AggregatorV3Wrapper(wrappedOracleAddress);
        } else {
            wrappedOracle = new AggregatorV3Wrapper{salt: _SALT}(token, aggregatorV3);
            assert(wrappedOracleAddress == address(wrappedOracle));
            console.log("Wrapped Oracle for %s deployed to %s", wrappedOracleAddress);
        }

        _saveDeploymentAddress(key, address(wrappedOracle));
    }

    function _deployVaultImplementationDeployer() private returns (address vaultImplementationDeployerAddress) {
        bytes memory bytecode = abi.encodePacked(type(VaultImplementationDeployer).creationCode);

        vaultImplementationDeployerAddress = vm.computeCreate2Address(_SALT, keccak256(bytecode));

        VaultImplementationDeployer vaultImplementationDeployer;

        if (_isDeployed(vaultImplementationDeployerAddress)) {
            console.log("Vault Implementation Deployer is already deployed to %s", vaultImplementationDeployerAddress);
            vaultImplementationDeployer = VaultImplementationDeployer(vaultImplementationDeployerAddress);
        } else {
            vaultImplementationDeployer = new VaultImplementationDeployer{salt: _SALT}();
            assert(vaultImplementationDeployerAddress == address(vaultImplementationDeployer));
            console.log("Vault Implementation Deployer deployed to %s", vaultImplementationDeployerAddress);
        }

        _saveDeploymentAddress("VaultImplementationDeployer", vaultImplementationDeployerAddress);
    }

    function _deployVaultDeployer(address vaultFactory, address implementationDeployer)
        private
        returns (address vaultDeployerProxy)
    {
        address weth = _getWETH9();
        bytes memory bytecode =
            abi.encodePacked(type(VaultDeployer).creationCode, abi.encode(weth, vaultFactory, implementationDeployer));

        address vaultDeployerAddress = vm.computeCreate2Address(_SALT, keccak256(bytecode));

        VaultDeployer vaultDeployer;

        if (_isDeployed(vaultDeployerAddress)) {
            console.log("Vault Deployer is already deployed to %s", vaultDeployerAddress);
            vaultDeployer = VaultDeployer(vaultDeployerAddress);
        } else {
            vaultDeployer = new VaultDeployer{salt: _SALT}(weth, vaultFactory, implementationDeployer);
            assert(vaultDeployerAddress == address(vaultDeployer));
            console.log("Vault Deployer deployed to %s", vaultDeployerAddress);
        }

        bytes memory init = abi.encodeWithSelector(VaultDeployer.initialize.selector);

        vaultDeployerProxy = _deployProxy("VaultDeployer", address(vaultDeployer), init);

        _saveDeploymentAddress("VaultDeployer", address(vaultDeployerProxy));
    }

    function _deployVaultFactory(
        address borrowTokenMinter,
        address borrowTokenOracle,
        address vaultDeployer,
        address feeReceiver
    ) private returns (address vaultFactoryProxy) {
        bytes memory bytecode = abi.encodePacked(type(VaultFactory).creationCode);

        address weth = _getWETH9();
        address vaultFactoryAddress =
            vm.computeCreate2Address(_SALT, keccak256(abi.encodePacked(bytecode, abi.encode(weth, borrowTokenMinter))));

        VaultFactory vaultFactory;

        if (_isDeployed(vaultFactoryAddress)) {
            console.log("Vault Factory is already deployed to %s", vaultFactoryAddress);
            vaultFactory = VaultFactory(vaultFactoryAddress);
        } else {
            vaultFactory = new VaultFactory{salt: _SALT}(weth, borrowTokenMinter);
            assert(vaultFactoryAddress == address(vaultFactory));
            console.log("Vault Factory deployed to %s", vaultFactoryAddress);
        }

        address penaltyReceiver = _getTeamWallet();
        bytes memory init = abi.encodeWithSelector(
            VaultFactory.initialize.selector, vaultDeployer, borrowTokenOracle, feeReceiver, penaltyReceiver
        );

        vaultFactoryProxy = _deployProxy(VAULT_FACTORY_KEY, address(vaultFactory), init);
        vaultFactory = VaultFactory(vaultFactoryProxy);

        _saveDeploymentAddress("VaultFactory", address(vaultFactoryProxy));

        if (vaultFactory.interestRateManager() != _getGelatoMessageSender()) {
            vaultFactory.setInterestRateManager(_getGelatoMessageSender());
        }

        if (vaultFactory.vaultDeployer() != vaultDeployer) {
            vaultFactory.setVaultDeployer(vaultDeployer);
        }

        if (vaultFactory.borrowTokenOracle() != borrowTokenOracle) {
            vaultFactory.setBorrowTokenOracle(borrowTokenOracle);
        }

        if (vaultFactory.vaultDeployer() != vaultDeployer) {
            vaultFactory.setVaultDeployer(vaultDeployer);
        }
    }

    function _deployPearlRouter() private returns (address pearlRouterProxy) {
        bytes memory bytecode = type(PearlRouter).creationCode;

        address pearlRouterAddress = vm.computeCreate2Address(_SALT, keccak256(bytecode));
        address swapRouterAddress = _getSwapRouterAddress();
        address quoterAddress = _getQuoterAddress();

        PearlRouter pearlRouter;

        if (_isDeployed(pearlRouterAddress)) {
            console.log("Pearl Router is already deployed to %s", pearlRouterAddress);
            pearlRouter = PearlRouter(pearlRouterAddress);
        } else {
            pearlRouter = new PearlRouter{salt: _SALT}();
            assert(pearlRouterAddress == address(pearlRouter));
            console.log("Pearl Router deployed to %s", pearlRouterAddress);
        }

        bytes memory init = abi.encodeCall(PearlRouter.initialize, (swapRouterAddress, quoterAddress));

        pearlRouterProxy = _deployProxy("PearlRouter", address(pearlRouter), init);
        pearlRouter = PearlRouter(pearlRouterProxy);

        _saveDeploymentAddress("PearlRouter", address(pearlRouterProxy));

        if (pearlRouter.getSwapRouter() != swapRouterAddress) {
            pearlRouter.setSwapRouter(swapRouterAddress);
        }
        if (pearlRouter.getQuoter() != quoterAddress) {
            pearlRouter.setQuoter(quoterAddress);
        }

        _deployPearlRouteFinder(pearlRouterProxy);
    }

    function _deployPearlRouteFinder(address router) private returns (address pearlRouterProxy) {
        address factory = _getPearlFactoryAddress();
        bytes memory bytecode = abi.encodePacked(type(PearlRouteFinder).creationCode, abi.encode(factory, router));

        address pearlRouteFinderAddress = vm.computeCreate2Address(_SALT, keccak256(bytecode));

        PearlRouteFinder pearlRouteFinder;

        if (_isDeployed(pearlRouteFinderAddress)) {
            console.log("Pearl Route Finder is already deployed to %s", pearlRouteFinderAddress);
            pearlRouteFinder = PearlRouteFinder(pearlRouteFinderAddress);
        } else {
            pearlRouteFinder = new PearlRouteFinder{salt: _SALT}(factory, router);
            assert(pearlRouteFinderAddress == address(pearlRouteFinder));
            console.log("Pearl Route Finder deployed to %s", pearlRouteFinderAddress);
        }

        _saveDeploymentAddress("PearlRouteFinder", address(pearlRouteFinder));
    }

    function _deployERC4626Router() private returns (address erc4626RouterAddress) {
        bytes memory bytecode = abi.encodePacked(type(ERC4626Router).creationCode);

        erc4626RouterAddress = vm.computeCreate2Address(_SALT, keccak256(bytecode));

        ERC4626Router erc4626Router;

        if (_isDeployed(erc4626RouterAddress)) {
            console.log("ERC4626 Router is already deployed to %s", erc4626RouterAddress);
            erc4626Router = ERC4626Router(erc4626RouterAddress);
        } else {
            erc4626Router = new ERC4626Router{salt: _SALT}();
            assert(erc4626RouterAddress == address(erc4626Router));
            console.log("ERC4626 Router deployed to %s", erc4626RouterAddress);
        }

        _saveDeploymentAddress("ERC4626Router", address(erc4626Router));
    }

    /**
     * @dev Retrieves the LayerZero chain ID for a given chain alias. This function is essential for setting up
     * cross-chain communication parameters in the deployment process.
     *
     * The function maps common chain aliases to their respective LayerZero chain IDs. This mapping is crucial for
     * identifying the correct LayerZero endpoint for each chain involved in the deployment.
     *
     * @param chainAlias The alias of the chain for which the LayerZero chain ID is required.
     * @return The LayerZero chain ID corresponding to the given chain alias.
     * Reverts with 'Unsupported chain' if the alias does not match any known chains.
     */
    function _getLzChainId(string memory chainAlias) internal pure returns (uint16) {
        bytes32 chain = keccak256(abi.encodePacked(chainAlias));
        if (chain == keccak256("mainnet")) {
            return 101;
        } else if (chain == keccak256("bnb_smart_chain")) {
            return 102;
        } else if (chain == keccak256("polygon")) {
            return 109;
        } else if (chain == keccak256("arbitrum_one")) {
            return 110;
        } else if (chain == keccak256("optimism")) {
            return 111;
        } else if (chain == keccak256("base")) {
            return 184;
            //} else if (chain == keccak256("real")) {
            //    return 0;
        } else if (chain == keccak256("goerli")) {
            return 10121;
        } else if (chain == keccak256("sepolia")) {
            return 10161;
        } else if (chain == keccak256("polygon_mumbai")) {
            return 10109;
        } else if (chain == keccak256("unreal")) {
            return 10252;
        } else {
            revert("Unsupported chain");
        }
    }

    function _getLzEndpoint() internal returns (address lzEndpoint) {
        lzEndpoint = _getLzEndpoint(block.chainid);
    }

    /**
     * @dev Overloaded version of `_getLzEndpoint` that retrieves the LayerZero endpoint address for a specified chain
     * ID. This variation allows for more flexibility in targeting specific chains during the deployment process.
     *
     * @param chainId The chain ID for which the LayerZero endpoint address is required.
     * @return lzEndpoint The LayerZero endpoint address for the specified chain ID. Reverts with an error if the chain
     * ID does not have a defined endpoint.
     */
    function _getLzEndpoint(uint256 chainId) internal returns (address lzEndpoint) {
        if (chainId == getChain("mainnet").chainId) {
            lzEndpoint = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;
        } else if (chainId == getChain("bnb_smart_chain").chainId) {
            lzEndpoint = 0x3c2269811836af69497E5F486A85D7316753cf62;
        } else if (chainId == getChain("polygon").chainId) {
            lzEndpoint = 0x3c2269811836af69497E5F486A85D7316753cf62;
        } else if (chainId == getChain("arbitrum_one").chainId) {
            lzEndpoint = 0x3c2269811836af69497E5F486A85D7316753cf62;
        } else if (chainId == getChain("optimism").chainId) {
            lzEndpoint = 0x3c2269811836af69497E5F486A85D7316753cf62;
        } else if (chainId == getChain("base").chainId) {
            lzEndpoint = 0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7;
            //} else if (chainId == getChain("real").chainId) {
            //    lzEndpoint = address(0);
        } else if (chainId == getChain("goerli").chainId) {
            lzEndpoint = 0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23;
        } else if (chainId == getChain("sepolia").chainId) {
            lzEndpoint = 0xae92d5aD7583AD66E49A0c67BAd18F6ba52dDDc1;
        } else if (chainId == getChain("polygon_mumbai").chainId) {
            lzEndpoint = 0xf69186dfBa60DdB133E91E9A4B5673624293d8F8;
        } else if (chainId == getChain("unreal").chainId) {
            lzEndpoint = 0x2cA20802fd1Fd9649bA8Aa7E50F0C82b479f35fe;
        } else {
            revert("No LayerZero endpoint defined for this chain.");
        }
    }
}
