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
import {InterestRateOracle} from "../../src/oracles/InterestRateOracle.sol";
import {CappedPriceOracle} from "../../src/oracles/CappedPriceOracle.sol";
import {StaticPriceOracle} from "../../src/oracles/StaticPriceOracle.sol";
import {StackVault} from "../../src/vaults/StackVault.sol";
import {AggregatorV3Wrapper} from "../../src/oracles/AggregatorV3Wrapper.sol";
import {PearlRouter} from "../../src/periphery/PearlRouter.sol";
import {PearlRouteFinder} from "../../src/periphery/PearlRouteFinder.sol";
import {ERC4626Router} from "../../src/periphery/ERC4626Router.sol";
import {ArcanaTokenConverter} from "../../src/periphery/converters/ArcanaTokenConverter.sol";
import {StackOracle} from "../../src/oracles/StackOracle.sol";
import {PoolToken0Oracle} from "../../src/oracles/PoolToken0Oracle.sol";
import {StackVaultTransfers} from "../../src/vaults/StackVaultTransfers.sol";

abstract contract DeployAllBase is PearlDeploymentScript {
    address constant ORACLE_HEARTBEAT_SENDER = 0xB805DfAD40ACA12C88F64f903275E3Bb1DcAE463;
    address constant ORACLE_UPDATER = 0xAC0926290232D07eD8b083F6BE3Ab040010f757F;

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
            require(moreAddress < _getUSTBAddress(), "Invalid MORE address (use a different salt)");
            address moreStakingVault = _deployMoreStakingVault(moreAddress, _chain.name, _chain.chainAlias);
            More more = More(moreAddress);
            (address vaultFactoryAddress,) = _computeProxyAddress("VaultFactory");
            console.log("Predicted vault factory address: %s", vaultFactoryAddress);
            address moreMinter = _deployMoreMinter(address(more), vaultFactoryAddress);
            if (more.minter() != moreMinter) {
                more.setMinter(moreMinter);
            }

            //address arcUSDOracle = _deployStackOracle("arcUSDOracle", "arcUSD/USD", "arcUSD/USD Oracle");
            //_deployOracleWrapper("arcUSDOracleWrapper", _getUSDaAddress(), arcUSDOracle);

            if (_chain.chainId == getChain("bnb_smart_chain").chainId) {
                address usdt = 0x55d398326f99059fF775485246999027B3197955;
                address usdtOracle = 0xB97Ad0E74fa7d920791E90258A6E2085088b4320;
                _deployOracleWrapper("USDTOracleWrapper", usdt, usdtOracle);
                address moreUsdtPool = 0x8540CF27FF440E2f53A13819c4788578658f6F83;
                address morePoolOracle =
                    _deployPoolToken0Oracle("MOREOracle", "MORE/USD", "MORE/USD Oracle", moreUsdtPool, usdtOracle);
                _deployOracleWrapper("MOREOracleWrapper", address(more), morePoolOracle);
            }

            if (_chain.chainId == getChain("scroll").chainId) {
                address usdc = 0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
                address usdcOracle = 0x43d12Fb3AfCAd5347fA764EeAB105478337b7200;
                _deployOracleWrapper("USDCOracleWrapper", usdc, usdcOracle);
                /*
                address moreUsdcPool = ;
                address morePoolOracle =
                _deployPoolToken0Oracle("MOREOracle", "MORE/USD", "MORE/USD Oracle", moreUsdcPool, usdcOracle);
                _deployOracleWrapper("MOREOracleWrapper", address(more), morePoolOracle);
                */
            }

            if (_chain.chainId == getChain("blast").chainId) {
                address usdb = 0x4300000000000000000000000000000000000003;
                address usdbOracle = 0x3A236F67Fce401D87D7215695235e201966576E4;
                _deployOracleWrapper("USDBOracleWrapper", usdb, usdbOracle);
                /*
                address moreUsdbPool = ;
                address morePoolOracle =
                _deployPoolToken0Oracle("MOREOracle", "MORE/USD", "MORE/USD Oracle", moreUsdbPool, usdbOracle);
                _deployOracleWrapper("MOREOracleWrapper", address(more), morePoolOracle);
                */
            }

            if (!isTokenOnlyChain(_chain.chainId)) {
                address[] memory feeReceivers;
                if (_chain.chainId == getChain("unreal").chainId || _chain.chainId == getChain("real").chainId) {
                    feeReceivers = new address[](1);
                    feeReceivers[0] = _getTangibleRevenueDistributor();
                } else {
                    feeReceivers = new address[](1);
                    feeReceivers[0] = _getGelatoMessageSender();
                }
                _deployInterestRateOracle("USTBInterestRateOracle", _getUSTBAddress(), 0.05e18);

                if (_chain.chainId == getChain("unreal").chainId || _chain.chainId == getChain("real").chainId) {
                    _deployInterestRateOracle("DAIInterestRateOracle", _getDAI(), 0);
                }
                address feeSplitter = _deployFeeSplitter(address(more), moreStakingVault, feeReceivers);

                address moreOracle = _deployStaticOracle("StaticMOREOracle", address(more), 1e18);
                _deployStaticOracle("StaticUSTBOracle", _getUSTBAddress(), 1e18);

                // TODO: remove condition when oracles have been deployed on all chains
                if (_chain.chainId == getChain("unreal").chainId || _chain.chainId == getChain("real").chainId) {
                    _deployOracleWrapper("DAIOracleWrapper", _getDAI(), _getDAIOracle());
                    _deployOracleWrapper("ETHOracleWrapper", _getWETH9(), _getETHOracle());
                    _deployOracleWrapper("USDAOracleWrapper", _getUSDaAddress(), _getUSDAOracle());
                    _deployOracleWrapper("USTBOracleWrapper", _getUSTBAddress(), _getUSTBOracle());
                    //_deployOracleWrapper("UKREOracleWrapper", _getUKREAddress(), _getUKREOracle());
                }

                address moreOracleWrapper = _deployOracleWrapper("MOREOracleWrapper", address(more), _getMOREOracle());
                moreOracle = _deployCappedOracle("CappedMOREOracle", moreOracleWrapper, 1e18);

                address implementationDeployer = _deployVaultImplementationDeployer();
                address transferHelper = _deployTransferHelper();
                address vaultDeployer =
                    _deployVaultDeployer(vaultFactoryAddress, implementationDeployer, transferHelper);
                address vaultFactory = _deployVaultFactory(moreMinter, moreOracle, vaultDeployer, feeSplitter);
                address pearlRouter = _deployPearlRouter();

                assert(vaultFactoryAddress == vaultFactory);

                if (!VaultFactory(vaultFactory).isTrustedSwapTarget(pearlRouter)) {
                    VaultFactory(vaultFactory).setTrustedSwapTarget(pearlRouter, true);
                }

                _deployERC4626Router();
            }

            for (uint256 j = 0; j < deploymentChainAliases.length; j++) {
                if (i != j) {
                    if (
                        !more.isTrustedRemote(
                            _getLzChainId(deploymentChainAliases[j]), abi.encodePacked(moreAddress, moreAddress)
                        )
                    ) {
                        if (more.owner() == _deployer) {
                            more.setTrustedRemoteAddress(
                                _getLzChainId(deploymentChainAliases[j]), abi.encodePacked(moreAddress)
                            );
                        } else {
                            emit ExecuteOnMultisig(
                                _chain.chainAlias,
                                address(more),
                                abi.encodeCall(
                                    more.setTrustedRemoteAddress,
                                    (_getLzChainId(deploymentChainAliases[j]), abi.encodePacked(moreAddress))
                                ),
                                "set trusted remote address"
                            );
                        }
                    }
                }
            }
            vm.stopBroadcast();
        }
    }

    function isTokenOnlyChain(uint256 chainId) internal returns (bool) {
        return chainId == getChain("bnb_smart_chain").chainId || chainId == getChain("blast").chainId
            || chainId == getChain("scroll").chainId;
    }

    function _getUSTBAddress() internal pure virtual returns (address);

    function _getUKREAddress() internal virtual returns (address);

    function _getUSDaAddress() internal virtual returns (address);

    function _getPTaAddress() internal virtual returns (address);

    function _getSwapRouterAddress() internal pure virtual returns (address);

    function _getPearlFactoryAddress() internal pure virtual returns (address);

    function _getQuoterAddress() internal pure virtual returns (address);

    function _getGelatoMessageSender() internal pure virtual returns (address);

    function _getTeamWallet() internal virtual returns (address);

    function _getDAI() internal virtual returns (address);

    function _getWETH9() internal virtual returns (address);

    function _getTangibleRevenueDistributor() internal pure virtual returns (address);

    function _getDAIOracle() internal virtual returns (address);

    function _getETHOracle() internal virtual returns (address);

    function _getMOREOracle() internal virtual returns (address);

    function _getUKREOracle() internal virtual returns (address);

    function _getUSDAOracle() internal virtual returns (address);

    function _getUSTBOracle() internal virtual returns (address);

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

        moreProxy = _deployProxy("MORE", address(more), init);
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

        proxy = _deployProxy("sMORE", address(vault), init);
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

        address team = _getTeamWallet();
        bytes memory init = abi.encodeWithSelector(MoreMinter.initialize.selector, team, vaultFactoryAddress);

        string memory forContract = "MoreMinter";
        if (block.chainid == getChain("bnb_smart_chain").chainId) {
            forContract = "MoreMinterBNB";
        }
        moreMinterProxy = _deployProxy(forContract, address(minter), init);

        minter = MoreMinter(moreMinterProxy);

        if (minter.team() != team) {
            minter.setTeam(team);
        }

        if (minter.vaultFactory() != vaultFactoryAddress) {
            minter.setVaultFactory(vaultFactoryAddress);
        }

        // if (minter.amo() != amo) {
        //     minter.setAMO(amo);
        // }
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

        feeSplitterProxy = _deployProxy("FeeSplitter", address(feeSplitter), init);

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

    function _deployInterestRateOracle(string memory key, address token, uint256 initialAPR)
        private
        returns (address interestRateOracleAddress)
    {
        bytes memory bytecode = abi.encodePacked(type(InterestRateOracle).creationCode);

        interestRateOracleAddress = vm.computeCreate2Address(
            _SALT,
            keccak256(abi.encodePacked(bytecode, abi.encode(token, _deployer, _getGelatoMessageSender(), initialAPR)))
        );

        InterestRateOracle interestRateOracle;

        if (_isDeployed(interestRateOracleAddress)) {
            console.log("Interest Rate Oracle (%s) is already deployed to %s", key, interestRateOracleAddress);
            interestRateOracle = InterestRateOracle(interestRateOracleAddress);
        } else {
            interestRateOracle =
                new InterestRateOracle{salt: _SALT}(token, _deployer, _getGelatoMessageSender(), initialAPR);
            assert(interestRateOracleAddress == address(interestRateOracle));
            console.log("Interest Rate Oracle (%s) deployed to %s", key, interestRateOracleAddress);
        }

        _saveDeploymentAddress(key, address(interestRateOracle));
    }

    function _deployCappedOracle(string memory key, address underlyingOracle, uint256 priceCap)
        private
        returns (address cappedOracleAddress)
    {
        bytes memory bytecode = abi.encodePacked(type(CappedPriceOracle).creationCode);

        cappedOracleAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(bytecode, abi.encode(underlyingOracle, priceCap)))
        );

        CappedPriceOracle cappedOracle;

        if (_isDeployed(cappedOracleAddress)) {
            console.log("Capped Oracle (%s) is already deployed to %s", key, cappedOracleAddress);
            cappedOracle = CappedPriceOracle(cappedOracleAddress);
        } else {
            cappedOracle = new CappedPriceOracle{salt: _SALT}(underlyingOracle, priceCap);
            assert(cappedOracleAddress == address(cappedOracle));
            console.log("Capped Oracle (%s) deployed to %s", key, cappedOracleAddress);
        }

        _saveDeploymentAddress(key, address(cappedOracle));
    }

    function _deployStaticOracle(string memory key, address token, uint256 price)
        private
        returns (address staticOracleAddress)
    {
        bytes memory bytecode = abi.encodePacked(type(StaticPriceOracle).creationCode);

        staticOracleAddress =
            vm.computeCreate2Address(_SALT, keccak256(abi.encodePacked(bytecode, abi.encode(token, price, 18))));

        StaticPriceOracle staticOracle;

        if (_isDeployed(staticOracleAddress)) {
            console.log("Static Oracle (%s) is already deployed to %s", key, staticOracleAddress);
            staticOracle = StaticPriceOracle(staticOracleAddress);
        } else {
            staticOracle = new StaticPriceOracle{salt: _SALT}(token, price, 18);
            assert(staticOracleAddress == address(staticOracle));
            console.log("Static Oracle (%s) deployed to %s", key, staticOracleAddress);
        }

        _saveDeploymentAddress(key, address(staticOracle));
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
            console.log("Wrapped oracle (%s) for %s is already deployed to %s", key, token, wrappedOracleAddress);
            wrappedOracle = AggregatorV3Wrapper(wrappedOracleAddress);
        } else {
            wrappedOracle = new AggregatorV3Wrapper{salt: _SALT}(token, aggregatorV3);
            assert(wrappedOracleAddress == address(wrappedOracle));
            console.log("Wrapped Oracle (%s) for %s deployed to %s", key, token, wrappedOracleAddress);
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

    function _deployTransferHelper() private returns (address transferHelperAddress) {
        bytes memory bytecode = abi.encodePacked(type(StackVaultTransfers).creationCode);

        transferHelperAddress = vm.computeCreate2Address(_SALT, keccak256(bytecode));

        StackVaultTransfers transferHelper;

        if (_isDeployed(transferHelperAddress)) {
            console.log("Transfer Helper is already deployed to %s", transferHelperAddress);
            transferHelper = StackVaultTransfers(transferHelperAddress);
        } else {
            transferHelper = new StackVaultTransfers{salt: _SALT}();
            assert(transferHelperAddress == address(transferHelper));
            console.log("Transfer Helper deployed to %s", transferHelperAddress);
        }

        _saveDeploymentAddress("StackVaultTransfers", transferHelperAddress);
    }

    function _deployVaultDeployer(address vaultFactory, address implementationDeployer, address transferHelper)
        private
        returns (address vaultDeployerProxy)
    {
        address weth = _getWETH9();
        bytes memory bytecode = abi.encodePacked(
            type(VaultDeployer).creationCode, abi.encode(weth, vaultFactory, implementationDeployer, transferHelper)
        );

        address vaultDeployerAddress = vm.computeCreate2Address(_SALT, keccak256(bytecode));

        VaultDeployer vaultDeployer;

        if (_isDeployed(vaultDeployerAddress)) {
            console.log("Vault Deployer is already deployed to %s", vaultDeployerAddress);
            vaultDeployer = VaultDeployer(vaultDeployerAddress);
        } else {
            vaultDeployer = new VaultDeployer{salt: _SALT}(weth, vaultFactory, implementationDeployer, transferHelper);
            assert(vaultDeployerAddress == address(vaultDeployer));
            console.log("Vault Deployer deployed to %s", vaultDeployerAddress);
        }

        bytes memory init = abi.encodeWithSelector(VaultDeployer.initialize.selector);

        vaultDeployerProxy = _deployProxy("VaultDeployer", address(vaultDeployer), init);
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

        vaultFactoryProxy = _deployProxy("VaultFactory", address(vaultFactory), init);
        vaultFactory = VaultFactory(vaultFactoryProxy);

        if (vaultFactory.interestRateManager() != _getGelatoMessageSender()) {
            console.log("Setting interest rate manager to %s", _getGelatoMessageSender());
            vaultFactory.setInterestRateManager(_getGelatoMessageSender());
        }

        if (vaultFactory.vaultDeployer() != vaultDeployer) {
            console.log("Setting vault deployer to %s", vaultDeployer);
            vaultFactory.setVaultDeployer(vaultDeployer);
        }

        if (vaultFactory.borrowTokenOracle() != borrowTokenOracle) {
            console.log("Setting borrow token oracle to %s", borrowTokenOracle);
            vaultFactory.setBorrowTokenOracle(borrowTokenOracle);
        }

        if (vaultFactory.vaultDeployer() != vaultDeployer) {
            console.log("Setting vault deployer to %s", vaultDeployer);
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

        if (pearlRouter.getSwapRouter() != swapRouterAddress) {
            pearlRouter.setSwapRouter(swapRouterAddress);
        }
        if (pearlRouter.getQuoter() != quoterAddress) {
            pearlRouter.setQuoter(quoterAddress);
        }

        _deployPearlRouteFinder(pearlRouterProxy);
        _deployTokenConverters(pearlRouter);
    }

    function _deployPearlRouteFinder(address router) private returns (address pearlRouteFinderAddress) {
        address factory = _getPearlFactoryAddress();
        bytes memory bytecode = abi.encodePacked(type(PearlRouteFinder).creationCode, abi.encode(factory, router));

        pearlRouteFinderAddress = vm.computeCreate2Address(_SALT, keccak256(bytecode));

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

    function _deployTokenConverters(PearlRouter router) private {
        address arcanaTokenConverter = _deployArcanaTokenConverter();
        address usda = _getUSDaAddress();
        address pta = _getPTaAddress();
        if (router.getTokenConverter(usda) != arcanaTokenConverter) {
            router.setTokenConverter(usda, arcanaTokenConverter);
        }
        if (router.getTokenConverter(pta) != arcanaTokenConverter) {
            router.setTokenConverter(pta, arcanaTokenConverter);
        }
    }

    function _deployArcanaTokenConverter() private returns (address arcanaTokenConverterAddress) {
        address usda = _getUSDaAddress();
        address pta = _getPTaAddress();
        bytes memory bytecode = abi.encodePacked(type(ArcanaTokenConverter).creationCode, abi.encode(usda, pta));

        arcanaTokenConverterAddress = vm.computeCreate2Address(_SALT, keccak256(bytecode));

        ArcanaTokenConverter arcanaTokenConverter;

        if (_isDeployed(arcanaTokenConverterAddress)) {
            console.log("Arcana Token Converter is already deployed to %s", arcanaTokenConverterAddress);
            arcanaTokenConverter = ArcanaTokenConverter(arcanaTokenConverterAddress);
        } else {
            arcanaTokenConverter = new ArcanaTokenConverter{salt: _SALT}(usda, pta);
            assert(arcanaTokenConverterAddress == address(arcanaTokenConverter));
            console.log("Arcana Token Converter deployed to %s", arcanaTokenConverterAddress);
        }

        _saveDeploymentAddress("ArcanaTokenConverter", address(arcanaTokenConverter));
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

    function _deployStackOracle(string memory storageKey, string memory pairKey, string memory description)
        private
        returns (address oracleAddress)
    {
        bytes memory bytecode =
            abi.encodePacked(type(StackOracle).creationCode, abi.encode(_deployer, 1e8, description, pairKey));

        oracleAddress = vm.computeCreate2Address(_SALT, keccak256(bytecode));

        StackOracle oracle;

        if (_isDeployed(oracleAddress)) {
            console.log("%s is already deployed to %s", description, oracleAddress);
            oracle = StackOracle(oracleAddress);
        } else {
            oracle = new StackOracle{salt: _SALT}(_deployer, 1e8, description, pairKey);
            assert(oracleAddress == address(oracle));
            console.log("%s deployed to %s", description, oracleAddress);
        }

        if (oracle.heartbeatSender() != ORACLE_HEARTBEAT_SENDER) {
            oracle.updateHeartbeatSenderAddress(ORACLE_HEARTBEAT_SENDER);
        }

        if (oracle.oracleUpdater() != ORACLE_UPDATER) {
            oracle.updateOracleUpdaterAddress(ORACLE_UPDATER);
        }

        if (keccak256(abi.encodePacked(oracle.pairKey())) != keccak256(abi.encodePacked(pairKey))) {
            oracle.setPairKey(pairKey);
        }

        if (keccak256(abi.encodePacked(oracle.description())) != keccak256(abi.encodePacked(description))) {
            oracle.setDescription(description);
        }

        _saveDeploymentAddress(storageKey, address(oracle));
    }

    function _deployPoolToken0Oracle(
        string memory storageKey,
        string memory pairKey,
        string memory description,
        address poolAddress,
        address token1Oracle
    ) private returns (address oracleAddress) {
        bytes memory bytecode = abi.encodePacked(
            type(PoolToken0Oracle).creationCode, abi.encode(_deployer, description, pairKey, poolAddress, token1Oracle)
        );

        oracleAddress = vm.computeCreate2Address(_SALT, keccak256(bytecode));

        PoolToken0Oracle oracle;

        if (_isDeployed(oracleAddress)) {
            console.log("%s is already deployed to %s", description, oracleAddress);
            oracle = PoolToken0Oracle(oracleAddress);
        } else {
            oracle = new PoolToken0Oracle{salt: _SALT}(_deployer, description, pairKey, poolAddress, token1Oracle);
            assert(oracleAddress == address(oracle));
            console.log("%s deployed to %s", description, oracleAddress);
        }

        if (keccak256(abi.encodePacked(oracle.pairKey())) != keccak256(abi.encodePacked(pairKey))) {
            oracle.setPairKey(pairKey);
        }

        if (keccak256(abi.encodePacked(oracle.description())) != keccak256(abi.encodePacked(description))) {
            oracle.setDescription(description);
        }

        _saveDeploymentAddress(storageKey, address(oracle));
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
        } else if (chain == keccak256("real")) {
            return 237;
        } else if (chain == keccak256("scroll")) {
            return 214;
        } else if (chain == keccak256("blast")) {
            return 243;
        } else if (chain == keccak256("goerli")) {
            return 10121;
        } else if (chain == keccak256("sepolia")) {
            return 10161;
        } else if (chain == keccak256("polygon_mumbai")) {
            return 10109;
        } else if (chain == keccak256("unreal")) {
            return 10262;
        } else {
            revert("Unsupported LZ chain");
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
        } else if (chainId == getChain("real").chainId) {
            lzEndpoint = 0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7;
        } else if (chainId == getChain("scroll").chainId) {
            lzEndpoint = 0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7;
        } else if (chainId == getChain("blast").chainId) {
            lzEndpoint = 0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7;
        } else if (chainId == getChain("goerli").chainId) {
            lzEndpoint = 0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23;
        } else if (chainId == getChain("sepolia").chainId) {
            lzEndpoint = 0xae92d5aD7583AD66E49A0c67BAd18F6ba52dDDc1;
        } else if (chainId == getChain("polygon_mumbai").chainId) {
            lzEndpoint = 0xf69186dfBa60DdB133E91E9A4B5673624293d8F8;
        } else if (chainId == getChain("unreal").chainId) {
            lzEndpoint = 0x83c73Da98cf733B03315aFa8758834b36a195b87;
        } else {
            revert("No LayerZero endpoint defined for this chain.");
        }
    }
}
