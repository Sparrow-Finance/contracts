const hre = require("hardhat");
const { upgrades } = require("hardhat");

async function main() {
  console.log("🚀 Deploying Sparrow Finance spAVAX (UUPS Upgradeable)...\n");

  // Get deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log("📝 Deploying with account:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("💰 Account balance:", hre.ethers.formatEther(balance), "AVAX\n");

  // Deploy using OpenZeppelin Upgrades plugin
  console.log("⏳ Deploying spAVAX with proxy...");
  const SpAVAX = await hre.ethers.getContractFactory("spAVAX");
  
  const spavax = await upgrades.deployProxy(SpAVAX, [], {
    initializer: "initialize",
    kind: "uups"
  });
  
  await spavax.waitForDeployment();
  const proxyAddress = await spavax.getAddress();
  
  console.log("✅ Proxy deployed to:", proxyAddress);
  
  // Get implementation address
  const implementationAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
  console.log("✅ Implementation deployed to:", implementationAddress);

  console.log("\n📊 Contract Details:");
  console.log("   Name:", await spavax.name());
  console.log("   Symbol:", await spavax.symbol());
  console.log("   Decimals:", await spavax.decimals());
  console.log("   Governance:", await spavax.governance());
  
  const stats = await spavax.getStats();
  console.log("\n⚙️  Initial Configuration:");
  console.log("   Total Pooled AVAX:", hre.ethers.formatEther(stats[0]));
  console.log("   Total Supply:", hre.ethers.formatEther(stats[1]));
  console.log("   Exchange Rate:", hre.ethers.formatEther(stats[2]));
  console.log("   DAO Fee:", stats[6].toString(), "basis points (", Number(stats[6]) / 100, "%)");
  console.log("   Dev Fee:", stats[7].toString(), "basis points (", Number(stats[7]) / 100, "%)");
  console.log("   Unlock Period:", (await spavax.unlockPeriod()).toString(), "seconds");
  console.log("   Claim Window:", (await spavax.claimWindow()).toString(), "seconds");
  
  console.log("\n🔗 Network:", hre.network.name);
  console.log("📍 Block Number:", await hre.ethers.provider.getBlockNumber());
  
  const deploymentInfo = {
    network: hre.network.name,
    proxyAddress: proxyAddress,
    implementationAddress: implementationAddress,
    deployer: deployer.address,
    blockNumber: await hre.ethers.provider.getBlockNumber(),
    timestamp: new Date().toISOString(),
    tokenName: await spavax.name(),
    tokenSymbol: await spavax.symbol(),
    daoFee: stats[6].toString(),
    devFee: stats[7].toString()
  };

  console.log("\n💾 Deployment Info:");
  console.log(JSON.stringify(deploymentInfo, null, 2));

  // Verification
  if (hre.network.name === "fuji" || hre.network.name === "mainnet") {
    console.log("\n⏳ Waiting 30 seconds before verification...");
    await new Promise(resolve => setTimeout(resolve, 30000));
    
    console.log("\n🔍 Verifying implementation on Snowtrace...");
    try {
      await hre.run("verify:verify", {
        address: implementationAddress,
        constructorArguments: [],
      });
      console.log("✅ Implementation verified!");
    } catch (error) {
      console.log("❌ Verification failed:", error.message);
      console.log("   You can verify manually later with:");
      console.log(`   npx hardhat verify --network ${hre.network.name} ${implementationAddress}`);
    }
  }

  console.log("\n🎉 Deployment complete!");
  console.log("\n📝 IMPORTANT - Save these addresses:");
  console.log("   🔷 Proxy (use this for interactions):", proxyAddress);
  console.log("   🔸 Implementation:", implementationAddress);
  console.log("\n📝 Next steps:");
  console.log("   1. Update UI with proxy address:", proxyAddress);
  console.log("   2. Test staking with: npx hardhat run scripts/testStake.js --network", hre.network.name);
  console.log("   3. View on Snowtrace:", 
    hre.network.name === "fuji" 
      ? `https://testnet.snowtrace.io/address/${proxyAddress}`
      : `https://snowtrace.io/address/${proxyAddress}`
  );
  console.log("\n⚠️  Token will appear in Snowtrace search after:");
  console.log("   - Contract is verified ✓");
  console.log("   - First transaction occurs");
  console.log("   - ~5 minutes for indexing");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
