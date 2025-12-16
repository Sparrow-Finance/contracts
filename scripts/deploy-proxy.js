const hre = require("hardhat");
const { upgrades } = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("🚀 SPARROW FINANCE - spAVAX V3 DEPLOYMENT (ERC4626 + NFT)");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  // ============================================
  // STEP 1: PRE-FLIGHT CHECKS
  // ============================================
  console.log("📋 Pre-flight Checks...\n");

  const [deployer] = await hre.ethers.getSigners();
  console.log("👤 Deployer Address:", deployer.address);
  
  const expectedAddress = process.env.C_CHAIN_ADDRESS;
  if (deployer.address.toLowerCase() !== expectedAddress.toLowerCase()) {
    console.log("⚠️  WARNING: Deployer address doesn't match C_CHAIN_ADDRESS in .env");
    console.log("   Expected:", expectedAddress);
    console.log("   Got:", deployer.address);
    throw new Error("Address mismatch - check your PRIVATE_KEY in .env");
  }
  console.log("✅ Deployer address verified\n");

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

  console.log("🌐 Network:", hre.network.name);
  const chainId = await hre.ethers.provider.getNetwork().then(n => n.chainId);
  console.log("🔗 Chain ID:", chainId);
  
  if (hre.network.name === "fuji" && chainId !== 43113n) {
    throw new Error("Chain ID mismatch - expected Fuji (43113)");
  }
  console.log("✅ Network verified\n");

  // ============================================
  // STEP 2: DEPLOY NFT CONTRACT
  // ============================================
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("📦 Deploying WithdrawalQueueNFT Contract...");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const WithdrawalQueueNFT = await hre.ethers.getContractFactory("WithdrawalQueueNFT");
  
  console.log("⏳ Deploying NFT contract...");
  const nft = await WithdrawalQueueNFT.deploy(deployer.address);
  
  console.log("⏳ Waiting for deployment transaction...");
  await nft.waitForDeployment();
  
  const nftAddress = await nft.getAddress();
  console.log("✅ NFT Contract deployed:", nftAddress, "\n");

  // Wait for confirmations
  const confirmations = parseInt(process.env.CONFIRMATIONS || "3");
  console.log(`⏳ Waiting for ${confirmations} confirmations...`);
  await new Promise(resolve => setTimeout(resolve, confirmations * 2000));
  console.log("✅ Confirmations complete\n");

  // ============================================
  // STEP 3: DEPLOY SPAVAX CONTRACT (UUPS PROXY)
  // ============================================
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("📦 Deploying spAVAX Contract...");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const SpAVAX = await hre.ethers.getContractFactory("spAVAX");
  
  console.log("⏳ Deploying UUPS proxy...");
  const spavax = await upgrades.deployProxy(SpAVAX, [], {
    initializer: "initialize",
    kind: "uups"
  });
  
  console.log("⏳ Waiting for deployment transaction...");
  await spavax.waitForDeployment();
  
  const proxyAddress = await spavax.getAddress();
  console.log("✅ Proxy deployed:", proxyAddress, "\n");

  const implementationAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
  console.log("✅ Implementation deployed:", implementationAddress, "\n");

  console.log(`⏳ Waiting for ${confirmations} confirmations...`);
  await new Promise(resolve => setTimeout(resolve, confirmations * 2000));
  console.log("✅ Confirmations complete\n");

  // ============================================
  // STEP 4: LINK CONTRACTS
  // ============================================
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("🔗 Linking Contracts...");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  console.log("⏳ Setting NFT contract in spAVAX...");
  const tx1 = await spavax.setWithdrawalNFT(nftAddress);
  await tx1.wait();
  console.log("✅ NFT contract set in spAVAX\n");

  console.log("⏳ Setting vault address in NFT...");
  const tx2 = await nft.setVault(proxyAddress);
  await tx2.wait();
  console.log("✅ Vault address set in NFT\n");

  // Verify linking
  const nftFromSpavax = await spavax.withdrawalQueueNFT();
  const vaultFromNft = await nft.vault();
  
  if (nftFromSpavax.toLowerCase() !== nftAddress.toLowerCase()) {
    throw new Error("NFT linking verification failed in spAVAX");
  }
  if (vaultFromNft.toLowerCase() !== proxyAddress.toLowerCase()) {
    throw new Error("Vault linking verification failed in NFT");
  }
  console.log("✅ Contract linking verified\n");

  // ============================================
  // STEP 5: VERIFY DEPLOYMENT
  // ============================================
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("🔍 Verifying Deployment...");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const name = await spavax.name();
  const symbol = await spavax.symbol();
  const decimals = await spavax.decimals();
  const governance = await spavax.governance();
  const asset = await spavax.asset();

  console.log("📊 Token Information:");
  console.log("   Name:", name);
  console.log("   Symbol:", symbol);
  console.log("   Decimals:", decimals);
  console.log("   Asset:", asset, "(native AVAX)");
  console.log("   Governance:", governance, "\n");

  if (governance.toLowerCase() !== deployer.address.toLowerCase()) {
    console.log("⚠️  WARNING: Governance address mismatch!");
    throw new Error("Governance should be deployer address");
  }

  const stats = await spavax.getStats();
  const unlockPeriod = await spavax.unlockPeriod();
  const claimWindow = await spavax.claimWindow();
  const minStakeAmount = await spavax.minStakeAmount();

  console.log("⚙️  Contract Configuration:");
  console.log("   Total Pooled AVAX:", hre.ethers.formatEther(stats[0]), "AVAX");
  console.log("   Total Supply:", hre.ethers.formatEther(stats[1]), "spAVAX");
  console.log("   Exchange Rate:", hre.ethers.formatEther(stats[2]));
  console.log("   Total Locked:", hre.ethers.formatEther(stats[3]), "AVAX");
  console.log("   DAO Fees:", hre.ethers.formatEther(stats[4]), "AVAX");
  console.log("   Dev Fees:", hre.ethers.formatEther(stats[5]), "AVAX");
  console.log("   Unlock Period:", unlockPeriod.toString(), "seconds");
  console.log("   Claim Window:", claimWindow.toString(), "seconds");
  console.log("   Min Stake:", hre.ethers.formatEther(minStakeAmount), "AVAX\n");

  // ============================================
  // STEP 6: VERIFY ON SNOWTRACE
  // ============================================
  if (process.env.VERIFY_CONTRACT === "true" && 
      (hre.network.name === "fuji" || hre.network.name === "mainnet")) {
    
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("🔍 Verifying on Snowtrace...");
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    
    console.log("⏳ Waiting 30 seconds for Snowtrace indexing...");
    await new Promise(resolve => setTimeout(resolve, 30000));
    
    try {
      console.log("⏳ Verifying NFT contract...");
      await hre.run("verify:verify", {
        address: nftAddress,
        constructorArguments: [deployer.address],
      });
      console.log("✅ NFT contract verified on Snowtrace!\n");
    } catch (error) {
      if (error.message.includes("Already Verified")) {
        console.log("✅ NFT contract already verified!\n");
      } else {
        console.log("❌ NFT verification failed:", error.message);
        console.log(`   Manual: npx hardhat verify --network ${hre.network.name} ${nftAddress} ${deployer.address}\n`);
      }
    }
    
    try {
      console.log("⏳ Verifying spAVAX implementation...");
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
        console.log(`   Manual: npx hardhat verify --network ${hre.network.name} ${implementationAddress}\n`);
      }
    }
  }

  // ============================================
  // STEP 7: DEPLOYMENT SUMMARY
  // ============================================
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("✅ DEPLOYMENT SUCCESSFUL!");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

  const deploymentInfo = {
    network: hre.network.name,
    chainId: Number(chainId),
    nftAddress: nftAddress,
    proxyAddress: proxyAddress,
    implementationAddress: implementationAddress,
    deployer: deployer.address,
    governance: governance,
    blockNumber: await hre.ethers.provider.getBlockNumber(),
    timestamp: new Date().toISOString(),
    tokenName: name,
    tokenSymbol: symbol,
    configuration: {
      unlockPeriodSeconds: unlockPeriod.toString(),
      claimWindowSeconds: claimWindow.toString(),
      minStakeAmount: hre.ethers.formatEther(minStakeAmount)
    }
  };

  console.log("📄 Deployment Information:");
  console.log(JSON.stringify(deploymentInfo, null, 2));
  console.log("");

  // ============================================
  // STEP 8: NEXT STEPS
  // ============================================
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("📝 IMPORTANT - SAVE THESE ADDRESSES:");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
  
  console.log("🔷 SPAVAX PROXY ADDRESS (use this for staking):");
  console.log("   " + proxyAddress);
  console.log("\n🔶 NFT CONTRACT ADDRESS (for withdrawal NFTs):");
  console.log("   " + nftAddress);
  console.log("\n🔸 IMPLEMENTATION ADDRESS (for reference only):");
  console.log("   " + implementationAddress);
  console.log("");

  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("📋 NEXT STEPS:");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
  
  console.log("1️⃣  Update .env file:");
  console.log("   SPAVAX_PROXY_ADDRESS=" + proxyAddress);
  console.log("   SPAVAX_NFT_ADDRESS=" + nftAddress);
  console.log("   SPAVAX_IMPLEMENTATION_ADDRESS=" + implementationAddress);
  console.log("");
  
  console.log("2️⃣  Test the deployment:");
  console.log("   npx hardhat test test/spAVAX.test.js --network " + hre.network.name);
  console.log("");
  
  console.log("3️⃣  View on Snowtrace:");
  const explorerUrl = hre.network.name === "fuji"
    ? `https://testnet.snowtrace.io/address/${proxyAddress}`
    : `https://snowtrace.io/address/${proxyAddress}`;
  console.log("   spAVAX: " + explorerUrl);
  const nftExplorerUrl = hre.network.name === "fuji"
    ? `https://testnet.snowtrace.io/address/${nftAddress}`
    : `https://snowtrace.io/address/${nftAddress}`;
  console.log("   NFT: " + nftExplorerUrl);
  console.log("");
  
  console.log("4️⃣  New Features in V3:");
  console.log("   ✅ ERC-4626 compliant (depositAVAX/withdraw)");
  console.log("   ✅ NFT-based withdrawals (tradeable positions)");
  console.log("   ✅ Backward compatible with V1 (stake/requestUnlock)");
  console.log("");

  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("⚠️  IMPORTANT NOTES:");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
  
  console.log("- Unlock period is 60 seconds (FOR TESTING ONLY)");
  console.log("- Change to 15 days for production: setUnlockPeriod(1296000)");
  console.log("- Users can use EITHER legacy or ERC-4626 flow");
  console.log("- Withdrawal NFTs are tradeable on OpenSea/Kalao");
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