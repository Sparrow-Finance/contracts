# Claim Window Timeline Visualization

## Timeline Overview

```
Day 0                Day 0 + 60s           Day 7                    Day 9
  │                      │                   │                        │
  │  Unlock Period       │   Claim Window    │                        │
  │◄────────────────────►│◄─────────────────►│                        │
  │                      │                   │                        │
  ▼                      ▼                   ▼                        ▼
Request                Ready              Still                   Expired
Unlock                to Claim           Claimable              (Get spAVAX back)
```

---

## Detailed Timeline

### **Phase 1: Unlock Period (60 seconds on Fuji, 2 days on Mainnet)**

```
Time: 0 → 60 seconds
Status: WAITING
Actions Available:
  ✅ cancelUnlock() - Get spAVAX back
  ❌ claimUnlock() - Too early
  ❌ claimExpired() - Not expired yet
```

**What's happening:**
- spAVAX locked in contract
- Exchange rate locked
- You (admin) prepare liquidity
- User waits

---

### **Phase 2: Claim Window (7 days)**

```
Time: 60 seconds → 7 days + 60 seconds
Status: READY TO CLAIM
Actions Available:
  ✅ claimUnlock() - Get AVAX
  ✅ cancelUnlock() - Get spAVAX back
  ❌ claimExpired() - Not expired yet
```

**What's happening:**
- User can claim AVAX anytime in this window
- Exchange rate still locked from request time
- User still has option to cancel
- Most users will claim here

---

### **Phase 3: Expired (After 7 days + 60 seconds)**

```
Time: After 7 days + 60 seconds
Status: EXPIRED
Actions Available:
  ❌ claimUnlock() - Window closed
  ❌ cancelUnlock() - Window closed
  ✅ claimExpired() - Get spAVAX back
```

**What's happening:**
- Claim window closed
- User missed their chance
- Can recover spAVAX tokens
- No AVAX payout
- Can request new unlock if desired

---

## Example with Real Numbers

### **Fuji Testnet (60 second unlock)**

```
Monday 12:00:00 PM - User requests unlock of 100 spAVAX
Monday 12:01:00 PM - Unlock ready (60 seconds passed)
Monday 12:01:00 PM to Monday 7 days later - Claim window open
Monday 7 days + 1 minute later - Expired, must use claimExpired()
```

### **Mainnet (2 day unlock)**

```
January 1, 12:00 PM - User requests unlock of 1000 spAVAX
January 3, 12:00 PM - Unlock ready (2 days passed)
January 3-10, 12:00 PM - Claim window open (7 days)
January 10, 12:01 PM - Expired, must use claimExpired()
```

---

## Why This Design?

### **Benefits:**

✅ **Prevents indefinite locks**
- Without expiry, spAVAX could be locked forever
- Expired unlocks return spAVAX to users

✅ **Manages liquidity**
- You know maximum time you need liquidity
- After 7 days, liquidity can be redeployed

✅ **Fair to users**
- 7 days is reasonable time to claim
- Can still recover tokens if missed

✅ **Protects protocol**
- Limits your liquidity obligations
- Predictable unlock lifecycle

---

## State Diagram

```
                    requestUnlock()
                         │
                         ▼
                   ┌──────────┐
                   │ WAITING  │ (Unlock Period)
                   └──────────┘
                    │        │
         cancelUnlock()      │ (time passes)
                    │        │
                    ▼        ▼
              ┌─────────┐  ┌──────────┐
              │ CANCELLED│  │  READY   │ (Claim Window)
              └─────────┘  └──────────┘
                              │    │   │
                   claimUnlock()   │   │ (time passes)
                              │    │   │
                              ▼    │   ▼
                         ┌────────┐  ┌──────────┐
                         │CLAIMED │  │ EXPIRED  │
                         └────────┘  └──────────┘
                                          │
                                   claimExpired()
                                          │
                                          ▼
                                    ┌──────────┐
                                    │ RECOVERED│
                                    └──────────┘
```

---

## Testing Timeline (Fuji)

For quick testing on Fuji with 60-second unlock:

```javascript
// Request unlock
await contract.requestUnlock(ethers.utils.parseEther("1"));
console.log("Unlock requested at:", new Date());

// Wait 61 seconds
await new Promise(r => setTimeout(r, 61000));

// Check status
const request = await contract.getUnlockRequest(userAddress, 0);
console.log("Is ready:", request.isReady);
console.log("Is expired:", request.isExpired);
console.log("Unlock time:", new Date(request.unlockTime * 1000));
console.log("Expiry time:", new Date(request.expiryTime * 1000));

// Claim
await contract.claimUnlock(0);
console.log("Claimed at:", new Date());
```

---

## Monitoring Recommendations

### **For Users:**
- Set reminder when unlock is ready
- Claim within 7 days
- Don't wait until last minute

### **For You (Admin):**
- Monitor `UnlockRequested` events
- Track expiring unlocks
- Notify users before expiry
- Monitor liquidity needs

### **Automation Ideas:**
- Email/Discord notifications when unlock ready
- Warning 1 day before expiry
- Auto-claim option (future feature)
- Dashboard showing all pending unlocks
