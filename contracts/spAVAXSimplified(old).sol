// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title spAVAX - Sparrow Staked AVAX (Simplified)
 * @author Cypher Networks
 * @notice Simple liquid staking token for Avalanche Fuji testnet
 * 
 * How it works:
 * 1. Users stake AVAX → receive spAVAX tokens
 * 2. spAVAX value increases as validator rewards are added
 * 3. Users request unlock → wait unlock period → claim AVAX within claim window
 * 4. Protocol earns 5% fee on validator rewards
 * 
 * Exchange Rate: 1 spAVAX = totalPooledAVAX / totalSupply()
 * Unlock System: 60s unlock period + 7 day claim window (configurable)
 */
contract spAVAXSimplified is ERC20, Ownable, ReentrancyGuard, Pausable {
    
    // ============================================
    // STATE VARIABLES
    // ============================================
    
    /// @notice Total AVAX controlled by protocol (includes staked with validators)
    uint256 public totalPooledAVAX;
    
    /// @notice Validator fee (5% = 500 basis points out of 10000)
    uint256 public validatorFeeBasisPoints = 500;
    
    /// @notice Protocol fee (5% = 500 basis points out of 10000)
    uint256 public protocolFeeBasisPoints = 500;
    
    /// @notice DAO treasury fee (2.5% = 250 basis points out of 10000)
    uint256 public daoFeeBasisPoints = 250;
    
    /// @notice Development fund fee (2.5% = 250 basis points out of 10000)
    uint256 public devFeeBasisPoints = 250;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_TOTAL_FEE = 2000; // Max 20% total fees
    
    /// @notice Accumulated validator fees
    uint256 public accumulatedValidatorFees;
    
    /// @notice Accumulated DAO treasury fees
    uint256 public accumulatedDaoFees;
    
    /// @notice Accumulated development fees
    uint256 public accumulatedDevFees;
    
    /// @notice Minimum stake amount (0.1 AVAX)
    uint256 public minStakeAmount = 0.1 ether;
    
    /// @notice Unlock period for withdrawals (default 60 seconds for testing, increase for mainnet)
    uint256 public unlockPeriod = 60; // seconds
    
    /// @notice Claim window - time after unlock to claim before expiring (default 7 days)
    uint256 public claimWindow = 7 days; // 604800 seconds
    
    /// @notice Struct to track unlock requests
    struct UnlockRequest {
        uint256 spAvaxAmount;
        uint256 avaxAmount;
        uint256 unlockTime;
        uint256 expiryTime;
    }
    
    /// @notice Mapping of user addresses to their unlock requests
    mapping(address => UnlockRequest[]) public unlockRequests;
    
    // ============================================
    // EVENTS
    // ============================================
    
    event Staked(address indexed user, uint256 avaxAmount, uint256 spAvaxAmount);
    event UnlockRequested(address indexed user, uint256 spAvaxAmount, uint256 avaxAmount, uint256 unlockTime, uint256 expiryTime);
    event Unstaked(address indexed user, uint256 spAvaxAmount, uint256 avaxAmount);
    event UnlockCancelled(address indexed user, uint256 index, uint256 spAvaxAmount);
    event UnlockExpired(address indexed user, uint256 index, uint256 spAvaxAmount);
    event RewardsAdded(uint256 totalReward, uint256 userReward, uint256 validatorFee, uint256 daoFee, uint256 devFee);
    event Withdrawn(address indexed to, uint256 amount);
    event Deposited(address indexed from, uint256 amount);
    event ValidatorFeesCollected(address indexed to, uint256 amount);
    event DaoFeesCollected(address indexed to, uint256 amount);
    event DevFeesCollected(address indexed to, uint256 amount);
    event UnlockPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event ClaimWindowUpdated(uint256 oldWindow, uint256 newWindow);
    event FeeStructureUpdated(uint256 validatorFee, uint256 protocolFee, uint256 daoFee, uint256 devFee);
    event MinStakeAmountUpdated(uint256 oldAmount, uint256 newAmount);
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    constructor() ERC20("Sparrow Staked AVAX", "spAVAX") Ownable(msg.sender) {
        totalPooledAVAX = 0;
    }
    
    // ============================================
    // USER FUNCTIONS
    // ============================================
    
    /**
     * @notice Stake AVAX and receive spAVAX tokens
     * @return spAvaxAmount Amount of spAVAX minted
     */
    function stake() external payable nonReentrant whenNotPaused returns (uint256 spAvaxAmount) {
        require(msg.value >= minStakeAmount, "Below minimum stake");
        
        // Calculate spAVAX to mint based on exchange rate
        if (totalSupply() == 0 || totalPooledAVAX == 0) {
            // First staker gets 1:1 ratio
            spAvaxAmount = msg.value;
        } else {
            // spAVAX = (AVAX deposited * total spAVAX) / total pooled AVAX
            spAvaxAmount = (msg.value * totalSupply()) / totalPooledAVAX;
        }
        
        require(spAvaxAmount > 0, "Invalid amount");
        
        // Update state
        totalPooledAVAX += msg.value;
        
        // Mint spAVAX to user
        _mint(msg.sender, spAvaxAmount);
        
        emit Staked(msg.sender, msg.value, spAvaxAmount);
        return spAvaxAmount;
    }
    
    /**
     * @notice Request to unstake spAVAX (starts unlock timer)
     * @param spAvaxAmount Amount of spAVAX to unstake
     * @return avaxAmount Amount of AVAX you'll receive after unlock period
     */
    function requestUnlock(uint256 spAvaxAmount) external nonReentrant whenNotPaused returns (uint256 avaxAmount) {
        require(spAvaxAmount > 0, "Amount must be > 0");
        require(balanceOf(msg.sender) >= spAvaxAmount, "Insufficient balance");
        require(totalSupply() > 0, "No shares exist");
        
        // Calculate AVAX to return based on current exchange rate
        avaxAmount = (spAvaxAmount * totalPooledAVAX) / totalSupply();
        require(avaxAmount > 0, "Invalid AVAX amount");
        
        // Transfer spAVAX to contract (locked during unlock period)
        _transfer(msg.sender, address(this), spAvaxAmount);
        
        // Create unlock request
        uint256 unlockTime = block.timestamp + unlockPeriod;
        uint256 expiryTime = unlockTime + claimWindow;
        
        unlockRequests[msg.sender].push(UnlockRequest({
            spAvaxAmount: spAvaxAmount,
            avaxAmount: avaxAmount,
            unlockTime: unlockTime,
            expiryTime: expiryTime
        }));
        
        emit UnlockRequested(msg.sender, spAvaxAmount, avaxAmount, unlockTime, expiryTime);
        return avaxAmount;
    }
    
    /**
     * @notice Claim unlocked AVAX after unlock period has passed
     * @param requestIndex Index of the unlock request to claim
     */
    function claimUnlock(uint256 requestIndex) external nonReentrant whenNotPaused {
        require(requestIndex < unlockRequests[msg.sender].length, "Invalid request index");
        
        UnlockRequest memory request = unlockRequests[msg.sender][requestIndex];
        require(block.timestamp >= request.unlockTime, "Unlock period not finished");
        require(block.timestamp <= request.expiryTime, "Claim window expired");
        require(address(this).balance >= request.avaxAmount, "Insufficient liquidity");
        
        // Remove unlock request (swap with last and pop)
        unlockRequests[msg.sender][requestIndex] = unlockRequests[msg.sender][unlockRequests[msg.sender].length - 1];
        unlockRequests[msg.sender].pop();
        
        // Update state
        totalPooledAVAX -= request.avaxAmount;
        
        // Burn spAVAX
        _burn(address(this), request.spAvaxAmount);
        
        // Send AVAX to user
        (bool success, ) = msg.sender.call{value: request.avaxAmount}("");
        require(success, "Transfer failed");
        
        emit Unstaked(msg.sender, request.spAvaxAmount, request.avaxAmount);
    }
    
    /**
     * @notice Cancel an unlock request and get spAVAX back (before expiry)
     * @param requestIndex Index of the unlock request to cancel
     */
    function cancelUnlock(uint256 requestIndex) external nonReentrant whenNotPaused {
        require(requestIndex < unlockRequests[msg.sender].length, "Invalid request index");
        
        UnlockRequest memory request = unlockRequests[msg.sender][requestIndex];
        require(block.timestamp <= request.expiryTime, "Request expired, use claimExpired");
        
        // Remove unlock request
        unlockRequests[msg.sender][requestIndex] = unlockRequests[msg.sender][unlockRequests[msg.sender].length - 1];
        unlockRequests[msg.sender].pop();
        
        // Return spAVAX to user
        _transfer(address(this), msg.sender, request.spAvaxAmount);
        
        emit UnlockCancelled(msg.sender, requestIndex, request.spAvaxAmount);
    }
    
    /**
     * @notice Claim expired unlock request (returns spAVAX after claim window expires)
     * @param requestIndex Index of the expired unlock request
     */
    function claimExpired(uint256 requestIndex) external nonReentrant whenNotPaused {
        require(requestIndex < unlockRequests[msg.sender].length, "Invalid request index");
        
        UnlockRequest memory request = unlockRequests[msg.sender][requestIndex];
        require(block.timestamp > request.expiryTime, "Not expired yet");
        
        // Remove unlock request
        unlockRequests[msg.sender][requestIndex] = unlockRequests[msg.sender][unlockRequests[msg.sender].length - 1];
        unlockRequests[msg.sender].pop();
        
        // Return spAVAX to user
        _transfer(address(this), msg.sender, request.spAvaxAmount);
        
        emit UnlockExpired(msg.sender, requestIndex, request.spAvaxAmount);
    }
    
    /**
     * @notice Get number of pending unlock requests for a user
     * @param user User address
     * @return count Number of pending requests
     */
    function getUnlockRequestCount(address user) external view returns (uint256 count) {
        return unlockRequests[user].length;
    }
    
    /**
     * @notice Get details of a specific unlock request
     * @param user User address
     * @param requestIndex Index of the request
     * @return spAvaxAmount Amount of spAVAX locked
     * @return avaxAmount Amount of AVAX to receive
     * @return unlockTime Timestamp when unlock is available
     * @return expiryTime Timestamp when claim window expires
     * @return isReady Whether the unlock period has passed
     * @return isExpired Whether the claim window has expired
     */
    function getUnlockRequest(address user, uint256 requestIndex) external view returns (
        uint256 spAvaxAmount,
        uint256 avaxAmount,
        uint256 unlockTime,
        uint256 expiryTime,
        bool isReady,
        bool isExpired
    ) {
        require(requestIndex < unlockRequests[user].length, "Invalid request index");
        UnlockRequest memory request = unlockRequests[user][requestIndex];
        return (
            request.spAvaxAmount,
            request.avaxAmount,
            request.unlockTime,
            request.expiryTime,
            block.timestamp >= request.unlockTime,
            block.timestamp > request.expiryTime
        );
    }
    
    /**
     * @notice Get current exchange rate (how much AVAX 1 spAVAX is worth)
     * @return rate Exchange rate scaled by 1e18 (1e18 = 1:1 ratio)
     */
    function getExchangeRate() public view returns (uint256 rate) {
        if (totalSupply() == 0 || totalPooledAVAX == 0) {
            return 1e18; // 1:1 ratio
        }
        return (totalPooledAVAX * 1e18) / totalSupply();
    }
    
    /**
     * @notice Preview how much spAVAX you'll get for AVAX amount
     * @param avaxAmount Amount of AVAX
     * @return spAvaxAmount Equivalent spAVAX amount
     */
    function previewStake(uint256 avaxAmount) public view returns (uint256 spAvaxAmount) {
        if (totalSupply() == 0 || totalPooledAVAX == 0) {
            return avaxAmount;
        }
        return (avaxAmount * totalSupply()) / totalPooledAVAX;
    }
    
    /**
     * @notice Preview how much AVAX you'll get for spAVAX amount
     * @param spAvaxAmount Amount of spAVAX
     * @return avaxAmount Equivalent AVAX amount
     */
    function previewUnlock(uint256 spAvaxAmount) public view returns (uint256 avaxAmount) {
        if (totalSupply() == 0) {
            return 0;
        }
        return (spAvaxAmount * totalPooledAVAX) / totalSupply();
    }
    
    // ============================================
    // ADMIN FUNCTIONS (OWNER ONLY)
    // ============================================
    
    /**
     * @notice Withdraw AVAX to stake with validators
     * @param amount Amount of AVAX to withdraw
     */
    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Amount must be > 0");
        require(address(this).balance >= amount, "Insufficient balance");
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit Withdrawn(msg.sender, amount);
    }
    
    /**
     * @notice Deposit AVAX back from validators (adds liquidity)
     */
    function deposit() external payable onlyOwner {
        require(msg.value > 0, "Amount must be > 0");
        emit Deposited(msg.sender, msg.value);
    }
    
    /**
     * @notice Add validator rewards with fee distribution
     * @param rewardAmount Total rewards earned from validators
     * @dev Splits fees: 5% validators, 5% protocol (2.5% DAO + 2.5% dev), 90% users
     */
    function addRewards(uint256 rewardAmount) external onlyOwner {
        require(rewardAmount > 0, "Reward must be > 0");
        
        // Calculate fees
        uint256 validatorFee = (rewardAmount * validatorFeeBasisPoints) / BASIS_POINTS;
        uint256 daoFee = (rewardAmount * daoFeeBasisPoints) / BASIS_POINTS;
        uint256 devFee = (rewardAmount * devFeeBasisPoints) / BASIS_POINTS;
        uint256 totalFees = validatorFee + daoFee + devFee;
        uint256 userReward = rewardAmount - totalFees;
        
        // Add user rewards to pool (increases spAVAX value)
        totalPooledAVAX += userReward;
        
        // Track fees separately
        accumulatedValidatorFees += validatorFee;
        accumulatedDaoFees += daoFee;
        accumulatedDevFees += devFee;
        
        emit RewardsAdded(rewardAmount, userReward, validatorFee, daoFee, devFee);
    }
    
    /**
     * @notice Collect accumulated validator fees
     */
    function collectValidatorFees() external onlyOwner nonReentrant {
        uint256 fees = accumulatedValidatorFees;
        require(fees > 0, "No validator fees to collect");
        require(address(this).balance >= fees, "Insufficient balance");
        
        accumulatedValidatorFees = 0;
        
        (bool success, ) = msg.sender.call{value: fees}("");
        require(success, "Transfer failed");
        
        emit ValidatorFeesCollected(msg.sender, fees);
    }
    
    /**
     * @notice Collect accumulated DAO treasury fees
     */
    function collectDaoFees() external onlyOwner nonReentrant {
        uint256 fees = accumulatedDaoFees;
        require(fees > 0, "No DAO fees to collect");
        require(address(this).balance >= fees, "Insufficient balance");
        
        accumulatedDaoFees = 0;
        
        (bool success, ) = msg.sender.call{value: fees}("");
        require(success, "Transfer failed");
        
        emit DaoFeesCollected(msg.sender, fees);
    }
    
    /**
     * @notice Collect accumulated development fees
     */
    function collectDevFees() external onlyOwner nonReentrant {
        uint256 fees = accumulatedDevFees;
        require(fees > 0, "No dev fees to collect");
        require(address(this).balance >= fees, "Insufficient balance");
        
        accumulatedDevFees = 0;
        
        (bool success, ) = msg.sender.call{value: fees}("");
        require(success, "Transfer failed");
        
        emit DevFeesCollected(msg.sender, fees);
    }
    
    /**
     * @notice Collect all accumulated fees at once
     */
    function collectAllFees() external onlyOwner nonReentrant {
        uint256 totalFees = accumulatedValidatorFees + accumulatedDaoFees + accumulatedDevFees;
        require(totalFees > 0, "No fees to collect");
        require(address(this).balance >= totalFees, "Insufficient balance");
        
        uint256 validatorFees = accumulatedValidatorFees;
        uint256 daoFees = accumulatedDaoFees;
        uint256 devFees = accumulatedDevFees;
        
        accumulatedValidatorFees = 0;
        accumulatedDaoFees = 0;
        accumulatedDevFees = 0;
        
        (bool success, ) = msg.sender.call{value: totalFees}("");
        require(success, "Transfer failed");
        
        if (validatorFees > 0) emit ValidatorFeesCollected(msg.sender, validatorFees);
        if (daoFees > 0) emit DaoFeesCollected(msg.sender, daoFees);
        if (devFees > 0) emit DevFeesCollected(msg.sender, devFees);
    }
    
    /**
     * @notice Update fee structure
     * @param newValidatorFee Validator fee in basis points
     * @param newDaoFee DAO treasury fee in basis points
     * @param newDevFee Development fee in basis points
     * @dev Total fees cannot exceed 20% (2000 basis points)
     */
    function setFeeStructure(
        uint256 newValidatorFee,
        uint256 newDaoFee,
        uint256 newDevFee
    ) external onlyOwner {
        uint256 totalFee = newValidatorFee + newDaoFee + newDevFee;
        require(totalFee <= MAX_TOTAL_FEE, "Total fees too high (max 20%)");
        
        validatorFeeBasisPoints = newValidatorFee;
        daoFeeBasisPoints = newDaoFee;
        devFeeBasisPoints = newDevFee;
        protocolFeeBasisPoints = newDaoFee + newDevFee; // Combined protocol fee
        
        emit FeeStructureUpdated(newValidatorFee, protocolFeeBasisPoints, newDaoFee, newDevFee);
    }
    
    /**
     * @notice Update minimum stake amount
     * @param newMinAmount New minimum in wei
     */
    function setMinStakeAmount(uint256 newMinAmount) external onlyOwner {
        require(newMinAmount > 0, "Min amount must be > 0");
        uint256 oldAmount = minStakeAmount;
        minStakeAmount = newMinAmount;
        emit MinStakeAmountUpdated(oldAmount, newMinAmount);
    }
    
    /**
     * @notice Update unlock period
     * @param newUnlockPeriod New unlock period in seconds
     */
    function setUnlockPeriod(uint256 newUnlockPeriod) external onlyOwner {
        require(newUnlockPeriod >= 1, "Unlock period too short");
        require(newUnlockPeriod <= 30 days, "Unlock period too long");
        uint256 oldPeriod = unlockPeriod;
        unlockPeriod = newUnlockPeriod;
        emit UnlockPeriodUpdated(oldPeriod, newUnlockPeriod);
    }
    
    /**
     * @notice Update claim window
     * @param newClaimWindow New claim window in seconds
     */
    function setClaimWindow(uint256 newClaimWindow) external onlyOwner {
        require(newClaimWindow >= 1 hours, "Claim window too short");
        require(newClaimWindow <= 30 days, "Claim window too long");
        uint256 oldWindow = claimWindow;
        claimWindow = newClaimWindow;
        emit ClaimWindowUpdated(oldWindow, newClaimWindow);
    }
    
    /**
     * @notice Emergency pause (stops staking/unstaking)
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Resume operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // ============================================
    // VIEW FUNCTIONS
    // ============================================
    
    /**
     * @notice Get all contract stats in one call
     */
    function getStats() external view returns (
        uint256 totalStaked,
        uint256 totalShares,
        uint256 exchangeRate,
        uint256 liquidBalance,
        uint256 pendingValidatorFees,
        uint256 pendingDaoFees,
        uint256 pendingDevFees,
        uint256 validatorFee,
        uint256 daoFee,
        uint256 devFee
    ) {
        return (
            totalPooledAVAX,
            totalSupply(),
            getExchangeRate(),
            address(this).balance,
            accumulatedValidatorFees,
            accumulatedDaoFees,
            accumulatedDevFees,
            validatorFeeBasisPoints,
            daoFeeBasisPoints,
            devFeeBasisPoints
        );
    }
    
    // ============================================
    // FALLBACK
    // ============================================
    
    /**
     * @notice Allow contract to receive AVAX directly
     * @dev Emits Deposited event for tracking
     */
    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }
}
