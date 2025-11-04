const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("spAVAX_V1", function () {
  let spavax;
  let owner;
  let user1;
  let user2;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    const SpAVAX = await ethers.getContractFactory("spAVAX_V1");
    spavax = await upgrades.deployProxy(SpAVAX, [], {
      initializer: "initialize",
      kind: "uups"
    });
    await spavax.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set correct governance", async function () {
      expect(await spavax.governance()).to.equal(owner.address);
    });

    it("Should have correct name and symbol", async function () {
      expect(await spavax.name()).to.equal("Sparrow Staked AVAX");
      expect(await spavax.symbol()).to.equal("spAVAX");
    });

    it("Should initialize with zero values", async function () {
      expect(await spavax.totalSupply()).to.equal(0);
      expect(await spavax.totalPooledAVAX()).to.equal(0);
      expect(await spavax.totalLockedInUnlocks()).to.equal(0);
    });

    it("Should have correct fee structure", async function () {
      expect(await spavax.daoFeeBasisPoints()).to.equal(500);
      expect(await spavax.devFeeBasisPoints()).to.equal(300);
      expect(await spavax.protocolFeeBasisPoints()).to.equal(800);
    });
  });

  describe("Staking", function () {
    it("Should reject stake below minimum", async function () {
      await expect(
        spavax.connect(user1).stake(0, { value: ethers.parseEther("0.05") })
      ).to.be.revertedWith("Below minimum stake");
    });

    it("Should allow stake and mint spAVAX", async function () {
      const stakeAmount = ethers.parseEther("1");
      
      await expect(spavax.connect(user1).stake(0, { value: stakeAmount }))
        .to.emit(spavax, "Staked")
        .withArgs(user1.address, stakeAmount, stakeAmount);

      expect(await spavax.balanceOf(user1.address)).to.equal(stakeAmount);
      expect(await spavax.totalPooledAVAX()).to.equal(stakeAmount);
    });

    it("Should enforce slippage protection", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("1") });
      
      await expect(
        spavax.connect(user2).stake(ethers.parseEther("100"), { value: ethers.parseEther("1") })
      ).to.be.revertedWith("Slippage too high");
    });

    it("Should calculate correct shares after rewards", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      await spavax.addRewards({ value: ethers.parseEther("1") });
      
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
  });

  describe("Unlock Requests", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
    });

    it("Should create unlock request", async function () {
      const unlockAmount = ethers.parseEther("5");
      
      await expect(spavax.connect(user1).requestUnlock(unlockAmount, 0))
        .to.emit(spavax, "UnlockRequested");

      expect(await spavax.getUnlockRequestCount(user1.address)).to.equal(1);
    });

    it("Should lock spAVAX in contract", async function () {
      const unlockAmount = ethers.parseEther("5");
      const initialBalance = await spavax.balanceOf(user1.address);
      
      await spavax.connect(user1).requestUnlock(unlockAmount, 0);
      
      expect(await spavax.balanceOf(user1.address)).to.equal(initialBalance - unlockAmount);
      expect(await spavax.balanceOf(await spavax.getAddress())).to.equal(unlockAmount);
    });

    it("Should update totalLockedInUnlocks", async function () {
      const unlockAmount = ethers.parseEther("5");
      
      expect(await spavax.totalLockedInUnlocks()).to.equal(0);
      await spavax.connect(user1).requestUnlock(unlockAmount, 0);
      expect(await spavax.totalLockedInUnlocks()).to.equal(unlockAmount);
    });

    it("Should enforce slippage protection", async function () {
      await expect(
        spavax.connect(user1).requestUnlock(ethers.parseEther("5"), ethers.parseEther("100"))
      ).to.be.revertedWith("Slippage too high");
    });

    it("Should lock exchange rate at request time", async function () {
      const unlockAmount = ethers.parseEther("5");
      
      await spavax.connect(user1).requestUnlock(unlockAmount, 0);
      const request = await spavax.getUnlockRequest(user1.address, 0);
      const lockedAvax = request[1];
      
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      const requestAfter = await spavax.getUnlockRequest(user1.address, 0);
      expect(requestAfter[1]).to.equal(lockedAvax);
    });

    it("Should not allow more than 100 requests", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("100") });
      
      for (let i = 0; i < 100; i++) {
        await spavax.connect(user1).requestUnlock(ethers.parseEther("0.1"), 0);
      }
      
      await expect(
        spavax.connect(user1).requestUnlock(ethers.parseEther("0.1"), 0)
      ).to.be.revertedWith("Too many pending requests");
    });
  });

  describe("Claim Unlock", function () {
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
      await time.increase(61);
      
      const initialBalance = await ethers.provider.getBalance(user1.address);
      await spavax.connect(user1).claimUnlock(0);
      const finalBalance = await ethers.provider.getBalance(user1.address);
      
      expect(finalBalance).to.be.gt(initialBalance);
    });

    it("Should decrease totalLockedInUnlocks", async function () {
      await time.increase(61);
      
      expect(await spavax.totalLockedInUnlocks()).to.equal(ethers.parseEther("5"));
      await spavax.connect(user1).claimUnlock(0);
      expect(await spavax.totalLockedInUnlocks()).to.equal(0);
    });

    it("Should not allow claim after expiry", async function () {
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      await expect(
        spavax.connect(user1).claimUnlock(0)
      ).to.be.revertedWith("Claim window expired");
    });

    it("Should check liquidity accounts for fees", async function () {
      // This test verifies that the liquidity check includes fees
      // The check is: balance >= request.avaxAmount + accumulatedDaoFees + accumulatedDevFees
      
      // Add rewards to accumulate fees
      await spavax.addRewards({ value: ethers.parseEther("2") });
      
      // Verify fees are accumulated
      const daoFees = await spavax.accumulatedDaoFees();
      const devFees = await spavax.accumulatedDevFees();
      expect(daoFees).to.be.gt(0);
      expect(devFees).to.be.gt(0);
      
      // Fast forward to allow claim
      await time.increase(61);
      
      // Claim should succeed (enough liquidity)
      await spavax.connect(user1).claimUnlock(0);
      
      // Verify the check protected the fees - they're still there
      expect(await spavax.accumulatedDaoFees()).to.equal(daoFees);
      expect(await spavax.accumulatedDevFees()).to.equal(devFees);
    });

    it("Should use locked exchange rate", async function () {
      const request = await spavax.getUnlockRequest(user1.address, 0);
      const lockedAvax = request[1];
      
      await spavax.addRewards({ value: ethers.parseEther("10") });
      await time.increase(61);
      
      const balanceBefore = await ethers.provider.getBalance(user1.address);
      const tx = await spavax.connect(user1).claimUnlock(0);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      
      const balanceAfter = await ethers.provider.getBalance(user1.address);
      const received = balanceAfter - balanceBefore + gasUsed;
      
      expect(received).to.be.closeTo(lockedAvax, ethers.parseEther("0.001"));
    });
  });

  describe("Cancel Unlock", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      await spavax.connect(user1).requestUnlock(ethers.parseEther("5"), 0);
    });

    it("Should allow canceling unlock", async function () {
      const balanceBefore = await spavax.balanceOf(user1.address);
      
      await spavax.connect(user1).cancelUnlock(0);
      
      expect(await spavax.balanceOf(user1.address)).to.be.gt(balanceBefore);
      expect(await spavax.getUnlockRequestCount(user1.address)).to.equal(0);
    });

    it("Should decrease totalLockedInUnlocks", async function () {
      expect(await spavax.totalLockedInUnlocks()).to.equal(ethers.parseEther("5"));
      
      await spavax.connect(user1).cancelUnlock(0);
      
      expect(await spavax.totalLockedInUnlocks()).to.equal(0);
    });

    it("Should not allow canceling after expiry", async function () {
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      await expect(
        spavax.connect(user1).cancelUnlock(0)
      ).to.be.revertedWith("Request expired, use claimExpired");
    });
  });

  describe("Claim Expired", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      await spavax.connect(user1).requestUnlock(ethers.parseEther("5"), 0);
    });

    it("Should allow claiming expired request", async function () {
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      const balanceBefore = await spavax.balanceOf(user1.address);
      await spavax.connect(user1).claimExpired(0);
      
      expect(await spavax.balanceOf(user1.address)).to.be.gt(balanceBefore);
    });

    it("Should decrease totalLockedInUnlocks", async function () {
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      expect(await spavax.totalLockedInUnlocks()).to.equal(ethers.parseEther("5"));
      await spavax.connect(user1).claimExpired(0);
      expect(await spavax.totalLockedInUnlocks()).to.equal(0);
    });

    it("Should not allow claiming non-expired", async function () {
      await expect(
        spavax.connect(user1).claimExpired(0)
      ).to.be.revertedWith("Not expired yet");
    });
  });

  describe("Rewards", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("100") });
    });

    it("Should distribute rewards correctly", async function () {
      await expect(spavax.addRewards({ value: ethers.parseEther("10") }))
        .to.emit(spavax, "RewardsAdded");

      expect(await spavax.accumulatedDaoFees()).to.equal(ethers.parseEther("0.5"));
      expect(await spavax.accumulatedDevFees()).to.equal(ethers.parseEther("0.3"));
      expect(await spavax.totalPooledAVAX()).to.equal(ethers.parseEther("109.2"));
    });

    it("Should increase exchange rate", async function () {
      const rateBefore = await spavax.getExchangeRate();
      
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      expect(await spavax.getExchangeRate()).to.be.gt(rateBefore);
    });

    it("Should not allow zero rewards", async function () {
      await expect(
        spavax.addRewards({ value: 0 })
      ).to.be.revertedWith("Reward must be > 0");
    });
  });

  describe("Fee Collection", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("100") });
      await spavax.addRewards({ value: ethers.parseEther("10") });
    });

    it("Should collect DAO fees", async function () {
      const balanceBefore = await ethers.provider.getBalance(owner.address);
      
      await spavax.collectDaoFees();
      
      expect(await ethers.provider.getBalance(owner.address)).to.be.gt(balanceBefore);
      expect(await spavax.accumulatedDaoFees()).to.equal(0);
    });

    it("Should collect dev fees", async function () {
      await spavax.collectDevFees();
      expect(await spavax.accumulatedDevFees()).to.equal(0);
    });

    it("Should collect all fees", async function () {
      await expect(spavax.collectAllFees())
        .to.emit(spavax, "AllFeesCollected");
      
      expect(await spavax.accumulatedDaoFees()).to.equal(0);
      expect(await spavax.accumulatedDevFees()).to.equal(0);
    });

    it("Should not allow non-governance to collect", async function () {
      await expect(
        spavax.connect(user1).collectDaoFees()
      ).to.be.revertedWith("Not governance");
    });
  });

  describe("Withdraw", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("100") });
    });

    it("Should allow withdrawal", async function () {
      const balanceBefore = await ethers.provider.getBalance(owner.address);
      
      await spavax.withdraw(ethers.parseEther("50"));
      
      expect(await ethers.provider.getBalance(owner.address)).to.be.gt(balanceBefore);
    });

    it("Should prevent withdrawing committed fees", async function () {
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      const balance = await ethers.provider.getBalance(await spavax.getAddress());
      const fees = await spavax.accumulatedDaoFees() + await spavax.accumulatedDevFees();
      
      await expect(
        spavax.withdraw(balance - fees + ethers.parseEther("0.1"))
      ).to.be.revertedWith("Insufficient liquidity after commitments");
    });

    it("Should prevent withdrawing when unlocks pending", async function () {
      await spavax.connect(user1).requestUnlock(ethers.parseEther("50"), 0);
      
      await expect(
        spavax.withdraw(ethers.parseEther("60"))
      ).to.be.revertedWith("Insufficient liquidity after commitments");
    });

    it("Should allow withdrawing only available liquidity", async function () {
      await spavax.addRewards({ value: ethers.parseEther("10") });
      await spavax.connect(user1).requestUnlock(ethers.parseEther("30"), 0);
      
      const balance = await ethers.provider.getBalance(await spavax.getAddress());
      const fees = await spavax.accumulatedDaoFees() + await spavax.accumulatedDevFees();
      const locked = await spavax.totalLockedInUnlocks();
      const available = balance - fees - locked;
      
      await spavax.withdraw(available);
      
      await expect(
        spavax.withdraw(1)
      ).to.be.revertedWith("Insufficient liquidity after commitments");
    });
  });

  describe("Admin Functions", function () {
    it("Should allow deposit", async function () {
      await expect(spavax.deposit({ value: ethers.parseEther("5") }))
        .to.emit(spavax, "Deposited");
    });

    it("Should update fee structure", async function () {
      await spavax.setFeeStructure(400, 200);
      
      expect(await spavax.daoFeeBasisPoints()).to.equal(400);
      expect(await spavax.devFeeBasisPoints()).to.equal(200);
      expect(await spavax.protocolFeeBasisPoints()).to.equal(600);
    });

    it("Should not allow fees above 10%", async function () {
      await expect(
        spavax.setFeeStructure(600, 500)
      ).to.be.revertedWith("Total fees too high (max 10%)");
    });

    it("Should not allow individual fees above 100%", async function () {
      await expect(
        spavax.setFeeStructure(11000, 0)
      ).to.be.revertedWith("DAO fee too high");
    });

    it("Should update minStakeAmount", async function () {
      await spavax.setMinStakeAmount(ethers.parseEther("0.5"));
      expect(await spavax.minStakeAmount()).to.equal(ethers.parseEther("0.5"));
    });

    it("Should update unlock period", async function () {
      await spavax.setUnlockPeriod(7 * 24 * 60 * 60);
      expect(await spavax.unlockPeriod()).to.equal(7 * 24 * 60 * 60);
    });

    it("Should pause and unpause", async function () {
      await spavax.pause();
      expect(await spavax.paused()).to.be.true;
      
      await spavax.unpause();
      expect(await spavax.paused()).to.be.false;
    });
  });

  describe("Governance", function () {
    it("Should transfer governance", async function () {
      await spavax.transferGovernance(user1.address);
      expect(await spavax.pendingGovernance()).to.equal(user1.address);
      
      await spavax.connect(user1).acceptGovernance();
      expect(await spavax.governance()).to.equal(user1.address);
    });

    it("Should not allow non-pending to accept", async function () {
      await spavax.transferGovernance(user1.address);
      
      await expect(
        spavax.connect(user2).acceptGovernance()
      ).to.be.revertedWith("Not pending governance");
    });

    it("Should not allow zero address", async function () {
      await expect(
        spavax.transferGovernance(ethers.ZeroAddress)
      ).to.be.revertedWith("Invalid address");
    });
  });

  describe("Receive Function", function () {
    it("Should reject from non-governance", async function () {
      const contractAddress = await spavax.getAddress();
      
      await expect(
        user1.sendTransaction({
          to: contractAddress,
          value: ethers.parseEther("1")
        })
      ).to.be.revertedWith("Use stake() function");
    });

    it("Should accept from governance", async function () {
      const contractAddress = await spavax.getAddress();
      
      await expect(
        owner.sendTransaction({
          to: contractAddress,
          value: ethers.parseEther("1")
        })
      ).to.emit(spavax, "Deposited");
    });
  });

  describe("View Functions", function () {
    it("Should return 1:1 exchange rate initially", async function () {
      expect(await spavax.getExchangeRate()).to.equal(ethers.parseEther("1"));
    });

    it("Should calculate correct exchange rate", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("100") });
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      expect(await spavax.getExchangeRate()).to.equal(ethers.parseEther("1.092"));
    });

    it("Should preview stake correctly", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("100") });
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      const preview = await spavax.previewStake(ethers.parseEther("10"));
      expect(preview).to.be.lt(ethers.parseEther("10"));
    });

    it("Should preview unlock correctly", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("100") });
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      const preview = await spavax.previewUnlock(ethers.parseEther("10"));
      expect(preview).to.be.gt(ethers.parseEther("10"));
    });

    it("Should return correct stats", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      
      const stats = await spavax.getStats();
      expect(stats[0]).to.equal(ethers.parseEther("10"));
      expect(stats[1]).to.equal(ethers.parseEther("10"));
      expect(stats[2]).to.equal(ethers.parseEther("1"));
    });
  });
});