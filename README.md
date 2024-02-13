# Stack CDP System

## Overview

The "Stack" project is a decentralized finance (DeFi) solution offering a Collateralized Debt Position (CDP) system. It enables users to lock up collateral in exchange for the MORE token, a stablecoin, allowing them to manage debt while leveraging their assets. Additionally, "Stack" provides a feature for users to earn rewards by depositing tokens.

## Features

- **CDP Management**: Create and manage your collateralized debt positions efficiently, utilizing your assets to generate MORE tokens.
- **Deposit for Rewards**: Deposit tokens to earn rewards, following the ERC-4626 standard for tokenized vaults.

## Technical Requirements

- [Foundry](https://getfoundry.sh/) for smart contract testing and deployment. Ensure you have Foundry installed and updated to the latest version for compiling and testing the smart contracts.

## Installation

To set up the project locally, follow these steps:

1. Clone the repository:

   ```bash
   git clone https://github.com/yourusername/stack-main.git
   cd stack-main
   ```

2. Install the specific commit of Foundry that is known to work well with the project:

   ```bash
   foundryup -C 05d60629f9a9c328763179204772562bea4cef40
   ```

3. Install Solidity dependencies using Foundry:

   ```bash
   forge install
   ```

## Deploying Contracts

Deployment is managed through Foundry scripts, specifically `DeployAllTestnet.s.sol` for testnet (and similarly for mainnet) environments. To deploy:

1. Review and update external contract addresses within the script as necessary, ensuring they point to the correct addresses for your deployment environment.
2. Execute the deployment script with Foundry, adjusting the command based on your target network and deployment preferences:

   ```bash
   forge script ./script/DeployAllTestnet.s.sol --legacy --sig "deployOnMainChain()" --rpc-url <YOUR_RPC_URL> --broadcast --sender <YOUR_DEPLOYER_ADDRESS> --verify --verifier blockscout --verifier-url "https://<BLOCKSCOUT_API_URL>"
   ```

   Replace `<YOUR_RPC_URL>`, `<YOUR_DEPLOYER_ADDRESS>`, and `https://<BLOCKSCOUT_API_URL>` with the appropriate values for your deployment.

## Testing

Run the included test suite with Foundry to ensure the contracts function as expected:

```bash
forge test
```

## License

This project is licensed under [MIT License](LICENSE).
