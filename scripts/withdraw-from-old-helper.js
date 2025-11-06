const hre = require("hardhat");

async function main() {
  console.log("💸 Withdrawing BEAM from Old Helper\n");

  const [signer] = await hre.ethers.getSigners();
  console.log("👤 Signer:", signer.address);

  const OLD_HELPER = "0xD0860B697825b80C6Cf21aB0Bb9B02A1Dc672F83";
  const NEW_HELPER = "0x1bc829d35A12520FB21429E5B10845f71aC864B2";

  // Check balance
  const oldBalance = await hre.ethers.provider.getBalance(OLD_HELPER);
  console.log("📍 Old Helper:", OLD_HELPER);
  console.log("💰 Balance:", hre.ethers.formatEther(oldBalance), "BEAM");

  if (oldBalance === 0n) {
    console.log("\n❌ No BEAM to withdraw!");
    return;
  }

  // Connect to old helper
  const oldHelper = await hre.ethers.getContractAt("spBeam_Validator_Helper", OLD_HELPER);

  // Check if there's a withdraw function
  console.log("\n⏳ Attempting to withdraw BEAM...");
  console.log("   Method: Send BEAM directly to new helper");

  try {
    // Try to send BEAM from old helper to new helper
    // This will only work if the old helper has a function to send BEAM
    
    // Option 1: If there's a withdraw function
    console.log("\n💡 Checking for withdraw function...");
    
    // Since we can't withdraw directly, let's just send BEAM manually
    console.log("\n⚠️  Old helper doesn't have a simple withdraw function.");
    console.log("💡 Alternative: Send BEAM directly from your wallet to new helper");
    console.log("\n📝 Run this instead:");
    console.log("   npx hardhat run scripts/send-beam-to-new-helper.js --network beamTestnet");
    
  } catch (error) {
    console.log("\n❌ Error:", error.message);
    console.log("\n💡 The old helper contract may not have a withdraw function.");
    console.log("   The BEAM is locked in the old helper contract.");
    console.log("   You'll need to:");
    console.log("   1. Stake fresh BEAM to spBEAM");
    console.log("   2. Send that to new helper");
    console.log("   3. Delegate from new helper");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
