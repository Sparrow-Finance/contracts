# Beam Validator Staking Integration

## Overview

Beam uses Avalanche's L1 (formerly Subnet) architecture with a **PoSValidatorManager** contract for validator staking and delegation.

---

## Contract Addresses

### **Mainnet:**
```
PoSValidatorManager: 0x2FD428A5484d113294b44E69Cb9f269abC1d5B54
Chain ID: 4337
Explorer: https://subnets.avax.network/beam
```

### **Testnet:**
```
PoSValidatorManager: [TO BE DETERMINED]
Chain ID: 13337
Explorer: https://subnets-test.avax.network/beam
```

**Note:** Validator Manager addresses are different per network!

---

## Key Functions

### 1. Stake BEAM to Validator (Delegate)

**Function:** `initializeDelegatorRegistration`  
**Method ID:** `0xcacd9755`

```solidity
function initializeDelegatorRegistration(
    bytes32 validationID  // Validator to delegate to
) external payable;
```

**Example:**
```solidity
// Stake 100 BEAM to validator
IPoSValidatorManager(0x0200000000000000000000000000000000000000)
    .initializeDelegatorRegistration{value: 100 ether}(
        0x91f190052e6ed57f0f2bf620ecf35f063d4f3075ab5211efb9cf294be5ba855a
    );
```

**What Happens:**
1. BEAM is locked in the contract
2. A Warp message is sent to P-Chain
3. P-Chain registers the delegation
4. Must call `completeDelegatorRegistration` after P-Chain confirms

---

### 2. Complete Delegation Registration

**Function:** `completeDelegatorRegistration`

```solidity
function completeDelegatorRegistration(
    bytes32 validationID,
    uint32 delegationID
) external;
```

**What Happens:**
- Confirms delegation on Beam chain
- Staking rewards begin accruing
- Delegation is now active

**Note:** Get `delegationID` from the `DelegatorAdded` event emitted by `initializeDelegatorRegistration`

---

### 3. Start Unstaking

**Function:** `initializeEndDelegation`

```solidity
function initializeEndDelegation(
    bytes32 validationID,
    uint32 delegationID
) external;
```

**What Happens:**
1. Sends Warp message to P-Chain to end delegation
2. Stops reward accrual
3. Must call `completeEndDelegation` after P-Chain confirms

---

### 4. Complete Unstaking & Claim Rewards

**Function:** `completeEndDelegation`

```solidity
function completeEndDelegation(
    bytes32 validationID,
    uint32 delegationID
) external;
```

**What Happens:**
- Returns staked BEAM to caller
- Includes accumulated staking rewards
- Delegation is fully closed

---

## Finding Validators

### Active Validators Dashboard:
```
https://nodes.onbeam.com/validators
```

Each validator has:
- **Validation ID** (bytes32) - Used for staking
- **Uptime %** - Validator reliability
- **Delegated Amount** - Total BEAM staked
- **Commission %** - Fee charged by validator

### Example Validator ID:
```
0x91f190052e6ed57f0f2bf620ecf35f063d4f3075ab5211efb9cf294be5ba855a
```

---

## Integration with spBEAM Contract

### Interface Definition:

```solidity
// contracts/interfaces/IPoSValidatorManager.sol
interface IPoSValidatorManager {
    /// @notice Stake BEAM to a validator
    function initializeDelegatorRegistration(
        bytes32 validationID
    ) external payable;
    
    /// @notice Complete delegation after P-Chain confirms
    function completeDelegatorRegistration(
        bytes32 validationID,
        uint32 delegationID
    ) external;
    
    /// @notice Start unstaking process
    function initializeEndDelegation(
        bytes32 validationID,
        uint32 delegationID
    ) external;
    
    /// @notice Complete unstaking and claim rewards
    function completeEndDelegation(
        bytes32 validationID,
        uint32 delegationID
    ) external;
    
    /// @notice Events
    event DelegatorAdded(
        bytes32 indexed validationID,
        uint32 indexed delegationID,
        address indexed delegatorAddress,
        uint64 nonce,
        uint64 validatorWeight,
        uint64 delegatorWeight,
        bytes32 setWeightMessageID
    );
    
    event DelegatorRemoved(
        bytes32 indexed validationID,
        uint32 indexed delegationID
    );
}
```

---

## Example Usage in spBEAM

### Add to spBEAM.sol:

```solidity
// State variables
IPoSValidatorManager public constant VALIDATOR_MANAGER = 
    IPoSValidatorManager(0x0200000000000000000000000000000000000000);

struct Delegation {
    bytes32 validationID;
    uint32 delegationID;
    uint256 amount;
    bool active;
}

mapping(uint256 => Delegation) public delegations;
uint256 public delegationCount;

// Events
event StakedToValidator(bytes32 validationID, uint256 amount);
event UnstakedFromValidator(bytes32 validationID, uint32 delegationID, uint256 amount);

// Functions
function stakeToValidator(
    bytes32 validationID,
    uint256 amount
) external onlyGovernance nonReentrant {
    require(address(this).balance >= amount, "Insufficient balance");
    require(amount >= 20000 ether, "Below validator minimum");
    
    // Stake to validator
    VALIDATOR_MANAGER.initializeDelegatorRegistration{value: amount}(
        validationID
    );
    
    emit StakedToValidator(validationID, amount);
}

function completeDelegation(
    bytes32 validationID,
    uint32 delegationID,
    uint256 amount
) external onlyGovernance {
    VALIDATOR_MANAGER.completeDelegatorRegistration(
        validationID,
        delegationID
    );
    
    // Track delegation
    delegations[delegationCount] = Delegation({
        validationID: validationID,
        delegationID: delegationID,
        amount: amount,
        active: true
    });
    delegationCount++;
}

function unstakeFromValidator(
    uint256 delegationIndex
) external onlyGovernance nonReentrant {
    Delegation storage delegation = delegations[delegationIndex];
    require(delegation.active, "Delegation not active");
    
    VALIDATOR_MANAGER.initializeEndDelegation(
        delegation.validationID,
        delegation.delegationID
    );
    
    delegation.active = false;
}

function completeUnstake(
    uint256 delegationIndex
) external onlyGovernance {
    Delegation storage delegation = delegations[delegationIndex];
    
    VALIDATOR_MANAGER.completeEndDelegation(
        delegation.validationID,
        delegation.delegationID
    );
    
    emit UnstakedFromValidator(
        delegation.validationID,
        delegation.delegationID,
        delegation.amount
    );
}
```

---

## Workflow for Sparrow Finance

### 1. User Stakes BEAM
```
User → spBEAM.stake() → Receives spBEAM tokens
BEAM sits in contract
```

### 2. Owner Delegates to Validator (Manual)
```
Owner → spBEAM.stakeToValidator(validationID, amount)
→ Calls VALIDATOR_MANAGER.initializeDelegatorRegistration()
→ Wait for P-Chain confirmation
→ Owner → spBEAM.completeDelegation(validationID, delegationID)
```

### 3. Rewards Accrue
```
Validator earns rewards on P-Chain
Rewards automatically compound
```

### 4. Owner Collects Rewards (Manual)
```
Owner → spBEAM.unstakeFromValidator(delegationIndex)
→ Calls VALIDATOR_MANAGER.initializeEndDelegation()
→ Wait for P-Chain confirmation
→ Owner → spBEAM.completeUnstake(delegationIndex)
→ BEAM + rewards returned to contract
→ Owner → spBEAM.addRewards() to distribute to users
```

### 5. User Unstakes
```
User → spBEAM.requestUnlock()
→ Wait 14 days
→ User → spBEAM.claimUnlock()
→ Receives BEAM + share of rewards
```

---

## Important Notes

### Cross-Chain Timing
- **Initialize functions** send Warp messages to P-Chain
- **Complete functions** must be called AFTER P-Chain confirms
- Typical confirmation time: **1-5 minutes**
- Monitor events to know when to call complete functions

### Minimum Amounts
- **Validator:** 20,000 BEAM minimum
- **Delegator:** No minimum (but gas costs apply)
- **Max per validator:** 200M BEAM + 1000 Node Tokens

### Fees
- **Validator commission:** Set by validator (typically 2-10%)
- **P-Chain fee:** 1.33 AVAX/month (paid by validator)
- **Gas costs:** ~0.21 BEAM per transaction

### Security Considerations
- Use **multisig** for all validator operations
- Track all delegations in contract state
- Monitor validator uptime and performance
- Diversify across multiple validators
- Keep liquidity reserve for user unstakes

---

## Testing on Beam Testnet

**Testnet RPC:** https://subnets.avax.network/beam/testnet/rpc  
**Testnet Chain ID:** 13337  
**Testnet Faucet:** https://faucet.avax.network/ (select Beam Testnet)

**Test Validator ID:**
```
[Get from https://nodes.onbeam.com/validators?network=testnet]
```

---

## Reference Transaction

**Example Delegation Transaction:**
```
Hash: 0x6c3ec397f435601f8e...3773
Block: 6562466
Value: 100 BEAM
Method: 0xcacd9755 (initializeDelegatorRegistration)
Validator: 0x91f190052e6ed57f0f2bf620ecf35f063d4f3075ab5211efb9cf294be5ba855a
```

**Explorer:** https://subnets.avax.network/beam/tx/[hash]

---

## Resources

- **Beam Docs:** https://docs.onbeam.com/nodes/delegation
- **Avalanche L1 Validator Manager:** https://build.avax.network/docs/avalanche-l1s/validator-manager
- **Active Validators:** https://nodes.onbeam.com/validators
- **Beam Explorer:** https://subnets.avax.network/beam

---

## Next Steps

1. ✅ Document validator staking contract (DONE)
2. ⏳ Add validator staking functions to spBEAM.sol
3. ⏳ Create interface file for IPoSValidatorManager
4. ⏳ Write tests for validator integration
5. ⏳ Deploy updated contract to testnet
6. ⏳ Test full staking workflow

---

**Last Updated:** October 19, 2025  
**Contract Version:** spBEAM v1.0  
**Network:** Beam L1 (Mainnet & Testnet)
