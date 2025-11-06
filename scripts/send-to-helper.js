// scripts/send-to-helper.js
const hre = require("hardhat");

async function main() {
  console.log("💸 Sending BEAM to Validator Helper\n");

  const [signer] = await hre.ethers.getSigners();
  console.log("👤 Signer:", signer.address);

  // Contract addresses
  const SPBEAM_ADDRESS = process.env.BEAM_V2_PROXY || "0x4d3F457c9a6Fd430F661283d92b9E7aA8ae638B8";
  const HELPER_ADDRESS = process.env.BEAM_VALIDATOR_HELPER || "0x1bc829d35A12520FB21429E5B10845f71aC864B2";
  const SEND_AMOUNT = hre.ethers.parseEther("100.0"); // 100 BEAM

  console.log("📍 spBEAM:", SPBEAM_ADDRESS);
  console.log("📍 Helper:", HELPER_ADDRESS);
  console.log("💰 Amount:", hre.ethers.formatEther(SEND_AMOUNT), "BEAM\n");

  // Connect to spBEAM
  const spBEAM = await hre.ethers.getContractAt("spBEAM_V2", SPBEAM_ADDRESS);

  // Check stats before
  const statsBefore = await spBEAM.getStats();
  console.log("📊 Before:");
  console.log("   Total Pooled:", hre.ethers.formatEther(statsBefore[0]), "BEAM");
  console.log("   Available to Stake:", hre.ethers.formatEther(statsBefore[4]), "BEAM");

  // Check helper balance before
  const helperBalanceBefore = await hre.ethers.provider.getBalance(HELPER_ADDRESS);
  console.log("   Helper Balance:", hre.ethers.formatEther(helperBalanceBefore), "BEAM");

  // Send BEAM to helper
  console.log("\n⏳ Sending BEAM to helper...");
  const tx = await spBEAM.sendToValidatorHelper(SEND_AMOUNT);
  console.log("📝 Transaction:", tx.hash);
  
  const receipt = await tx.wait();
  console.log("✅ Confirmed in block:", receipt.blockNumber);

  // Check stats after
  const statsAfter = await spBEAM.getStats();
  const helperBalanceAfter = await hre.ethers.provider.getBalance(HELPER_ADDRESS);
  
  console.log("\n📊 After:");
  console.log("   Total Pooled:", hre.ethers.formatEther(statsAfter[0]), "BEAM");
  console.log("   Available to Stake:", hre.ethers.formatEther(statsAfter[4]), "BEAM");
  console.log("   Helper Balance:", hre.ethers.formatEther(helperBalanceAfter), "BEAM");
  console.log("   Sent:", hre.ethers.formatEther(helperBalanceAfter - helperBalanceBefore), "BEAM");

  console.log("\n🎉 BEAM sent to helper!");
  console.log("💡 Next: Delegate to validator with scripts/delegate-beam.js");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });