const hre = require("hardhat");

async function main() {
  console.log("🔄 Upgrading spBEAM to V2 (No Expiry System)...\n");

  // Get deployer
  const [deployer] = await hre.ethers.getSigners();
  console.log("📝 Upgrader:", deployer.address);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("💰 Balance:", hre.ethers.formatEther(balance), "BEAM\n");

  // Get proxy address from .env or use default
  const PROXY_ADDRESS = process.env.BEAM_V2_PROXY || "0x4d3F457c9a6Fd430F661283d92b9E7aA8ae638B8";
  const HELPER_ADDRESS = process.env.BEAM_VALIDATOR_HELPER || "0xD0860B697825b80C6Cf21aB0Bb9B02A1Dc672F83";

  console.log("📍 Proxy Address:", PROXY_ADDRESS);
  console.log("📍 Helper Address:", HELPER_ADDRESS);

  // Get current implementation
  const currentImpl = await hre.upgrades.erc1967.getImplementationAddress(PROXY_ADDRESS);
  console.log("📦 Current Implementation:", currentImpl);

  // Deploy new implementation
  console.log("\n⏳ Deploying spBEAM_V2 (V3 features) implementation...");
  console.log("   New features in V3:");
  console.log("   ✅ sendToValidatorHelper() - Send BEAM to helper");
  console.log("   ✅ setValidatorHelper() - Set helper address");
  console.log("   ✅ Enhanced security and governance");
  console.log("   ✅ Automated delegation support\n");
  
  const SpBEAMV2 = await hre.ethers.getContractFactory("spBEAM_V2");

  // Upgrade the proxy
  const upgraded = await hre.upgrades.upgradeProxy(PROXY_ADDRESS, SpBEAMV2);
  await upgraded.waitForDeployment();

  // Get new implementation address
  const newImpl = await hre.upgrades.erc1967.getImplementationAddress(PROXY_ADDRESS);
  console.log("✅ New Implementation:", newImpl);

  // Verify upgrade
  console.log("\n🔍 Verifying upgrade...");
  const spbeam = SpBEAMV2.attach(PROXY_ADDRESS);

  console.log("\n📊 Contract Details (After Upgrade):");
  console.log("   Name:", await spbeam.name());
  console.log("   Symbol:", await spbeam.symbol());
  console.log("   Governance:", await spbeam.governance());

  const stats = await spbeam.getStats();
  console.log("\n⚙️  Current State:");
  console.log("   Total Pooled BEAM:", hre.ethers.formatEther(stats[0]));
  console.log("   Total Supply:", hre.ethers.formatEther(stats[1]));
  console.log("   Exchange Rate:", hre.ethers.formatEther(stats[2]));

  // Check unlock period
  const unlockPeriod = await spbeam.unlockPeriod();
  console.log("\n⚙️  Configuration:");
  console.log("   Unlock Period:", unlockPeriod.toString(), "seconds (", Number(unlockPeriod) / 86400, "days)");
  
  // Check validator helper (wrap in try-catch for first upgrade)
  console.log("\n🔗 Validator Helper:");
  try {
    const currentHelper = await spbeam.validatorHelper();
    console.log("   Current:", currentHelper);
    
    if (currentHelper === "0x0000000000000000000000000000000000000000") {
      console.log("   Status: ⚠️  Not set yet");
      console.log("\n⏳ Setting validator helper...");
      const setHelperTx = await spbeam.setValidatorHelper(HELPER_ADDRESS);
      await setHelperTx.wait();
      console.log("✅ Helper set to:", HELPER_ADDRESS);
    } else {
      console.log("   Status: ✅ Already set");
    }
  } catch (error) {
    console.log("   Status: ⚠️  Not initialized yet (first upgrade)");
    console.log("\n⏳ Setting validator helper...");
    const setHelperTx = await spbeam.setValidatorHelper(HELPER_ADDRESS);
    await setHelperTx.wait();
    console.log("✅ Helper set to:", HELPER_ADDRESS);
  }
  
  console.log("\n✅ New Functions (V3):");
  console.log("   - sendToValidatorHelper() - Send BEAM to helper for delegation");
  console.log("   - setValidatorHelper() - Update helper address");
  
  console.log("\n✅ Core Functions:");
  console.log("   - stake() - Deposit BEAM, get spBEAM");
  console.log("   - requestUnlock() - Start 21-day unlock");
  console.log("   - claimUnlock() - Claim after unlock (no expiry!)");
  console.log("   - addRewards() - Add rewards to pool");

  const upgradeInfo = {
    network: hre.network.name,
    proxyAddress: PROXY_ADDRESS,
    oldImplementation: currentImpl,
    newImplementation: newImpl,
    upgrader: deployer.address,
    blockNumber: await hre.ethers.provider.getBlockNumber(),
    timestamp: new Date().toISOString(),
    unlockPeriodDays: Number(unlockPeriod) / 86400,
    validatorHelper: HELPER_ADDRESS,
  };

  console.log("\n💾 Upgrade Info:");
  console.log(JSON.stringify(upgradeInfo, null, 2));

  console.log("\n📝 Next Steps:");
  console.log("   1) Send BEAM to helper: sendToValidatorHelper(100 ether)");
  console.log("   2) Activate validator: scripts/activate-validator.js");
  console.log("   3) Delegate to validator: scripts/delegate-beam.js");
  console.log("   4) Complete delegation: scripts/complete-delegation.js");
  console.log("   5) Claim rewards: scripts/claim-rewards.js");

  console.log("\n🎉 Upgrade to V2 complete! All user balances and data preserved!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Upgrade failed:", error);
    process.exit(1);
  });
