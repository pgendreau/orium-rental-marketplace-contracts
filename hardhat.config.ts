import * as dotenv from 'dotenv'
import 'solidity-coverage'
import 'hardhat-gas-reporter'
import '@openzeppelin/hardhat-upgrades'
import 'hardhat-spdx-license-identifier'
import '@nomicfoundation/hardhat-toolbox'
import 'hardhat-contract-sizer'

dotenv.config()

const {
  ENVIRONMENT,
  DEFENDER_TEAM_API_KEY,
  DEFENDER_TEAM_API_SECRET_KEY,
  MOONBEAM_PROVIDER_URL,
  POLYGON_PROVIDER_URL,
  BASE_PROVIDER_URL,
  DEV_PRIVATE_KEY,
  PROD_PRIVATE_KEY,
  POLYGONSCAN_API_KEY,
  ETHER_SCAN_API_KEY,
  BASESCAN_API_KEY,
  CRONOSSCAN_API_KEY,
  MOONSCAN_API_KEY,
  CRONOS_TESTNET_PROVIDER_URL,
  CRONOS_PROVIDER_URL,
  ARBITRUM_ONE_URL,
  ARBITRUM_API_KEY,
} = process.env

const BASE_CONFIG = {
  solidity: {
    version: '0.8.9',
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
  etherscan: {
    apiKey: {
      polygon: POLYGONSCAN_API_KEY,
      base: BASESCAN_API_KEY,
      // goerli: ETHER_SCAN_API_KEY,
      // cronosTestnet: CRONOSSCAN_API_KEY,
      // cronos: CRONOSSCAN_API_KEY,
      // moonbeam: MOONSCAN_API_KEY,
      // arbitrumOne: ARBITRUM_API_KEY,
    },
    customChains: [
      // For Base Mainnet
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=8453", // V2 API URL for mainnet
          browserURL: "https://basescan.org",     // V2 Browser URL for mainnet
        },
      },
    ],   
    // customChains: [
    //   {
    //     network: 'cronosTestnet',
    //     chainId: 338,
    //     urls: {
    //       apiURL: 'https://cronos.org/explorer/testnet3/api',
    //       blockExplorerURL: 'https://cronos.org/explorer/testnet3',
    //     },
    //   },
    //   {
    //     network: 'cronos',
    //     chainId: 25,
    //     urls: {
    //       apiURL: 'https://api.cronoscan.com/api',
    //       blockExplorerURL: 'https://cronos.org/explorer',
    //     },
    //   },
    // ],
  },
  networks: {
    hardhat: {
      forking: {
        url: POLYGON_PROVIDER_URL,
        blockNumber: 55899875,
        timeout: 20000,
      },
    },
  },
  mocha: {
    timeout: 840000,
  },
  gasReporter: {
    enabled: true,
    excludeContracts: ['contracts/test'],
    gasPrice: 100,
    token: 'MATIC',
    currency: 'USD',
  },
  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },
}

const PROD_CONFIG = {
  ...BASE_CONFIG,
  networks: {
    hardhat: {
      forking: {
        url: POLYGON_PROVIDER_URL,
        blockNumber: 55899875,
      },
    },
    polygon: {
      chainId: 137,
      url: POLYGON_PROVIDER_URL,
      accounts: [PROD_PRIVATE_KEY],
      pollingInterval: 15000,
    },
    // cronosTestnet: {
    //   chainId: 338,
    //   url: CRONOS_TESTNET_PROVIDER_URL,
    //   accounts: [DEV_PRIVATE_KEY],
    // },
    // cronos: {
    //   chainId: 25,
    //   url: CRONOS_PROVIDER_URL,
    //   accounts: [PROD_PRIVATE_KEY],
    // },
    // moonbeam: {
    //   chainId: 1284,
    //   url: MOONBEAM_PROVIDER_URL,
    //   accounts: [DEV_PRIVATE_KEY],
    // },
    // arbitrum: {
    //   chainId: 42161,
    //   url: ARBITRUM_ONE_URL,
    //   accounts: [DEV_PRIVATE_KEY],
    // },
    base: {
      chainId: 8453,
      url: BASE_PROVIDER_URL,
      accounts: [PROD_PRIVATE_KEY],
    },
  },
  // defender: {
  //   apiKey: DEFENDER_TEAM_API_KEY,
  //   apiSecret: DEFENDER_TEAM_API_SECRET_KEY,
  // },
}

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = ENVIRONMENT === 'prod' ? PROD_CONFIG : BASE_CONFIG
