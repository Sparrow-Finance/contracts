const hre = require("hardhat");

async function main() {
  console.log("🚀 Deploying Sparrow Finance spAVAX (UUPS Upgradeable)...\n");

  // Get deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log("📝 Deploying with account:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("💰 Account balance:", hre.ethers.formatEther(balance), "AVAX\n");

  // Deploy implementation
  console.log("⏳ Deploying spAVAX implementation...");
  const SpAVAX = await hre.ethers.getContractFactory("spAVAX");
  const implementation = await SpAVAX.deploy();
  await implementation.waitForDeployment();
  const implementationAddress = await implementation.getAddress();
  console.log("✅ Implementation deployed to:", implementationAddress);

  // Encode initialize call
  const initializeData = implementation.interface.encodeFunctionData("initialize", []);
  
  // Deploy proxy using ERC1967Proxy from OpenZeppelin
  console.log("\n⏳ Deploying ERC1967 Proxy...");
  
  // We'll deploy a minimal proxy that delegates to implementation
  const proxyABI = [
    "constructor(address _logic, bytes memory _data)"
  ];
  
  // ERC1967Proxy bytecode
  const proxyBytecode = "0x60806040526040516107e83803806107e88339818101604052810190610025919061048f565b610031828260006100

37565b50506105a9565b61004083610100565b6040516001600160a01b038416907fbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b90600090a260008251118061008157505b156100fb576100f9836001600160a01b0316635c60da1b6040518163ffffffff1660e01b8152600401602060405180830381865afa1580156100c7573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906100eb9190610552565b836102a560201b6100291760201c565b505b505050565b610113816102d160201b6100551760201c565b6101725760405162461bcd60e51b815260206004820152602560248201527f455243313936373a206e657720696d706c656d656e746174696f6e206973206e60448201526437ba1030b760d91b60648201526084015b60405180910390fd5b806101867f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc60001b6102e060201b6100641760201c565b80546001600160a01b0319166001600160a01b039290921691909117905550565b60606101ca838360405180606001604052806027815260200161093560279139610313565b9392505050565b6001600160a01b03163b151590565b90565b6060600080856001600160a01b03168560405161030091906104fa565b600060405180830381855af49150503d806000811461033b576040519150601f19603f3d011682016040523d82523d6000602084013e610340565b606091505b50915091506103528683838761035c565b9695505050505050565b606083156103c85782516103c1576001600160a01b0385163b6103c15760405162461bcd60e51b815260206004820152601d60248201527f416464726573733a2063616c6c20746f206e6f6e2d636f6e74726163740000006044820152606401610169565b50816103d2565b6103d283836103da565b949350505050565b8151156103ea5781518083602001fd5b8060405162461bcd60e51b81526004016101699190610516565b80516001600160a01b038116811461041b57600080fd5b919050565b634e487b7160e01b600052604160045260246000fd5b60005b83811015610451578181015183820152602001610439565b838111156100fb5750506000910152565b6000806040838503121561047557600080fd5b61047e83610404565b60208401519092506001600160401b038082111561049b57600080fd5b818501915085601f8301126104af57600080fd5b8151818111156104c1576104c1610420565b604051601f8201601f19908116603f011681019083821181831017156104e9576104e9610420565b8160405282815288602084870101111561050257600080fd5b610513836020830160208801610436565b80955050505050509250929050565b60006020828403121561053457600080fd5b61053d82610404565b9392505050565b6000815180845261055c816020860160208601610436565b601f01601f19169290920160200192915050565b61037f806105886000396000f3fe60806040523661001357610011610017565b005b6100115b610027610022610067565b61009f565b565b606061004e838360405180606001604052806027815260200161032360279139610100565b9392505050565b6001600160a01b03163b151590565b90565b600061009a7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc546001600160a01b031690565b905090565b3660008037600080366000845af43d6000803e8080156100be573d6000f35b3d6000fd5b60606000808573ffffffff166001600160a01b0316856040516100e691906102d3565b600060405180830381855af49150503d8060008114610121576040519150601f19603f3d011682016040523d82523d6000602084013e610126565b606091505b509150915061013786838387610141565b9695505050505050565b606083156101ad5782516101a6576001600160a01b0385163b6101a65760405162461bcd60e51b815260206004820152601d60248201527f416464726573733a2063616c6c20746f206e6f6e2d636f6e747261637400000060448201526064015b60405180910390fd5b50816101b7565b6101b783836101bf565b949350505050565b8151156101cf5781518083602001fd5b8060405162461bcd60e51b815260040161019d91906102ef565b60005b838110156102045781810151838201526020016101ec565b83811115610213576000848401525b50505050565b600082516102308184602087016101eb565b9190910192915050565b6000815180845261025281602086016020860161016c565b601f01601f19169290920160200192915050565b6001600160a01b0391909116815260200190565b6001600160a01b03929092168252602082015260400190565b6001600160a01b038316815260406020820181905260009061019d9083018461023c565b6000602082840312156102d557600080fd5b815180151581146102e557600080fd5b9392505050565b60208152600061004e602083018461023c56fe416464726573733a206c6f772d6c6576656c2064656c65676174652063616c6c206661696c6564a2646970667358221220d51e81d9f7b5e3d0b3e3f3e3f3e3f3e3f3e3f3e3f3e3f3e3f3e3f3e3f3e364736f6c63430008160033";
  
  const Proxy = new hre.ethers.ContractFactory(proxyABI, proxyBytecode, deployer);
  const proxy = await Proxy.deploy(implementationAddress, initializeData);
  await proxy.waitForDeployment();
  const proxyAddress = await proxy.getAddress();
  
  console.log("✅ Proxy deployed to:", proxyAddress);

  // Attach to proxy to interact
  const spavax = SpAVAX.attach(proxyAddress);

  console.log("\n📊 Contract Details:");
  console.log("   Name:", await spavax.name());
  console.log("   Symbol:", await spavax.symbol());
  console.log("   Decimals:", await spavax.decimals());
  console.log("   Governance:", await spavax.governance());
  
  const stats = await spavax.getStats();
  console.log("\n⚙️  Initial Configuration:");
  console.log("   Total Pooled AVAX:", hre.ethers.formatEther(stats[0]));
  console.log("   Total Supply:", hre.ethers.formatEther(stats[1]));
  console.log("   Exchange Rate:", hre.ethers.formatEther(stats[2]));
  console.log("   DAO Fee:", stats[6].toString(), "basis points (", Number(stats[6]) / 100, "%)");
  console.log("   Dev Fee:", stats[7].toString(), "basis points (", Number(stats[7]) / 100, "%)");
  console.log("   Unlock Period:", (await spavax.unlockPeriod()).toString(), "seconds");
  
  console.log("\n🔗 Network:", hre.network.name);
  console.log("📍 Block Number:", await hre.ethers.provider.getBlockNumber());
  
  const deploymentInfo = {
    network: hre.network.name,
    proxyAddress: proxyAddress,
    implementationAddress: implementationAddress,
    deployer: deployer.address,
    blockNumber: await hre.ethers.provider.getBlockNumber(),
    timestamp: new Date().toISOString(),
    tokenName: await spavax.name(),
    tokenSymbol: await spavax.symbol(),
  };

  console.log("\n💾 Deployment Info:");
  console.log(JSON.stringify(deploymentInfo, null, 2));

  // Verification
  if (hre.network.name === "fuji" || hre.network.name === "mainnet") {
    console.log("\n⏳ Waiting 30 seconds before verification...");
    await new Promise(resolve => setTimeout(resolve, 30000));
    
    console.log("\n🔍 Verifying implementation on Snowtrace...");
    try {
      await hre.run("verify:verify", {
        address: implementationAddress,
        constructorArguments: [],
      });
      console.log("✅ Implementation verified!");
    } catch (error) {
      console.log("❌ Verification failed:", error.message);
      console.log("   You can verify manually later with:");
      console.log(`   npx hardhat verify --network ${hre.network.name} ${implementationAddress}`);
    }
  }

  console.log("\n🎉 Deployment complete!");
  console.log("\n📝 IMPORTANT - Save these addresses:");
  console.log("   🔷 Proxy (use this for interactions):", proxyAddress);
  console.log("   🔸 Implementation:", implementationAddress);
  console.log("\n📝 Next steps:");
  console.log("   1. Update UI with proxy address:", proxyAddress);
  console.log("   2. View on Snowtrace:", 
    hre.network.name === "fuji" 
      ? `https://testnet.snowtrace.io/address/${proxyAddress}`
      : `https://snowtrace.io/address/${proxyAddress}`
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
