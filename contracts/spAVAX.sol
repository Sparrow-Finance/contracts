// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IWithdrawalQueueNFT.sol";

/**
 * @title spAVAX
 * @author Sparrow Finance
 * @notice Liquid staking vault for AVAX with ERC-4626 compliance and NFT withdrawals
 * @dev Supports both legacy flow (stake/requestUnlock) and new ERC-4626 flow (deposit/withdraw)
 */
contract spAVAX is
    ERC20Upgradeable,
    ERC4626Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using Math for uint256;

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Withdrawal NFT contract
    IWithdrawalQueueNFT public withdrawalQueueNFT;

    /// @notice Minimum stake amount (default: 0.1 AVAX)
    uint256 public minStakeAmount;

    /// @notice Time required for unlock (default: 60 seconds for testing)
    uint256 public unlockPeriod;

    /// @notice Time window to claim after unlock (default: 7 days)
    uint256 public claimWindow;

    /// @notice Total AVAX pooled (staked + rewards)
    uint256 public totalPooledAVAX;

    /// @notice Total AVAX locked in pending unlocks
    uint256 public totalLockedInUnlocks;

    /// @notice Accumulated DAO fees (5%)
    uint256 public accumulatedDaoFees;

    /// @notice Accumulated dev fees (3%)
    uint256 public accumulatedDevFees;

    /// @notice DAO fee in basis points (500 = 5%)
    uint256 public daoFeeBasisPoints;

    /// @notice Dev fee in basis points (300 = 3%)
    uint256 public devFeeBasisPoints;

    /// @notice Total protocol fee (dao + dev)
    uint256 public protocolFeeBasisPoints;

    /// @notice Governance address
    address public governance;

    /// @notice Pending governance for 2-step transfer
    address public pendingGovernance;

    // Legacy unlock system (for backward compatibility)
    struct UnlockRequest {
        uint256 spAvaxAmount;
        uint256 avaxAmount;
        uint256 unlockTime;
        uint256 expiryTime;
    }

    /// @notice User unlock requests (legacy system)
    mapping(address => UnlockRequest[]) public unlockRequests;

    // ============================================
    // EVENTS
    // ============================================

    event Staked(
        address indexed user,
        uint256 avaxAmount,
        uint256 spAvaxAmount
    );
    event UnlockRequested(
        address indexed user,
        uint256 spAvaxAmount,
        uint256 avaxAmount,
        uint256 unlockTime
    );
    event UnlockClaimed(address indexed user, uint256 avaxAmount);
    event UnlockCanceled(address indexed user, uint256 spAvaxAmount);
    event ExpiredClaimed(address indexed user, uint256 spAvaxAmount);
    event RewardsAdded(uint256 amount, uint256 daoFee, uint256 devFee);
    event DaoFeesCollected(uint256 amount);
    event DevFeesCollected(uint256 amount);
    event AllFeesCollected(uint256 daoAmount, uint256 devAmount);
    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event GovernanceTransferred(
        address indexed previousGovernance,
        address indexed newGovernance
    );
    event WithdrawalNFTClaimed(
        address indexed user,
        uint256 indexed tokenId,
        uint256 avaxAmount
    );
    event WithdrawalNFTCanceled(
        address indexed user,
        uint256 indexed tokenId,
        uint256 spAvaxAmount
    );
    event WithdrawalNFTExpiredClaimed(
        address indexed user,
        uint256 indexed tokenId,
        uint256 spAvaxAmount
    );

    // ============================================
    // ERRORS
    // ============================================

    error InvalidAmount();
    error InsufficientBalance();
    error InsufficientLiquidity();
    error UnlockPeriodNotFinished();
    error ClaimWindowExpired();
    error RequestExpired();
    error AlreadyUnlocked();
    error NotExpired();
    error TooManyRequests();
    error SlippageTooHigh();
    error NotGovernance();
    error InvalidAddress();
    error InvalidFeeStructure();

    // ============================================
    // MODIFIERS
    // ============================================

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        _;
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC20_init("Sparrow Staked AVAX", "spAVAX");
        __ERC4626_init(IERC20(address(0))); // Native AVAX as asset
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();

        governance = msg.sender;
        minStakeAmount = 0.1 ether;
        unlockPeriod = 60; // 60 seconds for testing
        claimWindow = 7 days;

        daoFeeBasisPoints = 500; // 5%
        devFeeBasisPoints = 300; // 3%
        protocolFeeBasisPoints = 800; // 8% total
    }

    function setWithdrawalNFT(address _withdrawalNFT) external onlyGovernance {
        require(address(withdrawalQueueNFT) == address(0), "NFT already set");
        require(_withdrawalNFT != address(0), "Invalid NFT address");
        withdrawalQueueNFT = IWithdrawalQueueNFT(_withdrawalNFT);
    }

    // ============================================
    // ERC-4626 OVERRIDES (Native AVAX Support)
    // ============================================

    /// @notice Override decimals (resolve conflict between ERC20 and ERC4626)
    function decimals()
        public
        view
        virtual
        override(ERC20Upgradeable, ERC4626Upgradeable)
        returns (uint8)
    {
        return 18;
    }

    /// @notice Returns address(0) to indicate native AVAX
    function asset() public pure override returns (address) {
        return address(0);
    }

    /// @notice Total assets = contract balance - fees - locked unlocks
    function totalAssets() public view override returns (uint256) {
        uint256 balance = address(this).balance;
        uint256 committed = accumulatedDaoFees +
            accumulatedDevFees +
            totalLockedInUnlocks;
        return balance > committed ? balance - committed : 0;
    }

    /// @notice Deposit AVAX and receive spAVAX (ERC-4626 compliant) - NOT PAYABLE
    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override whenNotPaused returns (uint256 shares) {
        revert("Use depositAVAX() for native AVAX");
    }

    /// @notice Mint exact shares by depositing AVAX - NOT PAYABLE
    function mint(
        uint256 shares,
        address receiver
    ) public virtual override whenNotPaused returns (uint256 assets) {
        revert("Use mintAVAX() for native AVAX");
    }

    /// @notice Deposit native AVAX (replacement for payable deposit)
    function depositAVAX(
        address receiver
    ) public payable whenNotPaused returns (uint256 shares) {
        uint256 assets = msg.value;
        require(assets >= minStakeAmount, "Below minimum stake");

        shares = previewDeposit(assets);
        require(shares > 0, "Zero shares");

        totalPooledAVAX += assets;
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
        emit Staked(receiver, assets, shares);

        return shares;
    }

    /// @notice Mint exact shares with native AVAX (replacement for payable mint)
    function mintAVAX(
        uint256 shares,
        address receiver
    ) public payable whenNotPaused returns (uint256 assets) {
        assets = previewMint(shares);
        require(msg.value == assets, "msg.value must equal assets");
        require(assets >= minStakeAmount, "Below minimum stake");

        totalPooledAVAX += assets;
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
        emit Staked(receiver, assets, shares);

        return assets;
    }

    /// @notice Withdraw AVAX by burning spAVAX - MINTS NFT instead of immediate transfer
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        require(assets > 0, "Zero assets");

        shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);

        // Mint NFT with withdrawal request
        uint256 unlockTime = block.timestamp + unlockPeriod;
        uint256 expiryTime = unlockTime + claimWindow;

        uint256 tokenId = withdrawalQueueNFT.mint(
            receiver,
            IWithdrawalQueueNFT.WithdrawalRequest({
                spAvaxAmount: shares,
                avaxAmount: assets,
                unlockTime: unlockTime,
                expiryTime: expiryTime
            })
        );

        totalLockedInUnlocks += assets;

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return shares;
    }

    /// @notice Redeem spAVAX for AVAX - MINTS NFT instead of immediate transfer
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        require(shares > 0, "Zero shares");

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        assets = previewRedeem(shares);
        _burn(owner, shares);

        // Mint NFT with withdrawal request
        uint256 unlockTime = block.timestamp + unlockPeriod;
        uint256 expiryTime = unlockTime + claimWindow;

        uint256 tokenId = withdrawalQueueNFT.mint(
            receiver,
            IWithdrawalQueueNFT.WithdrawalRequest({
                spAvaxAmount: shares,
                avaxAmount: assets,
                unlockTime: unlockTime,
                expiryTime: expiryTime
            })
        );

        totalLockedInUnlocks += assets;

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return assets;
    }

    /// @notice Preview how many shares for given assets
    function previewDeposit(
        uint256 assets
    ) public view override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /// @notice Preview how many assets for given shares
    function previewMint(
        uint256 shares
    ) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    /// @notice Preview how many shares to burn for assets
    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    /// @notice Preview how many assets for shares
    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /// @notice Max deposit (unlimited for AVAX)
    function maxDeposit(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Max mint (unlimited)
    function maxMint(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Max withdraw = user's AVAX balance
    function maxWithdraw(address owner) public view override returns (uint256) {
        return _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
    }

    /// @notice Max redeem = user's share balance
    function maxRedeem(address owner) public view override returns (uint256) {
        return balanceOf(owner);
    }

    // ============================================
    // INTERNAL CONVERSION OVERRIDES
    // ============================================

    /// @dev Override to use totalPooledAVAX for conversions
    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return assets; // 1:1 ratio on first deposit
        }

        // shares = assets * totalSupply / totalPooledAVAX
        return assets.mulDiv(supply, totalPooledAVAX, rounding);
    }

    /// @dev Override to use totalPooledAVAX for conversions
    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return shares; // 1:1 ratio (should never happen)
        }

        // assets = shares * totalPooledAVAX / totalSupply
        return shares.mulDiv(totalPooledAVAX, supply, rounding);
    }

    // ============================================
    // NFT WITHDRAWAL FUNCTIONS
    // ============================================

    /// @notice Claim AVAX using withdrawal NFT (after unlock period)
    /// @dev Can only be called between unlockTime and expiryTime
    function claimWithdrawalNFT(uint256 tokenId) external {
        require(
            withdrawalQueueNFT.ownerOf(tokenId) == msg.sender,
            "Not NFT owner"
        );

        IWithdrawalQueueNFT.WithdrawalRequest memory request = 
            withdrawalQueueNFT.getRequest(tokenId);

        require(
            block.timestamp >= request.unlockTime,
            "Unlock period not finished"
        );
        require(
            block.timestamp < request.expiryTime,
            "Claim window expired"
        );

        // Check liquidity
        uint256 balance = address(this).balance;
        uint256 fees = accumulatedDaoFees + accumulatedDevFees;
        require(
            balance >= request.avaxAmount + fees,
            "Insufficient liquidity"
        );

        // Burn NFT
        withdrawalQueueNFT.burn(tokenId);

        // Update accounting (match legacy claimUnlock)
        totalPooledAVAX -= request.avaxAmount;
        totalLockedInUnlocks -= request.avaxAmount;

        // Transfer AVAX
        (bool success, ) = msg.sender.call{value: request.avaxAmount}("");
        require(success, "AVAX transfer failed");

        emit WithdrawalNFTClaimed(msg.sender, tokenId, request.avaxAmount);
    }

    /// @notice Cancel withdrawal NFT and get spAVAX back (before unlock time)
    /// @dev Can only cancel BEFORE unlockTime to prevent rate gaming
    function cancelWithdrawalNFT(uint256 tokenId) external {
        require(
            withdrawalQueueNFT.ownerOf(tokenId) == msg.sender,
            "Not NFT owner"
        );

        IWithdrawalQueueNFT.WithdrawalRequest memory request = 
            withdrawalQueueNFT.getRequest(tokenId);

        require(
            block.timestamp < request.unlockTime,
            "Already unlocked, cannot cancel"
        );

        // Burn NFT
        withdrawalQueueNFT.burn(tokenId);

        // Update accounting
        totalLockedInUnlocks -= request.avaxAmount;

        _mint(msg.sender, request.spAvaxAmount);

        emit WithdrawalNFTCanceled(msg.sender, tokenId, request.spAvaxAmount);
    }

    /// @notice Claim expired NFT and get spAVAX back (after expiry time)
    /// @dev Can only be called after expiryTime
    function claimExpiredNFT(uint256 tokenId) external {
        require(
            withdrawalQueueNFT.ownerOf(tokenId) == msg.sender,
            "Not NFT owner"
        );

        IWithdrawalQueueNFT.WithdrawalRequest memory request = 
            withdrawalQueueNFT.getRequest(tokenId);

        require(
            block.timestamp >= request.expiryTime,
            "Not expired yet"
        );

        // Burn NFT
        withdrawalQueueNFT.burn(tokenId);

        // Update accounting
        totalLockedInUnlocks -= request.avaxAmount;

        _mint(msg.sender, request.spAvaxAmount);

        emit WithdrawalNFTExpiredClaimed(msg.sender, tokenId, request.spAvaxAmount);
    }

    // ============================================
    // LEGACY FUNCTIONS (Backward Compatibility)
    // ============================================

    /// @notice Legacy stake function (calls depositAVAX internally)
    function stake(
        uint256 minSpAvaxOut
    ) external payable whenNotPaused returns (uint256) {
        require(msg.value >= minStakeAmount, "Below minimum stake");

        uint256 shares = previewDeposit(msg.value);
        require(shares >= minSpAvaxOut, "Slippage too high");

        return depositAVAX(msg.sender);
    }

    /// @notice Legacy unlock request (array-based system)
    function requestUnlock(
        uint256 spAvaxAmount,
        uint256 minAvaxOut
    ) external returns (uint256) {
        require(spAvaxAmount > 0, "Zero amount");
        require(balanceOf(msg.sender) >= spAvaxAmount, "Insufficient balance");
        require(
            unlockRequests[msg.sender].length < 100,
            "Too many pending requests"
        );

        uint256 avaxAmount = previewRedeem(spAvaxAmount);
        require(avaxAmount >= minAvaxOut, "Slippage too high");

        // Transfer spAVAX to contract
        _transfer(msg.sender, address(this), spAvaxAmount);

        unlockRequests[msg.sender].push(
            UnlockRequest({
                spAvaxAmount: spAvaxAmount,
                avaxAmount: avaxAmount,
                unlockTime: block.timestamp + unlockPeriod,
                expiryTime: block.timestamp + unlockPeriod + claimWindow
            })
        );

        totalLockedInUnlocks += avaxAmount;

        emit UnlockRequested(
            msg.sender,
            spAvaxAmount,
            avaxAmount,
            block.timestamp + unlockPeriod
        );

        return unlockRequests[msg.sender].length - 1;
    }

    /// @notice Legacy claim unlock (array-based system)
    function claimUnlock(uint256 index) external {
        require(index < unlockRequests[msg.sender].length, "Invalid index");

        UnlockRequest memory request = unlockRequests[msg.sender][index];
        require(request.spAvaxAmount > 0, "Request already claimed");
        require(
            block.timestamp >= request.unlockTime,
            "Unlock period not finished"
        );
        require(
            block.timestamp < request.expiryTime,
            "Claim window expired"
        );

        // Check liquidity
        uint256 balance = address(this).balance;
        uint256 fees = accumulatedDaoFees + accumulatedDevFees;
        require(
            balance >= request.avaxAmount + fees,
            "Insufficient liquidity"
        );

        // Clear request and burn spAVAX
        delete unlockRequests[msg.sender][index];
        _burn(address(this), request.spAvaxAmount);

        // Update accounting
        totalPooledAVAX -= request.avaxAmount;
        totalLockedInUnlocks -= request.avaxAmount;

        (bool success, ) = msg.sender.call{value: request.avaxAmount}("");
        require(success, "AVAX transfer failed");

        emit UnlockClaimed(msg.sender, request.avaxAmount);
    }

    /// @notice Legacy cancel unlock
    function cancelUnlock(uint256 index) external {
        require(index < unlockRequests[msg.sender].length, "Invalid index");

        UnlockRequest memory request = unlockRequests[msg.sender][index];
        require(request.spAvaxAmount > 0, "Request already claimed");
        require(
            block.timestamp < request.expiryTime,
            "Request expired, use claimExpired"
        );

        // Clear request
        delete unlockRequests[msg.sender][index];
        totalLockedInUnlocks -= request.avaxAmount;

        // Return original spAVAX amount (locked rate)
        _transfer(address(this), msg.sender, request.spAvaxAmount);

        emit UnlockCanceled(msg.sender, request.spAvaxAmount);
    }

    /// @notice Legacy claim expired
    function claimExpired(uint256 index) external {
        require(index < unlockRequests[msg.sender].length, "Invalid index");

        UnlockRequest memory request = unlockRequests[msg.sender][index];
        require(request.spAvaxAmount > 0, "Request already claimed");
        require(
            block.timestamp >= request.expiryTime,
            "Not expired yet"
        );

        // Clear request
        delete unlockRequests[msg.sender][index];
        totalLockedInUnlocks -= request.avaxAmount;

        // Return original spAVAX amount (locked rate)
        _transfer(address(this), msg.sender, request.spAvaxAmount);

        emit ExpiredClaimed(msg.sender, request.spAvaxAmount);
    }

    /// @notice Get unlock request count for user
    function getUnlockRequestCount(
        address user
    ) external view returns (uint256) {
        return unlockRequests[user].length;
    }

    /// @notice Get specific unlock request
    function getUnlockRequest(
        address user,
        uint256 index
    )
        external
        view
        returns (
            uint256 spAvaxAmount,
            uint256 avaxAmount,
            uint256 unlockTime,
            uint256 expiryTime
        )
    {
        require(index < unlockRequests[user].length, "Invalid index");
        UnlockRequest memory request = unlockRequests[user][index];
        return (
            request.spAvaxAmount,
            request.avaxAmount,
            request.unlockTime,
            request.expiryTime
        );
    }

    // ============================================
    // REWARDS & FEES
    // ============================================

    /// @notice Add staking rewards
    function addRewards() external payable onlyGovernance {
        require(msg.value > 0, "Reward must be > 0");

        uint256 daoFee = (msg.value * daoFeeBasisPoints) / 10000;
        uint256 devFee = (msg.value * devFeeBasisPoints) / 10000;
        uint256 netReward = msg.value - daoFee - devFee;

        accumulatedDaoFees += daoFee;
        accumulatedDevFees += devFee;
        totalPooledAVAX += netReward;

        emit RewardsAdded(msg.value, daoFee, devFee);
    }

    /// @notice Collect DAO fees
    function collectDaoFees() external onlyGovernance {
        uint256 amount = accumulatedDaoFees;
        require(amount > 0, "No fees to collect");

        accumulatedDaoFees = 0;

        (bool success, ) = governance.call{value: amount}("");
        require(success, "Transfer failed");

        emit DaoFeesCollected(amount);
    }

    /// @notice Collect dev fees
    function collectDevFees() external onlyGovernance {
        uint256 amount = accumulatedDevFees;
        require(amount > 0, "No fees to collect");

        accumulatedDevFees = 0;

        (bool success, ) = governance.call{value: amount}("");
        require(success, "Transfer failed");

        emit DevFeesCollected(amount);
    }

    /// @notice Collect all fees
    function collectAllFees() external onlyGovernance {
        uint256 daoAmount = accumulatedDaoFees;
        uint256 devAmount = accumulatedDevFees;
        uint256 total = daoAmount + devAmount;

        require(total > 0, "No fees to collect");

        accumulatedDaoFees = 0;
        accumulatedDevFees = 0;

        (bool success, ) = governance.call{value: total}("");
        require(success, "Transfer failed");

        emit AllFeesCollected(daoAmount, devAmount);
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /// @notice Deposit AVAX to contract (governance only)
    function deposit() external payable onlyGovernance {
        emit Deposited(msg.value);
    }

    /// @notice Withdraw excess AVAX (protecting commitments)
    function withdraw(uint256 amount) external onlyGovernance {
        uint256 balance = address(this).balance;
        uint256 committed = accumulatedDaoFees +
            accumulatedDevFees +
            totalLockedInUnlocks;

        require(
            balance >= committed + amount,
            "Insufficient liquidity after commitments"
        );

        (bool success, ) = governance.call{value: amount}("");
        require(success, "Transfer failed");

        emit Withdrawn(amount);
    }

    /// @notice Set fee structure
    function setFeeStructure(
        uint256 _daoFeeBasisPoints,
        uint256 _devFeeBasisPoints
    ) external onlyGovernance {
        require(_daoFeeBasisPoints <= 10000, "DAO fee too high");
        require(_devFeeBasisPoints <= 10000, "Dev fee too high");
        require(
            _daoFeeBasisPoints + _devFeeBasisPoints <= 1000,
            "Total fees too high (max 10%)"
        );

        daoFeeBasisPoints = _daoFeeBasisPoints;
        devFeeBasisPoints = _devFeeBasisPoints;
        protocolFeeBasisPoints = _daoFeeBasisPoints + _devFeeBasisPoints;
    }

    /// @notice Set minimum stake amount
    function setMinStakeAmount(
        uint256 _minStakeAmount
    ) external onlyGovernance {
        minStakeAmount = _minStakeAmount;
    }

    /// @notice Set unlock period
    function setUnlockPeriod(uint256 _unlockPeriod) external onlyGovernance {
        unlockPeriod = _unlockPeriod;
    }

    /// @notice Set claim window
    function setClaimWindow(uint256 _claimWindow) external onlyGovernance {
        claimWindow = _claimWindow;
    }

    /// @notice Pause contract
    function pause() external onlyGovernance {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() external onlyGovernance {
        _unpause();
    }

    /// @notice Transfer governance (2-step)
    function transferGovernance(address newGovernance) external onlyGovernance {
        require(newGovernance != address(0), "Invalid address");
        pendingGovernance = newGovernance;
    }

    /// @notice Accept governance
    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "Not pending governance");

        address oldGovernance = governance;
        governance = pendingGovernance;
        pendingGovernance = address(0);

        emit GovernanceTransferred(oldGovernance, governance);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /// @notice Get exchange rate (1 spAVAX = X AVAX)
    function getExchangeRate() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return 1e18;
        return (totalPooledAVAX * 1e18) / supply;
    }

    /// @notice Preview stake (legacy)
    function previewStake(uint256 avaxAmount) external view returns (uint256) {
        return previewDeposit(avaxAmount);
    }

    /// @notice Preview unlock (legacy)
    function previewUnlock(
        uint256 spAvaxAmount
    ) external view returns (uint256) {
        return previewRedeem(spAvaxAmount);
    }

    /// @notice Get protocol stats
    function getStats()
        external
        view
        returns (
            uint256 _totalPooledAVAX,
            uint256 _totalSupply,
            uint256 _exchangeRate,
            uint256 _totalLockedInUnlocks,
            uint256 _accumulatedDaoFees,
            uint256 _accumulatedDevFees
        )
    {
        uint256 supply = totalSupply();
        uint256 rate = supply == 0 ? 1e18 : (totalPooledAVAX * 1e18) / supply;

        return (
            totalPooledAVAX,
            supply,
            rate,
            totalLockedInUnlocks,
            accumulatedDaoFees,
            accumulatedDevFees
        );
    }

    // ============================================
    // INTERNAL
    // ============================================

    /// @dev Required for UUPS upgrades
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /// @dev Accept AVAX from governance
    receive() external payable {
        require(msg.sender == governance, "Use stake() function");
        emit Deposited(msg.value);
    }
}