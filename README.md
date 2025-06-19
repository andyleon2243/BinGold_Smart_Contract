# BinGold Smart Contract

A comprehensive smart contract system for the BinGold token, featuring upgradeable contracts, vesting mechanisms, and meta-transaction support.

## Overview

BinGold is an ERC20 token built on the Binance Smart Chain (BSC) with advanced features including:

- **Upgradeable Contracts**: Using OpenZeppelin's proxy pattern
- **Token Vesting**: Controlled token distribution over time
- **Meta Transactions**: Gasless transaction support
- **Asset Protection**: Freeze/unfreeze functionality
- **Supply Control**: Minting and burning capabilities
- **Fee Management**: Configurable fee system

## Contract Architecture

### Core Contracts

- **`BinGoldToken.sol`** - Main ERC20 token implementation with upgradeable proxy
- **`BinGoldVesting.sol`** - Token vesting contract for controlled distribution
- **`IBinGold.sol`** - Interface for BinGold token functions
- **`BasicMetaTransaction.sol`** - Meta-transaction support
- **`OwnedUpgradeabilityProxy.sol`** - Proxy contract for upgradeability

### Key Features

- **Token Details**:

  - Name: BinGold Token
  - Symbol: BIGOD
  - Decimals: 6
  - Max Supply: 2,500,000 tokens

- **Upgradeable**: Contracts can be upgraded while preserving state
- **Pausable**: Emergency pause functionality
- **Asset Protection**: Address freezing capabilities
- **Supply Control**: Controlled minting and burning
- **Fee System**: Configurable fee rates and recipients

## Prerequisites

- Node.js (v16 or higher)
- npm or yarn
- Hardhat
- MetaMask or similar wallet

## Installation

1. Clone the repository:

```bash
git clone <repository-url>
cd BinGold_Smart_Contract
```

2. Install dependencies:

```bash
npm install
```

3. Create environment file:

```bash
cp .env.example .env
```

4. Configure your environment variables in `.env`:

```bash
BSC_TESTNET_RPC=your_bsc_testnet_rpc_url
BSC_TESTNET_PRIVATE_KEY=your_private_key
```

## Development

### Compile Contracts

```bash
npx hardhat compile
```

### Run Tests

```bash
npx hardhat test
```

### Local Development

```bash
npx hardhat node
npx hardhat run scripts/deploy.js --network localhost
```


## Project Structure

```
├── contracts/           # Smart contracts
│   ├── BinGold.sol     # Main token contract
│   ├── BinGoldVesting.sol # Vesting contract
│   ├── IBinGold.sol    # Interface
│   ├── BasicMetaTransaction.sol # Meta-transaction support
│   └── OwnedUpgradeabilityProxy.sol # Proxy contract
├── scripts/            # Deployment scripts
│   └── deploy.js       # Main deployment script
├── test/              # Test files
│   └── Vesting.js     # Vesting contract tests
├── hardhat.config.js  # Hardhat configuration
└── package.json       # Dependencies
```

## Security Features

- **Upgradeable Proxy Pattern**: Allows contract upgrades while preserving state
- **Access Control**: Role-based permissions for different functions
- **Asset Protection**: Emergency freeze functionality
- **Pausable**: Emergency pause mechanism
- **Supply Control**: Controlled minting and burning

## Testing

The project includes comprehensive tests for the vesting functionality. Run tests with:

```bash
npx hardhat test
```

## License

This project is licensed under the ISC License.

## Support

For questions and support, please refer to the project documentation or create an issue in the repository.

---

