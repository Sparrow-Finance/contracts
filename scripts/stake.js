const hre = require("hardhat");
require("dotenv").config();

async function main() {
  const proxyAddress = "0xE68f6732Ad4b2fD541926fEe43E0F353611Fa09d";
  const [deployer] = await hre.ethers.getSigners();
  
  const spavax = await hre.ethers.getContractAt("spAVAX", proxyAddress);

  console.log("💰 Staking 1 AVAX...");
  const tx = await spavax.stake(0, { value: hre.ethers.parseEther("1.0") });
  console.log("TX:", tx.hash);
  await tx.wait();
  console.log("✅ Staked!\n");
  
  const balance = await spavax.balanceOf(deployer.address);
  console.log("Your spAVAX:", hre.ethers.formatEther(balance));
}

main().catch(console.error);