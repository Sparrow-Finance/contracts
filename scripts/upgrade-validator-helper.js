const hre = require("hardhat");

async function main() {
  console.log("🔄 Upgrading Validator Helper...\n");

  const [deployer] = await hre.ethers.getSigners();
  console.log("📝 Upgrader:", deployer.address);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("💰 Balance:", hre.ethers.formatEther(balance), "BEAM\n");

  // Get proxy address
  const PROXY_ADDRESS = process.env.BEAM_VALIDATOR_HELPER || "0x1bc829d35A12520FB21429E5B10845f71aC864B2";

  console.log("📍 Proxy Address:", PROXY_ADDRESS);

  // Get current implementation
  const currentImpl = await hre.upgrades.erc1967.getImplementationAddress(PROXY_ADDRESS);
  console.log("📦 Current Implementation:", currentImpl);

  // Deploy new implementation
  console.log("\n⏳ Deploying new implementation...");
  console.log("   New feature:");
  console.log("   ✅ delegateFromBalance() - Delegate using helper's balance");
  console.log("   ✅ No need to send msg.value from caller\n");
  
  const HelperV2 = await hre.ethers.getContractFactory("spBeam_Validator_Helper");

  // Upgrade the proxy
  console.log("⏳ Upgrading proxy...");
  const upgraded = await hre.upgrades.upgradeProxy(PROXY_ADDRESS, HelperV2);
  await upgraded.waitForDeployment();

  // Get new implementation address
  const newImpl = await hre.upgrades.erc1967.getImplementationAddress(PROXY_ADDRESS);
  console.log("✅ New Implementation:", newImpl);

  // Verify upgrade
  console.log("\n🔍 Verifying upgrade...");
  const helper = HelperV2.attach(PROXY_ADDRESS);

  console.log("\n📊 Contract Details:");
  console.log("   Proxy:", PROXY_ADDRESS);

  // Check balance
  const helperBalance = await hre.ethers.provider.getBalance(PROXY_ADDRESS);
  console.log("   Balance:", hre.ethers.formatEther(helperBalance), "BEAM");

  const upgradeInfo = {
    network: hre.network.name,
    proxyAddress: PROXY_ADDRESS,
    oldImplementation: currentImpl,
    newImplementation: newImpl,
    upgrader: deployer.address,
    blockNumber: await hre.ethers.provider.getBlockNumber(),
    timestamp: new Date().toISOString(),
  };

  console.log("\n💾 Upgrade Info:");
  console.log(JSON.stringify(upgradeInfo, null, 2));

  console.log("\n📝 Next Steps:");
  console.log("   1) Delegate from balance: scripts/delegate-from-balance.js");
  console.log("   2) Helper will use its 300 BEAM balance");
  console.log("   3) No need to send BEAM from your wallet!");

  console.log("\n🎉 Upgrade complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Upgrade failed:", error);
    process.exit(1);
  });
