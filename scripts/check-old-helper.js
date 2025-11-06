const hre = require("hardhat");

async function main() {
  console.log("🔍 Checking Old Helper Balance\n");

  const [signer] = await hre.ethers.getSigners();
  console.log("👤 Signer:", signer.address);

  const OLD_HELPER = "0xD0860B697825b80C6Cf21aB0Bb9B02A1Dc672F83";
  const NEW_HELPER = "0x1bc829d35A12520FB21429E5B10845f71aC864B2";

  // Check balances
  const oldBalance = await hre.ethers.provider.getBalance(OLD_HELPER);
  const newBalance = await hre.ethers.provider.getBalance(NEW_HELPER);

  console.log("📊 Helper Balances:");
  console.log("   Old Helper:", hre.ethers.formatEther(oldBalance), "BEAM");
  console.log("   New Helper:", hre.ethers.formatEther(newBalance), "BEAM");

  // Connect to old helper
  const oldHelper = await hre.ethers.getContractAt("spBeam_Validator_Helper", OLD_HELPER);

  // Check governance
  try {
    const governance = await oldHelper.governance();
    console.log("\n🔐 Old Helper Governance:", governance);
    console.log("   Your Address:", signer.address);
    console.log("   You are governance:", governance.toLowerCase() === signer.address.toLowerCase());
  } catch (error) {
    console.log("\n⚠️  Could not read governance");
  }

  console.log("\n💡 If you are governance, you can withdraw the BEAM!");
  console.log("   Run: npx hardhat run scripts/withdraw-from-old-helper.js --network beamTestnet");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
