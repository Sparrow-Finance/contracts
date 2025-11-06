const hre = require("hardhat");

async function main() {
  console.log("🔗 Delegating BEAM from Helper Balance\n");

  const [signer] = await hre.ethers.getSigners();
  console.log("👤 Signer:", signer.address);

  // Connect to contracts
  const HELPER_ADDRESS = process.env.BEAM_VALIDATOR_HELPER || "0x1bc829d35A12520FB21429E5B10845f71aC864B2";
  
  const helper = await hre.ethers.getContractAt("spBeam_Validator_Helper", HELPER_ADDRESS);

  // Delegation parameters
  const VALIDATOR_ID = 0; // First validator
  const DELEGATE_AMOUNT = hre.ethers.parseEther("100.0"); // 100 BEAM

  console.log("📍 Validator Helper:", HELPER_ADDRESS);
  console.log("🎯 Validator ID:", VALIDATOR_ID);
  console.log("💰 Amount:", hre.ethers.formatEther(DELEGATE_AMOUNT), "BEAM\n");

  // Get validator info
  const validator = await helper.validators(VALIDATOR_ID);
  console.log("📋 Validator:");
  console.log("   ValidationID:", validator.validationID);
  console.log("   Name:", validator.name);
  console.log("   Active:", validator.active);
  console.log("   Delegated Amount:", hre.ethers.formatEther(validator.delegatedAmount), "BEAM");

  if (!validator.active) {
    console.log("\n❌ Validator is not active!");
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
    return;
  }

  // Delegate from helper's balance (NO msg.value needed!)
  console.log("\n⏳ Delegating from helper's balance...");
  console.log("   Using helper's BEAM (not your wallet!)");
  
  const tx = await helper.delegateFromBalance(VALIDATOR_ID, DELEGATE_AMOUNT);
  console.log("📝 Transaction:", tx.hash);
  
  const receipt = await tx.wait();
  console.log("✅ Confirmed in block:", receipt.blockNumber);

  // Get updated info
  const validatorAfter = await helper.validators(VALIDATOR_ID);
  const helperBalanceAfter = await hre.ethers.provider.getBalance(HELPER_ADDRESS);
  
  console.log("\n📊 After Delegation:");
  console.log("   Delegated Amount:", hre.ethers.formatEther(validatorAfter.delegatedAmount), "BEAM");
  console.log("   Helper Balance:", hre.ethers.formatEther(helperBalanceAfter), "BEAM");
  console.log("   Used:", hre.ethers.formatEther(helperBalance - helperBalanceAfter), "BEAM");

  console.log("\n🎉 Delegation from balance complete!");
  console.log("💡 Helper used its own BEAM, not yours!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
