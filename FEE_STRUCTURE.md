# Sparrow Finance spAVAX - Fee Structure

## Overview

The protocol uses a **three-way fee split** to ensure sustainability and fair compensation for all stakeholders.

---

## 💰 Fee Breakdown

### **Total Rewards: 100 AVAX**

```
100 AVAX Validator Rewards
├─ 90 AVAX (90%) → Users (increases spAVAX value)
├─ 5 AVAX (5%) → Validators (operational costs)
└─ 5 AVAX (5%) → Protocol
    ├─ 2.5 AVAX (2.5%) → DAO Treasury
    └─ 2.5 AVAX (2.5%) → Development Fund
```

---

## 📊 Fee Recipients

### **1. Users (90%)**
- **Purpose:** Increase spAVAX value
- **Mechanism:** Added to `totalPooledAVAX`
- **Benefit:** All spAVAX holders earn proportionally

### **2. Validators (5%)**
- **Purpose:** Cover validator operational costs
- **Includes:** Server costs, maintenance, monitoring
- **Collection:** `collectValidatorFees()`

### **3. DAO Treasury (2.5%)**
- **Purpose:** Community governance and growth
- **Uses:** 
  - Marketing campaigns
  - Community incentives
  - Protocol improvements
  - Emergency reserves
- **Collection:** `collectDaoFees()`

### **4. Development Fund (2.5%)**
- **Purpose:** Ongoing development and maintenance
- **Uses:**
  - Smart contract upgrades
  - Security audits
  - Bug fixes
  - New features
  - Developer compensation
- **Collection:** `collectDevFees()`

---

## 🔧 Configuration

### **Current Settings:**
```solidity
validatorFeeBasisPoints = 500  // 5%
daoFeeBasisPoints = 250        // 2.5%
devFeeBasisPoints = 250        // 2.5%
protocolFeeBasisPoints = 500   // 5% (DAO + Dev combined)

Total Fees = 10% (1000 basis points)
User Rewards = 90%
```

### **Maximum Allowed:**
```solidity
MAX_TOTAL_FEE = 2000  // 20% maximum
```

---

## 📝 Functions

### **For Distributing Rewards:**

#### `addRewards(uint256 rewardAmount)`
```javascript
// Example: 100 AVAX earned from validators
await contract.addRewards(ethers.utils.parseEther("100"));

// Automatic split:
// - 90 AVAX → Users (spAVAX value increases)
// - 5 AVAX → Validator fees (tracked)
// - 2.5 AVAX → DAO fees (tracked)
// - 2.5 AVAX → Dev fees (tracked)
```

---

### **For Collecting Fees:**

#### `collectValidatorFees()`
```javascript
// Collect validator operational fees
await contract.collectValidatorFees();
// Sends accumulated validator fees to owner
```

#### `collectDaoFees()`
```javascript
// Collect DAO treasury fees
await contract.collectDaoFees();
// Sends accumulated DAO fees to owner
```

#### `collectDevFees()`
```javascript
// Collect development fees
await contract.collectDevFees();
// Sends accumulated dev fees to owner
```

#### `collectAllFees()`
```javascript
// Collect all fees at once (convenient)
await contract.collectAllFees();
// Sends all accumulated fees to owner
```

---

### **For Updating Fee Structure:**

#### `setFeeStructure(validatorFee, daoFee, devFee)`
```javascript
// Change fee structure (all in basis points)
await contract.setFeeStructure(
    500,  // 5% validators
    250,  // 2.5% DAO
    250   // 2.5% dev
);

// Total must be ≤ 2000 (20%)
```

**Examples:**
```javascript
// More competitive (lower fees)
await contract.setFeeStructure(300, 150, 150); // 3% + 1.5% + 1.5% = 6% total

// Higher protocol revenue
await contract.setFeeStructure(500, 400, 400); // 5% + 4% + 4% = 13% total

// No validator fees (not recommended)
await contract.setFeeStructure(0, 500, 500); // 0% + 5% + 5% = 10% total
```

---

## 💡 Example Scenarios

### **Scenario 1: Standard Operation**

```
Month 1:
- 10,000 AVAX staked by users
- 8% APY = 800 AVAX rewards earned
- addRewards(800) called

Distribution:
- Users: 720 AVAX (90%) → spAVAX value increases 7.2%
- Validators: 40 AVAX (5%) → accumulatedValidatorFees
- DAO: 20 AVAX (2.5%) → accumulatedDaoFees
- Dev: 20 AVAX (2.5%) → accumulatedDevFees

Your earnings: 40 + 20 + 20 = 80 AVAX/month
Annual: 960 AVAX (~$38,400 at $40/AVAX)
```

---

### **Scenario 2: Collecting Fees**

```
After 3 months:
- accumulatedValidatorFees: 120 AVAX
- accumulatedDaoFees: 60 AVAX
- accumulatedDevFees: 60 AVAX

Option A: Collect separately
collectValidatorFees() → 120 AVAX
collectDaoFees() → 60 AVAX
collectDevFees() → 60 AVAX

Option B: Collect all at once
collectAllFees() → 240 AVAX total
```

---

### **Scenario 3: Adjusting Fees**

```
Initial: 5% + 2.5% + 2.5% = 10% total fees

Market is competitive, reduce fees:
setFeeStructure(400, 200, 200) // 4% + 2% + 2% = 8% total

Protocol grows, increase revenue:
setFeeStructure(500, 350, 350) // 5% + 3.5% + 3.5% = 12% total
```

---

## 📈 Revenue Projections

### **At 10% Total Fees (5% + 2.5% + 2.5%):**

| TVL | Annual Rewards (8% APY) | Your Annual Revenue |
|-----|------------------------|---------------------|
| 10,000 AVAX | 800 AVAX | 80 AVAX ($3,200) |
| 100,000 AVAX | 8,000 AVAX | 800 AVAX ($32,000) |
| 1,000,000 AVAX | 80,000 AVAX | 8,000 AVAX ($320,000) |
| 10,000,000 AVAX | 800,000 AVAX | 80,000 AVAX ($3.2M) |

*Assumes $40/AVAX and 8% validator APY*

---

## 🎯 Fee Allocation Strategy

### **Validator Fees (5%):**
Use for:
- ✅ Server hosting costs
- ✅ Monitoring tools
- ✅ Backup infrastructure
- ✅ Emergency reserves

### **DAO Treasury (2.5%):**
Use for:
- ✅ Marketing campaigns
- ✅ Liquidity mining incentives
- ✅ Community rewards
- ✅ Partnerships
- ✅ Governance token distribution (future)

### **Development Fund (2.5%):**
Use for:
- ✅ Smart contract audits
- ✅ Bug bounties
- ✅ Developer salaries
- ✅ New feature development
- ✅ Technical infrastructure

---

## ⚠️ Important Notes

### **Fee Collection:**
- Fees accumulate in the contract
- Must call collection functions to withdraw
- All fees go to owner wallet initially
- **Recommended:** Set up separate wallets for DAO and Dev funds

### **Transparency:**
- All fee collections emit events
- Tracked on blockchain
- Users can verify fee structure
- Changes emit `FeeStructureUpdated` event

### **Best Practices:**
1. Collect fees regularly (monthly recommended)
2. Keep fees competitive with other protocols
3. Communicate fee changes to community
4. Use multisig for fee collection
5. Separate DAO and Dev funds into different wallets

---

## 🔄 Comparison with Competitors

| Protocol | Total Fees | User APY (8% base) |
|----------|-----------|-------------------|
| **Sparrow (You)** | 10% | 7.2% |
| BENQI sAVAX | 10% | 7.2% |
| Lido stETH | 10% | 7.2% |
| Rocket Pool | 15% | 6.8% |

**Your fee structure is competitive and fair!**

---

## 📞 Future Enhancements

### **Potential Improvements:**

1. **Separate Wallets:**
```solidity
address public validatorWallet;
address public daoWallet;
address public devWallet;

// Send fees directly to designated wallets
```

2. **Automated Distribution:**
```solidity
// Auto-send fees on collection
function collectValidatorFees() {
    // Send to validatorWallet instead of owner
}
```

3. **Governance:**
```solidity
// Community votes on fee changes
function proposeFeeChange(...) { }
function voteFeeChange(...) { }
```

---

## ✅ Summary

**Current Structure:**
- ✅ 90% to users (competitive)
- ✅ 5% to validators (sustainable)
- ✅ 5% to protocol (2.5% DAO + 2.5% Dev)
- ✅ Total 10% fees (industry standard)
- ✅ Adjustable up to 20% maximum
- ✅ Transparent and fair

**Your protocol is now set up for long-term sustainability!**
