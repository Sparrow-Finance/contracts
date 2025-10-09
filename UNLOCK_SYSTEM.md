# spAVAX Unlock System with Claim Window

## Overview

The contract has a **two-phase unlock system**:
1. **Unlock Period**: 60 seconds (configurable) - gives you time to prepare liquidity
2. **Claim Window**: 7 days (configurable) - user must claim within this window or unlock expires

---

## How It Works

### **User Flow:**

```
Step 1: User calls requestUnlock(100 spAVAX)
   ↓
   - spAVAX locked in contract
   - Exchange rate locked at current value
   - Unlock timer starts (60 seconds)
   - Claim window starts (7 days after unlock)
   - User gets unlock request ID

Step 2: Wait 60 seconds (unlock period)

Step 3: User calls claimUnlock(requestID)
   ↓
   - Must be after unlock time
   - Must be before expiry time
   - Receives AVAX at locked exchange rate
   - spAVAX burned

Alternative: If claim window expires
   ↓
   User calls claimExpired(requestID)
   - Gets spAVAX back (no AVAX)
```

### **Your Flow (Admin):**

```
User requests unlock
   ↓
You see UnlockRequested event
   ↓
You have 60 seconds to:
   1. Check if contract has enough liquid AVAX
   2. If not, unstake from validators
   3. Call deposit() to add AVAX back
   ↓
User claims after 60 seconds
```

---

## Functions

### **User Functions:**

#### `requestUnlock(uint256 spAvaxAmount)`
- Starts the unlock process
- Locks spAVAX in contract
- Locks exchange rate
- Sets unlock time (now + 60 seconds)
- Sets expiry time (unlock time + 7 days)
- Returns: amount of AVAX they'll receive

#### `claimUnlock(uint256 requestIndex)`
- Claims AVAX after unlock period
- Must be after unlock time
- Must be before expiry time
- Burns spAVAX and sends AVAX

#### `cancelUnlock(uint256 requestIndex)`
- Cancel unlock request before expiry
- Get spAVAX back
- Can do anytime before claim window expires

#### `claimExpired(uint256 requestIndex)`
- Claim expired unlock request
- Only works after claim window expires
- Returns spAVAX to user (no AVAX)
- Useful if user missed claim window

#### `getUnlockRequestCount(address user)`
- See how many pending unlocks a user has

#### `getUnlockRequest(address user, uint256 index)`
- Get details of a specific unlock request
- Returns: spAVAX amount, AVAX amount, unlock time, expiry time, isReady, isExpired

---

### **Admin Functions:**

#### `setUnlockPeriod(uint256 newPeriod)`
- Change unlock period (in seconds)
- Default: 60 seconds (for testing)
- Mainnet suggestion: 2 days (172800 seconds)

#### `setClaimWindow(uint256 newWindow)`
- Change claim window (in seconds)
- Default: 7 days (604800 seconds)
- Mainnet suggestion: Keep at 7 days

---

## Configuration

### **Current Settings:**
```solidity
unlockPeriod = 60 seconds      // For Fuji testing
claimWindow = 7 days           // 604800 seconds
```

### **Recommended for Mainnet:**
```solidity
unlockPeriod = 172800 seconds  // 2 days
claimWindow = 604800 seconds   // 7 days (keep default)
```

**Why these timings?**
- **Unlock Period (2 days)**: Gives you time to unstake from validators and manage liquidity
- **Claim Window (7 days)**: Reasonable time for users to claim, prevents indefinite locks
- **Total time**: User has 2 days + 7 days = 9 days to complete unstaking

---

## Example Scenario

### **Scenario 1: Enough Liquidity**
```
1. User requests unlock of 100 spAVAX
2. Contract has 500 AVAX liquid
3. After 60 seconds, user claims
4. Receives 110 AVAX (if exchange rate is 1.1)
5. You do nothing - liquidity was sufficient
```

### **Scenario 2: Need to Unstake**
```
1. User requests unlock of 1000 spAVAX
2. Contract only has 100 AVAX liquid
3. You see the event, need 1100 AVAX
4. You unstake from validators (off-chain)
5. You call deposit() with 1000 AVAX
6. After 60 seconds, user claims successfully
```

### **Scenario 3: User Changes Mind**
```
1. User requests unlock of 50 spAVAX
2. Wait 30 seconds
3. User calls cancelUnlock()
4. Gets 50 spAVAX back
5. No AVAX needed
```

### **Scenario 4: User Misses Claim Window**
```
1. User requests unlock of 200 spAVAX
2. Unlock ready after 60 seconds
3. User forgets to claim for 8 days
4. Claim window expires (7 days after unlock)
5. User calls claimExpired()
6. Gets 200 spAVAX back (no AVAX)
7. Can stake again or request new unlock
```

---

## Events to Monitor

### `UnlockRequested`
```solidity
event UnlockRequested(
    address indexed user,
    uint256 spAvaxAmount,
    uint256 avaxAmount,
    uint256 unlockTime
);
```

**What to do:**
- Check contract balance
- If balance < avaxAmount, prepare to add liquidity
- You have `unlockPeriod` seconds

### `Unstaked`
```solidity
event Unstaked(
    address indexed user,
    uint256 spAvaxAmount,
    uint256 avaxAmount
);
```

**What it means:**
- User successfully claimed
- AVAX was sent
- spAVAX was burned

---

## Testing on Fuji

### **Test Flow:**
```javascript
// 1. User stakes
await contract.stake({ value: ethers.utils.parseEther("10") });

// 2. User requests unlock
await contract.requestUnlock(ethers.utils.parseEther("5"));

// 3. Check unlock request
const count = await contract.getUnlockRequestCount(userAddress);
const request = await contract.getUnlockRequest(userAddress, 0);
console.log("Unlock time:", new Date(request.unlockTime * 1000));
console.log("Is ready:", request.isReady);

// 4. Wait 60 seconds
await new Promise(r => setTimeout(r, 61000));

// 5. Claim
await contract.claimUnlock(0);
```

---

## Advantages of This System

✅ **Gives you time** to manage liquidity
✅ **Locks exchange rate** at request time (fair for users)
✅ **Users can cancel** if they change their mind
✅ **Simple to understand** - just 60 seconds
✅ **Configurable** - can increase for mainnet

---

## Mainnet Recommendations

1. **Set unlock period to 2 days** (172800 seconds)
2. **Keep 10-20% liquidity buffer** in contract
3. **Monitor UnlockRequested events** with a bot
4. **Automate liquidity management** if possible
5. **Communicate clearly** to users about unlock time
