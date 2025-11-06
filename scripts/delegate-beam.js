const hre = require("hardhat");

async function main() {
  console.log("🔗 Delegating BEAM to Validator\n");

  const [signer] = await hre.ethers.getSigners();
  console.log("👤 Signer:", signer.address);

  // Connect to contracts
  const HELPER_ADDRESS = process.env.BEAM_VALIDATOR_HELPER || "0x1bc829d35A12520FB21429E5B10845f71aC864B2";
  const SPBEAM_ADDRESS = process.env.BEAM_V2_PROXY || "0x4d3F457c9a6Fd430F661283d92b9E7aA8ae638B8";
  
  const helper = await hre.ethers.getContractAt("spBeam_Validator_Helper", HELPER_ADDRESS);
  const spBEAM = await hre.ethers.getContractAt("spBEAM_V2", SPBEAM_ADDRESS);

  // Delegation parameters (change these!)
  const VALIDATOR_ID = 0; // First validator
  const DELEGATE_AMOUNT = hre.ethers.parseEther("100.0"); // 100 BEAM (minimum for Beam)

  console.log("📍 Validator Helper:", HELPER_ADDRESS);
  console.log("📍 spBEAM:", SPBEAM_ADDRESS);
  console.log("🎯 Validator ID:", VALIDATOR_ID);
  console.log("💰 Amount:", hre.ethers.formatEther(DELEGATE_AMOUNT), "BEAM\n");

  // Get validator info
  const validator = await helper.validators(VALIDATOR_ID);
  console.log("📋 Validator:");
  console.log("   ValidationID:", validator.validationID);
  console.log("   Name:", validator.name);
  console.log("   Active:", validator.active);
  console.log("   Delegated Amount:", hre.ethers.formatEther(validator.delegatedAmount), "BEAM");
  console.log("   Weight:", validator.weight.toString());

  if (!validator.active) {
    console.log("\n❌ Validator is not active!");
    console.log("💡 Activate first with: npx hardhat run scripts/activate-validator.js --network beamTestnet");
    return;
  }

  // Check helper balance
  const helperBalance = await hre.ethers.provider.getBalance(HELPER_ADDRESS);
  console.log("\n📊 Helper Balance:");
  console.log("   Available:", hre.ethers.formatEther(helperBalance), "BEAM");

  if (helperBalance < DELEGATE_AMOUNT) {
    console.log("\n❌ Helper doesn't have enough BEAM!");
    console.log("💡 Available:", hre.ethers.formatEther(helperBalance), "BEAM");
    console.log("💡 Requested:", hre.ethers.formatEther(DELEGATE_AMOUNT), "BEAM");
    console.log("💡 Send more with: npx hardhat run scripts/send-to-helper.js --network beamTestnet");
    return;
  }

  // Initiate delegation
  console.log("\n⏳ Initiating delegation...");
  console.log("   This will call Beam's native staking contract");
  console.log("   Using", hre.ethers.formatEther(DELEGATE_AMOUNT), "BEAM from helper balance");
  
  // The helper contract already has the BEAM, so we send it as msg.value
  const tx = await helper.initiateDelegation(VALIDATOR_ID, DELEGATE_AMOUNT, { value: DELEGATE_AMOUNT });
  console.log("📝 Transaction:", tx.hash);
  
  const receipt = await tx.wait();
  console.log("✅ Confirmed in block:", receipt.blockNumber);

  // Get updated validator info
  const validatorAfter = await helper.validators(VALIDATOR_ID);
  console.log("\n📊 After Delegation:");
  console.log("   Delegated Amount:", hre.ethers.formatEther(validatorAfter.delegatedAmount), "BEAM");
  console.log("   Weight:", validatorAfter.weight.toString());
  console.log("   Delegation ID:", validatorAfter.delegationID.toString());

  console.log("\n🎉 Delegation initiated!");
  console.log("⏰ Wait for Beam network to confirm delegation (check explorer)");
  console.log("💡 Once confirmed, complete with: scripts/complete-delegation.js");
  console.log("\n⚠️  Note: Beam requires time to process delegation registration");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
