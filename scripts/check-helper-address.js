const hre = require("hardhat");

async function main() {
  console.log("🔍 Checking Helper Address in spBEAM\n");

  const SPBEAM_ADDRESS = "0x4d3F457c9a6Fd430F661283d92b9E7aA8ae638B8";
  const EXPECTED_HELPER = "0x1bc829d35A12520FB21429E5B10845f71aC864B2";

  const spBEAM = await hre.ethers.getContractAt("spBEAM_V2", SPBEAM_ADDRESS);

  const currentHelper = await spBEAM.validatorHelper();
  
  console.log("📍 spBEAM:", SPBEAM_ADDRESS);
  console.log("🔗 Current Helper:", currentHelper);
  console.log("🎯 Expected Helper:", EXPECTED_HELPER);
  console.log("✅ Match:", currentHelper.toLowerCase() === EXPECTED_HELPER.toLowerCase());

  if (currentHelper === "0x0000000000000000000000000000000000000000") {
    console.log("\n⚠️  Helper not set!");
    console.log("💡 Set with: await spBEAM.setValidatorHelper('" + EXPECTED_HELPER + "')");
  } else if (currentHelper.toLowerCase() !== EXPECTED_HELPER.toLowerCase()) {
    console.log("\n⚠️  Helper is set to wrong address!");
    console.log("💡 Update with: await spBEAM.setValidatorHelper('" + EXPECTED_HELPER + "')");
  } else {
    console.log("\n✅ Helper is correctly set!");
  }

  // Check contract balance
  const contractBalance = await hre.ethers.provider.getBalance(SPBEAM_ADDRESS);
  console.log("\n💰 spBEAM Contract Balance:", hre.ethers.formatEther(contractBalance), "BEAM");

  const stats = await spBEAM.getStats();
  console.log("📊 Total Pooled:", hre.ethers.formatEther(stats[0]), "BEAM");
  console.log("📊 Available to Stake:", hre.ethers.formatEther(stats[4]), "BEAM");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
