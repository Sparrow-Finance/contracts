const hre = require("hardhat");

async function main() {
  console.log("🚀 Deploying spBeam_Validator_Helper (UUPS Upgradeable) ...\n");

  // Deployer
  const [deployer] = await hre.ethers.getSigners();
  console.log("📝 Deployer:", deployer.address);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("💰 Balance:", hre.ethers.formatEther(balance), "BEAM\n");

  // Required addresses
  const SPBEAM_PROXY = process.env.BEAM_V2_PROXY || "0x4d3F457c9a6Fd430F661283d92b9E7aA8ae638B8";
  const BEAM_STAKING = process.env.BEAM_STAKING_CONTRACT || "0x0000000000000000000000000000000000000000"; // ← UPDATE THIS!

  console.log("📍 spBEAM_V2 Proxy:", SPBEAM_PROXY);
  console.log("📍 Beam Staking Contract:", BEAM_STAKING);

  if (BEAM_STAKING === "0x0000000000000000000000000000000000000000") {
    console.log("\n⚠️  WARNING: BEAM_STAKING_CONTRACT not set in .env!");
    console.log("   Please set BEAM_STAKING_CONTRACT to Beam's native staking address");
    console.log("   Continuing with placeholder...\n");
  }

  // Deploy UUPS proxy
  console.log("⏳ Deploying spBeam_Validator_Helper proxy (UUPS)...");
  console.log("   Features:");
  console.log("   - Multi-validator support");
  console.log("   - Batch delegation/undelegation");
  console.log("   - Per-validator tracking");
  console.log("   - Reward claiming");
  console.log("   - Rotation strategy\n");

  const ValidatorHelper = await hre.ethers.getContractFactory("spBeam_Validator_Helper");
  
  const proxy = await hre.upgrades.deployProxy(
    ValidatorHelper,
    [SPBEAM_PROXY, BEAM_STAKING],
    {
      kind: "uups",
      initializer: "initialize",
    }
  );
  
  await proxy.waitForDeployment();

  const proxyAddress = await proxy.getAddress();
  const implementationAddress = await hre.upgrades.erc1967.getImplementationAddress(proxyAddress);

  console.log("✅ Proxy deployed to:", proxyAddress);
  console.log("✅ Implementation deployed to:", implementationAddress);

  // Attach and print details
  const helper = ValidatorHelper.attach(proxyAddress);

  console.log("\n📊 Contract Details:");
  try {
    console.log("   spBEAM Address:", await helper.spBEAM());
    console.log("   Beam Staking:", await helper.beamStaking());
    
    const validatorCount = await helper.getValidatorCount();
    console.log("\n⚙️  Initial State:");
    console.log("   Validator Count:", validatorCount.toString());
    console.log("   Total Delegated:", hre.ethers.formatEther(await helper.getTotalDelegated()), "BEAM");
  } catch (error) {
    console.log("   (Contract details will be available after initialization)");
  }

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
    spBeamAddress: SPBEAM_PROXY,
    beamStakingAddress: BEAM_STAKING,
  };

  console.log("\n💾 Deployment Info:");
  console.log(JSON.stringify(deploymentInfo, null, 2));

  // Explorer hint
  console.log("\n📝 Next steps:");
  console.log("   1) Save addresses above.");
  if (hre.network.name === "beamTestnet") {
    console.log("   2) View on Explorer:", `https://subnets-test.avax.network/beam/address/${proxyAddress}`);
  }
  console.log("   3) Update .env with: BEAM_VALIDATOR_HELPER=", proxyAddress);
  console.log("   4) Add validators: addValidator(validatorAddress)");
  console.log("   5) Activate validators: setValidatorActive(validatorId, true)");
  console.log("   6) Delegate BEAM: initiateBatchDelegation(validatorId, amount)");
  console.log("   7) Set helper in spBEAM_V2 (if needed)");

  console.log("\n🎉 Validator Helper deployment complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
