const hre = require("hardhat");

async function main() {
  console.log("✅ Activating Validator\n");

  const [signer] = await hre.ethers.getSigners();
  console.log("👤 Signer:", signer.address);

  // Connect to Validator Helper
  const HELPER_ADDRESS = process.env.BEAM_VALIDATOR_HELPER || "0x1bc829d35A12520FB21429E5B10845f71aC864B2";
  const helper = await hre.ethers.getContractAt("spBeam_Validator_Helper", HELPER_ADDRESS);

  // Validator ID to activate (change this!)
  const VALIDATOR_ID = 0; // First validator

  console.log("📍 Validator Helper:", HELPER_ADDRESS);
  console.log("🎯 Activating Validator ID:", VALIDATOR_ID);

  // Get validator info before
  const validatorBefore = await helper.validators(VALIDATOR_ID);
  console.log("\n📊 Before:");
  console.log("   ValidationID:", validatorBefore.validationID);
  console.log("   Name:", validatorBefore.name);
  console.log("   Active:", validatorBefore.active);

  if (validatorBefore.active) {
    console.log("\n✅ Validator is already active!");
    console.log("💡 Skip to delegation: npx hardhat run scripts/delegate-beam.js --network beamTestnet");
    return;
  }

  // Activate
  console.log("\n⏳ Activating...");
  const tx = await helper.activateValidator(VALIDATOR_ID);
  console.log("📝 Transaction:", tx.hash);
  
  const receipt = await tx.wait();
  console.log("✅ Confirmed in block:", receipt.blockNumber);

  // Get validator info after
  const validatorAfter = await helper.validators(VALIDATOR_ID);
  console.log("\n📊 After:");
  console.log("   Active:", validatorAfter.active);

  console.log("\n🎉 Validator activated!");
  console.log("💡 Next: Delegate BEAM with scripts/delegate-beam.js");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
