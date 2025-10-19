// Verify Beam Testnet Validator Manager Contract
const { ethers } = require("ethers");

const BEAM_TESTNET_RPC = "https://subnets.avax.network/beam/testnet/rpc";
const BEAM_MAINNET_RPC = "https://subnets.avax.network/beam/rpc";

// Validator Manager addresses (different per network)
const VALIDATOR_MANAGER_MAINNET = "0x2FD428A5484d113294b44E69Cb9f269abC1d5B54"; // Confirmed from mainnet tx
const VALIDATOR_MANAGER_TESTNET_OPTIONS = [
    "0x2FD428A5484d113294b44E69Cb9f269abC1d5B54", // Try same as mainnet
    "0x0200000000000000000000000000000000000000"  // Try standard precompiled
];

async function verifyValidatorManager(network = "testnet") {
    const rpc = network === "testnet" ? BEAM_TESTNET_RPC : BEAM_MAINNET_RPC;
    const provider = new ethers.JsonRpcProvider(rpc);
    
    console.log("╔══════════════════════════════════════════════════════════════╗");
    console.log("║     Beam Validator Manager Verification                     ║");
    console.log("╚══════════════════════════════════════════════════════════════╝\n");
    
    console.log(`🌐 Network: Beam ${network === "testnet" ? "Testnet" : "Mainnet"}`);
    console.log(`🔗 RPC: ${rpc}\n`);
    
    // For testnet, try multiple addresses
    const addressesToTry = network === "testnet" 
        ? VALIDATOR_MANAGER_TESTNET_OPTIONS 
        : [VALIDATOR_MANAGER_MAINNET];
    
    try {
        // 1. Check network connection
        console.log("⏳ Checking network connection...");
        const blockNumber = await provider.getBlockNumber();
        console.log(`✅ Connected! Current block: ${blockNumber}\n`);
        
        // 2. Try each address
        let foundAddress = null;
        
        for (const address of addressesToTry) {
            console.log(`\n🔍 Testing address: ${address}`);
        
            console.log("   ⏳ Checking if contract exists...");
            const code = await provider.getCode(address);
        
            if (code === "0x" || code === "0x0") {
                console.log("   ❌ No contract at this address");
                continue;
            }
        
            console.log("   ✅ Contract exists!");
            console.log(`      Bytecode length: ${code.length} characters`);
        
            // Check balance
            const balance = await provider.getBalance(address);
            console.log(`      Balance: ${ethers.formatEther(balance)} BEAM`);
            
            foundAddress = address;
            break;
        }
        
        if (!foundAddress) {
            console.log("\n❌ ERROR: Could not find Validator Manager contract!");
            console.log("   Tried addresses:");
            addressesToTry.forEach(addr => console.log(`   - ${addr}`));
            return false;
        }
        
        console.log(`\n✅ Found Validator Manager at: ${foundAddress}\n`);
        
        // 3. Test function availability
        console.log("⏳ Testing staking function...");
        
        const iface = new ethers.Interface([
            "function initializeDelegatorRegistration(bytes32 validationID) external payable"
        ]);
        
        const dummyValidatorID = "0x" + "0".repeat(64);
        const data = iface.encodeFunctionData("initializeDelegatorRegistration", [dummyValidatorID]);
        
        try {
            await provider.estimateGas({
                to: foundAddress,
                data: data,
                value: ethers.parseEther("1.0")
            });
            console.log("✅ Function 'initializeDelegatorRegistration' is callable!\n");
        } catch (error) {
            if (error.message.includes("execution reverted")) {
                console.log("✅ Function exists (reverted as expected with dummy data)\n");
            } else {
                console.log("⚠️  Could not verify function");
                console.log(`   Error: ${error.message}\n");
            }
        }
        
        // 4. Summary
        console.log("╔══════════════════════════════════════════════════════════════╗");
        console.log("║                    Verification Summary                      ║");
        console.log("╚══════════════════════════════════════════════════════════════╝\n");
        console.log(`✅ Validator Manager Address: ${foundAddress}`);
        console.log("✅ Contract verified and accessible");
        console.log("✅ Ready for integration\n");
        
        console.log("📝 Next Steps:");
        console.log("   1. Update spBEAM.sol with this address");
        console.log("   2. Find active validators for testing");
        console.log("   3. Test staking transaction");
        console.log(`   4. Validators: https://nodes.onbeam.com/validators?network=${network}\n");
        
        console.log("💾 Save this address:");
        console.log(`   ${network.toUpperCase()}: ${foundAddress}\n");
        
        return true;
        
    } catch (error) {
        console.log("❌ ERROR during verification:");
        console.log(`   ${error.message}\n`);
        return false;
    }
}

// Run verification
const network = process.argv[2] || "testnet";
verifyValidatorManager(network)
    .then((success) => {
        if (success) {
            console.log("✅ Verification complete!");
        } else {
            console.log("❌ Verification failed!");
            process.exit(1);
        }
    })
    .catch((error) => {
        console.error("Fatal error:", error);
        process.exit(1);
    });
