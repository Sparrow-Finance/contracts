const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("spAVAX - COMPLETE Test Suite", function () {
  let spavax;
  let nft;
  let owner;
  let user1;
  let user2;
  let user3;

  beforeEach(async function () {
    [owner, user1, user2, user3] = await ethers.getSigners();

    // Deploy NFT contract first
    const WithdrawalQueueNFT = await ethers.getContractFactory("WithdrawalQueueNFT");
    nft = await WithdrawalQueueNFT.deploy(owner.address);
    await nft.waitForDeployment();

    // Deploy spAVAX contract
    const SpAVAX = await ethers.getContractFactory("spAVAX");
    spavax = await upgrades.deployProxy(SpAVAX, [await nft.getAddress()], {
      initializer: "initialize",
      kind: "uups"
    });
    await spavax.waitForDeployment();

    // Link contracts
    await nft.setVault(await spavax.getAddress());
  });

  describe("Deployment", function () {
    it("Should set correct owner", async function () {
      expect(await spavax.owner()).to.equal(owner.address);
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

    it("Should have NFT contract set", async function () {
      expect(await spavax.withdrawalQueueNFT()).to.equal(await nft.getAddress());
    });

    it("Should have correct ERC-4626 asset (address(0) for native AVAX)", async function () {
      expect(await spavax.asset()).to.equal(ethers.ZeroAddress);
    });

    it("Should have 18 decimals", async function () {
      expect(await spavax.decimals()).to.equal(18);
    });
  });

  describe("Legacy Staking (stake function)", function () {
    it("Should reject stake below minimum", async function () {
      await expect(
        spavax.connect(user1).stake(0, { value: ethers.parseEther("0.05") })
      ).to.be.revertedWithCustomError(spavax, "BelowMinimumStake");
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
      ).to.be.revertedWithCustomError(spavax, "SlippageTooHigh");
    });

    it("Should calculate correct shares after rewards", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      await spavax.addRewards({ value: ethers.parseEther("1") });
      
      const stakeAmount = ethers.parseEther("10");
      // Use preview to get expected shares based on current rate
      const expectedShares = await spavax.previewDeposit(stakeAmount);
      
      await spavax.connect(user2).stake(0, { value: stakeAmount });
      
      // Should match preview exactly
      expect(await spavax.balanceOf(user2.address)).to.equal(expectedShares);
    });

    it("Should not allow staking when paused", async function () {
      await spavax.pause();
      
      await expect(
        spavax.connect(user1).stake(0, { value: ethers.parseEther("1") })
      ).to.be.revertedWithCustomError(spavax, "EnforcedPause");
    });
  });

  describe("ERC-4626: deposit()", function () {
    it("Should deposit AVAX and mint spAVAX", async function () {
      const depositAmount = ethers.parseEther("1");
      
      await expect(
        spavax.connect(user1).deposit(user1.address, { value: depositAmount })
      ).to.emit(spavax, "Staked")
        .withArgs(user1.address, depositAmount, depositAmount);

      expect(await spavax.balanceOf(user1.address)).to.equal(depositAmount);
      expect(await spavax.totalPooledAVAX()).to.equal(depositAmount);
    });

    it("Should reject deposit below minimum", async function () {
      await expect(
        spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("0.05") })
      ).to.be.revertedWithCustomError(spavax, "BelowMinimumStake");
    });

    it("Should calculate correct shares after rewards", async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
      await spavax.addRewards({ value: ethers.parseEther("1") });
      
      // Use preview to get expected shares
      const expectedShares = await spavax.previewDeposit(ethers.parseEther("10"));
      
      await spavax.connect(user2).deposit(user2.address, { value: ethers.parseEther("10") });
      
      // Should match preview exactly
      expect(await spavax.balanceOf(user2.address)).to.equal(expectedShares);
    });

    it("Should allow depositing to different receiver", async function () {
      await spavax.connect(user1).deposit(user2.address, { value: ethers.parseEther("1") });
      expect(await spavax.balanceOf(user2.address)).to.equal(ethers.parseEther("1"));
      expect(await spavax.balanceOf(user1.address)).to.equal(0);
    });
  });

  describe("ERC-4626: mint()", function () {
    it("Should mint exact shares", async function () {
      const shares = ethers.parseEther("10");
      const assets = await spavax.previewMint(shares);
      
      await spavax.connect(user1).mint(shares, user1.address, { value: assets });
      
      expect(await spavax.balanceOf(user1.address)).to.equal(shares);
    });

    it("Should reject if msg.value != required assets", async function () {
      const shares = ethers.parseEther("10");
      const assets = await spavax.previewMint(shares);
      
      await expect(
        spavax.connect(user1).mint(shares, user1.address, { value: assets + 1n })
      ).to.be.revertedWithCustomError(spavax, "InvalidAmount");
    });

    it("Should reject below minimum", async function () {
      await expect(
        spavax.connect(user1).mint(ethers.parseEther("0.05"), user1.address, { value: ethers.parseEther("0.05") })
      ).to.be.revertedWithCustomError(spavax, "BelowMinimumStake");
    });

    it("Should work after rate changes", async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
      await spavax.addRewards({ value: ethers.parseEther("1") });
      
      const shares = ethers.parseEther("5");
      const assets = await spavax.previewMint(shares);
      
      // Send exact amount required
      await spavax.connect(user2).mint(shares, user2.address, { value: assets });
      
      expect(await spavax.balanceOf(user2.address)).to.equal(shares);
    });
  });

  describe("Legacy Unlock Requests (requestUnlock)", function () {
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
      ).to.be.revertedWithCustomError(spavax, "SlippageTooHigh");
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
      ).to.be.revertedWithCustomError(spavax, "TooManyRequests");
    });
  });

  describe("ERC-4626: withdraw() → NFT", function () {
    beforeEach(async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
    });

    it("Should create NFT withdrawal request", async function () {
      const withdrawAmount = ethers.parseEther("5");
      
      await expect(
        spavax.connect(user1).withdraw(withdrawAmount, user1.address, user1.address)
      ).to.emit(spavax, "Withdraw");

      expect(await nft.balanceOf(user1.address)).to.equal(1);
    });

    it("Should lock AVAX in totalLockedInUnlocks", async function () {
      const withdrawAmount = ethers.parseEther("5");
      
      expect(await spavax.totalLockedInUnlocks()).to.equal(0);
      await spavax.connect(user1).withdraw(withdrawAmount, user1.address, user1.address);
      expect(await spavax.totalLockedInUnlocks()).to.equal(withdrawAmount);
    });

    it("Should burn spAVAX tokens", async function () {
      const withdrawAmount = ethers.parseEther("5");
      const balanceBefore = await spavax.balanceOf(user1.address);
      
      await spavax.connect(user1).withdraw(withdrawAmount, user1.address, user1.address);
      
      const balanceAfter = await spavax.balanceOf(user1.address);
      expect(balanceAfter).to.be.lt(balanceBefore);
    });

    it("Should lock exchange rate in NFT", async function () {
      const withdrawAmount = ethers.parseEther("5");
      
      await spavax.connect(user1).withdraw(withdrawAmount, user1.address, user1.address);
      const request = await nft.getRequest(1);
      const lockedAvax = request.avaxAmount;
      
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      const requestAfter = await nft.getRequest(1);
      expect(requestAfter.avaxAmount).to.equal(lockedAvax);
    });

    it("Should support allowance for third-party withdraw", async function () {
      await spavax.connect(user1).approve(user2.address, ethers.parseEther("5"));
      
      await spavax.connect(user2).withdraw(
        ethers.parseEther("5"),
        user2.address,
        user1.address
      );
      
      expect(await nft.balanceOf(user2.address)).to.equal(1);
      expect(await spavax.balanceOf(user1.address)).to.be.lt(ethers.parseEther("10"));
    });
  });

  describe("ERC-4626: redeem() → NFT", function () {
    beforeEach(async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
    });

    it("Should create NFT withdrawal request", async function () {
      const shares = ethers.parseEther("5");
      
      await spavax.connect(user1).redeem(shares, user1.address, user1.address);
      
      expect(await nft.balanceOf(user1.address)).to.equal(1);
    });

    it("Should burn exact shares", async function () {
      const shares = ethers.parseEther("5");
      const balanceBefore = await spavax.balanceOf(user1.address);
      
      await spavax.connect(user1).redeem(shares, user1.address, user1.address);
      
      expect(await spavax.balanceOf(user1.address)).to.equal(balanceBefore - shares);
    });

    it("Should lock AVAX in totalLockedInUnlocks", async function () {
      const shares = ethers.parseEther("5");
      const expectedAvax = await spavax.previewRedeem(shares);
      
      await spavax.connect(user1).redeem(shares, user1.address, user1.address);
      
      expect(await spavax.totalLockedInUnlocks()).to.equal(expectedAvax);
    });

    it("Should support allowance for third-party redeem", async function () {
      await spavax.connect(user1).approve(user2.address, ethers.parseEther("5"));
      
      await spavax.connect(user2).redeem(
        ethers.parseEther("5"),
        user2.address,
        user1.address
      );
      
      expect(await nft.balanceOf(user2.address)).to.equal(1);
    });
  });

  describe("ERC-4626: Preview Functions", function () {
    it("Should preview deposit correctly at 1:1 rate", async function () {
      const assets = ethers.parseEther("10");
      expect(await spavax.previewDeposit(assets)).to.equal(assets);
    });

    it("Should preview deposit after rate change", async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("100") });
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      const assets = ethers.parseEther("10");
      const shares = await spavax.previewDeposit(assets);
      
      expect(shares).to.be.lt(assets);
    });

    it("Should preview mint correctly", async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("100") });
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      const shares = ethers.parseEther("10");
      const assets = await spavax.previewMint(shares);
      
      expect(assets).to.be.gt(shares);
    });

    it("Should preview withdraw correctly", async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("100") });
      
      const assets = ethers.parseEther("10");
      const shares = await spavax.previewWithdraw(assets);
      
      expect(shares).to.equal(assets);
    });

    it("Should preview redeem correctly", async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("100") });
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      const shares = ethers.parseEther("10");
      const assets = await spavax.previewRedeem(shares);
      
      expect(assets).to.be.gt(shares);
    });
  });

  describe("ERC-4626: Max Functions", function () {
    it("Should return unlimited maxDeposit", async function () {
      expect(await spavax.maxDeposit(user1.address)).to.equal(ethers.MaxUint256);
    });

    it("Should return unlimited maxMint", async function () {
      expect(await spavax.maxMint(user1.address)).to.equal(ethers.MaxUint256);
    });

    it("Should return user balance for maxWithdraw", async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
      
      const maxWithdraw = await spavax.maxWithdraw(user1.address);
      expect(maxWithdraw).to.equal(ethers.parseEther("10"));
    });

    it("Should return user shares for maxRedeem", async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
      
      expect(await spavax.maxRedeem(user1.address)).to.equal(ethers.parseEther("10"));
    });

    it("Should update maxWithdraw after rate change", async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
      await spavax.addRewards({ value: ethers.parseEther("1") });
      
      const maxWithdraw = await spavax.maxWithdraw(user1.address);
      expect(maxWithdraw).to.be.gt(ethers.parseEther("10"));
    });
  });

  describe("ERC-4626: totalAssets()", function () {
    it("Should return zero initially", async function () {
      expect(await spavax.totalAssets()).to.equal(0);
    });

    it("Should return totalPooledAVAX minus fees and locked", async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
      expect(await spavax.totalAssets()).to.equal(ethers.parseEther("10"));
    });

    it("Should increase with rewards", async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
      await spavax.addRewards({ value: ethers.parseEther("1") });
      
      expect(await spavax.totalAssets()).to.equal(ethers.parseEther("10.92"));
    });
  });

  describe("Legacy Claim Unlock", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      await spavax.connect(user1).requestUnlock(ethers.parseEther("5"), 0);
    });

    it("Should not allow claim before unlock period", async function () {
      await expect(
        spavax.connect(user1).claimUnlock(0)
      ).to.be.revertedWithCustomError(spavax, "UnlockPeriodNotFinished");
    });

    it("Should allow claim after unlock period", async function () {
      await time.increase(61);
      
      const initialBalance = await ethers.provider.getBalance(user1.address);
      await spavax.connect(user1).claimUnlock(0);
      const finalBalance = await ethers.provider.getBalance(user1.address);
      
      expect(finalBalance).to.be.gt(initialBalance);
    });

    it("Should decrease totalPooledAVAX on claim", async function () {
      await time.increase(61);
      
      const totalBefore = await spavax.totalPooledAVAX();
      await spavax.connect(user1).claimUnlock(0);
      const totalAfter = await spavax.totalPooledAVAX();
      
      expect(totalAfter).to.equal(totalBefore - ethers.parseEther("5"));
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
      ).to.be.revertedWithCustomError(spavax, "ClaimWindowExpired");
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

  describe("NFT Withdrawal Claim (claimWithdrawalNFT)", function () {
    beforeEach(async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
      await spavax.connect(user1).withdraw(ethers.parseEther("5"), user1.address, user1.address);
    });

    it("Should not allow claim before unlock period", async function () {
      await expect(
        spavax.connect(user1).claimWithdrawalNFT(1)
      ).to.be.revertedWithCustomError(spavax, "UnlockPeriodNotFinished");
    });

    it("Should claim AVAX after unlock period", async function () {
      await time.increase(61);
      
      const balanceBefore = await ethers.provider.getBalance(user1.address);
      await spavax.connect(user1).claimWithdrawalNFT(1);
      const balanceAfter = await ethers.provider.getBalance(user1.address);
      
      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should decrease totalPooledAVAX on claim", async function () {
      await time.increase(61);
      
      const totalBefore = await spavax.totalPooledAVAX();
      await spavax.connect(user1).claimWithdrawalNFT(1);
      const totalAfter = await spavax.totalPooledAVAX();
      
      expect(totalAfter).to.equal(totalBefore - ethers.parseEther("5"));
    });

    it("Should decrease totalLockedInUnlocks", async function () {
      await time.increase(61);
      
      expect(await spavax.totalLockedInUnlocks()).to.equal(ethers.parseEther("5"));
      await spavax.connect(user1).claimWithdrawalNFT(1);
      expect(await spavax.totalLockedInUnlocks()).to.equal(0);
    });

    it("Should burn NFT on claim", async function () {
      await time.increase(61);
      
      expect(await nft.balanceOf(user1.address)).to.equal(1);
      await spavax.connect(user1).claimWithdrawalNFT(1);
      expect(await nft.balanceOf(user1.address)).to.equal(0);
    });

    it("Should use locked exchange rate", async function () {
      const request = await nft.getRequest(1);
      const lockedAvax = request.avaxAmount;
      
      await spavax.addRewards({ value: ethers.parseEther("10") });
      await time.increase(61);
      
      const balanceBefore = await ethers.provider.getBalance(user1.address);
      const tx = await spavax.connect(user1).claimWithdrawalNFT(1);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      
      const balanceAfter = await ethers.provider.getBalance(user1.address);
      const received = balanceAfter - balanceBefore + gasUsed;
      
      expect(received).to.be.closeTo(lockedAvax, ethers.parseEther("0.001"));
    });
  });

  describe("Legacy Cancel Unlock", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      await spavax.connect(user1).requestUnlock(ethers.parseEther("5"), 0);
    });

    it("Should allow canceling unlock", async function () {
      const balanceBefore = await spavax.balanceOf(user1.address);
      
      await spavax.connect(user1).cancelUnlock(0);
      
      expect(await spavax.balanceOf(user1.address)).to.be.gt(balanceBefore);
    });

    it("Should decrease totalLockedInUnlocks", async function () {
      expect(await spavax.totalLockedInUnlocks()).to.equal(ethers.parseEther("5"));
      
      await spavax.connect(user1).cancelUnlock(0);
      
      expect(await spavax.totalLockedInUnlocks()).to.equal(0);
    });

    it("Should NOT change totalPooledAVAX", async function () {
      const totalBefore = await spavax.totalPooledAVAX();
      await spavax.connect(user1).cancelUnlock(0);
      const totalAfter = await spavax.totalPooledAVAX();
      
      expect(totalAfter).to.equal(totalBefore);
    });

    it("Should not allow canceling after unlock time", async function () {
      await time.increase(61);
      
      await expect(
        spavax.connect(user1).cancelUnlock(0)
      ).to.be.revertedWithCustomError(spavax, "AlreadyUnlocked");
    });

    it("Should return original spAVAX amount on cancel", async function () {
      const request = await spavax.getUnlockRequest(user1.address, 0);
      const lockedSpAvax = request[0];
      
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      const balanceBefore = await spavax.balanceOf(user1.address);
      await spavax.connect(user1).cancelUnlock(0);
      const balanceAfter = await spavax.balanceOf(user1.address);
      
      expect(balanceAfter - balanceBefore).to.equal(lockedSpAvax);
    });
  });

  describe("NFT Withdrawal Cancel (cancelWithdrawalNFT)", function () {
    beforeEach(async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
      await spavax.connect(user1).withdraw(ethers.parseEther("5"), user1.address, user1.address);
    });

    it("Should cancel withdrawal and return spAVAX", async function () {
      const balanceBefore = await spavax.balanceOf(user1.address);
      
      await spavax.connect(user1).cancelWithdrawalNFT(1);
      
      const balanceAfter = await spavax.balanceOf(user1.address);
      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should decrease totalLockedInUnlocks", async function () {
      expect(await spavax.totalLockedInUnlocks()).to.equal(ethers.parseEther("5"));
      await spavax.connect(user1).cancelWithdrawalNFT(1);
      expect(await spavax.totalLockedInUnlocks()).to.equal(0);
    });

    it("Should NOT change totalPooledAVAX", async function () {
      const totalBefore = await spavax.totalPooledAVAX();
      await spavax.connect(user1).cancelWithdrawalNFT(1);
      const totalAfter = await spavax.totalPooledAVAX();
      
      expect(totalAfter).to.equal(totalBefore);
    });

    it("Should burn NFT", async function () {
      expect(await nft.balanceOf(user1.address)).to.equal(1);
      await spavax.connect(user1).cancelWithdrawalNFT(1);
      expect(await nft.balanceOf(user1.address)).to.equal(0);
    });

    it("Should return original spAVAX amount (locked rate)", async function () {
      const request = await nft.getRequest(1);
      const lockedSpAvax = request.spAvaxAmount;
      
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      const balanceBefore = await spavax.balanceOf(user1.address);
      await spavax.connect(user1).cancelWithdrawalNFT(1);
      const balanceAfter = await spavax.balanceOf(user1.address);
      
      expect(balanceAfter - balanceBefore).to.equal(lockedSpAvax);
    });

    it("Should NOT allow cancel after unlock_time", async function () {
      await time.increase(61);
      
      await expect(
        spavax.connect(user1).cancelWithdrawalNFT(1)
      ).to.be.revertedWithCustomError(spavax, "AlreadyUnlocked");
    });

    it("Should allow cancel before unlock_time", async function () {
      const balanceBefore = await spavax.balanceOf(user1.address);
      await spavax.connect(user1).cancelWithdrawalNFT(1);
      const balanceAfter = await spavax.balanceOf(user1.address);
      
      expect(balanceAfter).to.be.gt(balanceBefore);
      expect(await nft.balanceOf(user1.address)).to.equal(0);
    });
  });

  describe("Legacy Claim Expired", function () {
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
      ).to.be.revertedWithCustomError(spavax, "NotExpired");
    });

    it("Should return original spAVAX amount on expiry", async function () {
      const request = await spavax.getUnlockRequest(user1.address, 0);
      const lockedSpAvax = request[0];
      
      await spavax.addRewards({ value: ethers.parseEther("10") });
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      const balanceBefore = await spavax.balanceOf(user1.address);
      await spavax.connect(user1).claimExpired(0);
      const balanceAfter = await spavax.balanceOf(user1.address);
      
      expect(balanceAfter - balanceBefore).to.equal(lockedSpAvax);
    });
  });

  describe("NFT Claim Expired (claimExpiredNFT)", function () {
    beforeEach(async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
      await spavax.connect(user1).withdraw(ethers.parseEther("5"), user1.address, user1.address);
    });

    it("Should allow claiming expired NFT", async function () {
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      const balanceBefore = await spavax.balanceOf(user1.address);
      await spavax.connect(user1).claimExpiredNFT(1);
      
      expect(await spavax.balanceOf(user1.address)).to.be.gt(balanceBefore);
    });

    it("Should decrease totalLockedInUnlocks", async function () {
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      expect(await spavax.totalLockedInUnlocks()).to.equal(ethers.parseEther("5"));
      await spavax.connect(user1).claimExpiredNFT(1);
      expect(await spavax.totalLockedInUnlocks()).to.equal(0);
    });

    it("Should not allow claiming non-expired", async function () {
      await expect(
        spavax.connect(user1).claimExpiredNFT(1)
      ).to.be.revertedWithCustomError(spavax, "NotExpired");
    });

    it("Should return original spAVAX amount (locked rate)", async function () {
      const request = await nft.getRequest(1);
      const lockedSpAvax = request.spAvaxAmount;
      
      await spavax.addRewards({ value: ethers.parseEther("10") });
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      const balanceBefore = await spavax.balanceOf(user1.address);
      await spavax.connect(user1).claimExpiredNFT(1);
      const balanceAfter = await spavax.balanceOf(user1.address);
      
      expect(balanceAfter - balanceBefore).to.equal(lockedSpAvax);
    });
  });

  describe("Rate Gaming Prevention", function () {
    beforeEach(async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("100") });
    });

    it("Should prevent canceling NFT after seeing rate increase", async function () {
      await spavax.connect(user1).withdraw(ethers.parseEther("50"), user1.address, user1.address);
      
      await spavax.addRewards({ value: ethers.parseEther("50") });
      await time.increase(61);
      
      await expect(
        spavax.connect(user1).cancelWithdrawalNFT(1)
      ).to.be.revertedWithCustomError(spavax, "AlreadyUnlocked");
    });

    it("Should allow cancel before unlock_time (normal use case)", async function () {
      await spavax.connect(user1).withdraw(ethers.parseEther("50"), user1.address, user1.address);
      await time.increase(30);
      
      await spavax.connect(user1).cancelWithdrawalNFT(1);
      expect(await nft.balanceOf(user1.address)).to.equal(0);
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
      ).to.be.revertedWithCustomError(spavax, "InvalidAmount");
    });

    it("Should handle multiple sequential rewards", async function () {
      await spavax.addRewards({ value: ethers.parseEther("10") });
      await spavax.addRewards({ value: ethers.parseEther("5") });
      await spavax.addRewards({ value: ethers.parseEther("3") });
      
      // Total rewards: 18 AVAX
      // Fees: 18 * 0.08 = 1.44
      // User rewards: 18 * 0.92 = 16.56
      expect(await spavax.totalPooledAVAX()).to.equal(ethers.parseEther("116.56"));
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

    it("Should not allow non-owner to collect", async function () {
      await expect(
        spavax.connect(user1).collectDaoFees()
      ).to.be.revertedWithCustomError(spavax, "OwnableUnauthorizedAccount");
    });

    it("Should not allow collecting zero fees", async function () {
      await spavax.collectAllFees();
      
      await expect(
        spavax.collectDaoFees()
      ).to.be.revertedWithCustomError(spavax, "NoFeesToCollect");
    });
  });

  describe("Admin Withdraw", function () {
    beforeEach(async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("100") });
    });

    it("Should allow adminWithdraw", async function () {
      const balanceBefore = await ethers.provider.getBalance(owner.address);
      await spavax.adminWithdraw(ethers.parseEther("50"));
      expect(await ethers.provider.getBalance(owner.address)).to.be.gt(balanceBefore);
    });

    it("Should enforce reserve ratio (10%)", async function () {
      const totalPooled = await spavax.totalPooledAVAX();
      const minReserve = totalPooled * 1000n / 10000n;
      
      const balance = await ethers.provider.getBalance(await spavax.getAddress());
      
      await expect(
        spavax.adminWithdraw(balance - minReserve + ethers.parseEther("0.1"))
      ).to.be.revertedWithCustomError(spavax, "InsufficientLiquidity");
    });

    it("Should prevent withdrawing committed fees", async function () {
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      const balance = await ethers.provider.getBalance(await spavax.getAddress());
      const fees = (await spavax.accumulatedDaoFees()) + (await spavax.accumulatedDevFees());
      
      await expect(
        spavax.adminWithdraw(balance - fees + ethers.parseEther("0.1"))
      ).to.be.revertedWithCustomError(spavax, "InsufficientLiquidity");
    });

    it("Should prevent withdrawing when unlocks pending", async function () {
      await spavax.connect(user1).requestUnlock(ethers.parseEther("50"), 0);
      
      await expect(
        spavax.adminWithdraw(ethers.parseEther("60"))
      ).to.be.revertedWithCustomError(spavax, "InsufficientLiquidity");
    });
  });

  describe("Admin Functions", function () {
    it("Should allow adminDeposit", async function () {
      await expect(spavax.adminDeposit({ value: ethers.parseEther("5") }))
        .to.emit(spavax, "Deposited");
    });

    it("Should update fee structure", async function () {
      await expect(spavax.setFeeStructure(400, 200))
        .to.emit(spavax, "FeeStructureUpdated")
        .withArgs(600, 400, 200);
      
      expect(await spavax.daoFeeBasisPoints()).to.equal(400);
      expect(await spavax.devFeeBasisPoints()).to.equal(200);
      expect(await spavax.protocolFeeBasisPoints()).to.equal(600);
    });

    it("Should not allow fees above 10%", async function () {
      await expect(
        spavax.setFeeStructure(600, 500)
      ).to.be.revertedWithCustomError(spavax, "InvalidFeeStructure");
    });

    it("Should update minStakeAmount", async function () {
      await expect(spavax.setMinStakeAmount(ethers.parseEther("0.5")))
        .to.emit(spavax, "MinStakeAmountUpdated");
      
      expect(await spavax.minStakeAmount()).to.equal(ethers.parseEther("0.5"));
    });

    it("Should update unlock period", async function () {
      const newPeriod = 7 * 24 * 60 * 60;
      await expect(spavax.setUnlockPeriod(newPeriod))
        .to.emit(spavax, "UnlockPeriodUpdated");
      
      expect(await spavax.unlockPeriod()).to.equal(newPeriod);
    });

    it("Should not allow unlock period below minimum", async function () {
      await expect(
        spavax.setUnlockPeriod(6 * 24 * 60 * 60)
      ).to.be.revertedWithCustomError(spavax, "InvalidAmount");
    });

    it("Should not allow unlock period above maximum", async function () {
      await expect(
        spavax.setUnlockPeriod(31 * 24 * 60 * 60)
      ).to.be.revertedWithCustomError(spavax, "InvalidAmount");
    });

    it("Should update claim window", async function () {
      const newWindow = 10 * 24 * 60 * 60;
      await expect(spavax.setClaimWindow(newWindow))
        .to.emit(spavax, "ClaimWindowUpdated");
      
      expect(await spavax.claimWindow()).to.equal(newWindow);
    });

    it("Should not allow claim window below minimum", async function () {
      await expect(
        spavax.setClaimWindow(30 * 60)
      ).to.be.revertedWithCustomError(spavax, "InvalidAmount");
    });

    it("Should not allow claim window above maximum", async function () {
      await expect(
        spavax.setClaimWindow(31 * 24 * 60 * 60)
      ).to.be.revertedWithCustomError(spavax, "InvalidAmount");
    });

    it("Should pause and unpause", async function () {
      await spavax.pause();
      expect(await spavax.paused()).to.be.true;
      
      await spavax.unpause();
      expect(await spavax.paused()).to.be.false;
    });

    it("Should not allow non-owner to call admin functions", async function () {
      await expect(
        spavax.connect(user1).setFeeStructure(400, 200)
      ).to.be.revertedWithCustomError(spavax, "OwnableUnauthorizedAccount");
      
      await expect(
        spavax.connect(user1).pause()
      ).to.be.revertedWithCustomError(spavax, "OwnableUnauthorizedAccount");
    });
  });

  describe("Receive Function", function () {
    it("Should reject from non-owner", async function () {
      const contractAddress = await spavax.getAddress();
      
      await expect(
        user1.sendTransaction({
          to: contractAddress,
          value: ethers.parseEther("1")
        })
      ).to.be.revertedWithCustomError(spavax, "InvalidAddress");
    });

    it("Should accept from owner", async function () {
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

    it("Should return correct stats", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      
      const stats = await spavax.getStats();
      expect(stats[0]).to.equal(ethers.parseEther("10"));
      expect(stats[1]).to.equal(ethers.parseEther("10"));
      expect(stats[2]).to.equal(ethers.parseEther("1"));
    });

    it("Should return unlock request details with status flags", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      await spavax.connect(user1).requestUnlock(ethers.parseEther("5"), 0);
      
      const request = await spavax.getUnlockRequest(user1.address, 0);
      
      expect(request[0]).to.equal(ethers.parseEther("5"));
      expect(request[1]).to.equal(ethers.parseEther("5"));
      expect(request[4]).to.equal(false);
      expect(request[5]).to.equal(false);
      
      await time.increase(61);
      
      const request2 = await spavax.getUnlockRequest(user1.address, 0);
      expect(request2[4]).to.equal(true);
      
      await time.increase(7 * 24 * 60 * 60);
      
      const request3 = await spavax.getUnlockRequest(user1.address, 0);
      expect(request3[5]).to.equal(true);
    });
  });

  describe("NFT Transfer and Third-Party Claims", function () {
    beforeEach(async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
      await spavax.connect(user1).withdraw(ethers.parseEther("5"), user1.address, user1.address);
    });

    it("Should allow NFT transfer to another user", async function () {
      await nft.connect(user1).transferFrom(user1.address, user2.address, 1);
      expect(await nft.ownerOf(1)).to.equal(user2.address);
    });

    it("Should allow new owner to claim", async function () {
      await nft.connect(user1).transferFrom(user1.address, user2.address, 1);
      await time.increase(61);
      
      const balanceBefore = await ethers.provider.getBalance(user2.address);
      await spavax.connect(user2).claimWithdrawalNFT(1);
      const balanceAfter = await ethers.provider.getBalance(user2.address);
      
      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should prevent original owner from claiming after transfer", async function () {
      await nft.connect(user1).transferFrom(user1.address, user2.address, 1);
      await time.increase(61);
      
      await expect(
        spavax.connect(user1).claimWithdrawalNFT(1)
      ).to.be.revertedWithCustomError(spavax, "NotNFTOwner");
    });
  });

  describe("WithdrawalQueueNFT Contract Tests", function () {
    it("Should have correct name and symbol", async function () {
      expect(await nft.name()).to.equal("Sparrow Withdrawal Request");
      expect(await nft.symbol()).to.equal("spWR");
    });

    it("Should not allow non-vault to mint", async function () {
      const request = {
        spAvaxAmount: ethers.parseEther("1"),
        avaxAmount: ethers.parseEther("1"),
        unlockTime: Math.floor(Date.now() / 1000) + 60,
        expiryTime: Math.floor(Date.now() / 1000) + 7 * 24 * 60 * 60
      };
      
      await expect(
        nft.connect(user1).mint(user1.address, request)
      ).to.be.revertedWith("Only vault can call");
    });

    it("Should not allow non-vault to burn", async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
      await spavax.connect(user1).withdraw(ethers.parseEther("5"), user1.address, user1.address);
      
      await expect(
        nft.connect(user1).burn(1)
      ).to.be.revertedWith("Only vault can call");
    });

    it("Should return correct isClaimable status", async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
      await spavax.connect(user1).withdraw(ethers.parseEther("5"), user1.address, user1.address);
      
      expect(await nft.isClaimable(1)).to.be.false;
      
      await time.increase(61);
      
      expect(await nft.isClaimable(1)).to.be.true;
      
      await time.increase(7 * 24 * 60 * 60);
      
      expect(await nft.isClaimable(1)).to.be.false;
    });

    it("Should return correct isExpired status", async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
      await spavax.connect(user1).withdraw(ethers.parseEther("5"), user1.address, user1.address);
      
      expect(await nft.isExpired(1)).to.be.false;
      
      await time.increase(7 * 24 * 60 * 60 + 61);
      
      expect(await nft.isExpired(1)).to.be.true;
    });

    it("Should generate tokenURI with metadata", async function () {
      await spavax.connect(user1).deposit(user1.address, { value: ethers.parseEther("10") });
      await spavax.connect(user1).withdraw(ethers.parseEther("5"), user1.address, user1.address);
      
      const uri = await nft.tokenURI(1);
      expect(uri).to.include("data:application/json;base64,");
      
      const json = Buffer.from(uri.split(",")[1], "base64").toString();
      const metadata = JSON.parse(json);
      
      expect(metadata.name).to.include("Sparrow Withdrawal Request #1");
      expect(metadata.description).to.include("5 AVAX");
    });
  });

  describe("Array Removal Edge Cases", function () {
    it("Should handle removing first element", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      
      await spavax.connect(user1).requestUnlock(ethers.parseEther("1"), 0);
      await spavax.connect(user1).requestUnlock(ethers.parseEther("1"), 0);
      await spavax.connect(user1).requestUnlock(ethers.parseEther("1"), 0);
      
      expect(await spavax.getUnlockRequestCount(user1.address)).to.equal(3);
      
      await spavax.connect(user1).cancelUnlock(0);
      
      expect(await spavax.getUnlockRequestCount(user1.address)).to.equal(2);
    });

    it("Should handle removing middle element", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      
      await spavax.connect(user1).requestUnlock(ethers.parseEther("1"), 0);
      await spavax.connect(user1).requestUnlock(ethers.parseEther("2"), 0);
      await spavax.connect(user1).requestUnlock(ethers.parseEther("3"), 0);
      
      await spavax.connect(user1).cancelUnlock(1);
      
      expect(await spavax.getUnlockRequestCount(user1.address)).to.equal(2);
    });

    it("Should handle removing last element", async function () {
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      
      await spavax.connect(user1).requestUnlock(ethers.parseEther("1"), 0);
      await spavax.connect(user1).requestUnlock(ethers.parseEther("2"), 0);
      await spavax.connect(user1).requestUnlock(ethers.parseEther("3"), 0);
      
      await spavax.connect(user1).cancelUnlock(2);
      
      expect(await spavax.getUnlockRequestCount(user1.address)).to.equal(2);
    });
  });

  describe("Complex Integration Tests", function () {
    it("Should handle multiple users with multiple flows", async function () {
      // Initial stakes
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("10") });
      await spavax.connect(user2).deposit(user2.address, { value: ethers.parseEther("10") });
      
      // Add rewards
      await spavax.addRewards({ value: ethers.parseEther("2") });
      
      // User1 requests unlock (legacy)
      await spavax.connect(user1).requestUnlock(ethers.parseEther("5"), 0);
      
      // User2 withdraws (NFT) - need to calculate shares for 5 AVAX worth
      const assets = ethers.parseEther("5");
      await spavax.connect(user2).withdraw(assets, user2.address, user2.address);
      
      // Wait unlock period
      await time.increase(61);
      
      // Both claim
      await spavax.connect(user1).claimUnlock(0);
      await spavax.connect(user2).claimWithdrawalNFT(1);
      
      // Both should have remaining balances
      expect(await spavax.balanceOf(user1.address)).to.be.gt(0);
      expect(await spavax.balanceOf(user2.address)).to.be.gt(0);
    });

    it("Should maintain accounting across complex scenarios", async function () {
      // Multiple users stake using different methods
      await spavax.connect(user1).stake(0, { value: ethers.parseEther("50") });
      await spavax.connect(user2).deposit(user2.address, { value: ethers.parseEther("30") });
      
      // User3 mints exact shares (at 1:1 rate initially)
      const shares = ethers.parseEther("20");
      const assets = await spavax.previewMint(shares);
      await spavax.connect(user3).mint(shares, user3.address, { value: assets });
      
      // Add rewards
      await spavax.addRewards({ value: ethers.parseEther("10") });
      
      // Various unlock requests
      await spavax.connect(user1).requestUnlock(ethers.parseEther("10"), 0);
      await spavax.connect(user2).withdraw(ethers.parseEther("5"), user2.address, user2.address);
      
      // Check accounting
      const totalSupply = await spavax.totalSupply();
      const totalPooled = await spavax.totalPooledAVAX();
      const totalLocked = await spavax.totalLockedInUnlocks();
      
      // totalSupply should be less than initial (user2 burned shares)
      expect(totalSupply).to.be.lt(ethers.parseEther("100"));
      
      // totalPooled should be initial + rewards (no claims yet)
      expect(totalPooled).to.equal(ethers.parseEther("109.2"));
      
      // totalLocked should equal requested unlocks
      expect(totalLocked).to.be.gt(0);
    });
  });
});