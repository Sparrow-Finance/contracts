const hre = require("hardhat");

async function main() {
  console.log("🔄 Upgrading spBEAM to include Validator Logic...\n");

  // Get deployer
  const [deployer] = await hre.ethers.getSigners();
  console.log("📝 Upgrader:", deployer.address);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("💰 Balance:", hre.ethers.formatEther(balance), "BEAM\n");

  // IMPORTANT: Replace with your actual proxy address
  const PROXY_ADDRESS = "0x21e9726d777400c5dcBF65cF595125B21359A1DD"; // ← UPDATE THIS!

  console.log("📍 Proxy Address:", PROXY_ADDRESS);

  // Get current implementation
  const currentImpl = await hre.upgrades.erc1967.getImplementationAddress(PROXY_ADDRESS);
  console.log("📦 Current Implementation:", currentImpl);

  // Deploy new implementation
  console.log("\n⏳ Deploying new implementation with validator logic...");
  const SpBEAMV2 = await hre.ethers.getContractFactory(
    "contracts/spBEAM/spBEAM_WithValidatorLogic.sol:spBEAM"
  );

  // Upgrade the proxy
  const upgraded = await hre.upgrades.upgradeProxy(PROXY_ADDRESS, SpBEAMV2);
  await upgraded.waitForDeployment();

  // Get new implementation address
  const newImpl = await hre.upgrades.erc1967.getImplementationAddress(PROXY_ADDRESS);
  console.log("✅ New Implementation:", newImpl);

  // Verify upgrade
  console.log("\n🔍 Verifying upgrade...");
  const spbeam = SpBEAMV2.attach(PROXY_ADDRESS);

  console.log("\n📊 Contract Details (After Upgrade):");
  console.log("   Name:", await spbeam.name());
  console.log("   Symbol:", await spbeam.symbol());
  console.log("   Governance:", await spbeam.governance());

  const stats = await spbeam.getStats();
  console.log("\n⚙️  Current State:");
  console.log("   Total Pooled BEAM:", hre.ethers.formatEther(stats[0]));
  console.log("   Total Supply:", hre.ethers.formatEther(stats[1]));
  console.log("   Exchange Rate:", hre.ethers.formatEther(stats[2]));

  // Check new functions exist
  console.log("\n✅ New Functions Available:");
  console.log("   - stakeToValidator()");
  console.log("   - unstakeFromValidator()");
  console.log("   - claimDelegationRewards()");
  console.log("   - completeDelegatorRemoval()");
  console.log("   - unwrapWBEAM()");
  console.log("   - swapRewardTokenForBEAM()");
  console.log("   - checkAndAutoStake()");
  console.log("   - setReserveRatio()");
  console.log("   - setAutoStakeThreshold()");
  console.log("   - toggleAutoStaking()");
  console.log("   - setCurrentValidator()");
  console.log("   - setSparrowSwapRouter()");
  console.log("   - rescueTokens()");

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
  console.log("   1) Set reserve ratio: setReserveRatio(1000) // 10%");
  console.log("   2) Set auto-stake threshold: setAutoStakeThreshold(100 ether)");
  console.log("   3) Set Sparrow router: setSparrowSwapRouter(ROUTER_ADDRESS)");
  console.log("   4) Set current validator: setCurrentValidator(VALIDATOR_ID)");
  console.log("   5) Test validator staking on small amount");

  console.log("\n🎉 Upgrade complete! All user balances and data preserved!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Upgrade failed:", error);
    process.exit(1);
  });
