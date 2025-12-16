const hre = require("hardhat");
const { upgrades } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("🚀 SPARROW FINANCE - spAVAX DEPLOYMENT (UUPS)");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // ============================================
  // STEP 1: PRE-FLIGHT CHECKS
  // ============================================
  console.log("📋 Pre-flight Checks...\n");

  // Get deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log("👤 Deployer Address:", deployer.address);
  
  // Check if deployer matches expected address
  const expectedAddress = process.env.C_CHAIN_ADDRESS;
  if (deployer.address.toLowerCase() !== expectedAddress.toLowerCase()) {
    console.log("⚠️  WARNING: Deployer address doesn't match C_CHAIN_ADDRESS in .env");
    console.log("   Expected:", expectedAddress);
    console.log("   Got:", deployer.address);
    throw new Error("Address mismatch - check your PRIVATE_KEY in .env");
  }
  console.log("✅ Deployer address verified\n");

  // Check balance
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  const balanceInAvax = hre.ethers.formatEther(balance);
  console.log("💰 Balance:", balanceInAvax, "AVAX");
  
  if (parseFloat(balanceInAvax) < 1) {
    console.log("⚠️  WARNING: Low balance detected!");
    console.log("   Minimum recommended: 1 AVAX");
    console.log("   Get testnet AVAX from: https://core.app/tools/testnet-faucet/");
    throw new Error("Insufficient balance for deployment");
  }
  console.log("✅ Sufficient balance for deployment\n");

  // Network info
  console.log("🌐 Network:", hre.network.name);
  const chainId = await hre.ethers.provider.getNetwork().then(n => n.chainId);
  console.log("🔗 Chain ID:", chainId);
  
  if (hre.network.name === "fuji" && chainId !== 43113n) {
    throw new Error("Chain ID mismatch - expected Fuji (43113)");
  }
  console.log("✅ Network verified\n");

  // ============================================
  // STEP 2: DEPLOY CONTRACT
  // ============================================
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("📦 Deploying spAVAX Contract...");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const SpAVAX = await hre.ethers.getContractFactory("spAVAX");
  
  console.log("⏳ Deploying proxy...");
  const spavax = await upgrades.deployProxy(SpAVAX, [], {
    initializer: "initialize",
    kind: "uups"
  });
  
  console.log("⏳ Waiting for deployment transaction...");
  await spavax.waitForDeployment();
  
  const proxyAddress = await spavax.getAddress();
  console.log("✅ Proxy deployed:", proxyAddress, "\n");

  // Get implementation address
  const implementationAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
  console.log("✅ Implementation deployed:", implementationAddress, "\n");

  // Wait for confirmations
  const confirmations = parseInt(process.env.CONFIRMATIONS || "3");
  console.log(`⏳ Waiting for ${confirmations} confirmations...`);
  await new Promise(resolve => setTimeout(resolve, confirmations * 2000)); // ~2 sec per block
  console.log("✅ Confirmations complete\n");

  // ============================================
  // STEP 3: VERIFY DEPLOYMENT
  // ============================================
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("🔍 Verifying Deployment...");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // Basic contract info
  const name = await spavax.name();
  const symbol = await spavax.symbol();
  const decimals = await spavax.decimals();
  const governance = await spavax.governance();

  console.log("📊 Token Information:");
  console.log("   Name:", name);
  console.log("   Symbol:", symbol);
  console.log("   Decimals:", decimals);
  console.log("   Governance:", governance, "\n");

  if (governance.toLowerCase() !== deployer.address.toLowerCase()) {
    console.log("⚠️  WARNING: Governance address mismatch!");
    throw new Error("Governance should be deployer address");
  }

  // Get contract stats
  const stats = await spavax.getStats();
  const unlockPeriod = await spavax.unlockPeriod();
  const claimWindow = await spavax.claimWindow();
  const minStakeAmount = await spavax.minStakeAmount();

  console.log("⚙️  Contract Configuration:");
  console.log("   Total Pooled AVAX:", hre.ethers.formatEther(stats[0]), "AVAX");
  console.log("   Total Supply:", hre.ethers.formatEther(stats[1]), "spAVAX");
  console.log("   Exchange Rate:", hre.ethers.formatEther(stats[2]));
  console.log("   Liquid Balance:", hre.ethers.formatEther(stats[3]), "AVAX");
  console.log("   DAO Fee:", stats[6].toString(), "bps (", Number(stats[6]) / 100, "%)");
  console.log("   Dev Fee:", stats[7].toString(), "bps (", Number(stats[7]) / 100, "%)");
  console.log("   Unlock Period:", unlockPeriod.toString(), "seconds (", Number(unlockPeriod) / 86400, "days)");
  console.log("   Claim Window:", claimWindow.toString(), "seconds (", Number(claimWindow) / 86400, "days)");
  console.log("   Min Stake:", hre.ethers.formatEther(minStakeAmount), "AVAX\n");

  // ============================================
  // STEP 4: VERIFY ON SNOWTRACE
  // ============================================
  if (process.env.VERIFY_CONTRACT === "true" && 
      (hre.network.name === "fuji" || hre.network.name === "mainnet")) {
    
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("🔍 Verifying on Snowtrace...");
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    
    console.log("⏳ Waiting 30 seconds for Snowtrace indexing...");
    await new Promise(resolve => setTimeout(resolve, 30000));
    
    try {
      console.log("⏳ Verifying implementation contract...");
      await hre.run("verify:verify", {
        address: implementationAddress,
        constructorArguments: [],
      });
      console.log("✅ Implementation verified on Snowtrace!\n");
    } catch (error) {
      if (error.message.includes("Already Verified")) {
        console.log("✅ Implementation already verified!\n");
      } else {
        console.log("❌ Verification failed:", error.message);
        console.log("   You can verify manually with:");
        console.log(`   npx hardhat verify --network ${hre.network.name} ${implementationAddress}\n`);
      }
    }
  }

  // ============================================
  // STEP 5: DEPLOYMENT SUMMARY
  // ============================================
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("✅ DEPLOYMENT SUCCESSFUL!");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const deploymentInfo = {
    network: hre.network.name,
    chainId: Number(chainId),
    proxyAddress: proxyAddress,
    implementationAddress: implementationAddress,
    deployer: deployer.address,
    governance: governance,
    blockNumber: await hre.ethers.provider.getBlockNumber(),
    timestamp: new Date().toISOString(),
    tokenName: name,
    tokenSymbol: symbol,
    configuration: {
      daoFeeBps: stats[6].toString(),
      devFeeBps: stats[7].toString(),
      unlockPeriodSeconds: unlockPeriod.toString(),
      claimWindowSeconds: claimWindow.toString(),
      minStakeAmount: hre.ethers.formatEther(minStakeAmount)
    }
  };

  console.log("📄 Deployment Information:");
  console.log(JSON.stringify(deploymentInfo, null, 2));
  console.log("");

  // ============================================
  // STEP 6: NEXT STEPS
  // ============================================
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("📝 IMPORTANT - SAVE THESE ADDRESSES:");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
  
  console.log("🔷 PROXY ADDRESS (use this for all interactions):");
  console.log("   " + proxyAddress);
  console.log("\n🔸 IMPLEMENTATION ADDRESS (for reference only):");
  console.log("   " + implementationAddress);
  console.log("");

  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("📋 NEXT STEPS:");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
  
  console.log("1️⃣  Update .env file:");
  console.log("   SPAVAX_PROXY_ADDRESS=" + proxyAddress);
  console.log("   SPAVAX_IMPLEMENTATION_ADDRESS=" + implementationAddress);
  console.log("");
  
  console.log("2️⃣  Update frontend configuration:");
  console.log("   - Update contract address in UI");
  console.log("   - Update ABI if needed");
  console.log("");
  
  console.log("3️⃣  Test the deployment:");
  console.log("   npx hardhat run scripts/testStake.js --network " + hre.network.name);
  console.log("");
  
  console.log("4️⃣  View on Snowtrace:");
  const explorerUrl = hre.network.name === "fuji"
    ? `https://testnet.snowtrace.io/address/${proxyAddress}`
    : `https://snowtrace.io/address/${proxyAddress}`;
  console.log("   " + explorerUrl);
  console.log("");
  
  console.log("5️⃣  Add validator delegation:");
  console.log("   - Use withdraw() to send AVAX to validator");
  console.log("   - Delegate to: " + process.env.VALIDATOR_NODE_ID);
  console.log("");

  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("⚠️  IMPORTANT NOTES:");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
  
  console.log("- Contract will appear in Snowtrace after first transaction");
  console.log("- Indexing may take 5-10 minutes");
  console.log("- Current unlock period is 60 seconds (FOR TESTING ONLY)");
  console.log("- Change to 15 days for production using setUnlockPeriod()");
  console.log("");
  
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ DEPLOYMENT FAILED:", error);
    console.error("\nError details:", error.message);
    if (error.stack) {
      console.error("\nStack trace:", error.stack);
    }
    process.exit(1);
  });