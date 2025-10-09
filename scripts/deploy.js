const hre = require("hardhat");

async function main() {
  console.log("🚀 Deploying Sparrow Finance spAVAX...\n");

  // Get deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log("📝 Deploying with account:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("💰 Account balance:", hre.ethers.formatEther(balance), "AVAX\n");

  // Deploy contract
  console.log("⏳ Deploying spAVAXSimplified contract...");
  const SpAVAX = await hre.ethers.getContractFactory("spAVAXSimplified");
  const spavax = await SpAVAX.deploy();
  
  await spavax.waitForDeployment();
  const contractAddress = await spavax.getAddress();

  console.log("✅ spAVAXSimplified deployed to:", contractAddress);
  console.log("\n📊 Contract Details:");
  console.log("   Name:", await spavax.name());
  console.log("   Symbol:", await spavax.symbol());
  console.log("   Owner:", await spavax.owner());
  
  // Get initial configuration
  const stats = await spavax.getStats();
  console.log("\n⚙️  Initial Configuration:");
  console.log("   Total Pooled AVAX:", hre.ethers.formatEther(stats[0]));
  console.log("   Total Supply:", hre.ethers.formatEther(stats[1]));
  console.log("   Exchange Rate:", hre.ethers.formatEther(stats[2]));
  console.log("   Validator Fee:", stats[7].toString(), "basis points (", Number(stats[7]) / 100, "%)");
  console.log("   DAO Fee:", stats[8].toString(), "basis points (", Number(stats[8]) / 100, "%)");
  console.log("   Dev Fee:", stats[9].toString(), "basis points (", Number(stats[9]) / 100, "%)");
  
  console.log("\n🔗 Network:", hre.network.name);
  console.log("📍 Block Number:", await hre.ethers.provider.getBlockNumber());
  
  // Save deployment info
  const deploymentInfo = {
    network: hre.network.name,
    contractAddress: contractAddress,
    deployer: deployer.address,
    blockNumber: await hre.ethers.provider.getBlockNumber(),
    timestamp: new Date().toISOString(),
    validatorFee: stats[7].toString(),
    daoFee: stats[8].toString(),
    devFee: stats[9].toString()
  };

  console.log("\n💾 Deployment Info:");
  console.log(JSON.stringify(deploymentInfo, null, 2));

  if (hre.network.name === "fuji" || hre.network.name === "mainnet") {
    console.log("\n⏳ Waiting 30 seconds before verification...");
    await new Promise(resolve => setTimeout(resolve, 30000));
    
    console.log("\n🔍 Verifying contract on Snowtrace...");
    try {
      await hre.run("verify:verify", {
        address: contractAddress,
        constructorArguments: [],
      });
      console.log("✅ Contract verified!");
    } catch (error) {
      console.log("❌ Verification failed:", error.message);
      console.log("   You can verify manually later with:");
      console.log(`   npx hardhat verify --network ${hre.network.name} ${contractAddress}`);
    }
  }

  console.log("\n🎉 Deployment complete!");
  console.log("\n📝 Next steps:");
  console.log("   1. Save the contract address:", contractAddress);
  console.log("   2. Test staking with: npx hardhat run scripts/testStake.js --network", hre.network.name);
  console.log("   3. View on Snowtrace:", 
    hre.network.name === "fuji" 
      ? `https://testnet.snowtrace.io/address/${contractAddress}`
      : `https://snowtrace.io/address/${contractAddress}`
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
