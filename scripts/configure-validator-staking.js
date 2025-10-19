const hre = require("hardhat");

async function main() {
  console.log("⚙️  Configuring Validator Staking Parameters...\n");

  // Get deployer
  const [deployer] = await hre.ethers.getSigners();
  console.log("📝 Configurer:", deployer.address);

  // IMPORTANT: Replace with your actual proxy address
  const PROXY_ADDRESS = "0x21e9726d777400c5dcBF65cF595125B21359A1DD"; // Testnet proxy

  // Configuration parameters
  const CONFIG = {
    reserveRatio: 1000, // 10% (1000 basis points)
    autoStakeThreshold: hre.ethers.parseEther("100"), // 100 BEAM
    sparrowSwapRouter: "0x05425Ff0BC14431E9009d3b40471FFdFBBF637a9", // Sparrow Swap Router
    currentValidator: "0x0000000000000000000000000000000000000000000000000000000000000000", // ← UPDATE THIS! (optional)
  };

  console.log("\n📋 Configuration:");
  console.log("   Reserve Ratio:", CONFIG.reserveRatio / 100, "%");
  console.log("   Auto-Stake Threshold:", hre.ethers.formatEther(CONFIG.autoStakeThreshold), "BEAM");
  console.log("   Sparrow Router:", CONFIG.sparrowSwapRouter);
  console.log("   Current Validator:", CONFIG.currentValidator);

  // Attach to contract
  const SpBEAM = await hre.ethers.getContractFactory(
    "contracts/spBEAM/spBEAM_WithValidatorLogic.sol:spBEAM"
  );
  const spbeam = SpBEAM.attach(PROXY_ADDRESS);

  // Check governance
  const governance = await spbeam.governance();
  console.log("\n🔐 Governance Address:", governance);
  
  if (deployer.address.toLowerCase() !== governance.toLowerCase()) {
    console.log("⚠️  WARNING: You are not governance! These calls will fail.");
    console.log("   Current signer:", deployer.address);
    console.log("   Governance:", governance);
    return;
  }

  console.log("\n⏳ Setting parameters...\n");

  // 1. Set Reserve Ratio
  console.log("1️⃣  Setting reserve ratio to", CONFIG.reserveRatio / 100, "%...");
  const tx1 = await spbeam.setReserveRatio(CONFIG.reserveRatio);
  await tx1.wait();
  console.log("   ✅ Reserve ratio set!");

  // 2. Set Auto-Stake Threshold
  console.log("\n2️⃣  Setting auto-stake threshold to", hre.ethers.formatEther(CONFIG.autoStakeThreshold), "BEAM...");
  const tx2 = await spbeam.setAutoStakeThreshold(CONFIG.autoStakeThreshold);
  await tx2.wait();
  console.log("   ✅ Auto-stake threshold set!");

  // 3. Set Sparrow Swap Router (if provided)
  if (CONFIG.sparrowSwapRouter !== "YOUR_SPARROW_ROUTER_ADDRESS") {
    console.log("\n3️⃣  Setting Sparrow Swap router...");
    const tx3 = await spbeam.setSparrowSwapRouter(CONFIG.sparrowSwapRouter);
    await tx3.wait();
    console.log("   ✅ Sparrow router set!");
  } else {
    console.log("\n3️⃣  ⏭️  Skipping Sparrow router (not configured)");
  }

  // 4. Set Current Validator (if provided)
  if (CONFIG.currentValidator !== "0x0000000000000000000000000000000000000000000000000000000000000000") {
    console.log("\n4️⃣  Setting current validator...");
    const tx4 = await spbeam.setCurrentValidator(CONFIG.currentValidator);
    await tx4.wait();
    console.log("   ✅ Current validator set!");
  } else {
    console.log("\n4️⃣  ⏭️  Skipping current validator (not configured)");
  }

  // 5. Enable Auto-Staking (optional)
  console.log("\n5️⃣  Do you want to enable auto-staking? (Currently disabled by default)");
  console.log("   To enable, call: toggleAutoStaking(true)");
  console.log("   ⏭️  Skipping for now (can enable later)");

  // Verify configuration
  console.log("\n🔍 Verifying configuration...");
  const reserveRatio = await spbeam.reserveRatio();
  const autoStakeThreshold = await spbeam.autoStakeThreshold();
  const autoStakingEnabled = await spbeam.autoStakingEnabled();
  const sparrowRouter = await spbeam.sparrowSwapRouter();
  const currentVal = await spbeam.currentValidatorID();

  console.log("\n✅ Current Configuration:");
  console.log("   Reserve Ratio:", reserveRatio.toString(), "bps (", Number(reserveRatio) / 100, "%)");
  console.log("   Auto-Stake Threshold:", hre.ethers.formatEther(autoStakeThreshold), "BEAM");
  console.log("   Auto-Staking Enabled:", autoStakingEnabled);
  console.log("   Sparrow Router:", sparrowRouter);
  console.log("   Current Validator:", currentVal);

  console.log("\n📝 Next Steps:");
  console.log("   1) Test staking to validator: stakeToValidator(validationID, amount)");
  console.log("   2) Monitor reserve ratio");
  console.log("   3) Enable auto-staking when ready: toggleAutoStaking(true)");
  console.log("   4) Test reward claiming after earning rewards");

  console.log("\n🎉 Configuration complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Configuration failed:", error);
    process.exit(1);
  });
