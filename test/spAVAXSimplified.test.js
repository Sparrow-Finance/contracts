const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("spAVAXSimplified", function () {
  let spavax;
  let owner;
  let user1;
  let user2;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();
    
    const SpAVAX = await ethers.getContractFactory("spAVAXSimplified");
    spavax = await SpAVAX.deploy();
    await spavax.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await spavax.owner()).to.equal(owner.address);
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
      expect(await spavax.validatorFeeBasisPoints()).to.equal(500); // 5%
      expect(await spavax.daoFeeBasisPoints()).to.equal(250); // 2.5%
      expect(await spavax.devFeeBasisPoints()).to.equal(250); // 2.5%
    });
  });

  describe("Staking", function () {
    it("Should allow users to stake AVAX", async function () {
      const stakeAmount = ethers.parseEther("10");
      
      await expect(spavax.connect(user1).stake({ value: stakeAmount }))
        .to.emit(spavax, "Staked")
        .withArgs(user1.address, stakeAmount, stakeAmount);

      expect(await spavax.balanceOf(user1.address)).to.equal(stakeAmount);
      expect(await spavax.totalPooledAVAX()).to.equal(stakeAmount);
    });

    it("Should reject stakes below minimum", async function () {
      const tooSmall = ethers.parseEther("0.05");
      
      await expect(
        spavax.connect(user1).stake({ value: tooSmall })
      ).to.be.revertedWith("Below minimum stake");
    });

    it("Should calculate correct share amount for subsequent stakes", async function () {
      // First stake: 1:1 ratio
      await spavax.connect(user1).stake({ value: ethers.parseEther("10") });
      
      // Add rewards to change ratio
      await spavax.addRewards(ethers.parseEther("1"));
      
      // Second stake should get fewer shares
      const stakeAmount = ethers.parseEther("10");
      const expectedShares = await spavax.previewStake(stakeAmount);
      
      await spavax.connect(user2).stake({ value: stakeAmount });
      
      expect(await spavax.balanceOf(user2.address)).to.equal(expectedShares);
    });

    it("Should not allow staking when paused", async function () {
      await spavax.pause();
      
      await expect(
        spavax.connect(user1).stake({ value: ethers.parseEther("1") })
      ).to.be.revertedWithCustomError(spavax, "EnforcedPause");
    });
  });

  describe("Unlock Requests", function () {
    beforeEach(async function () {
      // User stakes first
      await spavax.connect(user1).stake({ value: ethers.parseEther("10") });
    });

    it("Should allow users to request unlock", async function () {
      const unlockAmount = ethers.parseEther("5");
      
      await expect(spavax.connect(user1).requestUnlock(unlockAmount))
        .to.emit(spavax, "UnlockRequested");

      const count = await spavax.getUnlockRequestCount(user1.address);
      expect(count).to.equal(1);
    });

    it("Should lock spAVAX in contract during unlock", async function () {
      const unlockAmount = ethers.parseEther("5");
      const initialBalance = await spavax.balanceOf(user1.address);
      
      await spavax.connect(user1).requestUnlock(unlockAmount);
      
      expect(await spavax.balanceOf(user1.address)).to.equal(initialBalance - unlockAmount);
      expect(await spavax.balanceOf(await spavax.getAddress())).to.equal(unlockAmount);
    });

    it("Should not allow unlock of more than balance", async function () {
      await expect(
        spavax.connect(user1).requestUnlock(ethers.parseEther("20"))
      ).to.be.revertedWith("Insufficient balance");
    });
  });

  describe("Claiming Unlocks", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake({ value: ethers.parseEther("10") });
      await spavax.connect(user1).requestUnlock(ethers.parseEther("5"));
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
  });

  describe("Cancel Unlock", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake({ value: ethers.parseEther("10") });
      await spavax.connect(user1).requestUnlock(ethers.parseEther("5"));
    });

    it("Should allow canceling unlock request", async function () {
      const balanceBefore = await spavax.balanceOf(user1.address);
      
      await spavax.connect(user1).cancelUnlock(0);
      
      const balanceAfter = await spavax.balanceOf(user1.address);
      expect(balanceAfter).to.be.gt(balanceBefore);
      
      const count = await spavax.getUnlockRequestCount(user1.address);
      expect(count).to.equal(0);
    });
  });

  describe("Rewards Distribution", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake({ value: ethers.parseEther("100") });
    });

    it("Should distribute rewards correctly", async function () {
      const rewardAmount = ethers.parseEther("10");
      
      await expect(spavax.addRewards(rewardAmount))
        .to.emit(spavax, "RewardsAdded");

      // Check fee distribution
      expect(await spavax.accumulatedValidatorFees()).to.equal(ethers.parseEther("0.5")); // 5%
      expect(await spavax.accumulatedDaoFees()).to.equal(ethers.parseEther("0.25")); // 2.5%
      expect(await spavax.accumulatedDevFees()).to.equal(ethers.parseEther("0.25")); // 2.5%
      
      // User rewards (90%) should increase totalPooledAVAX
      expect(await spavax.totalPooledAVAX()).to.equal(ethers.parseEther("109")); // 100 + 9
    });

    it("Should increase spAVAX value after rewards", async function () {
      const rateBefore = await spavax.getExchangeRate();
      
      await spavax.addRewards(ethers.parseEther("10"));
      
      const rateAfter = await spavax.getExchangeRate();
      expect(rateAfter).to.be.gt(rateBefore);
    });
  });

  describe("Fee Collection", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake({ value: ethers.parseEther("100") });
      await spavax.addRewards(ethers.parseEther("10"));
    });

    it("Should allow owner to collect validator fees", async function () {
      const balanceBefore = await ethers.provider.getBalance(owner.address);
      
      await spavax.collectValidatorFees();
      
      const balanceAfter = await ethers.provider.getBalance(owner.address);
      expect(balanceAfter).to.be.gt(balanceBefore);
      expect(await spavax.accumulatedValidatorFees()).to.equal(0);
    });

    it("Should allow owner to collect DAO fees", async function () {
      await spavax.collectDaoFees();
      expect(await spavax.accumulatedDaoFees()).to.equal(0);
    });

    it("Should allow owner to collect dev fees", async function () {
      await spavax.collectDevFees();
      expect(await spavax.accumulatedDevFees()).to.equal(0);
    });

    it("Should allow collecting all fees at once", async function () {
      await spavax.collectAllFees();
      
      expect(await spavax.accumulatedValidatorFees()).to.equal(0);
      expect(await spavax.accumulatedDaoFees()).to.equal(0);
      expect(await spavax.accumulatedDevFees()).to.equal(0);
    });

    it("Should not allow non-owner to collect fees", async function () {
      await expect(
        spavax.connect(user1).collectValidatorFees()
      ).to.be.revertedWithCustomError(spavax, "OwnableUnauthorizedAccount");
    });
  });

  describe("Admin Functions", function () {
    it("Should allow owner to withdraw AVAX", async function () {
      await spavax.connect(user1).stake({ value: ethers.parseEther("10") });
      
      const balanceBefore = await ethers.provider.getBalance(owner.address);
      await spavax.withdraw(ethers.parseEther("5"));
      const balanceAfter = await ethers.provider.getBalance(owner.address);
      
      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should allow owner to deposit AVAX", async function () {
      await expect(spavax.deposit({ value: ethers.parseEther("5") }))
        .to.emit(spavax, "Deposited");
    });

    it("Should allow owner to update fee structure", async function () {
      await spavax.setFeeStructure(400, 200, 200);
      
      expect(await spavax.validatorFeeBasisPoints()).to.equal(400);
      expect(await spavax.daoFeeBasisPoints()).to.equal(200);
      expect(await spavax.devFeeBasisPoints()).to.equal(200);
    });

    it("Should not allow fees above maximum", async function () {
      await expect(
        spavax.setFeeStructure(1000, 1000, 1000)
      ).to.be.revertedWith("Total fees too high (max 20%)");
    });

    it("Should allow owner to pause and unpause", async function () {
      await spavax.pause();
      expect(await spavax.paused()).to.be.true;
      
      await spavax.unpause();
      expect(await spavax.paused()).to.be.false;
    });
  });

  describe("Exchange Rate", function () {
    it("Should return 1:1 ratio initially", async function () {
      const rate = await spavax.getExchangeRate();
      expect(rate).to.equal(ethers.parseEther("1"));
    });

    it("Should calculate correct exchange rate after rewards", async function () {
      await spavax.connect(user1).stake({ value: ethers.parseEther("100") });
      await spavax.addRewards(ethers.parseEther("10"));
      
      const rate = await spavax.getExchangeRate();
      // 109 AVAX / 100 spAVAX = 1.09
      expect(rate).to.equal(ethers.parseEther("1.09"));
    });
  });

  describe("Preview Functions", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake({ value: ethers.parseEther("100") });
      await spavax.addRewards(ethers.parseEther("10"));
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
  });

  describe("Edge Cases", function () {
    it("Should handle multiple unlock requests", async function () {
      await spavax.connect(user1).stake({ value: ethers.parseEther("10") });
      
      await spavax.connect(user1).requestUnlock(ethers.parseEther("2"));
      await spavax.connect(user1).requestUnlock(ethers.parseEther("2"));
      await spavax.connect(user1).requestUnlock(ethers.parseEther("2"));
      
      const count = await spavax.getUnlockRequestCount(user1.address);
      expect(count).to.equal(3);
    });

    it("Should handle zero rewards correctly", async function () {
      await spavax.connect(user1).stake({ value: ethers.parseEther("10") });
      
      await expect(
        spavax.addRewards(0)
      ).to.be.revertedWith("Reward must be > 0");
    });

    it("Should handle contract receiving AVAX directly", async function () {
      const contractAddress = await spavax.getAddress();
      
      await expect(
        owner.sendTransaction({
          to: contractAddress,
          value: ethers.parseEther("1")
        })
      ).to.emit(spavax, "Deposited");
    });
  });
});
