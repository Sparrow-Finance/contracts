const hre = require("hardhat");

async function main() {
  console.log("🔧 spBEAM_V2 Interaction Script\n");

  const [signer] = await hre.ethers.getSigners();
  console.log("👤 Signer:", signer.address);

  const balance = await hre.ethers.provider.getBalance(signer.address);
  console.log("💰 BEAM Balance:", hre.ethers.formatEther(balance), "BEAM\n");

  // Connect to spBEAM_V2
  const SPBEAM_ADDRESS = process.env.BEAM_V2_PROXY || "0x4d3F457c9a6Fd430F661283d92b9E7aA8ae638B8";
  const spBEAM = await hre.ethers.getContractAt("spBEAM_V2", SPBEAM_ADDRESS);

  console.log("📍 spBEAM_V2:", SPBEAM_ADDRESS);
  console.log("");

  // Get contract stats
  console.log("📊 Contract Stats:");
  const stats = await spBEAM.getStats();
  console.log("   Total Pooled BEAM:", hre.ethers.formatEther(stats[0]));
  console.log("   Total Supply spBEAM:", hre.ethers.formatEther(stats[1]));
  console.log("   Exchange Rate:", hre.ethers.formatEther(stats[2]));
  console.log("   Total Locked in Unlocks:", hre.ethers.formatEther(stats[3]));
  console.log("   Available to Stake:", hre.ethers.formatEther(stats[4]));
  console.log("   Min Stake:", hre.ethers.formatEther(stats[5]), "BEAM");
  console.log("   DAO Fee:", Number(stats[6]) / 100, "%");
  console.log("   Dev Fee:", Number(stats[7]) / 100, "%");

  const unlockPeriod = await spBEAM.unlockPeriod();
  console.log("   Unlock Period:", Number(unlockPeriod) / 86400, "days");

  // Get user balance
  const spBeamBalance = await spBEAM.balanceOf(signer.address);
  console.log("\n👤 Your Balance:");
  console.log("   spBEAM:", hre.ethers.formatEther(spBeamBalance));

  // Get unlock requests (access public mapping directly)
  console.log("\n📋 Checking Unlock Requests...");
  try {
    // Try to get first request to see if any exist
    const firstRequest = await spBEAM.unlockRequests(signer.address, 0);
    
    // If we got here, there's at least one request
    let unlockRequests = [firstRequest];
    let i = 1;
    
    // Try to get more requests
    while (true) {
      try {
        const req = await spBEAM.unlockRequests(signer.address, i);
        unlockRequests.push(req);
        i++;
      } catch {
        break; // No more requests
      }
    }
    
    console.log("   Total Requests:", unlockRequests.length);
    
    const now = Math.floor(Date.now() / 1000);
    
    for (let j = 0; j < unlockRequests.length; j++) {
      const req = unlockRequests[j];
      const unlockTime = Number(req.unlockTime);
      const isReady = now >= unlockTime;
      
      console.log(`\n   Request #${j}:`);
      console.log(`      spBEAM Amount: ${hre.ethers.formatEther(req.spBeamAmount)}`);
      console.log(`      BEAM Amount: ${hre.ethers.formatEther(req.beamAmount)}`);
      console.log(`      Unlock Time: ${new Date(unlockTime * 1000).toLocaleString()}`);
      console.log(`      Status: ${isReady ? "✅ Ready to claim!" : "⏳ Waiting..."}`);
      
      if (isReady) {
        console.log(`      💡 Run: claimUnlock(${j})`);
      }
    }
  } catch (error) {
    console.log("   No unlock requests found");
  }

  console.log("\n\n🎯 Available Actions:");
  console.log("   1. Stake BEAM:        stake(amount)");
  console.log("   2. Request Unlock:    requestUnlock(spBeamAmount, minBeamOut)");
  console.log("   3. Claim Unlock:      claimUnlock(requestIndex)");
  console.log("   4. View Stats:        getStats()");
  console.log("");
  console.log("💡 Example commands:");
  console.log("   npx hardhat run scripts/stake-beam.js --network beamTestnet");
  console.log("   npx hardhat run scripts/unlock-beam.js --network beamTestnet");
  console.log("   npx hardhat run scripts/claim-beam.js --network beamTestnet");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
