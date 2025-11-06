require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-verify");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200  // Default for most contracts
          }
        }
      }
    ],
    overrides: {
      // Special optimization for size-constrained contracts
      "contracts/ERC4626/spBEAM_V2.sol": {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1  // Maximum size reduction (contract too large)
          }
        }
      },
      "contracts/ERC4626/spAVAX_V2.sol": {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1  // Maximum size reduction (contract too large)
          }
        }
      }
    }
  },
  networks: {
    // Avalanche Fuji Testnet
    fuji: {
      url: process.env.FUJI_RPC_URL || "https://api.avax-test.network/ext/bc/C/rpc",
      chainId: 43113,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gasPrice: 25000000000, // 25 gwei
    },
    // Avalanche Mainnet
    mainnet: {
      url: process.env.MAINNET_RPC_URL || "https://api.avax.network/ext/bc/C/rpc",
      chainId: 43114,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gasPrice: 25000000000, // 25 gwei
    },
    // Beam Testnet (Avalanche Subnet)
    beamTestnet: {
      url: process.env.BEAM_TESTNET_RPC_URL || "https://build.onbeam.com/rpc/testnet",
      chainId: 13337,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    // Local Hardhat Network
    hardhat: {
      chainId: 31337
    }
  },
  etherscan: {
    apiKey: {
      avalanche: process.env.SNOWTRACE_API_KEY || "",
      avalancheFujiTestnet: process.env.SNOWTRACE_API_KEY || "",
      beamTestnet: "no-api-key-needed" // Beam testnet doesn't require API key
    },
    customChains: [
      {
        network: "beamTestnet",
        chainId: 13337,
        urls: {
          apiURL: "https://subnets-test.avax.network/beam/api",
          browserURL: "https://subnets-test.avax.network/beam"
        }
      }
    ]
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  }
};
