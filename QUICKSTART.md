# Quick Start Guide - Sparrow Finance spAVAX

## 🚀 Setup Complete!

Your project is now ready to compile and test.

---

## 📋 Prerequisites

✅ Node.js installed  
✅ npm packages installed (`npm install` - DONE!)  
✅ Contract in `contracts/` folder  
✅ Hardhat configured  

---

## 🔨 Step 1: Compile the Contract

```powershell
npx hardhat compile
```

**Expected output:**
```
Compiled 1 Solidity file successfully
```

**What this does:**
- Compiles `spAVAXSimplified.sol`
- Generates ABI and bytecode
- Creates `artifacts/` folder
- Checks for syntax errors

---

## 🧪 Step 2: Run Tests

```powershell
npx hardhat test
```

**Expected output:**
```
  spAVAXSimplified
    Deployment
      ✔ Should set the right owner
      ✔ Should have correct name and symbol
      ... (50+ tests)
    
  50 passing (2s)
```

**What this tests:**
- ✅ Staking functionality
- ✅ Unlock requests
- ✅ Claim unlocks
- ✅ Fee distribution
- ✅ Admin functions
- ✅ Edge cases

---

## 📊 Step 3: Check Test Coverage (Optional)

```powershell
npx hardhat coverage
```

---

## 🌐 Step 4: Deploy to Fuji Testnet

### **4.1 Get Test AVAX**

Visit: https://faucet.avax.network/
- Connect your wallet
- Request test AVAX

### **4.2 Create .env File**

Copy `.env.example` to `.env`:
```powershell
Copy-Item .env.example .env
```

Edit `.env` and add:
```
PRIVATE_KEY=your_private_key_here
FUJI_RPC_URL=https://api.avax-test.network/ext/bc/C/rpc
```

⚠️ **NEVER commit .env to git!**

### **4.3 Deploy**

```powershell
npx hardhat run scripts/deploy.js --network fuji
```

**Expected output:**
```
🚀 Deploying Sparrow Finance spAVAX...
📝 Deploying with account: 0x...
💰 Account balance: 10.0 AVAX

✅ spAVAXSimplified deployed to: 0x...
📊 Contract Details:
   Name: Sparrow Staked AVAX
   Symbol: spAVAX
   Owner: 0x...
```

**Save the contract address!**

---

## 🔍 Step 5: Verify on Snowtrace

### **Automatic (if configured):**
Verification happens automatically after deployment.

### **Manual:**
```powershell
npx hardhat verify --network fuji YOUR_CONTRACT_ADDRESS
```

---

## 🎮 Step 6: Interact with Contract

### **Using Hardhat Console:**

```powershell
npx hardhat console --network fuji
```

Then:
```javascript
const SpAVAX = await ethers.getContractFactory("spAVAXSimplified");
const spavax = await SpAVAX.attach("YOUR_CONTRACT_ADDRESS");

// Check stats
const stats = await spavax.getStats();
console.log("Total Pooled AVAX:", ethers.formatEther(stats[0]));

// Stake AVAX
await spavax.stake({ value: ethers.parseEther("1") });

// Check balance
const balance = await spavax.balanceOf("YOUR_ADDRESS");
console.log("spAVAX Balance:", ethers.formatEther(balance));
```

---

## 📝 Common Commands

### **Compile:**
```powershell
npx hardhat compile
```

### **Test:**
```powershell
npx hardhat test                    # Run all tests
npx hardhat test --grep "Staking"  # Run specific tests
```

### **Deploy:**
```powershell
npx hardhat run scripts/deploy.js --network fuji      # Fuji testnet
npx hardhat run scripts/deploy.js --network mainnet   # Mainnet (careful!)
```

### **Verify:**
```powershell
npx hardhat verify --network fuji CONTRACT_ADDRESS
```

### **Clean:**
```powershell
npx hardhat clean  # Remove artifacts and cache
```

---

## 🐛 Troubleshooting

### **Error: Cannot find module '@openzeppelin/contracts'**
```powershell
npm install @openzeppelin/contracts
```

### **Error: Invalid private key**
- Check your `.env` file
- Make sure `PRIVATE_KEY` is set correctly
- Don't include "0x" prefix

### **Error: Insufficient funds**
- Get test AVAX from faucet
- Check your balance: `npx hardhat console --network fuji`
  ```javascript
  const balance = await ethers.provider.getBalance("YOUR_ADDRESS");
  console.log(ethers.formatEther(balance));
  ```

### **Compilation errors:**
- Check Solidity version in `hardhat.config.js` matches contract (0.8.20)
- Run `npx hardhat clean` then compile again

---

## 📚 Next Steps

After successful deployment:

1. **Test on Fuji:**
   - Stake some test AVAX
   - Request unlock
   - Test all functions

2. **Build Interface:**
   - Create web UI
   - Connect with ethers.js
   - Test user flows

3. **Prepare for Mainnet:**
   - Get professional audit
   - Set up multisig
   - Update configuration
   - Deploy!

---

## 🔗 Useful Links

- **Fuji Faucet:** https://faucet.avax.network/
- **Fuji Explorer:** https://testnet.snowtrace.io/
- **Mainnet Explorer:** https://snowtrace.io/
- **Avalanche Docs:** https://docs.avax.network/
- **Hardhat Docs:** https://hardhat.org/docs

---

## 📞 Need Help?

Check the documentation:
- `README.md` - Project overview
- `FEE_STRUCTURE.md` - Fee distribution
- `UNLOCK_SYSTEM.md` - Unlock mechanics
- `AUDIT_REPORT.md` - Security audit

---

## ✅ Checklist

- [ ] Compiled successfully
- [ ] All tests passing
- [ ] Deployed to Fuji
- [ ] Verified on Snowtrace
- [ ] Tested staking
- [ ] Tested unstaking
- [ ] Tested admin functions
- [ ] Ready for mainnet!

---

**🎉 You're ready to go! Start with `npx hardhat compile`**
