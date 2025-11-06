const hre = require("hardhat");

async function main() {
  console.log("💎 Claiming Unlocked BEAM\n");

  const [signer] = await hre.ethers.getSigners();
  console.log("👤 Signer:", signer.address);

  // Connect to spBEAM_V2
  const SPBEAM_ADDRESS = process.env.BEAM_V2_PROXY || "0x4d3F457c9a6Fd430F661283d92b9E7aA8ae638B8";
  const spBEAM = await hre.ethers.getContractAt("spBEAM_V2", SPBEAM_ADDRESS);

  // Get unlock requests (count them first)
  let requestCount = 0;
  while (true) {
    try {
      await spBEAM.unlockRequests(signer.address, requestCount);
      requestCount++;
    } catch {
      break;
    }
  }
  
  if (requestCount === 0) {
    console.log("❌ You have no unlock requests!");
    console.log("💡 Request unlock first with: npx hardhat run scripts/unlock-beam.js --network beamTestnet");
    return;
  }

  console.log("📋 Your Unlock Requests:\n");
  
  const now = Math.floor(Date.now() / 1000);
  let readyToClaim = [];

  for (let i = 0; i < requestCount; i++) {
    const req = await spBEAM.unlockRequests(signer.address, i);
    const unlockTime = Number(req.unlockTime);
    const isReady = now >= unlockTime;
    const timeLeft = unlockTime - now;
    
    console.log(`Request #${i}:`);
    console.log(`   spBEAM: ${hre.ethers.formatEther(req.spBeamAmount)}`);
    console.log(`   BEAM: ${hre.ethers.formatEther(req.beamAmount)}`);
    console.log(`   Unlock Time: ${new Date(unlockTime * 1000).toLocaleString()}`);
    
    if (isReady) {
      console.log(`   Status: ✅ Ready to claim!`);
      readyToClaim.push(i);
    } else {
      const daysLeft = Math.ceil(timeLeft / 86400);
      console.log(`   Status: ⏳ ${daysLeft} days left`);
    }
    console.log("");
  }

  if (readyToClaim.length === 0) {
    console.log("❌ No requests are ready to claim yet!");
    console.log("⏰ Please wait until unlock period is over");
    return;
  }

  // Claim the first ready request (change index if needed)
  const REQUEST_INDEX = readyToClaim[0];
  const request = await spBEAM.unlockRequests(signer.address, REQUEST_INDEX);
  
  console.log(`\n🎯 Claiming Request #${REQUEST_INDEX}...`);
  console.log(`   Will receive: ${hre.ethers.formatEther(request.beamAmount)} BEAM`);

  // Check balance before
  const beamBefore = await hre.ethers.provider.getBalance(signer.address);
  console.log(`   BEAM before: ${hre.ethers.formatEther(beamBefore)}`);

  // Claim
  console.log("\n⏳ Claiming...");
  const tx = await spBEAM.claimUnlock(REQUEST_INDEX);
  console.log("📝 Transaction:", tx.hash);
  
  const receipt = await tx.wait();
  console.log("✅ Confirmed in block:", receipt.blockNumber);

  // Check balance after
  const beamAfter = await hre.ethers.provider.getBalance(signer.address);
  const received = beamAfter - beamBefore;
  
  console.log("\n📊 After Claiming:");
  console.log("   BEAM after:", hre.ethers.formatEther(beamAfter));
  console.log("   Net received:", hre.ethers.formatEther(received), "BEAM (after gas)");

  console.log("\n🎉 Claim complete!");
  console.log("💡 Stake again with: npx hardhat run scripts/stake-beam.js --network beamTestnet");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
