const hre = require("hardhat");

async function main() {
  console.log("💰 Adding Rewards to spBEAM...\n");

  // Get deployer (must be governance)
  const [deployer] = await hre.ethers.getSigners();
  console.log("📝 Caller:", deployer.address);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("💰 Balance:", hre.ethers.formatEther(balance), "BEAM\n");

  // Contract address
  const PROXY_ADDRESS = "0x21e9726d777400c5dcBF65cF595125B21359A1DD"; // Update for mainnet
  
  console.log("📍 spBEAM Address:", PROXY_ADDRESS);
  console.log("🌐 Network:", hre.network.name);

  // Attach to contract
  const SpBEAM = await hre.ethers.getContractFactory(
    "contracts/spBEAM/spBEAM_WithValidatorLogic.sol:spBEAM"
  );
  const spbeam = SpBEAM.attach(PROXY_ADDRESS);

  // Check governance
  const governance = await spbeam.governance();
  console.log("🔐 Governance:", governance);
  
  if (deployer.address.toLowerCase() !== governance.toLowerCase()) {
    console.log("⚠️  WARNING: You are not governance! This call will fail.");
    return;
  }

  // Get stats before
  console.log("\n📊 Stats Before:");
  const statsBefore = await spbeam.getStats();
  console.log("   Total Pooled BEAM:", hre.ethers.formatEther(statsBefore[0]));
  console.log("   Total Supply:", hre.ethers.formatEther(statsBefore[1]));
  console.log("   Exchange Rate:", hre.ethers.formatEther(statsBefore[2]));
  console.log("   DAO Fees:", hre.ethers.formatEther(statsBefore[4]));
  console.log("   Dev Fees:", hre.ethers.formatEther(statsBefore[5]));

  // Add rewards (change this amount as needed)
  const rewardAmount = hre.ethers.parseEther("20"); // 1 BEAM
  
  console.log("\n⏳ Adding", hre.ethers.formatEther(rewardAmount), "BEAM as rewards...");
  
  const tx = await spbeam.addRewards({ value: rewardAmount });
  console.log("📝 Transaction hash:", tx.hash);
  
  console.log("⏳ Waiting for confirmation...");
  await tx.wait();
  console.log("✅ Rewards added!\n");

  // Get stats after
  console.log("📊 Stats After:");
  const statsAfter = await spbeam.getStats();
  console.log("   Total Pooled BEAM:", hre.ethers.formatEther(statsAfter[0]));
  console.log("   Total Supply:", hre.ethers.formatEther(statsAfter[1]));
  console.log("   Exchange Rate:", hre.ethers.formatEther(statsAfter[2]));
  console.log("   DAO Fees:", hre.ethers.formatEther(statsAfter[4]));
  console.log("   Dev Fees:", hre.ethers.formatEther(statsAfter[5]));

  // Calculate fee distribution
  const daoFeeIncrease = statsAfter[4] - statsBefore[4];
  const devFeeIncrease = statsAfter[5] - statsBefore[5];
  const userReward = rewardAmount - daoFeeIncrease - devFeeIncrease;

  console.log("\n💰 Reward Distribution:");
  console.log("   Total Reward:", hre.ethers.formatEther(rewardAmount), "BEAM");
  console.log("   DAO Fee (5%):", hre.ethers.formatEther(daoFeeIncrease), "BEAM");
  console.log("   Dev Fee (3%):", hre.ethers.formatEther(devFeeIncrease), "BEAM");
  console.log("   User Reward (92%):", hre.ethers.formatEther(userReward), "BEAM");

  // Calculate exchange rate increase
  const rateIncrease = statsAfter[2] - statsBefore[2];
  const rateIncreasePercent = (Number(rateIncrease) / Number(statsBefore[2])) * 100;

  console.log("\n📈 Exchange Rate Impact:");
  console.log("   Before:", hre.ethers.formatEther(statsBefore[2]), "BEAM per spBEAM");
  console.log("   After:", hre.ethers.formatEther(statsAfter[2]), "BEAM per spBEAM");
  console.log("   Increase:", rateIncreasePercent.toFixed(4), "%");

  console.log("\n🎉 Done!");
  console.log("💡 Users holding spBEAM just earned rewards automatically!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
