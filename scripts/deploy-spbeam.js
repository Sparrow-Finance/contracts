const hre = require("hardhat");

async function main() {
  console.log("🚀 Deploying Sparrow Finance spBEAM (UUPS Upgradeable) ...\n");

  // Deployer
  const [deployer] = await hre.ethers.getSigners();
  console.log("📝 Deployer:", deployer.address);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("💰 Balance:", hre.ethers.formatEther(balance), "BEAM\n");

  // Deploy UUPS proxy
  console.log("⏳ Deploying spBEAM proxy (UUPS)...");
  // Change contract path below to deploy different versions:
  // "contracts/spBEAM/spBEAM.sol:spBEAM" = Basic version (no validator logic)
  // "contracts/spBEAM/spBEAM_WithValidatorLogic.sol:spBEAM" = With validator staking
  const SpBEAM = await hre.ethers.getContractFactory("contracts/spBEAM/spBEAM_WithValidatorLogic.sol:spBEAM");
  const proxy = await hre.upgrades.deployProxy(SpBEAM, [], {
    kind: "uups",
    initializer: "initialize",
  });
  await proxy.waitForDeployment();

  const proxyAddress = await proxy.getAddress();
  const implementationAddress = await hre.upgrades.erc1967.getImplementationAddress(proxyAddress);

  console.log("✅ Proxy deployed to:", proxyAddress);
  console.log("✅ Implementation deployed to:", implementationAddress);

  // Attach and print details
  const spbeam = SpBEAM.attach(proxyAddress);

  console.log("\n📊 Contract Details:");
  console.log("   Name:", await spbeam.name());
  console.log("   Symbol:", await spbeam.symbol());
  console.log("   Decimals:", await spbeam.decimals());
  console.log("   Governance:", await spbeam.governance());

  const stats = await spbeam.getStats();
  console.log("\n⚙️  Initial Configuration:");
  console.log("   Total Pooled BEAM:", hre.ethers.formatEther(stats[0]));
  console.log("   Total Supply:", hre.ethers.formatEther(stats[1]));
  console.log("   Exchange Rate:", hre.ethers.formatEther(stats[2]));
  console.log("   DAO Fee:", stats[6].toString(), "bps (", Number(stats[6]) / 100, "%)");
  console.log("   Dev Fee:", stats[7].toString(), "bps (", Number(stats[7]) / 100, "%)");
  console.log("   Unlock Period:", (await spbeam.unlockPeriod()).toString(), "seconds");

  console.log("\n🔗 Network:", hre.network.name);
  const currentBlock = await hre.ethers.provider.getBlockNumber();
  console.log("📍 Block Number:", currentBlock);

  const deploymentInfo = {
    network: hre.network.name,
    proxyAddress: proxyAddress,
    implementationAddress: implementationAddress,
    deployer: deployer.address,
    blockNumber: currentBlock,
    timestamp: new Date().toISOString(),
    tokenName: await spbeam.name(),
    tokenSymbol: await spbeam.symbol(),
  };

  console.log("\n💾 Deployment Info:");
  console.log(JSON.stringify(deploymentInfo, null, 2));

  // Explorer hint
  console.log("\n📝 Next steps:");
  console.log("   1) Save addresses above.");
  if (hre.network.name === "beamTestnet") {
    console.log("   2) View on Explorer:", `https://subnets-test.avax.network/beam/address/${proxyAddress}`);
  } else if (hre.network.name === "fuji") {
    console.log("   2) View on Snowtrace:", `https://testnet.snowtrace.io/address/${proxyAddress}`);
  } else if (hre.network.name === "mainnet") {
    console.log("   2) View on Snowtrace:", `https://snowtrace.io/address/${proxyAddress}`);
  } else {
    console.log("   2) Explorer link depends on network.");
  }

  console.log("\n🎉 spBEAM deployment complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
