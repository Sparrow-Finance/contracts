const hre = require("hardhat");

async function main() {
  console.log("✅ Completing Delegation\n");

  const [signer] = await hre.ethers.getSigners();
  console.log("👤 Signer:", signer.address);

  // Connect to Validator Helper
  const HELPER_ADDRESS = process.env.BEAM_VALIDATOR_HELPER || "0xD0860B697825b80C6Cf21aB0Bb9B02A1Dc672F83";
  const helper = await hre.ethers.getContractAt("spBeam_Validator_Helper", HELPER_ADDRESS);

  // Parameters (UPDATE THESE!)
  const VALIDATOR_ID = 0; // First validator
  const DELEGATION_ID = 36; // Get this from your delegation transaction on Beam explorer!

  console.log("📍 Validator Helper:", HELPER_ADDRESS);
  console.log("🎯 Validator ID:", VALIDATOR_ID);
  console.log("🔢 Delegation ID:", DELEGATION_ID);

  // Get validator info before
  const validatorBefore = await helper.validators(VALIDATOR_ID);
  console.log("\n📊 Before Completion:");
  console.log("   ValidationID:", validatorBefore.validationID);
  console.log("   Name:", validatorBefore.name);
  console.log("   Delegated Amount:", hre.ethers.formatEther(validatorBefore.delegatedAmount), "BEAM");
  console.log("   Current Delegation ID:", validatorBefore.delegationID.toString());

  if (validatorBefore.delegationID > 0) {
    console.log("\n⚠️  Delegation already completed!");
    console.log("   Current Delegation ID:", validatorBefore.delegationID.toString());
    return;
  }

  // Complete delegation
  console.log("\n⏳ Completing delegation...");
  const tx = await helper.completeDelegation(VALIDATOR_ID, DELEGATION_ID);
  console.log("📝 Transaction:", tx.hash);
  
  const receipt = await tx.wait();
  console.log("✅ Confirmed in block:", receipt.blockNumber);

  // Get validator info after
  const validatorAfter = await helper.validators(VALIDATOR_ID);
  console.log("\n📊 After Completion:");
  console.log("   Delegation ID:", validatorAfter.delegationID.toString());
  console.log("   Delegated Amount:", hre.ethers.formatEther(validatorAfter.delegatedAmount), "BEAM");
  console.log("   Weight:", validatorAfter.weight.toString());

  console.log("\n🎉 Delegation completed!");
  console.log("💡 Now earning staking rewards!");
  console.log("💡 Claim rewards with: scripts/claim-rewards.js");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
