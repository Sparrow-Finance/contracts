const hre = require("hardhat");
require("dotenv").config();

async function main() {
  console.log("💸 Sending AVAX to Contract...\n");

  // Contract address to send AVAX to
  const contractAddress = "0x639573C396C52ED735DA74A3215b736a618EaDC2";

  // Amount to send (in AVAX)
  const amountInAVAX = "0.9"; // Change this amount as needed
  const amountInWei = hre.ethers.parseEther(amountInAVAX);

  // Get signer from PRIVATE_KEY in .env
  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) {
    throw new Error("PRIVATE_KEY not found in .env file");
  }

  const signer = new hre.ethers.Wallet(privateKey, hre.ethers.provider);

  console.log("📝 Sender Address:", signer.address);

  const balanceBefore = await hre.ethers.provider.getBalance(signer.address);
  console.log("💰 Sender Balance:", hre.ethers.formatEther(balanceBefore), "AVAX");

  const contractBalanceBefore = await hre.ethers.provider.getBalance(contractAddress);
  console.log("💰 Contract Balance Before:", hre.ethers.formatEther(contractBalanceBefore), "AVAX\n");

  console.log(`⏳ Sending ${amountInAVAX} AVAX to ${contractAddress}...`);

  // Send transaction
  const tx = await signer.sendTransaction({
    to: contractAddress,
    value: amountInWei,
  });

  console.log("📤 Transaction sent:", tx.hash);
  console.log("⏳ Waiting for confirmation...");

  const receipt = await tx.wait();
  console.log("✅ Transaction confirmed in block:", receipt.blockNumber);

  // Check balances after
  const balanceAfter = await hre.ethers.provider.getBalance(signer.address);
  console.log("\n💰 Sender Balance After:", hre.ethers.formatEther(balanceAfter), "AVAX");

  const contractBalanceAfter = await hre.ethers.provider.getBalance(contractAddress);
  console.log("💰 Contract Balance After:", hre.ethers.formatEther(contractBalanceAfter), "AVAX");

  console.log("\n🎉 Transfer complete!");
  console.log("🔗 View on Snowtrace:", `https://testnet.snowtrace.io/tx/${tx.hash}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Transfer failed:", error);
    process.exit(1);
  });
