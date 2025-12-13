import { ethers } from "ethers";
import {
  createAvalancheWalletClient,
  createPChainClient,
  createAvalancheClient,
  formatEther,
} from "@avalanche-sdk/client";
import { privateKeyToAvalancheAccount } from "@avalanche-sdk/client/accounts";
import { avalancheFuji } from "@avalanche-sdk/client/chains";
import {
  avaxToWei,
  avaxToNanoAvax,
  nanoAvaxToAvax,
} from "@avalanche-sdk/client/utils";
import dotenv from "dotenv";

dotenv.config();

// Configuration
const PRIVATE_KEY = process.env.PRIVATE_KEY!;
const C_CHAIN_ADDRESS = process.env.C_CHAIN_ADDRESS!;
const P_CHAIN_ADDRESS = process.env.P_CHAIN_ADDRESS!;
const SPAVAX_CONTRACT_ADDRESS = process.env.SPAVAX_CONTRACT_ADDRESS || "";
const VALIDATOR_NODE_ID = process.env.VALIDATOR_NODE_ID!;
const FUJI_RPC_URL = "https://api.avax-test.network/ext/bc/C/rpc";

// Contract ABI
const SPAVAX_ABI = [
  "function totalPooledAVAX() view returns (uint256)",
  "function getStats() view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256)",
  "function withdraw(uint256 amount) external",
  "function deposit() external payable",
  "function addRewards() external payable",
];

const PRIMARY_NETWORK_ID = "11111111111111111111111111111111LpoYY";

class SparrowBackend {
  private ethersProvider: ethers.JsonRpcProvider;
  private ethersWallet: ethers.Wallet;
  private contract?: ethers.Contract;
  private avaxWallet: any;
  private pChain: any;
  private cChain: any;

  constructor() {
    const account = privateKeyToAvalancheAccount(PRIVATE_KEY);

    this.cChain = createAvalancheClient({
      chain: avalancheFuji,
      transport: { type: "http" },
    });

    this.pChain = createPChainClient({
      chain: avalancheFuji,
      transport: { type: "http" },
    });

    this.avaxWallet = createAvalancheWalletClient({
      account,
      chain: avalancheFuji,
      transport: { type: "http" },
    });

    this.ethersProvider = new ethers.JsonRpcProvider(FUJI_RPC_URL);
    this.ethersWallet = new ethers.Wallet(PRIVATE_KEY, this.ethersProvider);

    if (SPAVAX_CONTRACT_ADDRESS) {
      this.contract = new ethers.Contract(
        SPAVAX_CONTRACT_ADDRESS,
        SPAVAX_ABI,
        this.ethersWallet
      );
    }
  }

  // ============================================
  // BALANCE CHECKS
  // ============================================

  async checkBalances() {
    console.log("💰 Checking balances...\n");

    const cBalance = await this.cChain.getBalance({
      address: C_CHAIN_ADDRESS,
    });
    console.log("📍 C-Chain:", C_CHAIN_ADDRESS);
    console.log("   Balance:", formatEther(cBalance), "AVAX\n");

    const pBalance = await this.pChain.getBalance({
      addresses: [P_CHAIN_ADDRESS],
    });
    console.log("📍 P-Chain:", P_CHAIN_ADDRESS);
    console.log("   Balance:", nanoAvaxToAvax(pBalance.balance), "AVAX\n");
  }

  // ============================================
  // CONTRACT OPERATIONS
  // ============================================

  async getContractStats() {
    if (!this.contract || !SPAVAX_CONTRACT_ADDRESS) {
      console.log("❌ Contract not set. Deploy first and update .env\n");
      return;
    }

    console.log("📊 Contract Stats:\n");
    const stats = await this.contract.getStats();

    console.log("  Total Staked:", ethers.formatEther(stats[0]), "AVAX");
    console.log("  Total Supply:", ethers.formatEther(stats[1]), "spAVAX");
    console.log("  Exchange Rate:", ethers.formatEther(stats[2]));
    console.log("  Contract Balance:", ethers.formatEther(stats[3]), "AVAX");
    console.log("  DAO Fees:", ethers.formatEther(stats[4]), "AVAX");
    console.log("  Dev Fees:", ethers.formatEther(stats[5]), "AVAX\n");
  }

  async withdrawFromContract(amountAvax: string) {
    if (!this.contract) throw new Error("Contract not initialized");

    console.log(`💸 Withdrawing ${amountAvax} AVAX from contract...\n`);
    const tx = await this.contract.withdraw(ethers.parseEther(amountAvax));
    console.log("  TX:", tx.hash);
    await tx.wait();
    console.log("✅ Done!\n");
  }

  async addRewardsToContract(rewardAvax: string) {
    if (!this.contract) throw new Error("Contract not initialized");

    console.log(`💰 Adding ${rewardAvax} AVAX as rewards...\n`);
    const tx = await this.contract.addRewards({
      value: ethers.parseEther(rewardAvax),
    });
    console.log("  TX:", tx.hash);
    await tx.wait();
    console.log("✅ Done!\n");
  }

  // ============================================
  // CROSS-CHAIN BRIDGING
  // ============================================

  async bridgeCToP(amountAvax: number) {
    console.log(`🌉 Bridging ${amountAvax} AVAX: C → P\n`);

    const result = await this.avaxWallet.send({
      to: P_CHAIN_ADDRESS,
      amount: avaxToWei(amountAvax),
      sourceChain: "C",
      destinationChain: "P",
    });

    console.log("✅ Done!");
    console.log("  TXs:", result.txHashes, "\n");
    await this.sleep(10000);
  }

  async bridgePToC(amountAvax: number) {
    console.log(`🌉 Bridging ${amountAvax} AVAX: P → C\n`);

    const result = await this.avaxWallet.send({
      to: C_CHAIN_ADDRESS,
      amount: avaxToWei(amountAvax),
      sourceChain: "P",
      destinationChain: "C",
    });

    console.log("✅ Done!");
    console.log("  TXs:", result.txHashes, "\n");
    await this.sleep(10000);
  }

  // ============================================
  // P-CHAIN DELEGATION
  // ============================================

  async listValidators() {
    console.log("📡 Fetching validators...\n");

    const result = await this.pChain.getCurrentValidators({
      subnetID: PRIMARY_NETWORK_ID,
    });

    const now = Math.floor(Date.now() / 1000);

    const suitable = result.validators
      .filter((v: any) => {
        const hoursLeft = (Number(v.endTime) - now) / 3600;
        return hoursLeft >= 24;
      })
      .sort((a: any, b: any) => Number(b.stakeAmount) - Number(a.stakeAmount))
      .slice(0, 10);

    console.log("✅ Top 10 Validators (24+ hours left):\n");
    console.log("=".repeat(80));

    suitable.forEach((v: any, i: number) => {
      const timeLeft = Number(v.endTime) - now;
      const days = Math.floor(timeLeft / 86400);
      const hours = Math.floor((timeLeft % 86400) / 3600);

      const stakeAmount =
        typeof v.stakeAmount === "bigint"
          ? Number(v.stakeAmount) / 1e9
          : v.stakeAmount
          ? Number(v.stakeAmount) / 1e9
          : 0;

      console.log(`\n${i + 1}. ${v.nodeID}`);
      console.log(`   Stake: ${stakeAmount.toFixed(2)} AVAX`);
      console.log(`   Time Left: ${days}d ${hours}h`);
    });

    console.log("\n" + "=".repeat(80) + "\n");
  }

  async checkValidator() {
    console.log(`🔍 Checking validator ${VALIDATOR_NODE_ID}...\n`);

    const result = await this.pChain.getCurrentValidators({
      subnetID: PRIMARY_NETWORK_ID,
      nodeIDs: [VALIDATOR_NODE_ID],
    });

    if (!result.validators || result.validators.length === 0) {
      console.log("❌ Validator not found!\n");
      return false;
    }

    const validator = result.validators[0];
    const now = Math.floor(Date.now() / 1000);
    const hoursLeft = (Number(validator.endTime) - now) / 3600;

    const stakeAmount =
      typeof validator.stakeAmount === "bigint"
        ? Number(validator.stakeAmount) / 1e9
        : validator.stakeAmount
        ? Number(validator.stakeAmount) / 1e9
        : 0;

    console.log("✅ Validator Found:");
    console.log(`   Stake: ${stakeAmount.toFixed(2)} AVAX`);
    console.log(`   Time Left: ${(hoursLeft / 24).toFixed(1)} days`);
    console.log(`   Delegators: ${validator.delegators?.length || 0}\n`);

    return hoursLeft >= 24;
  }

  async delegate(amountAvax: number, durationDays: number) {
    console.log(`🚀 Delegating ${amountAvax} AVAX for ${durationDays} days\n`);

    const isValid = await this.checkValidator();
    if (!isValid) {
      throw new Error("Validator not good");
    }

    const endTime = BigInt(
      Math.floor(Date.now() / 1000) + durationDays * 24 * 60 * 60
    );

    console.log("📝 Preparing...");
    const prepared =
      await this.avaxWallet.pChain.prepareAddPermissionlessDelegatorTxn({
        nodeId: VALIDATOR_NODE_ID,
        stakeInAvax: avaxToNanoAvax(amountAvax),
        end: endTime,
        rewardAddresses: [P_CHAIN_ADDRESS],
        threshold: 1,
      });

    console.log("✍️  Signing...");
    const signed = await this.avaxWallet.signXPTransaction({
      tx: prepared.tx,
      chainAlias: "P",
    });

    console.log("📤 Sending...");
    const { txHash } = await this.avaxWallet.sendXPTransaction({
      tx: signed.signedTxHex,
      chainAlias: "P",
    });

    console.log("\n🎉 Success!");
    console.log(`  TX: ${txHash}`);
    console.log(
      `  View: https://subnets-test.avax.network/p-chain/tx/${txHash}\n`
    );
  }

  async checkDelegations() {
  console.log("📊 Checking YOUR delegations...\n");
  console.log(`Validator: ${VALIDATOR_NODE_ID}\n`);
  
  const result = await this.pChain.getCurrentValidators({
    subnetID: PRIMARY_NETWORK_ID,
    nodeIDs: [VALIDATOR_NODE_ID],
  });
  
  if (!result.validators || result.validators.length === 0) {
    console.log("❌ Validator not found\n");
    return 0;
  }
  
  const validator = result.validators[0];
  console.log(`✅ Found validator`);
  console.log(`   Total delegators: ${validator.delegators?.length || 0}\n`);
  
  if (!validator.delegators || validator.delegators.length === 0) {
    console.log("❌ No delegators on this validator\n");
    return 0;
  }
  
  let found = 0;
  const now = Math.floor(Date.now() / 1000);
  
  for (const d of validator.delegators) {
    const addresses = d.rewardOwner?.addresses || [];
    const isYours = addresses.some((addr: string) => 
      addr.toLowerCase() === P_CHAIN_ADDRESS.toLowerCase()
    );
    
    if (isYours) {
      found++;
      const timeLeft = Number(d.endTime) - now;
      const days = Math.floor(timeLeft / 86400);
      const hours = Math.floor((timeLeft % 86400) / 3600);
      
      // FIX: Use 'weight' field (in nanoAVAX)
      const amount = Number(d.weight) / 1e9;
      const reward = Number(d.potentialReward || 0) / 1e9;
      
      console.log(`🎉 YOUR DELEGATION #${found}:`);
      console.log(`   Amount: ${amount.toFixed(4)} AVAX`);
      console.log(`   Started: ${new Date(Number(d.startTime) * 1000).toISOString()}`);
      console.log(`   Ends: ${new Date(Number(d.endTime) * 1000).toISOString()}`);
      console.log(`   Time Left: ${days}d ${hours}h`);
      console.log(`   Potential Reward: ${reward.toFixed(6)} AVAX`);
      console.log(`   TX: ${d.txID}`);
      console.log(`   View: https://subnets-test.avax.network/p-chain/tx/${d.txID}\n`);
    }
  }
  
  if (found === 0) {
    console.log("⚠️  Your address not found in delegators\n");
  }
  
  return found;
}

  private sleep(ms: number) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}

// ============================================
// CLI
// ============================================

const backend = new SparrowBackend();
const cmd = process.argv[2];
const arg1 = process.argv[3];
const arg2 = process.argv[4];

(async () => {
  try {
    if (!cmd) {
      console.log("📖 SPARROW BACKEND - USAGE:\n");
      console.log("Balances:");
      console.log("  npm run dev balances\n");
      console.log("Contract:");
      console.log("  npm run dev stats");
      console.log("  npm run dev withdraw <amount>");
      console.log("  npm run dev add-rewards <amount>\n");
      console.log("Bridging:");
      console.log("  npm run dev bridge-c-to-p <amount>");
      console.log("  npm run dev bridge-p-to-c <amount>\n");
      console.log("Delegation:");
      console.log("  npm run dev list-validators");
      console.log("  npm run dev check-validator");
      console.log("  npm run dev delegate <amount> <days>");
      console.log("  npm run dev delegations\n");
      return;
    }

    switch (cmd) {
      case "balances":
        await backend.checkBalances();
        break;
      case "stats":
        await backend.getContractStats();
        break;
      case "withdraw":
        await backend.withdrawFromContract(arg1 || "1");
        break;
      case "add-rewards":
        await backend.addRewardsToContract(arg1 || "0.1");
        break;
      case "bridge-c-to-p":
        await backend.bridgeCToP(parseFloat(arg1 || "1"));
        break;
      case "bridge-p-to-c":
        await backend.bridgePToC(parseFloat(arg1 || "1"));
        break;
      case "list-validators":
        await backend.listValidators();
        break;
      case "check-validator":
        await backend.checkValidator();
        break;
      case "delegate":
        await backend.delegate(parseFloat(arg1 || "1"), parseInt(arg2 || "2"));
        break;
      case "delegations":
        await backend.checkDelegations();
        break;
      default:
        console.log("❌ Unknown command. Run: npm run dev");
    }
  } catch (error: any) {
    console.error("\n❌ Error:", error.message);
    process.exit(1);
  }
})();
