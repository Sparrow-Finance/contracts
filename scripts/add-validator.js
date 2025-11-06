const hre = require("hardhat");

async function main() {
  console.log("➕ Adding Validator to Helper\n");

  const [signer] = await hre.ethers.getSigners();
  console.log("👤 Signer:", signer.address);

  // Connect to Validator Helper
  const HELPER_ADDRESS = process.env.BEAM_VALIDATOR_HELPER || "0x1bc829d35A12520FB21429E5B10845f71aC864B2";
  const helper = await hre.ethers.getContractAt("spBeam_Validator_Helper", HELPER_ADDRESS);

  console.log("📍 Validator Helper:", HELPER_ADDRESS);

  // Validator details (UPDATE THESE!)
  // Get the validationID from your delegation transaction on Beam explorer!
  const VALIDATION_ID = "0xe3e5d56c19cf095e34246aad06526b3c1253229f8cc26889e82024b4c9c50d23";
  const VALIDATOR_NAME = "Beam Validator 1";
  const WEIGHT_TO_VALUE_FACTOR = 1000000000000n; // 1e12 (standard for Beam)

  console.log("\n📝 Validator Details:");
  console.log("   ValidationID:", VALIDATION_ID);
  console.log("   Name:", VALIDATOR_NAME);
  console.log("   Weight Factor:", WEIGHT_TO_VALUE_FACTOR.toString());

  // Add validator
  console.log("\n⏳ Adding validator...");
  const tx = await helper.addValidator(VALIDATION_ID, VALIDATOR_NAME, WEIGHT_TO_VALUE_FACTOR);
  console.log("📝 Transaction:", tx.hash);
  
  const receipt = await tx.wait();
  console.log("✅ Confirmed in block:", receipt.blockNumber);

  // Get validator count (it's a public variable, not a function)
  const validatorCount = await helper.validatorCount();
  console.log("\n📊 Total Validators:", validatorCount.toString());

  // Get validator info
  const validatorId = validatorCount - 1n;
  const validator = await helper.validators(validatorId);
  
  console.log("\n📋 Validator Info:");
  console.log("   ID:", validatorId.toString());
  console.log("   ValidationID:", validator.validationID);
  console.log("   Name:", validator.name);
  console.log("   Active:", validator.active);
  console.log("   Delegated Amount:", hre.ethers.formatEther(validator.delegatedAmount), "BEAM");
  console.log("   Weight:", validator.weight.toString());
  console.log("   Delegation ID:", validator.delegationID.toString());

  console.log("\n🎉 Validator added!");
  console.log("💡 Next: Activate with scripts/activate-validator.js");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
