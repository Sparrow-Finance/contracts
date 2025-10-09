# Hardhat CLI Guide - Sparrow Finance Contracts

Complete guide for interacting with spAVAX and spBEAM contracts using Hardhat console and scripts.

---

## Table of Contents
- [Setup](#setup)
- [Network Configuration](#network-configuration)
- [Hardhat Console Basics](#hardhat-console-basics)
- [spAVAX Operations (Fuji)](#spavax-operations-fuji)
- [spBEAM Operations (Beam Testnet)](#spbeam-operations-beam-testnet)
- [Admin/Governance Operations](#admingovernance-operations)
- [Deployment Commands](#deployment-commands)
- [Troubleshooting](#troubleshooting)

---

## Setup

### Prerequisites
```bash
# Install dependencies (if not already done)
npm install

# Create .env file with your private key
echo "PRIVATE_KEY=your_private_key_here" > .env
```

### Environment Variables
```bash
# Required
PRIVATE_KEY=0x...                    # Your wallet private key

# Optional
FUJI_RPC_URL=https://api.avax-test.network/ext/bc/C/rpc
BEAM_TESTNET_RPC_URL=https://build.onbeam.com/rpc/testnet
SNOWTRACE_API_KEY=your_api_key      # For contract verification
```

---

## Network Configuration

### Available Networks
- **fuji** - Avalanche Fuji Testnet (chainId: 43113)
- **mainnet** - Avalanche Mainnet (chainId: 43114)
- **beamTestnet** - Beam L1 Testnet (chainId: 13337)
- **hardhat** - Local Hardhat Network (chainId: 31337)

### Deployed Contracts
```javascript
// Avalanche Fuji
spAVAX: 0xd5be2F451C0B1B8cA17Cc64a1f904405B8120c9B

// Beam Testnet
spBEAM Proxy: 0x21e9726d777400c5dcBF65cF595125B21359A1DD
spBEAM Implementation: 0x8F8926A38D03125c448b5EF5f2Edbfc3BE8C69D2
```

---

## Hardhat Console Basics

### Open Console
```bash
# Fuji Testnet
npx hardhat console --network fuji

# Beam Testnet
npx hardhat console --network beamTestnet

# Local network
npx hardhat console
```

### Basic Commands
```javascript
// Get your signer (deployer account)
const [signer] = await ethers.getSigners()
console.log("Address:", signer.address)

// Check balance
const balance = await ethers.provider.getBalance(signer.address)
console.log("Balance:", ethers.formatEther(balance))

// Get current block
const block = await ethers.provider.getBlockNumber()
console.log("Block:", block)

// Exit console
.exit
```

---

## spAVAX Operations (Fuji)

### Connect to Contract
```javascript
// Open console
npx hardhat console --network fuji

// Get contract instance
const spAVAX = await ethers.getContractAt(
  "spAVAX", 
  "0xd5be2F451C0B1B8cA17Cc64a1f904405B8120c9B"
)
```

### Read Functions (View)
```javascript
// Get token info
await spAVAX.name()                    // "Sparrow Staked AVAX"
await spAVAX.symbol()                  // "spAVAX"
await spAVAX.decimals()                // 18n
await spAVAX.totalSupply()             // Total spAVAX minted

// Get stats
const stats = await spAVAX.getStats()
console.log("Total Pooled AVAX:", ethers.formatEther(stats[0]))
console.log("Total Supply:", ethers.formatEther(stats[1]))
console.log("Exchange Rate:", ethers.formatEther(stats[2]))
console.log("Liquid Balance:", ethers.formatEther(stats[3]))
console.log("DAO Fees:", ethers.formatEther(stats[4]))
console.log("Dev Fees:", ethers.formatEther(stats[5]))

// Get exchange rate
const rate = await spAVAX.getExchangeRate()
console.log("1 spAVAX =", ethers.formatEther(rate), "AVAX")

// Preview stake
const preview = await spAVAX.previewStake(ethers.parseEther("1.0"))
console.log("1 AVAX will mint:", ethers.formatEther(preview), "spAVAX")

// Check user balance
const [signer] = await ethers.getSigners()
const balance = await spAVAX.balanceOf(signer.address)
console.log("Your spAVAX:", ethers.formatEther(balance))

// Get unlock requests
const count = await spAVAX.getUnlockRequestCount(signer.address)
console.log("Pending unlock requests:", count.toString())

// Get specific unlock request
if (count > 0n) {
  const request = await spAVAX.getUnlockRequest(signer.address, 0)
  console.log("spAVAX locked:", ethers.formatEther(request[0]))
  console.log("AVAX to receive:", ethers.formatEther(request[1]))
  console.log("Unlock time:", new Date(Number(request[2]) * 1000))
  console.log("Expiry time:", new Date(Number(request[3]) * 1000))
  console.log("Ready to claim:", request[4])
  console.log("Expired:", request[5])
}
```

### Write Functions (Transactions)

#### Stake AVAX
```javascript
// Stake 1 AVAX
const tx = await spAVAX.stake(0, { 
  value: ethers.parseEther("1.0") 
})
await tx.wait()
console.log("Staked! Tx:", tx.hash)

// Stake with slippage protection
const expectedSpAVAX = await spAVAX.previewStake(ethers.parseEther("1.0"))
const minOut = expectedSpAVAX * 99n / 100n  // 1% slippage
const tx = await spAVAX.stake(minOut, { 
  value: ethers.parseEther("1.0") 
})
await tx.wait()
```

#### Request Unlock
```javascript
// Request to unlock 0.5 spAVAX
const amount = ethers.parseEther("0.5")
const tx = await spAVAX.requestUnlock(amount, 0)
await tx.wait()
console.log("Unlock requested! Tx:", tx.hash)

// With slippage protection
const expectedAVAX = await spAVAX.previewUnlock(amount)
const minOut = expectedAVAX * 99n / 100n
const tx = await spAVAX.requestUnlock(amount, minOut)
await tx.wait()
```

#### Claim Unlocked AVAX
```javascript
// Wait for unlock period to pass, then claim
const tx = await spAVAX.claimUnlock(0)  // 0 = first request
await tx.wait()
console.log("Claimed! Tx:", tx.hash)
```

#### Cancel Unlock Request
```javascript
// Cancel before expiry to get spAVAX back
const tx = await spAVAX.cancelUnlock(0)
await tx.wait()
console.log("Cancelled! Tx:", tx.hash)
```

#### Claim Expired Request
```javascript
// After claim window expires, reclaim spAVAX
const tx = await spAVAX.claimExpired(0)
await tx.wait()
console.log("Reclaimed! Tx:", tx.hash)
```

---

## spBEAM Operations (Beam Testnet)

### Connect to Contract
```javascript
// Open console
npx hardhat console --network beamTestnet

// Get contract instance (use PROXY address)
const spBEAM = await ethers.getContractAt(
  "spBEAM", 
  "0x21e9726d777400c5dcBF65cF595125B21359A1DD"
)
```

### Read Functions
```javascript
// Same as spAVAX, just replace AVAX with BEAM
await spBEAM.name()                    // "Sparrow Staked BEAM"
await spBEAM.symbol()                  // "spBEAM"
await spBEAM.totalSupply()

const stats = await spBEAM.getStats()
console.log("Total Pooled BEAM:", ethers.formatEther(stats[0]))
console.log("Total Supply:", ethers.formatEther(stats[1]))
console.log("Exchange Rate:", ethers.formatEther(stats[2]))

// Check balance
const [signer] = await ethers.getSigners()
const balance = await spBEAM.balanceOf(signer.address)
console.log("Your spBEAM:", ethers.formatEther(balance))
```

### Write Functions
```javascript
// Stake 0.02 BEAM (minimum is 0.01)
const tx = await spBEAM.stake(0, { 
  value: ethers.parseEther("0.02") 
})
await tx.wait()
console.log("Staked! Tx:", tx.hash)

// Request unlock
const tx = await spBEAM.requestUnlock(ethers.parseEther("0.01"), 0)
await tx.wait()

// Wait 60 seconds (testnet unlock period), then claim
const tx = await spBEAM.claimUnlock(0)
await tx.wait()
console.log("Claimed! Tx:", tx.hash)
```

---

## Admin/Governance Operations

**⚠️ Only callable by governance address (deployer)**

### Add Rewards
```javascript
// Add 1 AVAX/BEAM as validator rewards
// Fees are automatically split: 5% DAO + 3% Dev = 8% total
const tx = await spAVAX.addRewards({ 
  value: ethers.parseEther("1.0") 
})
await tx.wait()
console.log("Rewards added! Tx:", tx.hash)
```

### Collect Fees
```javascript
// Collect DAO treasury fees
const daoFees = await spAVAX.accumulatedDaoFees()
console.log("DAO fees:", ethers.formatEther(daoFees))
const tx = await spAVAX.collectDaoFees()
await tx.wait()

// Collect dev fees
const devFees = await spAVAX.accumulatedDevFees()
console.log("Dev fees:", ethers.formatEther(devFees))
const tx = await spAVAX.collectDevFees()
await tx.wait()
```

### Withdraw/Deposit (Validator Management)
```javascript
// Withdraw AVAX to stake with validators
const tx = await spAVAX.withdraw(ethers.parseEther("10.0"))
await tx.wait()

// Deposit AVAX back from validators
const tx = await spAVAX.deposit({ 
  value: ethers.parseEther("10.0") 
})
await tx.wait()
```

### Update Parameters
```javascript
// Update unlock period (7-30 days)
const tx = await spAVAX.setUnlockPeriod(14 * 24 * 60 * 60)  // 14 days
await tx.wait()

// Update claim window (1 hour - 30 days)
const tx = await spAVAX.setClaimWindow(7 * 24 * 60 * 60)  // 7 days
await tx.wait()

// Update fee structure (max 10% total)
const tx = await spAVAX.setFeeStructure(400, 200)  // 4% DAO, 2% Dev
await tx.wait()

// Update minimum stake
const tx = await spAVAX.setMinStakeAmount(ethers.parseEther("0.1"))
await tx.wait()
```

### Emergency Controls
```javascript
// Pause contract (stops staking/unstaking)
const tx = await spAVAX.pause()
await tx.wait()

// Unpause
const tx = await spAVAX.unpause()
await tx.wait()

// Check if paused
const isPaused = await spAVAX.paused()
console.log("Paused:", isPaused)
```

### Transfer Governance
```javascript
// Step 1: Initiate transfer
const newGov = "0x..."
const tx = await spAVAX.transferGovernance(newGov)
await tx.wait()

// Step 2: New governance accepts (must be called by new address)
const tx = await spAVAX.acceptGovernance()
await tx.wait()
```

---

## Deployment Commands

### Deploy spAVAX (Fuji)
```bash
npx hardhat run scripts/deploy-simple.js --network fuji
```

### Deploy spBEAM (Beam Testnet)
```bash
npx hardhat run scripts/deploy-spbeam.js --network beamTestnet
```

### Compile Contracts
```bash
npx hardhat compile
```

### Clean Build
```bash
npx hardhat clean
npx hardhat compile
```

---

## Troubleshooting

### Common Errors

#### "Insufficient funds"
```javascript
// Check your balance
const balance = await ethers.provider.getBalance(signer.address)
console.log("Balance:", ethers.formatEther(balance))

// Get testnet tokens
// Fuji: https://faucet.avax.network/
// Beam: https://faucet.onbeam.com/
```

#### "Below minimum stake"
```javascript
// Check minimum
const min = await spAVAX.minStakeAmount()
console.log("Minimum stake:", ethers.formatEther(min))

// Stake at least the minimum
const tx = await spAVAX.stake(0, { value: min })
```

#### "Unlock period not finished"
```javascript
// Check unlock request status
const request = await spAVAX.getUnlockRequest(signer.address, 0)
const unlockTime = Number(request[2])
const now = Math.floor(Date.now() / 1000)
const remaining = unlockTime - now

if (remaining > 0) {
  console.log("Wait", remaining, "seconds")
} else {
  console.log("Ready to claim!")
}
```

#### "Not governance"
```javascript
// Check who is governance
const gov = await spAVAX.governance()
console.log("Governance:", gov)
console.log("Your address:", signer.address)

// Only governance can call admin functions
```

#### "Wrong network"
```javascript
// Check current network
const network = await ethers.provider.getNetwork()
console.log("Chain ID:", network.chainId)

// Expected:
// Fuji: 43113
// Beam: 13337
```

### Get Transaction Details
```javascript
// Get transaction receipt
const tx = await spAVAX.stake(0, { value: ethers.parseEther("1.0") })
const receipt = await tx.wait()

console.log("Tx hash:", receipt.hash)
console.log("Block:", receipt.blockNumber)
console.log("Gas used:", receipt.gasUsed.toString())
console.log("Status:", receipt.status === 1 ? "Success" : "Failed")

// View events
receipt.logs.forEach(log => {
  try {
    const parsed = spAVAX.interface.parseLog(log)
    console.log("Event:", parsed.name)
    console.log("Args:", parsed.args)
  } catch (e) {}
})
```

### Estimate Gas
```javascript
// Estimate before sending
const gasEstimate = await spAVAX.stake.estimateGas(0, { 
  value: ethers.parseEther("1.0") 
})
console.log("Estimated gas:", gasEstimate.toString())

// Get current gas price
const gasPrice = await ethers.provider.getFeeData()
console.log("Gas price:", ethers.formatUnits(gasPrice.gasPrice, "gwei"), "gwei")
```

---

## Useful Scripts

### Check All Stats
```javascript
async function checkStats() {
  const [signer] = await ethers.getSigners()
  const spAVAX = await ethers.getContractAt("spAVAX", "0xd5be2F451C0B1B8cA17Cc64a1f904405B8120c9B")
  
  console.log("\n=== Contract Stats ===")
  const stats = await spAVAX.getStats()
  console.log("Total Pooled:", ethers.formatEther(stats[0]), "AVAX")
  console.log("Total Supply:", ethers.formatEther(stats[1]), "spAVAX")
  console.log("Exchange Rate:", ethers.formatEther(stats[2]))
  console.log("Liquid Balance:", ethers.formatEther(stats[3]), "AVAX")
  console.log("DAO Fees:", ethers.formatEther(stats[4]), "AVAX")
  console.log("Dev Fees:", ethers.formatEther(stats[5]), "AVAX")
  
  console.log("\n=== Your Balance ===")
  const balance = await spAVAX.balanceOf(signer.address)
  console.log("spAVAX:", ethers.formatEther(balance))
  
  const avaxBalance = await ethers.provider.getBalance(signer.address)
  console.log("AVAX:", ethers.formatEther(avaxBalance))
  
  console.log("\n=== Unlock Requests ===")
  const count = await spAVAX.getUnlockRequestCount(signer.address)
  console.log("Pending:", count.toString())
  
  for (let i = 0; i < count; i++) {
    const req = await spAVAX.getUnlockRequest(signer.address, i)
    console.log(`\nRequest ${i}:`)
    console.log("  Amount:", ethers.formatEther(req[0]), "spAVAX")
    console.log("  Will receive:", ethers.formatEther(req[1]), "AVAX")
    console.log("  Ready:", req[4])
    console.log("  Expired:", req[5])
  }
}

// Run it
await checkStats()
```

### Batch Operations
```javascript
// Stake multiple times
async function batchStake(amounts) {
  const spAVAX = await ethers.getContractAt("spAVAX", "0xd5be2F451C0B1B8cA17Cc64a1f904405B8120c9B")
  
  for (const amount of amounts) {
    console.log(`Staking ${amount} AVAX...`)
    const tx = await spAVAX.stake(0, { 
      value: ethers.parseEther(amount) 
    })
    await tx.wait()
    console.log("Done! Tx:", tx.hash)
  }
}

// Usage
await batchStake(["0.1", "0.2", "0.5"])
```

---

## Quick Reference

### Common Commands
```bash
# Console
npx hardhat console --network fuji
npx hardhat console --network beamTestnet

# Deploy
npx hardhat run scripts/deploy-simple.js --network fuji
npx hardhat run scripts/deploy-spbeam.js --network beamTestnet

# Compile
npx hardhat compile

# Test
npx hardhat test

# Clean
npx hardhat clean
```

### Contract Addresses
```javascript
// Fuji
const SPAVAX = "0xd5be2F451C0B1B8cA17Cc64a1f904405B8120c9B"

// Beam Testnet
const SPBEAM = "0x21e9726d777400c5dcBF65cF595125B21359A1DD"
```

### Explorers
- Fuji: https://testnet.snowtrace.io
- Beam: https://subnets-test.avax.network/beam

### Faucets
- Fuji: https://faucet.avax.network/
- Beam: https://faucet.onbeam.com/

---

## Support

For issues or questions:
1. Check the [main README](./README.md)
2. Review contract source in `contracts/`
3. Check deployment logs in console output
4. View transactions on block explorers

**Remember:** Always use the PROXY address for spBEAM interactions, not the implementation!
