const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("spBEAM_V1", function () {
  let spbeam;
  let owner;
  let user1;
  let user2;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    const SpBEAM = await ethers.getContractFactory("spBEAM_V1");
    spbeam = await upgrades.deployProxy(SpBEAM, [], {
      initializer: "initialize",
      kind: "uups"
    });
    await spbeam.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set correct governance", async function () {
      expect(await spbeam.governance()).to.equal(owner.address);
    });

    it("Should have correct name and symbol", async function () {
      expect(await spbeam.name()).to.equal("Sparrow Staked BEAM");
      expect(await spbeam.symbol()).to.equal("spBEAM");
    });

    it("Should initialize with zero values", async function () {
      expect(await spbeam.totalSupply()).to.equal(0);
      expect(await spbeam.totalPooledBEAM()).to.equal(0);
      expect(await spbeam.totalLockedInUnlocks()).to.equal(0);
    });

    it("Should have correct fee structure", async function () {
      expect(await spbeam.daoFeeBasisPoints()).to.equal(500);
      expect(await spbeam.devFeeBasisPoints()).to.equal(300);
      expect(await spbeam.protocolFeeBasisPoints()).to.equal(800);
    });
  });

  describe("Staking", function () {
    it("Should reject stake below minimum", async function () {
      await expect(
        spbeam.connect(user1).stake(0, { value: ethers.parseEther("0.05") })
      ).to.be.revertedWith("Below minimum stake");
    });

    it("Should allow stake and mint spBEAM", async function () {
      const stakeAmount = ethers.parseEther("1");
      
      await expect(spbeam.connect(user1).stake(0, { value: stakeAmount }))
        .to.emit(spbeam, "Staked")
        .withArgs(user1.address, stakeAmount, stakeAmount);

      expect(await spbeam.balanceOf(user1.address)).to.equal(stakeAmount);
      expect(await spbeam.totalPooledBEAM()).to.equal(stakeAmount);
    });

    it("Should enforce slippage protection", async function () {
      await spbeam.connect(user1).stake(0, { value: ethers.parseEther("1") });
      
      await expect(
        spbeam.connect(user2).stake(ethers.parseEther("100"), { value: ethers.parseEther("1") })
      ).to.be.revertedWith("Slippage too high");
    });

    it("Should calculate correct shares after rewards", async function () {
      await spbeam.connect(user1).stake(0, { value: ethers.parseEther("10") });
      await spbeam.addRewards({ value: ethers.parseEther("1") });
      
      const stakeAmount = ethers.parseEther("10");
      const expectedShares = await spbeam.previewStake(stakeAmount);
      
      await spbeam.connect(user2).stake(0, { value: stakeAmount });
      
      expect(await spbeam.balanceOf(user2.address)).to.equal(expectedShares);
    });

    it("Should not allow staking when paused", async function () {
      await spbeam.pause();
      
      await expect(
        spbeam.connect(user1).stake(0, { value: ethers.parseEther("1") })
      ).to.be.revertedWithCustomError(spbeam, "EnforcedPause");
    });
  });

  describe("Unlock Requests", function () {
    beforeEach(async function () {
      await spbeam.connect(user1).stake(0, { value: ethers.parseEther("10") });
    });

    it("Should create unlock request", async function () {
      const unlockAmount = ethers.parseEther("5");
      
      await expect(spbeam.connect(user1).requestUnlock(unlockAmount, 0))
        .to.emit(spbeam, "UnlockRequested");

      expect(await spbeam.getUnlockRequestCount(user1.address)).to.equal(1);
    });

    it("Should lock spBEAM in contract", async function () {
      const unlockAmount = ethers.parseEther("5");
      const initialBalance = await spbeam.balanceOf(user1.address);
      
      await spbeam.connect(user1).requestUnlock(unlockAmount, 0);
      
      expect(await spbeam.balanceOf(user1.address)).to.equal(initialBalance - unlockAmount);
      expect(await spbeam.balanceOf(await spbeam.getAddress())).to.equal(unlockAmount);
    });

    it("Should update totalLockedInUnlocks", async function () {
      const unlockAmount = ethers.parseEther("5");
      
      expect(await spbeam.totalLockedInUnlocks()).to.equal(0);
      await spbeam.connect(user1).requestUnlock(unlockAmount, 0);
      expect(await spbeam.totalLockedInUnlocks()).to.equal(unlockAmount);
    });

    it("Should enforce slippage protection", async function () {
      await expect(
        spbeam.connect(user1).requestUnlock(ethers.parseEther("5"), ethers.parseEther("100"))
      ).to.be.revertedWith("Slippage too high");
    });

    it("Should lock exchange rate at request time", async function () {
      const unlockAmount = ethers.parseEther("5");
      
      await spbeam.connect(user1).requestUnlock(unlockAmount, 0);
      const request = await spbeam.getUnlockRequest(user1.address, 0);
      const lockedBeam = request[1];
      
      await spbeam.addRewards({ value: ethers.parseEther("10") });
      
      const requestAfter = await spbeam.getUnlockRequest(user1.address, 0);
      expect(requestAfter[1]).to.equal(lockedBeam);
    });

    it("Should not allow more than 100 requests", async function () {
      await spbeam.connect(user1).stake(0, { value: ethers.parseEther("100") });
      
      for (let i = 0; i < 100; i++) {
        await spbeam.connect(user1).requestUnlock(ethers.parseEther("0.1"), 0);
      }
      
      await expect(
        spbeam.connect(user1).requestUnlock(ethers.parseEther("0.1"), 0)
      ).to.be.revertedWith("Too many pending requests");
    });
  });

  describe("Claim Unlock", function () {
    beforeEach(async function () {
      await spbeam.connect(user1).stake(0, { value: ethers.parseEther("10") });
      await spbeam.connect(user1).requestUnlock(ethers.parseEther("5"), 0);
    });

    it("Should not allow claim before unlock period", async function () {
      await expect(
        spbeam.connect(user1).claimUnlock(0)
      ).to.be.revertedWith("Unlock period not finished");
    });

    it("Should allow claim after unlock period", async function () {
      await time.increase(61);
      
      const initialBalance = await ethers.provider.getBalance(user1.address);
      await spbeam.connect(user1).claimUnlock(0);
      const finalBalance = await ethers.provider.getBalance(user1.address);
      
      expect(finalBalance).to.be.gt(initialBalance);
    });

    it("Should decrease totalLockedInUnlocks", async function () {
      await time.increase(61);
      
      expect(await spbeam.totalLockedInUnlocks()).to.equal(ethers.parseEther("5"));
      await spbeam.connect(user1).claimUnlock(0);
      expect(await spbeam.totalLockedInUnlocks()).to.equal(0);
    });

    it("Should not allow claim after expiry", async function () {
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      await expect(
        spbeam.connect(user1).claimUnlock(0)
      ).to.be.revertedWith("Claim window expired");
    });

    it("Should check liquidity accounts for fees", async function () {
      await spbeam.addRewards({ value: ethers.parseEther("2") });
      
      const daoFees = await spbeam.accumulatedDaoFees();
      const devFees = await spbeam.accumulatedDevFees();
      expect(daoFees).to.be.gt(0);
      expect(devFees).to.be.gt(0);
      
      await time.increase(61);
      
      await spbeam.connect(user1).claimUnlock(0);
      
      expect(await spbeam.accumulatedDaoFees()).to.equal(daoFees);
      expect(await spbeam.accumulatedDevFees()).to.equal(devFees);
    });

    it("Should use locked exchange rate", async function () {
      const request = await spbeam.getUnlockRequest(user1.address, 0);
      const lockedBeam = request[1];
      
      await spbeam.addRewards({ value: ethers.parseEther("10") });
      await time.increase(61);
      
      const balanceBefore = await ethers.provider.getBalance(user1.address);
      const tx = await spbeam.connect(user1).claimUnlock(0);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      
      const balanceAfter = await ethers.provider.getBalance(user1.address);
      const received = balanceAfter - balanceBefore + gasUsed;
      
      expect(received).to.be.closeTo(lockedBeam, ethers.parseEther("0.001"));
    });
  });

  describe("Cancel Unlock", function () {
    beforeEach(async function () {
      await spbeam.connect(user1).stake(0, { value: ethers.parseEther("10") });
      await spbeam.connect(user1).requestUnlock(ethers.parseEther("5"), 0);
    });

    it("Should allow canceling unlock", async function () {
      const balanceBefore = await spbeam.balanceOf(user1.address);
      
      await spbeam.connect(user1).cancelUnlock(0);
      
      expect(await spbeam.balanceOf(user1.address)).to.be.gt(balanceBefore);
      expect(await spbeam.getUnlockRequestCount(user1.address)).to.equal(0);
    });

    it("Should decrease totalLockedInUnlocks", async function () {
      expect(await spbeam.totalLockedInUnlocks()).to.equal(ethers.parseEther("5"));
      
      await spbeam.connect(user1).cancelUnlock(0);
      
      expect(await spbeam.totalLockedInUnlocks()).to.equal(0);
    });

    it("Should not allow canceling after expiry", async function () {
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      await expect(
        spbeam.connect(user1).cancelUnlock(0)
      ).to.be.revertedWith("Request expired, use claimExpired");
    });
  });

  describe("Claim Expired", function () {
    beforeEach(async function () {
      await spbeam.connect(user1).stake(0, { value: ethers.parseEther("10") });
      await spbeam.connect(user1).requestUnlock(ethers.parseEther("5"), 0);
    });

    it("Should allow claiming expired request", async function () {
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      const balanceBefore = await spbeam.balanceOf(user1.address);
      await spbeam.connect(user1).claimExpired(0);
      
      expect(await spbeam.balanceOf(user1.address)).to.be.gt(balanceBefore);
    });

    it("Should decrease totalLockedInUnlocks", async function () {
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      expect(await spbeam.totalLockedInUnlocks()).to.equal(ethers.parseEther("5"));
      await spbeam.connect(user1).claimExpired(0);
      expect(await spbeam.totalLockedInUnlocks()).to.equal(0);
    });

    it("Should not allow claiming non-expired", async function () {
      await expect(
        spbeam.connect(user1).claimExpired(0)
      ).to.be.revertedWith("Not expired yet");
    });
  });

  describe("Rewards", function () {
    beforeEach(async function () {
      await spbeam.connect(user1).stake(0, { value: ethers.parseEther("100") });
    });

    it("Should distribute rewards correctly", async function () {
      await expect(spbeam.addRewards({ value: ethers.parseEther("10") }))
        .to.emit(spbeam, "RewardsAdded");

      expect(await spbeam.accumulatedDaoFees()).to.equal(ethers.parseEther("0.5"));
      expect(await spbeam.accumulatedDevFees()).to.equal(ethers.parseEther("0.3"));
      expect(await spbeam.totalPooledBEAM()).to.equal(ethers.parseEther("109.2"));
    });

    it("Should increase exchange rate", async function () {
      const rateBefore = await spbeam.getExchangeRate();
      
      await spbeam.addRewards({ value: ethers.parseEther("10") });
      
      expect(await spbeam.getExchangeRate()).to.be.gt(rateBefore);
    });

    it("Should not allow zero rewards", async function () {
      await expect(
        spbeam.addRewards({ value: 0 })
      ).to.be.revertedWith("Reward must be > 0");
    });
  });

  describe("Fee Collection", function () {
    beforeEach(async function () {
      await spbeam.connect(user1).stake(0, { value: ethers.parseEther("100") });
      await spbeam.addRewards({ value: ethers.parseEther("10") });
    });

    it("Should collect DAO fees", async function () {
      const balanceBefore = await ethers.provider.getBalance(owner.address);
      
      await spbeam.collectDaoFees();
      
      expect(await ethers.provider.getBalance(owner.address)).to.be.gt(balanceBefore);
      expect(await spbeam.accumulatedDaoFees()).to.equal(0);
    });

    it("Should collect dev fees", async function () {
      await spbeam.collectDevFees();
      expect(await spbeam.accumulatedDevFees()).to.equal(0);
    });

    it("Should collect all fees", async function () {
      await expect(spbeam.collectAllFees())
        .to.emit(spbeam, "AllFeesCollected");
      
      expect(await spbeam.accumulatedDaoFees()).to.equal(0);
      expect(await spbeam.accumulatedDevFees()).to.equal(0);
    });

    it("Should not allow non-governance to collect", async function () {
      await expect(
        spbeam.connect(user1).collectDaoFees()
      ).to.be.revertedWith("Not governance");
    });
  });

  describe("Withdraw", function () {
    beforeEach(async function () {
      await spbeam.connect(user1).stake(0, { value: ethers.parseEther("100") });
    });

    it("Should allow withdrawal", async function () {
      const balanceBefore = await ethers.provider.getBalance(owner.address);
      
      await spbeam.withdraw(ethers.parseEther("50"));
      
      expect(await ethers.provider.getBalance(owner.address)).to.be.gt(balanceBefore);
    });

    it("Should prevent withdrawing committed fees", async function () {
      await spbeam.addRewards({ value: ethers.parseEther("10") });
      
      const balance = await ethers.provider.getBalance(await spbeam.getAddress());
      const fees = await spbeam.accumulatedDaoFees() + await spbeam.accumulatedDevFees();
      
      await expect(
        spbeam.withdraw(balance - fees + ethers.parseEther("0.1"))
      ).to.be.revertedWith("Insufficient liquidity after commitments");
    });

    it("Should prevent withdrawing when unlocks pending", async function () {
      await spbeam.connect(user1).requestUnlock(ethers.parseEther("50"), 0);
      
      await expect(
        spbeam.withdraw(ethers.parseEther("60"))
      ).to.be.revertedWith("Insufficient liquidity after commitments");
    });

    it("Should allow withdrawing only available liquidity", async function () {
      await spbeam.addRewards({ value: ethers.parseEther("10") });
      await spbeam.connect(user1).requestUnlock(ethers.parseEther("30"), 0);
      
      const balance = await ethers.provider.getBalance(await spbeam.getAddress());
      const fees = await spbeam.accumulatedDaoFees() + await spbeam.accumulatedDevFees();
      const locked = await spbeam.totalLockedInUnlocks();
      const available = balance - fees - locked;
      
      await spbeam.withdraw(available);
      
      await expect(
        spbeam.withdraw(1)
      ).to.be.revertedWith("Insufficient liquidity after commitments");
    });
  });

  describe("Admin Functions", function () {
    it("Should allow deposit", async function () {
      await expect(spbeam.deposit({ value: ethers.parseEther("5") }))
        .to.emit(spbeam, "Deposited");
    });

    it("Should update fee structure", async function () {
      await spbeam.setFeeStructure(400, 200);
      
      expect(await spbeam.daoFeeBasisPoints()).to.equal(400);
      expect(await spbeam.devFeeBasisPoints()).to.equal(200);
      expect(await spbeam.protocolFeeBasisPoints()).to.equal(600);
    });

    it("Should not allow fees above 10%", async function () {
      await expect(
        spbeam.setFeeStructure(600, 500)
      ).to.be.revertedWith("Total fees too high (max 10%)");
    });

    it("Should not allow individual fees above 100%", async function () {
      await expect(
        spbeam.setFeeStructure(11000, 0)
      ).to.be.revertedWith("DAO fee too high");
    });

    it("Should update minStakeAmount", async function () {
      await spbeam.setMinStakeAmount(ethers.parseEther("0.5"));
      expect(await spbeam.minStakeAmount()).to.equal(ethers.parseEther("0.5"));
    });

    it("Should update unlock period", async function () {
      await spbeam.setUnlockPeriod(7 * 24 * 60 * 60);
      expect(await spbeam.unlockPeriod()).to.equal(7 * 24 * 60 * 60);
    });

    it("Should pause and unpause", async function () {
      await spbeam.pause();
      expect(await spbeam.paused()).to.be.true;
      
      await spbeam.unpause();
      expect(await spbeam.paused()).to.be.false;
    });
  });

  describe("Governance", function () {
    it("Should transfer governance", async function () {
      await spbeam.transferGovernance(user1.address);
      expect(await spbeam.pendingGovernance()).to.equal(user1.address);
      
      await spbeam.connect(user1).acceptGovernance();
      expect(await spbeam.governance()).to.equal(user1.address);
    });

    it("Should not allow non-pending to accept", async function () {
      await spbeam.transferGovernance(user1.address);
      
      await expect(
        spbeam.connect(user2).acceptGovernance()
      ).to.be.revertedWith("Not pending governance");
    });

    it("Should not allow zero address", async function () {
      await expect(
        spbeam.transferGovernance(ethers.ZeroAddress)
      ).to.be.revertedWith("Invalid address");
    });
  });

  describe("Receive Function", function () {
    it("Should reject from non-governance", async function () {
      const contractAddress = await spbeam.getAddress();
      
      await expect(
        user1.sendTransaction({
          to: contractAddress,
          value: ethers.parseEther("1")
        })
      ).to.be.revertedWith("Use stake() function");
    });

    it("Should accept from governance", async function () {
      const contractAddress = await spbeam.getAddress();
      
      await expect(
        owner.sendTransaction({
          to: contractAddress,
          value: ethers.parseEther("1")
        })
      ).to.emit(spbeam, "Deposited");
    });
  });

  describe("View Functions", function () {
    it("Should return 1:1 exchange rate initially", async function () {
      expect(await spbeam.getExchangeRate()).to.equal(ethers.parseEther("1"));
    });

    it("Should calculate correct exchange rate", async function () {
      await spbeam.connect(user1).stake(0, { value: ethers.parseEther("100") });
      await spbeam.addRewards({ value: ethers.parseEther("10") });
      
      expect(await spbeam.getExchangeRate()).to.equal(ethers.parseEther("1.092"));
    });

    it("Should preview stake correctly", async function () {
      await spbeam.connect(user1).stake(0, { value: ethers.parseEther("100") });
      await spbeam.addRewards({ value: ethers.parseEther("10") });
      
      const preview = await spbeam.previewStake(ethers.parseEther("10"));
      expect(preview).to.be.lt(ethers.parseEther("10"));
    });

    it("Should preview unlock correctly", async function () {
      await spbeam.connect(user1).stake(0, { value: ethers.parseEther("100") });
      await spbeam.addRewards({ value: ethers.parseEther("10") });
      
      const preview = await spbeam.previewUnlock(ethers.parseEther("10"));
      expect(preview).to.be.gt(ethers.parseEther("10"));
    });

    it("Should return correct stats", async function () {
      await spbeam.connect(user1).stake(0, { value: ethers.parseEther("10") });
      
      const stats = await spbeam.getStats();
      expect(stats[0]).to.equal(ethers.parseEther("10"));
      expect(stats[1]).to.equal(ethers.parseEther("10"));
      expect(stats[2]).to.equal(ethers.parseEther("1"));
    });
  });
});