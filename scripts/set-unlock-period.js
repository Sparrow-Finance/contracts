const hre = require("hardhat");

async function main() {
  console.log("⏰ Setting Unlock Period...\n");

  // Get deployer
  const [deployer] = await hre.ethers.getSigners();
  console.log("📝 Caller:", deployer.address);

  const PROXY_ADDRESS = "0x21e9726d777400c5dcBF65cF595125B21359A1DD";
  
  // Set to 60 seconds for testnet, 22 days for mainnet
  const UNLOCK_PERIOD = hre.network.name === "beamTestnet" ? 60 : (22 * 24 * 60 * 60);
  
  console.log("📍 Proxy Address:", PROXY_ADDRESS);
  console.log("🌐 Network:", hre.network.name);
  console.log("⏰ New Unlock Period:", UNLOCK_PERIOD, "seconds");
  
  if (hre.network.name === "beamTestnet") {
    console.log("   (60 seconds = 1 minute for testing)");
  } else {
    console.log("   (22 days for mainnet)");
  }

  // Attach to contract
  const SpBEAM = await hre.ethers.getContractFactory(
    "contracts/spBEAM/spBEAM_WithValidatorLogic.sol:spBEAM"
  );
  const spbeam = SpBEAM.attach(PROXY_ADDRESS);

  // Check governance
  const governance = await spbeam.governance();
  console.log("\n🔐 Governance Address:", governance);
  
  if (deployer.address.toLowerCase() !== governance.toLowerCase()) {
    console.log("⚠️  WARNING: You are not governance! This call will fail.");
    return;
  }

  // Get current unlock period
  const currentPeriod = await spbeam.unlockPeriod();
  console.log("\n📊 Current Unlock Period:", currentPeriod.toString(), "seconds");
  
  if (currentPeriod.toString() === UNLOCK_PERIOD.toString()) {
    console.log("✅ Unlock period is already set to", UNLOCK_PERIOD, "seconds!");
    return;
  }

  // Set new unlock period
  console.log("\n⏳ Setting unlock period to", UNLOCK_PERIOD, "seconds...");
  const tx = await spbeam.setUnlockPeriod(UNLOCK_PERIOD);
  console.log("📝 Transaction hash:", tx.hash);
  
  await tx.wait();
  console.log("✅ Transaction confirmed!");

  // Verify
  const newPeriod = await spbeam.unlockPeriod();
  console.log("\n✅ New Unlock Period:", newPeriod.toString(), "seconds");
  
  if (hre.network.name === "beamTestnet") {
    console.log("   (1 minute for fast testing)");
  } else {
    console.log("   (22 days for mainnet)");
  }

  console.log("\n🎉 Unlock period updated successfully!");
  console.log("\n📝 Users can now:");
  console.log("   1) Request unlock");
  console.log("   2) Wait", UNLOCK_PERIOD, "seconds");
  console.log("   3) Claim their BEAM");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Failed:", error);
    process.exit(1);
  });
