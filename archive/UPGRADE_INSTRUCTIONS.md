# 🚀 spBEAM Validator Staking Upgrade Instructions

## Overview
This upgrade adds validator staking functionality to the existing spBEAM contract while preserving all user balances and data.

---

## ✅ What Stays the Same
- ✅ Contract address (proxy)
- ✅ All user balances
- ✅ All unlock requests
- ✅ Total supply
- ✅ Exchange rate
- ✅ UI compatibility (no changes needed)
- ✅ Liquidity pools (no migration needed)

## 🆕 What's New
- ✅ Stake BEAM with validators
- ✅ Claim multi-token rewards (WBEAM, ATH, etc.)
- ✅ Auto-staking functionality
- ✅ Reserve ratio management
- ✅ Reward token swapping via Sparrow Swap

---

## 📋 Deployment Steps

### Option 1: Upgrade Existing Contract (Recommended for Mainnet)

#### Step 1: Update Configuration
Edit `scripts/upgrade-spbeam.js`:
```javascript
const PROXY_ADDRESS = "YOUR_ACTUAL_PROXY_ADDRESS"; // ← Update this!
```

#### Step 2: Run Upgrade
```bash
# For testnet
npx hardhat run scripts/upgrade-spbeam.js --network beamTestnet

# For mainnet
npx hardhat run scripts/upgrade-spbeam.js --network beamMainnet
```

#### Step 3: Configure Parameters
Edit `scripts/configure-validator-staking.js`:
```javascript
const CONFIG = {
  reserveRatio: 1000, // 10%
  autoStakeThreshold: hre.ethers.parseEther("100"), // 100 BEAM
  sparrowSwapRouter: "YOUR_SPARROW_ROUTER_ADDRESS", // ← Update!
  currentValidator: "VALIDATOR_ID", // ← Optional
};
```

Then run:
```bash
npx hardhat run scripts/configure-validator-staking.js --network beamMainnet
```

---

### Option 2: Fresh Deployment (For Testing)

#### Step 1: Deploy New Contract
```bash
npx hardhat run scripts/deploy-spbeam.js --network beamTestnet
```

#### Step 2: Configure
Use the configuration script as shown above.

---

## ⚙️ Post-Deployment Configuration

### Required Settings:
1. **Reserve Ratio** (10% recommended)
   ```javascript
   await spbeam.setReserveRatio(1000); // 10%
   ```

2. **Auto-Stake Threshold** (100 BEAM recommended)
   ```javascript
   await spbeam.setAutoStakeThreshold(ethers.parseEther("100"));
   ```

3. **Sparrow Swap Router**
   ```javascript
   await spbeam.setSparrowSwapRouter(ROUTER_ADDRESS);
   ```

### Optional Settings:
4. **Current Validator** (for auto-staking)
   ```javascript
   await spbeam.setCurrentValidator(VALIDATION_ID);
   ```

5. **Enable Auto-Staking**
   ```javascript
   await spbeam.toggleAutoStaking(true);
   ```

---

## 🎯 Testing Checklist

### Basic Functions (Should Still Work):
- [ ] Users can stake BEAM
- [ ] Users can request unlock
- [ ] Users can claim unlocked BEAM
- [ ] Exchange rate is correct
- [ ] UI displays balances correctly

### New Functions (Test These):
- [ ] Governance can stake to validator
- [ ] Governance can unstake from validator
- [ ] Governance can claim rewards
- [ ] Rewards can be swapped via Sparrow
- [ ] WBEAM can be unwrapped
- [ ] Auto-staking works (if enabled)
- [ ] Reserve ratio is maintained

---

## 📊 Monitoring

### Key Metrics to Watch:
1. **Reserve Ratio**
   ```javascript
   const liquid = await spbeam.getLiquidBEAM();
   const total = await spbeam.totalPooledBEAM();
   const ratio = (liquid * 10000) / total; // basis points
   ```

2. **Staked with Validators**
   ```javascript
   const staked = await spbeam.totalStakedWithValidators();
   ```

3. **Exchange Rate**
   ```javascript
   const rate = await spbeam.getExchangeRate();
   ```

---

## 🔧 Validator Staking Workflow

### 1. Stake to Validator
```javascript
await spbeam.stakeToValidator(
  validationID,
  amount // in wei
);
```

### 2. Claim Rewards (Weekly/Monthly)
```javascript
// Claim rewards without unstaking
await spbeam.claimDelegationRewards(
  validationID,
  delegationID,
  [WBEAM_ADDRESS, ATH_ADDRESS] // reward tokens
);

// Swap ATH → WBEAM
await spbeam.swapRewardTokenForBEAM(
  ATH_ADDRESS,
  amount,
  minWBEAMOut,
  [ATH_ADDRESS, WBEAM_ADDRESS],
  deadline
);

// Unwrap WBEAM → Native BEAM
await spbeam.unwrapWBEAM(wbeamBalance);

// Distribute to users
await spbeam.addRewards();
```

### 3. Unstake (When Needed)
```javascript
// Initiate unstaking
await spbeam.unstakeFromValidator(delegationIndex);

// Wait for unstaking period...

// Complete unstaking
await spbeam.completeDelegatorRemoval(delegationIndex);
```

---

## ⚠️ Important Notes

### Reserve Ratio:
- Keep 10% liquid for user withdrawals
- Monitor and adjust as needed
- Auto-staking respects reserve ratio

### Reward Claiming:
- Claim function signature is uncertain (based on transaction analysis)
- Has backup: `rescueTokens()` for manual claiming
- Contract is upgradeable if function needs fixing

### Auto-Staking:
- Disabled by default
- Enable only after testing
- Requires `currentValidatorID` to be set

---

## 🆘 Troubleshooting

### If Upgrade Fails:
1. Check you're using governance address
2. Verify proxy address is correct
3. Ensure sufficient gas

### If Claim Function Fails:
1. Use `rescueTokens()` to withdraw reward tokens
2. Swap manually via Sparrow UI
3. Upgrade contract with correct function signature

### If Auto-Staking Issues:
1. Disable auto-staking: `toggleAutoStaking(false)`
2. Stake manually via `stakeToValidator()`
3. Check reserve ratio is maintained

---

## 📞 Support

If you encounter issues:
1. Check transaction logs
2. Verify all addresses are correct
3. Test on testnet first
4. Contract is upgradeable - can fix issues

---

## 🎉 Success Criteria

Upgrade is successful when:
- ✅ All user balances preserved
- ✅ Users can stake/unstake normally
- ✅ Governance can stake to validators
- ✅ Rewards can be claimed and distributed
- ✅ Exchange rate increases over time
- ✅ UI works without changes

---

**Good luck with the upgrade!** 🚀
