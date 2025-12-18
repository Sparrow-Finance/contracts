// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IspAVAX.sol";
import "./interfaces/IWithdrawalQueueNFT.sol";

/**
 * @title spAVAX
 * @author Sparrow Finance
 * @notice Liquid staking vault for AVAX with ERC-4626-like interface and NFT withdrawals
 *
 * @dev This contract provides an ERC-4626-LIKE interface adapted for native AVAX
 *      NOT standard ERC-4626 compliant - documented for transparency
 *
 * ARCHITECTURE DECISIONS (Based on Industry Best Practices):
 *
 * 1. DUAL FLOW SYSTEM (Like Lido's stETH + wstETH pattern):
 *    - Legacy: Simple stake/unstake for basic users
 *    - Modern: ERC-4626-like with NFT for DeFi composability
 *
 * 2. NFT WITHDRAWALS (Inspired by Morpho, Pendle):
 *    - Immediate liquidity via secondary market
 *    - Tradeable unlock positions
 *    - Clean on-chain UX
 *
 * 3. NO REBASING (Like Rocket Pool's rETH):
 *    - Fixed supply increases value per share
 *    - Better for DeFi integrations
 *    - Gas efficient
 *
 * 4. EXTERNAL VALIDATOR MANAGEMENT:
 *    - Smart contract handles accounting only
 *    - Backend handles validator operations
 *    - Separation of concerns
 */
contract spAVAX is
    ERC20Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    IspAVAX
{
    // ============================================
    // CONSTANTS
    // ============================================

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_TOTAL_FEE = 1000; // 10%
    uint256 public constant MIN_UNLOCK_PERIOD = 7 days;
    uint256 public constant MAX_UNLOCK_PERIOD = 30 days;
    uint256 public constant MIN_CLAIM_WINDOW = 1 hours;
    uint256 public constant MAX_CLAIM_WINDOW = 30 days;
    uint256 public constant MAX_UNLOCK_REQUESTS = 100;
    uint256 public constant RESERVE_RATIO = 1000; // 10%

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Withdrawal NFT contract
    IWithdrawalQueueNFT public withdrawalQueueNFT;

    /// @notice Minimum stake amount (default: 0.1 AVAX)
    uint256 public minStakeAmount;

    /// @notice Time required for unlock (default: 60s for testing, 15 days for production)
    uint256 public unlockPeriod;

    /// @notice Time window to claim after unlock (default: 7 days)
    uint256 public claimWindow;

    /// @notice Total AVAX pooled (staked + rewards) - excludes fees and locked
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

    /// @notice User unlock requests (legacy array system)
    mapping(address => IspAVAX.UnlockRequest[]) public unlockRequests;

    // ============================================
    // ERRORS
    // ============================================

    error InvalidAmount();
    error BelowMinimumStake();
    error InsufficientBalance();
    error InsufficientLiquidity();
    error InsufficientShares();
    error SlippageTooHigh();
    error UnlockPeriodNotFinished();
    error ClaimWindowExpired();
    error RequestExpired();
    error AlreadyUnlocked();
    error NotExpired();
    error TooManyRequests();
    error InvalidAddress();
    error InvalidFeeStructure();
    error InvalidRequestIndex();
    error TransferFailed();
    error NotNFTOwner();
    error NFTNotSet();
    error NoFeesToCollect();
    error NoSharesExist();

    // ============================================
    // INITIALIZATION
    // ============================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract (replaces constructor for upgradeable contracts)
     * @param _withdrawalNFT Address of withdrawal NFT contract
     */
    function initialize(address _withdrawalNFT) public initializer {
        __ERC20_init("Sparrow Staked AVAX", "spAVAX");
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        // Set withdrawal NFT
        if (_withdrawalNFT != address(0)) {
            withdrawalQueueNFT = IWithdrawalQueueNFT(_withdrawalNFT);
        }

        // Initialize fees (5% DAO + 3% Dev = 8% total)
        daoFeeBasisPoints = 500;
        devFeeBasisPoints = 300;
        protocolFeeBasisPoints = 800;

        // Initialize parameters
        minStakeAmount = 0.1 ether;
        unlockPeriod = 60; // 60 seconds for testing (change to 15 days for production)
        claimWindow = 7 days;
        totalPooledAVAX = 0;
        totalLockedInUnlocks = 0;
    }

    // ============================================
    // ERC-4626-LIKE INTERFACE (CUSTOM FOR NATIVE AVAX)
    // ============================================

    /**
     * @notice Returns address(0) to indicate native AVAX (not ERC-20)
     * @dev NOT standard ERC-4626 compliant - documented behavior
     */
    function asset() public pure returns (address) {
        return address(0);
    }

    /**
     * @notice Total assets under management (AVAX available to shareholders)
     * @dev Uses totalPooledAVAX which excludes fees and is updated after share calculations
     *      This ensures preview functions match actual minted shares
     * @return Total AVAX backing spAVAX shares
     */
    function totalAssets() public view returns (uint256) {
        return totalPooledAVAX;
    }

    /**
     * @notice Deposit AVAX and receive spAVAX shares (ERC-4626-like)
     * @param receiver Address to receive spAVAX shares
     * @return shares Amount of spAVAX minted
     */
    function deposit(
        address receiver
    ) public payable nonReentrant whenNotPaused returns (uint256 shares) {
        if (msg.value < minStakeAmount) revert BelowMinimumStake();
        if (receiver == address(0)) revert InvalidAddress();

        shares = previewDeposit(msg.value);
        if (shares == 0) revert InsufficientShares();

        totalPooledAVAX += msg.value;
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, msg.value, shares);
        emit Staked(receiver, msg.value, shares);

        return shares;
    }

    /**
     * @notice Mint exact spAVAX shares by depositing AVAX (ERC-4626-like)
     * @param shares Amount of spAVAX shares to mint
     * @param receiver Address to receive shares
     * @return assets Amount of AVAX deposited
     */
    function mint(
        uint256 shares,
        address receiver
    ) public payable nonReentrant whenNotPaused returns (uint256 assets) {
        if (shares == 0) revert InvalidAmount();
        if (receiver == address(0)) revert InvalidAddress();

        assets = previewMint(shares);
        if (msg.value != assets) revert InvalidAmount();
        if (assets < minStakeAmount) revert BelowMinimumStake();

        totalPooledAVAX += assets;
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
        emit Staked(receiver, assets, shares);

        return assets;
    }

    /**
     * @notice Withdraw AVAX by burning spAVAX - MINTS NFT (ERC-4626-like)
     * @dev Burns shares immediately, mints withdrawal NFT to receiver
     * @param assets Amount of AVAX to withdraw
     * @param receiver Address to receive withdrawal NFT
     * @param owner Address that owns the spAVAX shares
     * @return shares Amount of spAVAX burned
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public nonReentrant whenNotPaused returns (uint256 shares) {
        if (assets == 0) revert InvalidAmount();
        if (receiver == address(0)) revert InvalidAddress();
        if (address(withdrawalQueueNFT) == address(0)) revert NFTNotSet();

        shares = previewWithdraw(assets);

        // Check allowance if not owner
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // Burn shares immediately
        _burn(owner, shares);

        // Create withdrawal request and mint NFT
        uint256 unlockTime = block.timestamp + unlockPeriod;
        uint256 expiryTime = unlockTime + claimWindow;

        withdrawalQueueNFT.mint(
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
        emit UnlockRequested(receiver, shares, assets, unlockTime, expiryTime);

        return shares;
    }

    /**
     * @notice Redeem spAVAX shares for AVAX - MINTS NFT (ERC-4626-like)
     * @dev Burns shares immediately, mints withdrawal NFT to receiver
     * @param shares Amount of spAVAX to redeem
     * @param receiver Address to receive withdrawal NFT
     * @param owner Address that owns the spAVAX shares
     * @return assets Amount of AVAX to be received
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public nonReentrant whenNotPaused returns (uint256 assets) {
        if (shares == 0) revert InvalidAmount();
        if (receiver == address(0)) revert InvalidAddress();
        if (address(withdrawalQueueNFT) == address(0)) revert NFTNotSet();

        // Check allowance if not owner
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        assets = previewRedeem(shares);

        // Burn shares immediately
        _burn(owner, shares);

        // Create withdrawal request and mint NFT
        uint256 unlockTime = block.timestamp + unlockPeriod;
        uint256 expiryTime = unlockTime + claimWindow;

        withdrawalQueueNFT.mint(
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
        emit UnlockRequested(receiver, shares, assets, unlockTime, expiryTime);

        return assets;
    }

    // ============================================
    // ERC-4626-LIKE PREVIEW FUNCTIONS
    // ============================================

    /**
     * @notice Preview shares received for depositing assets
     * @param assets Amount of AVAX
     * @return shares Amount of spAVAX
     */
    function previewDeposit(
        uint256 assets
    ) public view returns (uint256 shares) {
        return _convertToShares(assets);
    }

    /**
     * @notice Preview assets needed to mint exact shares
     * @param shares Amount of spAVAX
     * @return assets Amount of AVAX needed
     */
    function previewMint(uint256 shares) public view returns (uint256 assets) {
        return _convertToAssets(shares);
    }

    /**
     * @notice Preview shares needed to withdraw exact assets
     * @param assets Amount of AVAX
     * @return shares Amount of spAVAX needed
     */
    function previewWithdraw(
        uint256 assets
    ) public view returns (uint256 shares) {
        return _convertToShares(assets);
    }

    /**
     * @notice Preview assets received for redeeming shares
     * @param shares Amount of spAVAX
     * @return assets Amount of AVAX
     */
    function previewRedeem(
        uint256 shares
    ) public view returns (uint256 assets) {
        return _convertToAssets(shares);
    }

    // ============================================
    // ERC-4626-LIKE MAX FUNCTIONS
    // ============================================

    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        return _convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }

    // ============================================
    // INTERNAL CONVERSION FUNCTIONS
    // ============================================

    /**
     * @notice Convert AVAX to spAVAX shares
     * @dev Uses totalAssets() which excludes fees and locked
     */
    function _convertToShares(uint256 assets) internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return assets; // 1:1 on first deposit
        }
        return (assets * supply) / totalAssets();
    }

    /**
     * @notice Convert spAVAX shares to AVAX
     * @dev Uses totalAssets() which excludes fees and locked
     */
    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return shares;
        }
        return (shares * totalAssets()) / supply;
    }

    // ============================================
    // ERC-4626 PUBLIC CONVERSION FUNCTIONS
    // ============================================

    /**
     * @notice Convert AVAX to spAVAX shares (public)
     * @param assets Amount of AVAX
     * @return shares Amount of spAVAX
     */
    function convertToShares(
        uint256 assets
    ) public view returns (uint256 shares) {
        return _convertToShares(assets);
    }

    /**
     * @notice Convert spAVAX shares to AVAX (public)
     * @param shares Amount of spAVAX
     * @return assets Amount of AVAX
     */
    function convertToAssets(
        uint256 shares
    ) public view returns (uint256 assets) {
        return _convertToAssets(shares);
    }

    // ============================================
    // NFT WITHDRAWAL FUNCTIONS
    // ============================================

    /**
     * @notice Claim AVAX using withdrawal NFT (after unlock period)
     * @param tokenId NFT token ID
     */
    function claimWithdrawalNFT(
        uint256 tokenId
    ) external nonReentrant whenNotPaused {
        if (withdrawalQueueNFT.ownerOf(tokenId) != msg.sender)
            revert NotNFTOwner();

        IWithdrawalQueueNFT.WithdrawalRequest
            memory request = withdrawalQueueNFT.getRequest(tokenId);

        // Validation
        if (request.avaxAmount == 0) revert InvalidAmount();
        if (block.timestamp < request.unlockTime)
            revert UnlockPeriodNotFinished();
        if (block.timestamp >= request.expiryTime) revert ClaimWindowExpired();

        // Check liquidity
        uint256 balance = address(this).balance;
        uint256 fees = accumulatedDaoFees + accumulatedDevFees;
        if (balance < request.avaxAmount + fees) revert InsufficientLiquidity();

        // Burn NFT
        withdrawalQueueNFT.burn(tokenId);

        // Update accounting
        totalPooledAVAX -= request.avaxAmount;
        totalLockedInUnlocks -= request.avaxAmount;

        // Transfer AVAX
        (bool success, ) = msg.sender.call{value: request.avaxAmount}("");
        if (!success) revert TransferFailed();

        emit Unstaked(msg.sender, request.spAvaxAmount, request.avaxAmount);
    }

    /**
     * @notice Cancel withdrawal NFT and get spAVAX back (before unlock)
     * @param tokenId NFT token ID
     */
    function cancelWithdrawalNFT(
        uint256 tokenId
    ) external nonReentrant whenNotPaused {
        if (withdrawalQueueNFT.ownerOf(tokenId) != msg.sender)
            revert NotNFTOwner();

        IWithdrawalQueueNFT.WithdrawalRequest
            memory request = withdrawalQueueNFT.getRequest(tokenId);

        // Can only cancel BEFORE unlock time
        if (block.timestamp >= request.unlockTime) revert AlreadyUnlocked();

        // Burn NFT
        withdrawalQueueNFT.burn(tokenId);

        // Update accounting
        totalLockedInUnlocks -= request.avaxAmount;

        // Mint spAVAX back to user
        _mint(msg.sender, request.spAvaxAmount);

        emit UnlockCancelled(msg.sender, tokenId, request.spAvaxAmount);
    }

    /**
     * @notice Claim expired NFT and get spAVAX back (after expiry)
     * @param tokenId NFT token ID
     */
    function claimExpiredNFT(
        uint256 tokenId
    ) external nonReentrant whenNotPaused {
        if (withdrawalQueueNFT.ownerOf(tokenId) != msg.sender)
            revert NotNFTOwner();

        IWithdrawalQueueNFT.WithdrawalRequest
            memory request = withdrawalQueueNFT.getRequest(tokenId);

        // Must be expired
        if (block.timestamp < request.expiryTime) revert NotExpired();

        // Burn NFT
        withdrawalQueueNFT.burn(tokenId);

        // Update accounting
        totalLockedInUnlocks -= request.avaxAmount;

        // Mint spAVAX back to user
        _mint(msg.sender, request.spAvaxAmount);

        emit UnlockExpired(msg.sender, tokenId, request.spAvaxAmount);
    }

    // ============================================
    // LEGACY FUNCTIONS (ARRAY-BASED, BACKWARD COMPATIBLE)
    // ============================================

    /**
     * @notice Stake AVAX and receive spAVAX (LEGACY)
     * @param minSpAvaxOut Minimum spAVAX to receive (slippage protection)
     * @return spAvaxAmount Amount of spAVAX minted
     */
    function stake(
        uint256 minSpAvaxOut
    )
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint256 spAvaxAmount)
    {
        if (msg.value < minStakeAmount) revert BelowMinimumStake();

        spAvaxAmount = _convertToShares(msg.value);

        if (spAvaxAmount == 0) revert InsufficientShares();
        if (spAvaxAmount < minSpAvaxOut) revert SlippageTooHigh();

        totalPooledAVAX += msg.value;
        _mint(msg.sender, spAvaxAmount);

        emit Staked(msg.sender, msg.value, spAvaxAmount);
        return spAvaxAmount;
    }

    /**
     * @notice Request to unstake spAVAX (LEGACY ARRAY SYSTEM)
     * @dev Transfers spAVAX to contract, stores in array
     * @param spAvaxAmount Amount of spAVAX to unstake
     * @param minAvaxOut Minimum AVAX to receive (slippage protection)
     * @return avaxAmount Amount of AVAX you'll receive after unlock
     */
    function requestUnlock(
        uint256 spAvaxAmount,
        uint256 minAvaxOut
    ) external nonReentrant whenNotPaused returns (uint256 avaxAmount) {
        if (spAvaxAmount == 0) revert InvalidAmount();
        if (balanceOf(msg.sender) < spAvaxAmount) revert InsufficientBalance();
        if (totalSupply() == 0) revert NoSharesExist();
        if (unlockRequests[msg.sender].length >= MAX_UNLOCK_REQUESTS)
            revert TooManyRequests();

        avaxAmount = _convertToAssets(spAvaxAmount);

        if (avaxAmount == 0) revert InvalidAmount();
        if (avaxAmount < minAvaxOut) revert SlippageTooHigh();

        // Transfer spAVAX to contract (held as collateral)
        _transfer(msg.sender, address(this), spAvaxAmount);

        uint256 unlockTime = block.timestamp + unlockPeriod;
        uint256 expiryTime = unlockTime + claimWindow;

        unlockRequests[msg.sender].push(
            UnlockRequest({
                spAvaxAmount: spAvaxAmount,
                avaxAmount: avaxAmount,
                unlockTime: unlockTime,
                expiryTime: expiryTime
            })
        );

        totalLockedInUnlocks += avaxAmount;

        emit UnlockRequested(
            msg.sender,
            spAvaxAmount,
            avaxAmount,
            unlockTime,
            expiryTime
        );
        return avaxAmount;
    }

    /**
     * @notice Claim unlocked AVAX (LEGACY)
     * @param requestIndex Index of unlock request
     */
    function claimUnlock(
        uint256 requestIndex
    ) external nonReentrant whenNotPaused {
        if (requestIndex >= unlockRequests[msg.sender].length)
            revert InvalidRequestIndex();

        UnlockRequest memory request = unlockRequests[msg.sender][requestIndex];

        if (block.timestamp < request.unlockTime)
            revert UnlockPeriodNotFinished();
        if (block.timestamp >= request.expiryTime) revert ClaimWindowExpired();
        if (request.avaxAmount == 0) revert InvalidAmount();

        uint256 balance = address(this).balance;
        uint256 fees = accumulatedDaoFees + accumulatedDevFees;
        if (balance < request.avaxAmount + fees) revert InsufficientLiquidity();

        // Remove request from array
        uint256 lastIndex = unlockRequests[msg.sender].length - 1;
        if (requestIndex != lastIndex) {
            unlockRequests[msg.sender][requestIndex] = unlockRequests[
                msg.sender
            ][lastIndex];
        }
        unlockRequests[msg.sender].pop();

        // Update accounting
        totalPooledAVAX -= request.avaxAmount;
        totalLockedInUnlocks -= request.avaxAmount;

        // Burn spAVAX from contract
        _burn(address(this), request.spAvaxAmount);

        // Transfer AVAX
        (bool success, ) = msg.sender.call{value: request.avaxAmount}("");
        if (!success) revert TransferFailed();

        emit Unstaked(msg.sender, request.spAvaxAmount, request.avaxAmount);
    }

    /**
     * @notice Cancel unlock request (LEGACY)
     * @param requestIndex Index of unlock request
     */
    function cancelUnlock(
        uint256 requestIndex
    ) external nonReentrant whenNotPaused {
        if (requestIndex >= unlockRequests[msg.sender].length)
            revert InvalidRequestIndex();

        UnlockRequest memory request = unlockRequests[msg.sender][requestIndex];

        // Can only cancel BEFORE unlock time (matches NFT logic)
        if (block.timestamp >= request.unlockTime) revert AlreadyUnlocked();

        // Remove request from array
        uint256 lastIndex = unlockRequests[msg.sender].length - 1;
        if (requestIndex != lastIndex) {
            unlockRequests[msg.sender][requestIndex] = unlockRequests[
                msg.sender
            ][lastIndex];
        }
        unlockRequests[msg.sender].pop();

        // Update accounting
        totalLockedInUnlocks -= request.avaxAmount;

        // Transfer spAVAX back to user
        _transfer(address(this), msg.sender, request.spAvaxAmount);

        emit UnlockCancelled(msg.sender, requestIndex, request.spAvaxAmount);
    }

    /**
     * @notice Claim expired unlock request (LEGACY)
     * @param requestIndex Index of expired request
     */
    function claimExpired(
        uint256 requestIndex
    ) external nonReentrant whenNotPaused {
        if (requestIndex >= unlockRequests[msg.sender].length)
            revert InvalidRequestIndex();

        UnlockRequest memory request = unlockRequests[msg.sender][requestIndex];

        if (block.timestamp < request.expiryTime) revert NotExpired();

        // Remove request from array
        uint256 lastIndex = unlockRequests[msg.sender].length - 1;
        if (requestIndex != lastIndex) {
            unlockRequests[msg.sender][requestIndex] = unlockRequests[
                msg.sender
            ][lastIndex];
        }
        unlockRequests[msg.sender].pop();

        // Update accounting
        totalLockedInUnlocks -= request.avaxAmount;

        // Transfer spAVAX back to user
        _transfer(address(this), msg.sender, request.spAvaxAmount);

        emit UnlockExpired(msg.sender, requestIndex, request.spAvaxAmount);
    }

    // ============================================
    // VIEW FUNCTIONS (LEGACY)
    // ============================================

    function getUnlockRequestCount(
        address user
    ) external view returns (uint256) {
        return unlockRequests[user].length;
    }

    function getUnlockRequest(
        address user,
        uint256 requestIndex
    )
        external
        view
        returns (
            uint256 spAvaxAmount,
            uint256 avaxAmount,
            uint256 unlockTime,
            uint256 expiryTime,
            bool isReady,
            bool isExpired
        )
    {
        if (requestIndex >= unlockRequests[user].length)
            revert InvalidRequestIndex();
        UnlockRequest memory request = unlockRequests[user][requestIndex];

        return (
            request.spAvaxAmount,
            request.avaxAmount,
            request.unlockTime,
            request.expiryTime,
            block.timestamp >= request.unlockTime,
            block.timestamp >= request.expiryTime
        );
    }

    function getExchangeRate() public view returns (uint256) {
        if (totalSupply() == 0 || totalAssets() == 0) {
            return 1e18; // 1:1 ratio
        }
        return (totalAssets() * 1e18) / totalSupply();
    }

    /**
     * @notice Preview how much spAVAX you'll get for AVAX amount (LEGACY)
     * @param avaxAmount Amount of AVAX
     * @return spAvaxAmount Equivalent spAVAX amount
     */
    function previewStake(uint256 avaxAmount) public view returns (uint256 spAvaxAmount) {
        return _convertToShares(avaxAmount);
    }

    /**
     * @notice Preview how much AVAX you'll get for spAVAX amount (LEGACY)
     * @param spAvaxAmount Amount of spAVAX
     * @return avaxAmount Equivalent AVAX amount
     */
    function previewUnlock(uint256 spAvaxAmount) public view returns (uint256 avaxAmount) {
        return _convertToAssets(spAvaxAmount);
    }

    /**
     * @notice Get withdrawal NFT data (convenience function)
     * @param tokenId NFT token ID
     * @return request The withdrawal request data
     * @return isReady Whether the unlock period has passed
     * @return isExpired Whether the claim window has expired
     */
    function getWithdrawalNFTData(uint256 tokenId) 
        external 
        view 
        returns (
            IWithdrawalQueueNFT.WithdrawalRequest memory request,
            bool isReady,
            bool isExpired
        ) 
    {
        request = withdrawalQueueNFT.getRequest(tokenId);
        isReady = withdrawalQueueNFT.isClaimable(tokenId);
        isExpired = withdrawalQueueNFT.isExpired(tokenId);
    }

    function getStats()
        external
        view
        returns (
            uint256 totalStaked,
            uint256 totalShares,
            uint256 exchangeRate,
            uint256 liquidBalance,
            uint256 pendingDaoFees,
            uint256 pendingDevFees,
            uint256 daoFee,
            uint256 devFee
        )
    {
        return (
            totalPooledAVAX,
            totalSupply(),
            getExchangeRate(),
            address(this).balance,
            accumulatedDaoFees,
            accumulatedDevFees,
            daoFeeBasisPoints,
            devFeeBasisPoints
        );
    }

    // ============================================
    // ADMIN FUNCTIONS (OWNER ONLY)
    // ============================================

    /**
     * @notice Withdraw AVAX (for external validator staking via backend)
     * @param amount Amount to withdraw
     */
    function adminWithdraw(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert InvalidAmount();

        uint256 minReserve = (totalPooledAVAX * RESERVE_RATIO) / BASIS_POINTS;
        uint256 committedAVAX = accumulatedDaoFees +
            accumulatedDevFees +
            totalLockedInUnlocks;
        uint256 mustKeep = committedAVAX > minReserve
            ? committedAVAX
            : minReserve;

        if (address(this).balance < amount + mustKeep)
            revert InsufficientLiquidity();

        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Deposit AVAX back (from validator rewards/unstaking)
     */
    function adminDeposit() external payable onlyOwner {
        if (msg.value == 0) revert InvalidAmount();
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @notice Add validator rewards
     * @dev Splits: 92% users, 5% DAO, 3% dev
     */
    function addRewards() external payable onlyOwner {
        if (msg.value == 0) revert InvalidAmount();
        if (totalSupply() == 0) revert NoSharesExist();

        uint256 daoFee = (msg.value * daoFeeBasisPoints) / BASIS_POINTS;
        uint256 devFee = (msg.value * devFeeBasisPoints) / BASIS_POINTS;
        uint256 totalFees = daoFee + devFee;
        uint256 userReward = msg.value - totalFees;

        totalPooledAVAX += userReward;
        accumulatedDaoFees += daoFee;
        accumulatedDevFees += devFee;

        emit RewardsAdded(msg.value, userReward, daoFee, devFee);
    }

    function collectDaoFees() external onlyOwner nonReentrant {
        uint256 fees = accumulatedDaoFees;
        if (fees == 0) revert NoFeesToCollect();
        if (address(this).balance < fees) revert InsufficientBalance();

        accumulatedDaoFees = 0;

        (bool success, ) = msg.sender.call{value: fees}("");
        if (!success) revert TransferFailed();

        emit DaoFeesCollected(msg.sender, fees);
    }

    function collectDevFees() external onlyOwner nonReentrant {
        uint256 fees = accumulatedDevFees;
        if (fees == 0) revert NoFeesToCollect();
        if (address(this).balance < fees) revert InsufficientBalance();

        accumulatedDevFees = 0;

        (bool success, ) = msg.sender.call{value: fees}("");
        if (!success) revert TransferFailed();

        emit DevFeesCollected(msg.sender, fees);
    }

    function collectAllFees() external onlyOwner nonReentrant {
        uint256 totalFees = accumulatedDaoFees + accumulatedDevFees;
        if (totalFees == 0) revert NoFeesToCollect();
        if (address(this).balance < totalFees) revert InsufficientBalance();

        uint256 daoFees = accumulatedDaoFees;
        uint256 devFees = accumulatedDevFees;

        accumulatedDaoFees = 0;
        accumulatedDevFees = 0;

        (bool success, ) = msg.sender.call{value: totalFees}("");
        if (!success) revert TransferFailed();

        emit AllFeesCollected(msg.sender, daoFees, devFees, totalFees);
    }

    function setFeeStructure(
        uint256 newDaoFee,
        uint256 newDevFee
    ) external onlyOwner {
        uint256 totalFee = newDaoFee + newDevFee;
        if (totalFee > MAX_TOTAL_FEE) revert InvalidFeeStructure();

        daoFeeBasisPoints = newDaoFee;
        devFeeBasisPoints = newDevFee;
        protocolFeeBasisPoints = totalFee;

        emit FeeStructureUpdated(protocolFeeBasisPoints, newDaoFee, newDevFee);
    }

    function setMinStakeAmount(uint256 newMinAmount) external onlyOwner {
        if (newMinAmount == 0) revert InvalidAmount();
        uint256 oldAmount = minStakeAmount;
        minStakeAmount = newMinAmount;
        emit MinStakeAmountUpdated(oldAmount, newMinAmount);
    }

    function setUnlockPeriod(uint256 newUnlockPeriod) external onlyOwner {
        if (
            newUnlockPeriod < MIN_UNLOCK_PERIOD ||
            newUnlockPeriod > MAX_UNLOCK_PERIOD
        ) {
            revert InvalidAmount();
        }
        uint256 oldPeriod = unlockPeriod;
        unlockPeriod = newUnlockPeriod;
        emit UnlockPeriodUpdated(oldPeriod, newUnlockPeriod);
    }

    function setClaimWindow(uint256 newClaimWindow) external onlyOwner {
        if (
            newClaimWindow < MIN_CLAIM_WINDOW ||
            newClaimWindow > MAX_CLAIM_WINDOW
        ) {
            revert InvalidAmount();
        }
        uint256 oldWindow = claimWindow;
        claimWindow = newClaimWindow;
        emit ClaimWindowUpdated(oldWindow, newClaimWindow);
    }

    /**
     * @notice Update withdrawal NFT contract address
     * @param newNFT New NFT contract address
     */
    function setWithdrawalNFT(address newNFT) external onlyOwner {
        if (newNFT == address(0)) revert InvalidAddress();
        address oldNFT = address(withdrawalQueueNFT);
        withdrawalQueueNFT = IWithdrawalQueueNFT(newNFT);
        emit WithdrawalNFTUpdated(oldNFT, newNFT);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============================================
    // FALLBACK
    // ============================================

    receive() external payable {
        if (msg.sender != owner()) revert InvalidAddress();
        emit Deposited(msg.sender, msg.value);
    }

    // ============================================
    // UPGRADEABLE
    // ============================================

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
