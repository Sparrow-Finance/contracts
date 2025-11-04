const hre = require("hardhat");

async function main() {
  console.log("💰 Adding Rewards to spAVAX...\n");

  const [deployer] = await hre.ethers.getSigners();
  console.log("📝 Adding rewards with account:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("💰 Account balance:", hre.ethers.formatEther(balance), "AVAX\n");

  // Contract address (proxy)
  const contractAddress = "0xd5be2F451C0B1B8cA17Cc64a1f904405B8120c9B";
  
  // Get contract instance
  const SpAVAX = await hre.ethers.getContractFactory("spAVAX");
  const spavax = SpAVAX.attach(contractAddress);

  // Get stats before
  console.log("📊 Stats Before:");
  const statsBefore = await spavax.getStats();
  console.log("   Total Pooled AVAX:", hre.ethers.formatEther(statsBefore[0]));
  console.log("   Total Supply:", hre.ethers.formatEther(statsBefore[1]));
  console.log("   Exchange Rate:", hre.ethers.formatEther(statsBefore[2]));
  console.log("   DAO Fees:", hre.ethers.formatEther(statsBefore[4]));
  console.log("   Dev Fees:", hre.ethers.formatEther(statsBefore[5]));

  // Add rewards (change this amount as needed)
  const rewardAmount = hre.ethers.parseEther("0.1"); // 0.1 AVAX
  
  console.log("\n⏳ Adding", hre.ethers.formatEther(rewardAmount), "AVAX as rewards...");
  
  const tx = await spavax.addRewards({ value: rewardAmount });
  console.log("📝 Transaction hash:", tx.hash);
  
  console.log("⏳ Waiting for confirmation...");
  await tx.wait();
  console.log("✅ Rewards added!\n");

  // Get stats after
  console.log("📊 Stats After:");
  const statsAfter = await spavax.getStats();
  console.log("   Total Pooled AVAX:", hre.ethers.formatEther(statsAfter[0]));
  console.log("   Total Supply:", hre.ethers.formatEther(statsAfter[1]));
  console.log("   Exchange Rate:", hre.ethers.formatEther(statsAfter[2]));
  console.log("   DAO Fees:", hre.ethers.formatEther(statsAfter[4]));
  console.log("   Dev Fees:", hre.ethers.formatEther(statsAfter[5]));

  // Calculate fee distribution
  const daoFeeIncrease = statsAfter[4] - statsBefore[4];
  const devFeeIncrease = statsAfter[5] - statsBefore[5];
  const userReward = rewardAmount - daoFeeIncrease - devFeeIncrease;

  console.log("\n💰 Reward Distribution:");
  console.log("   Total Reward:", hre.ethers.formatEther(rewardAmount), "AVAX");
  console.log("   DAO Fee (5%):", hre.ethers.formatEther(daoFeeIncrease), "AVAX");
  console.log("   Dev Fee (3%):", hre.ethers.formatEther(devFeeIncrease), "AVAX");
  console.log("   User Reward (92%):", hre.ethers.formatEther(userReward), "AVAX");

  console.log("\n🎉 Done!");
  console.log("📈 New exchange rate:", hre.ethers.formatEther(statsAfter[2]), "AVAX per spAVAX");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
