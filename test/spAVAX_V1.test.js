const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("spAVAX (Upgradeable)", function () {
  let spavax;
  let owner;
  let user1;
  let user2;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    const SpAVAX = await ethers.getContractFactory("spAVAX_V1");
    // Deploy as upgradeable proxy
    spavax = await upgrades.deployProxy(SpAVAX, [], {
      initializer: "initialize",
      kind: "uups"
    });
    await spavax.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the right governance", async function () {
      expect(await spavax.governance()).to.equal(owner.address);
    });

    it("Should have correct name and symbol", async function () {
      expect(await spavax.name()).to.equal("Sparrow Staked AVAX");
      expect(await spavax.symbol()).to.equal("spAVAX");
    });

    it("Should initialize with zero supply", async function () {
      expect(await spavax.totalSupply()).to.equal(0);
      expect(await spavax.totalPooledAVAX()).to.equal(0);
    });

    it("Should have correct fee structure", async function () {
      expect(await spavax.daoFeeBasisPoints()).to.equal(500); // 5%
      expect(await spavax.devFeeBasisPoints()).to.equal(300); // 3%
      expect(await spavax.protocolFeeBasisPoints()).to.equal(800); // 8%
    });

    it("Should have correct minimum stake amount", async function () {
      expect(await spavax.minStakeAmount()).to.equal(ethers.parseEther("0.1"));
    });
  });

  describe("Staking", function () {
    it("Should reject stake below 0.1 AVAX", async function () {
      const tooSmall = ethers.parseEther("0.05");
      
      await expect(
        spavax.connect(user1).stake(0, { value: tooSmall })
      ).to.be.revertedWith("Below minimum stake");
    });

    it("Should allow first stake with 0.1 AVAX", async function () {
      const stakeAmount = ethers.parseEther("0.1");
      
      await expect(spavax.connect(user1).stake(0, { value: stakeAmount }))
        .to.emit(spavax, "Staked")
        .withArgs(user1.address, stakeAmount, stakeAmount);

      expect(await spavax.balanceOf(user1.address)).to.equal(stakeAmount);
      expect(await spavax.totalPooledAVAX()).to.equal(stakeAmount);
    });

    it("Should allow multiple users to stake", async function () {
      // First user stakes
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("0.1") });
      
      // Second user stakes
      const stakeAmount = ethers.parseEther("0.1");
      
      await expect(spavax.connect(user2).stake(0, { value: stakeAmount }))
        .to.emit(spavax, "Staked");

      expect(await spavax.balanceOf(user2.address)).to.be.gt(0);
    });

    it("Should reject stakes below minimum", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("0.1") });
      
      const tooSmall = ethers.parseEther("0.05"); // Below 0.1 AVAX minimum
      
      await expect(
        spavax.connect(user2).stake(0, { value: tooSmall })
      ).to.be.revertedWith("Below minimum stake");
    });

    it("Should enforce slippage protection", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("1") });
      
      // Request too many shares
      await expect(
        spavax.connect(user2).stake(ethers.parseEther("100"), { value: ethers.parseEther("1") })
      ).to.be.revertedWith("Slippage too high");
    });

    it("Should calculate correct share amount for subsequent stakes", async function () {
      // First stake: 1:1 ratio
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      
      // Add rewards to change ratio
      await spavax.addRewards({ value: ethers.parseEther("1") });
      
      // Second stake should get fewer shares
      const stakeAmount = ethers.parseEther("10");
      const expectedShares = await spavax.previewStake(stakeAmount);
      
      await spavax.connect(user2).stake(0, { value: stakeAmount });
      
      expect(await spavax.balanceOf(user2.address)).to.equal(expectedShares);
    });

    it("Should not allow staking when paused", async function () {
      await spavax.pause();
      
      await expect(
        spavax.connect(user1).stake(0, { value: ethers.parseEther("1") })
      ).to.be.revertedWithCustomError(spavax, "EnforcedPause");
    });

    it("Should handle large stakes correctly", async function () {
      const largeStake = ethers.parseEther("100");
      
      await expect(spavax.connect(user1).stake(0, { value: largeStake }))
        .to.emit(spavax, "Staked");

      expect(await spavax.balanceOf(user1.address)).to.equal(largeStake);
      expect(await spavax.totalPooledAVAX()).to.equal(largeStake);
    });
  });

  describe("Unlock Requests", function () {
    beforeEach(async function () {
      // User stakes first
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
    });

    it("Should allow users to request unlock", async function () {
      const unlockAmount = ethers.parseEther("5");
      
      await expect(spavax.connect(user1).requestUnlock(unlockAmount, 0))
        .to.emit(spavax, "UnlockRequested");

      const count = await spavax.getUnlockRequestCount(user1.address);
      expect(count).to.equal(1);
    });

    it("Should lock spAVAX in contract during unlock", async function () {
      const unlockAmount = ethers.parseEther("5");
      const initialBalance = await spavax.balanceOf(user1.address);
      
      await spavax.connect(user1).requestUnlock(unlockAmount, 0);
      
      expect(await spavax.balanceOf(user1.address)).to.equal(initialBalance - unlockAmount);
      expect(await spavax.balanceOf(await spavax.getAddress())).to.equal(unlockAmount);
    });

    it("Should enforce slippage protection on unlock", async function () {
      await expect(
        spavax.connect(user1).requestUnlock(ethers.parseEther("5"), ethers.parseEther("100"))
      ).to.be.revertedWith("Slippage too high");
    });

    it("Should not allow unlock of more than balance", async function () {
      await expect(
        spavax.connect(user1).requestUnlock(ethers.parseEther("20"), 0)
      ).to.be.revertedWith("Insufficient balance");
    });

    it("Should lock exchange rate at request time", async function () {
      const unlockAmount = ethers.parseEther("5");
      
      // Request unlock
      await spavax.connect(user1).requestUnlock(unlockAmount, 0);
      
      // Get unlock request details
      const request = await spavax.getUnlockRequest(user1.address, 0);
      const lockedAvax = request[1]; // avaxAmount
      
      // Add rewards (changes exchange rate)
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      // Check that locked amount hasn't changed
      const requestAfter = await spavax.getUnlockRequest(user1.address, 0);
      expect(requestAfter[1]).to.equal(lockedAvax); // Still same amount
    });

    it("Should not allow more than 100 unlock requests", async function () {
      // Create 100 requests (need to have enough balance)
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("100") }); // Add more balance
      
      for (let i = 0; i < 100; i++) {
        await spavax.connect(user1).requestUnlock(ethers.parseEther("0.1"), 0);
      }
      
      // 101st should fail
      await expect(
        spavax.connect(user1).requestUnlock(ethers.parseEther("0.1"), 0)
      ).to.be.revertedWith("Too many pending requests");
    });

    it("Should allow multiple unlock requests from same user", async function () {
      await spavax.connect(user1).requestUnlock(ethers.parseEther("2"), 0);
      await spavax.connect(user1).requestUnlock(ethers.parseEther("2"), 0);
      await spavax.connect(user1).requestUnlock(ethers.parseEther("2"), 0);
      
      const count = await spavax.getUnlockRequestCount(user1.address);
      expect(count).to.equal(3);
    });
  });

  describe("Claiming Unlocks", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      await spavax.connect(user1).requestUnlock(ethers.parseEther("5"), 0);
    });

    it("Should not allow claim before unlock period", async function () {
      await expect(
        spavax.connect(user1).claimUnlock(0)
      ).to.be.revertedWith("Unlock period not finished");
    });

    it("Should allow claim after unlock period", async function () {
      // Fast forward 61 seconds
      await time.increase(61);
      
      const initialBalance = await ethers.provider.getBalance(user1.address);
      
      await spavax.connect(user1).claimUnlock(0);
      
      const finalBalance = await ethers.provider.getBalance(user1.address);
      expect(finalBalance).to.be.gt(initialBalance);
    });

    it("Should not allow claim after expiry", async function () {
      // Fast forward past claim window (7 days + 61 seconds)
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      await expect(
        spavax.connect(user1).claimUnlock(0)
      ).to.be.revertedWith("Claim window expired");
    });

    it("Should allow claiming expired unlock for spAVAX", async function () {
      // Fast forward past claim window
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      const balanceBefore = await spavax.balanceOf(user1.address);
      
      await spavax.connect(user1).claimExpired(0);
      
      const balanceAfter = await spavax.balanceOf(user1.address);
      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should use locked exchange rate when claiming", async function () {
      // Get locked AVAX amount
      const request = await spavax.getUnlockRequest(user1.address, 0);
      const lockedAvax = request[1];
      
      // Add huge rewards (doubles exchange rate)
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      // Fast forward
      await time.increase(61);
      
      const balanceBefore = await ethers.provider.getBalance(user1.address);
      const tx = await spavax.connect(user1).claimUnlock(0);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      
      const balanceAfter = await ethers.provider.getBalance(user1.address);
      
      // Should receive locked amount (not new higher rate)
      const received = balanceAfter - balanceBefore + gasUsed;
      expect(received).to.be.closeTo(lockedAvax, ethers.parseEther("0.001"));
    });

    it("Should properly update totalPooledAVAX after claim", async function () {
      const pooledBefore = await spavax.totalPooledAVAX();
      
      await time.increase(61);
      await spavax.connect(user1).claimUnlock(0);
      
      const pooledAfter = await spavax.totalPooledAVAX();
      expect(pooledAfter).to.be.lt(pooledBefore);
    });
  });

  describe("Cancel Unlock", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      await spavax.connect(user1).requestUnlock(ethers.parseEther("5"), 0);
    });

    it("Should allow canceling unlock request", async function () {
      const balanceBefore = await spavax.balanceOf(user1.address);
      
      await spavax.connect(user1).cancelUnlock(0);
      
      const balanceAfter = await spavax.balanceOf(user1.address);
      expect(balanceAfter).to.be.gt(balanceBefore);
      
      const count = await spavax.getUnlockRequestCount(user1.address);
      expect(count).to.equal(0);
    });

    it("Should not allow canceling after expiry", async function () {
      // Fast forward past expiry
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      await expect(
        spavax.connect(user1).cancelUnlock(0)
      ).to.be.revertedWith("Request expired, use claimExpired");
    });
  });

  describe("Rewards Distribution", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("100") });
    });

    it("Should distribute rewards correctly", async function () {
      const rewardAmount = ethers.parseEther("10");
      
      await expect(spavax.addRewards({ value: rewardAmount }))
        .to.emit(spavax, "RewardsAdded");

      // Check fee distribution (5% DAO + 3% dev = 8% total, 92% to users)
      expect(await spavax.accumulatedDaoFees()).to.equal(ethers.parseEther("0.5")); // 5%
      expect(await spavax.accumulatedDevFees()).to.equal(ethers.parseEther("0.3")); // 3%
      
      // User rewards (92%) should increase totalPooledAVAX
      expect(await spavax.totalPooledAVAX()).to.equal(ethers.parseEther("109.2")); // 100 + 9.2
    });

    it("Should increase spAVAX value after rewards", async function () {
      const rateBefore = await spavax.getExchangeRate();
      
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      const rateAfter = await spavax.getExchangeRate();
      expect(rateAfter).to.be.gt(rateBefore);
    });

    it("Should not allow adding zero rewards", async function () {
      await expect(
        spavax.addRewards({ value: 0 })
      ).to.be.revertedWith("Reward must be > 0");
    });

    it("Should handle multiple reward additions", async function () {
      await spavax.addRewards({ value: ethers.parseEther("5") });
      await spavax.addRewards({ value: ethers.parseEther("5") });
      
      expect(await spavax.totalPooledAVAX()).to.equal(ethers.parseEther("109.2")); // 100 + 9.2
    });
  });

  describe("Fee Collection", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("100") });
      await spavax.addRewards({ value: ethers.parseEther("10") });
    });

    it("Should allow governance to collect DAO fees", async function () {
      const balanceBefore = await ethers.provider.getBalance(owner.address);
      
      await spavax.collectDaoFees();
      
      const balanceAfter = await ethers.provider.getBalance(owner.address);
      expect(balanceAfter).to.be.gt(balanceBefore);
      expect(await spavax.accumulatedDaoFees()).to.equal(0);
    });

    it("Should allow governance to collect dev fees", async function () {
      await spavax.collectDevFees();
      expect(await spavax.accumulatedDevFees()).to.equal(0);
    });

    it("Should allow collecting all fees at once", async function () {
      await expect(spavax.collectAllFees())
        .to.emit(spavax, "AllFeesCollected");
      
      expect(await spavax.accumulatedDaoFees()).to.equal(0);
      expect(await spavax.accumulatedDevFees()).to.equal(0);
    });

    it("Should not allow non-governance to collect fees", async function () {
      await expect(
        spavax.connect(user1).collectDaoFees()
      ).to.be.revertedWith("Not governance");
    });

    it("Should not allow collecting fees when none accumulated", async function () {
      await spavax.collectAllFees(); // Collect all first
      
      await expect(
        spavax.collectAllFees()
      ).to.be.revertedWith("No fees to collect");
    });
  });

  describe("Admin Functions", function () {
    it("Should allow governance to withdraw AVAX", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      
      const balanceBefore = await ethers.provider.getBalance(owner.address);
      await spavax.withdraw(ethers.parseEther("5"));
      const balanceAfter = await ethers.provider.getBalance(owner.address);
      
      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should allow governance to deposit AVAX", async function () {
      await expect(spavax.deposit({ value: ethers.parseEther("5") }))
        .to.emit(spavax, "Deposited");
    });

    it("Should allow governance to update fee structure", async function () {
      await spavax.setFeeStructure(400, 200);
      
      expect(await spavax.daoFeeBasisPoints()).to.equal(400);
      expect(await spavax.devFeeBasisPoints()).to.equal(200);
      expect(await spavax.protocolFeeBasisPoints()).to.equal(600);
    });

    it("Should not allow fees above maximum (10%)", async function () {
      await expect(
        spavax.setFeeStructure(600, 500)
      ).to.be.revertedWith("Total fees too high (max 10%)");
    });

    it("Should allow setting fees to zero", async function () {
      await spavax.setFeeStructure(0, 0);
      
      expect(await spavax.daoFeeBasisPoints()).to.equal(0);
      expect(await spavax.devFeeBasisPoints()).to.equal(0);
    });

    it("Should allow governance to update minStakeAmount", async function () {
      await spavax.setMinStakeAmount(ethers.parseEther("0.5"));
      expect(await spavax.minStakeAmount()).to.equal(ethers.parseEther("0.5"));
    });

    it("Should allow governance to update unlock period", async function () {
      await spavax.setUnlockPeriod(7 * 24 * 60 * 60); // 7 days
      expect(await spavax.unlockPeriod()).to.equal(7 * 24 * 60 * 60);
    });

    it("Should allow governance to pause and unpause", async function () {
      await spavax.pause();
      expect(await spavax.paused()).to.be.true;
      
      await spavax.unpause();
      expect(await spavax.paused()).to.be.false;
    });
  });

  describe("Governance Transfer", function () {
    it("Should allow 2-step governance transfer", async function () {
      await spavax.transferGovernance(user1.address);
      expect(await spavax.pendingGovernance()).to.equal(user1.address);
      
      await spavax.connect(user1).acceptGovernance();
      expect(await spavax.governance()).to.equal(user1.address);
    });

    it("Should not allow non-pending to accept governance", async function () {
      await spavax.transferGovernance(user1.address);
      
      await expect(
        spavax.connect(user2).acceptGovernance()
      ).to.be.revertedWith("Not pending governance");
    });

    it("Should not allow transferring to zero address", async function () {
      await expect(
        spavax.transferGovernance(ethers.ZeroAddress)
      ).to.be.revertedWith("Invalid address");
    });
  });

  describe("Receive Function", function () {
    it("Should reject direct AVAX from non-governance", async function () {
      const contractAddress = await spavax.getAddress();
      
      await expect(
        user1.sendTransaction({
          to: contractAddress,
          value: ethers.parseEther("1")
        })
      ).to.be.revertedWith("Use stake() function");
    });

    it("Should accept direct AVAX from governance", async function () {
      const contractAddress = await spavax.getAddress();
      
      await expect(
        owner.sendTransaction({
          to: contractAddress,
          value: ethers.parseEther("1")
        })
      ).to.emit(spavax, "Deposited");
    });
  });

  describe("Exchange Rate", function () {
    it("Should return 1:1 ratio initially", async function () {
      const rate = await spavax.getExchangeRate();
      expect(rate).to.equal(ethers.parseEther("1"));
    });

    it("Should calculate correct exchange rate after rewards", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("100") });
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      const rate = await spavax.getExchangeRate();
      // 109.2 AVAX / 100 spAVAX = 1.092
      expect(rate).to.equal(ethers.parseEther("1.092"));
    });

    it("Should maintain exchange rate through stake/unstake cycle", async function () {
      // User1 stakes
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      
      // Add rewards
      await spavax.addRewards({ value: ethers.parseEther("1") });
      const rateAfterRewards = await spavax.getExchangeRate();
      
      // User2 stakes
      await spavax.connect(user2).stake(0, { value: ethers.parseEther("10") });
      
      // Rate should still be close (accounting for new stake)
      const rateAfterStake = await spavax.getExchangeRate();
      expect(rateAfterStake).to.be.closeTo(rateAfterRewards, ethers.parseEther("0.01"));
    });
  });

  describe("Preview Functions", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("100") });
      await spavax.addRewards({ value: ethers.parseEther("10") });
    });

    it("Should preview stake amount correctly", async function () {
      const avaxAmount = ethers.parseEther("10");
      const preview = await spavax.previewStake(avaxAmount);
      
      // Should get less spAVAX due to increased value
      expect(preview).to.be.lt(avaxAmount);
    });

    it("Should preview unlock amount correctly", async function () {
      const spAvaxAmount = ethers.parseEther("10");
      const preview = await spavax.previewUnlock(spAvaxAmount);
      
      // Should get more AVAX due to increased value
      expect(preview).to.be.gt(spAvaxAmount);
    });

    it("Should return correct preview for first stake", async function () {
      // Deploy new contract
      const SpAVAX = await ethers.getContractFactory("spAVAX");
      const newSpavax = await upgrades.deployProxy(SpAVAX, [], {
        initializer: "initialize",
        kind: "uups"
      });
      await newSpavax.waitForDeployment();
      
      const preview = await newSpavax.previewStake(ethers.parseEther("1"));
      expect(preview).to.equal(ethers.parseEther("1")); // 1:1 for first
    });
  });

  describe("Edge Cases", function () {
    it("Should handle contract with zero balance", async function () {
      const stats = await spavax.getStats();
      expect(stats[3]).to.equal(0); // liquidBalance should be 0
    });

    it("Should handle getStats correctly", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      
      const stats = await spavax.getStats();
      expect(stats[0]).to.equal(ethers.parseEther("10")); // totalStaked
      expect(stats[1]).to.equal(ethers.parseEther("10")); // totalShares
      expect(stats[2]).to.equal(ethers.parseEther("1")); // exchangeRate
    });

    it("Should handle empty unlock requests array", async function () {
      const count = await spavax.getUnlockRequestCount(user1.address);
      expect(count).to.equal(0);
    });
  });
});