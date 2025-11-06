const hre = require("hardhat");

async function main() {
  console.log("💰 Staking BEAM to get spBEAM\n");

  const [signer] = await hre.ethers.getSigners();
  console.log("👤 Signer:", signer.address);

  // Amount to stake (change this!)
  const STAKE_AMOUNT = hre.ethers.parseEther("100.0"); // 1 BEAM
  console.log("💵 Staking:", hre.ethers.formatEther(STAKE_AMOUNT), "BEAM\n");

  // Connect to spBEAM_V2
  const SPBEAM_ADDRESS = process.env.BEAM_V2_PROXY || "0x4d3F457c9a6Fd430F661283d92b9E7aA8ae638B8";
  const spBEAM = await hre.ethers.getContractAt("spBEAM_V2", SPBEAM_ADDRESS);

  // Check balance before
  const beamBefore = await hre.ethers.provider.getBalance(signer.address);
  const spBeamBefore = await spBEAM.balanceOf(signer.address);
  
  console.log("📊 Before Staking:");
  console.log("   BEAM:", hre.ethers.formatEther(beamBefore));
  console.log("   spBEAM:", hre.ethers.formatEther(spBeamBefore));

  // Get exchange rate
  const stats = await spBEAM.getStats();
  const exchangeRate = stats[2];
  console.log("   Exchange Rate:", hre.ethers.formatEther(exchangeRate));

  // Calculate expected spBEAM
  const expectedSpBeam = (STAKE_AMOUNT * hre.ethers.parseEther("1")) / exchangeRate;
  const minSpBeamOut = (expectedSpBeam * 99n) / 100n; // 1% slippage
  console.log("   Expected spBEAM:", hre.ethers.formatEther(expectedSpBeam));
  console.log("   Min spBEAM (1% slippage):", hre.ethers.formatEther(minSpBeamOut));

  // Stake
  console.log("\n⏳ Staking...");
  const tx = await spBEAM.stake(minSpBeamOut, { value: STAKE_AMOUNT });
  console.log("📝 Transaction:", tx.hash);
  
  const receipt = await tx.wait();
  console.log("✅ Confirmed in block:", receipt.blockNumber);

  // Check balance after
  const beamAfter = await hre.ethers.provider.getBalance(signer.address);
  const spBeamAfter = await spBEAM.balanceOf(signer.address);
  
  console.log("\n📊 After Staking:");
  console.log("   BEAM:", hre.ethers.formatEther(beamAfter));
  console.log("   spBEAM:", hre.ethers.formatEther(spBeamAfter));
  console.log("   Received:", hre.ethers.formatEther(spBeamAfter - spBeamBefore), "spBEAM");

  console.log("\n🎉 Staking complete!");
  console.log("💡 Next: Request unlock with scripts/unlock-beam.js");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
