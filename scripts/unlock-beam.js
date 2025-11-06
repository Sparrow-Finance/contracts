const hre = require("hardhat");

async function main() {
  console.log("🔓 Requesting BEAM Unlock\n");

  const [signer] = await hre.ethers.getSigners();
  console.log("👤 Signer:", signer.address);

  // Connect to spBEAM_V2
  const SPBEAM_ADDRESS = process.env.BEAM_V2_PROXY || "0x4d3F457c9a6Fd430F661283d92b9E7aA8ae638B8";
  const spBEAM = await hre.ethers.getContractAt("spBEAM_V2", SPBEAM_ADDRESS);

  // Check current balance
  const spBeamBalance = await spBEAM.balanceOf(signer.address);
  console.log("💰 Your spBEAM Balance:", hre.ethers.formatEther(spBeamBalance));

  if (spBeamBalance === 0n) {
    console.log("❌ You have no spBEAM to unlock!");
    console.log("💡 Stake first with: npx hardhat run scripts/stake-beam.js --network beamTestnet");
    return;
  }

  // Amount to unlock (change this!)
  const UNLOCK_AMOUNT = spBeamBalance; // Unlock all
  console.log("🔓 Unlocking:", hre.ethers.formatEther(UNLOCK_AMOUNT), "spBEAM");

  // Get exchange rate
  const stats = await spBEAM.getStats();
  const exchangeRate = stats[2];
  console.log("📊 Exchange Rate:", hre.ethers.formatEther(exchangeRate));

  // Calculate expected BEAM (with 1% slippage)
  const expectedBeam = (UNLOCK_AMOUNT * exchangeRate) / hre.ethers.parseEther("1");
  const minBeamOut = (expectedBeam * 99n) / 100n; // 1% slippage
  console.log("💵 Expected BEAM:", hre.ethers.formatEther(expectedBeam));
  console.log("💵 Min BEAM (1% slippage):", hre.ethers.formatEther(minBeamOut));

  // Get unlock period
  const unlockPeriod = await spBEAM.unlockPeriod();
  const unlockDays = Number(unlockPeriod) / 86400;
  console.log("⏰ Unlock Period:", unlockDays, "days");

  // Request unlock
  console.log("\n⏳ Requesting unlock...");
  const tx = await spBEAM.requestUnlock(UNLOCK_AMOUNT, minBeamOut);
  console.log("📝 Transaction:", tx.hash);
  
  const receipt = await tx.wait();
  console.log("✅ Confirmed in block:", receipt.blockNumber);

  // Get unlock requests (count them)
  let requestCount = 0;
  while (true) {
    try {
      await spBEAM.unlockRequests(signer.address, requestCount);
      requestCount++;
    } catch {
      break;
    }
  }
  
  // Get the latest request
  const latestRequest = await spBEAM.unlockRequests(signer.address, requestCount - 1);
  const unlockTime = Number(latestRequest.unlockTime);
  const unlockDate = new Date(unlockTime * 1000);

  console.log("\n📋 Unlock Request Created:");
  console.log("   Request Index:", requestCount - 1);
  console.log("   spBEAM Amount:", hre.ethers.formatEther(latestRequest.spBeamAmount));
  console.log("   BEAM Amount:", hre.ethers.formatEther(latestRequest.beamAmount));
  console.log("   Unlock Time:", unlockDate.toLocaleString());
  console.log("   Days to wait:", unlockDays);

  console.log("\n🎉 Unlock request created!");
  console.log(`💡 Come back after ${unlockDate.toLocaleString()} to claim`);
  console.log("💡 Claim with: npx hardhat run scripts/claim-beam.js --network beamTestnet");
  console.log("\n⚠️  Note: No expiry! You can claim anytime after unlock period.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
