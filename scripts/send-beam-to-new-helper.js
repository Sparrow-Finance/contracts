const hre = require("hardhat");

async function main() {
  console.log("💸 Sending BEAM Directly to New Helper\n");

  const [signer] = await hre.ethers.getSigners();
  console.log("👤 Signer:", signer.address);

  const NEW_HELPER = "0x1bc829d35A12520FB21429E5B10845f71aC864B2";
  const SEND_AMOUNT = hre.ethers.parseEther("100.0"); // 100 BEAM

  console.log("📍 New Helper:", NEW_HELPER);
  console.log("💰 Amount:", hre.ethers.formatEther(SEND_AMOUNT), "BEAM");

  // Check your balance
  const yourBalance = await hre.ethers.provider.getBalance(signer.address);
  console.log("\n📊 Your Balance:", hre.ethers.formatEther(yourBalance), "BEAM");

  if (yourBalance < SEND_AMOUNT) {
    console.log("\n❌ Insufficient balance!");
    return;
  }

  // Send BEAM directly
  console.log("\n⏳ Sending BEAM to new helper...");
  const tx = await signer.sendTransaction({
    to: NEW_HELPER,
    value: SEND_AMOUNT
  });
  console.log("📝 Transaction:", tx.hash);
  
  const receipt = await tx.wait();
  console.log("✅ Confirmed in block:", receipt.blockNumber);

  // Check new helper balance
  const newBalance = await hre.ethers.provider.getBalance(NEW_HELPER);
  console.log("\n📊 New Helper Balance:", hre.ethers.formatEther(newBalance), "BEAM");

  console.log("\n🎉 BEAM sent to new helper!");
  console.log("💡 Next: Delegate to validator");
  console.log("   npx hardhat run scripts/delegate-beam.js --network beamTestnet");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });
