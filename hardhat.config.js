require("@nomicfoundation/hardhat-toolbox");
require("hardhat-contract-sizer");
require("@openzeppelin/hardhat-upgrades");

require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    bscTestnet: {
      url: process.env.BSC_TESTNET_RPC, // Use the correct RPC URL
      accounts: [process.env.BSC_TESTNET_PRIVATE_KEY], // Use the correct private key
    },

    bscmainnet: {
      url: "https://bsc-dataseed1.binance.org/",
      accounts: [process.env.BSC_MAINNET_PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: process.env.BSCSCAN_API_KEY, // BSCScan API key
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: true,
    only: ["contracts/"], // Adjust if needed
  },
  allowUnlimitedContractSize: true,
  sourcify: {
    enabled: true,
  },
};
