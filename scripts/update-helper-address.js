const hre = require("hardhat");

async function main() {
  console.log("🔄 Updating Helper Address in spBEAM\n");

  const [signer] = await hre.ethers.getSigners();
  console.log("👤 Signer:", signer.address);

  const SPBEAM_ADDRESS = "0x4d3F457c9a6Fd430F661283d92b9E7aA8ae638B8";
  const NEW_HELPER = "0x1bc829d35A12520FB21429E5B10845f71aC864B2";

  const spBEAM = await hre.ethers.getContractAt("spBEAM_V2", SPBEAM_ADDRESS);

  // Check current helper
  const currentHelper = await spBEAM.validatorHelper();
  console.log("📍 spBEAM:", SPBEAM_ADDRESS);
  console.log("🔗 Current Helper:", currentHelper);
  console.log("🎯 New Helper:", NEW_HELPER);

  // Update helper
  console.log("\n⏳ Updating helper address...");
  const tx = await spBEAM.setValidatorHelper(NEW_HELPER);
  console.log("📝 Transaction:", tx.hash);
  
  const receipt = await tx.wait();
  console.log("✅ Confirmed in block:", receipt.blockNumber);

  // Verify
  const updatedHelper = await spBEAM.validatorHelper();
  console.log("\n✅ Updated Helper:", updatedHelper);
  console.log("🎉 Helper address updated successfully!");
  
  console.log("\n💡 Next: Send BEAM to new helper");
  console.log("   npx hardhat run scripts/send-to-helper.js --network beamTestnet");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
