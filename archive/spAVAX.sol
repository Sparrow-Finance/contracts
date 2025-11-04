// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title spAVAX - Sparrow Staked AVAX (Upgradeable with Governance)
 * @author Cypher Networks, LLC
 * @notice Upgradeable liquid staking token for Avalanche with DAO governance
 * 
 * How it works:
 * 1. Users stake AVAX → receive spAVAX tokens
 * 2. spAVAX value increases as validator rewards are added
 * 3. Users request unlock → wait unlock period → claim AVAX within claim window
 * 4. Protocol earns fees: 5% DAO treasury + 3% development = 8% total
 * 5. Governance (DAO) controls fees, unlock period, and upgrades
 * 
 * Exchange Rate: 1 spAVAX = totalPooledAVAX / totalSupply()
 * Unlock System: 15 days unlock period + 7 day claim window (DAO adjustable)
 * 
 * CLARITY Act Compliant:
 * - Governance controlled (decentralized)
 * - Max 10% total fees (hardcoded)
 * - Unlock period 7-30 days (hardcoded limits)
 * - Upgradeable via DAO vote with 2-day timelock
 */
contract spAVAX is 
    Initializable,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable 
{
    
    // ============================================
    // STATE VARIABLES
    // ============================================
    
    /// @notice Governance address (owner, multisig, or DAO)
    address public governance;
    
    /// @notice Pending governance for 2-step transfer
    address public pendingGovernance;
    
    /// @notice Total AVAX controlled by protocol (includes staked with validators)
    uint256 public totalPooledAVAX;
    
    /// @notice Combined protocol fee (DAO + Dev)
    uint256 public protocolFeeBasisPoints;
    
    /// @notice DAO treasury fee (5% = 500 basis points out of 10000)
    uint256 public daoFeeBasisPoints;
    
    /// @notice Development fund fee (3% = 300 basis points out of 10000)
    uint256 public devFeeBasisPoints;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_TOTAL_FEE = 1000; // Max 10% total fees (CLARITY Act)
    uint256 public constant MIN_UNLOCK_PERIOD = 7 days;
    uint256 public constant MAX_UNLOCK_PERIOD = 30 days;
    uint256 public constant MIN_CLAIM_WINDOW = 1 hours;
    uint256 public constant MAX_CLAIM_WINDOW = 30 days;
    uint256 public constant MAX_UNLOCK_REQUESTS = 100; // Max pending unlock requests per user
    
    /// @notice Accumulated DAO treasury fees
    uint256 public accumulatedDaoFees;
    
    /// @notice Accumulated development fees
    uint256 public accumulatedDevFees;
    
    /// @notice Minimum stake amount (initialized in initialize())
    uint256 public minStakeAmount;
    
    /// @notice Unlock period for withdrawals (initialized in initialize())
    uint256 public unlockPeriod;
    
    /// @notice Claim window - time after unlock to claim before expiring (initialized in initialize())
    uint256 public claimWindow;
    
    /// @notice Struct to track unlock requests
    struct UnlockRequest {
        uint256 spAvaxAmount;
        uint256 unlockTime;
        uint256 expiryTime;
    }
    
    /// @notice Mapping of user addresses to their unlock requests
    mapping(address => UnlockRequest[]) public unlockRequests;
    
    // ============================================
    // EVENTS
    // ============================================
    
    event Staked(address indexed user, uint256 indexed avaxAmount, uint256 spAvaxAmount);
    event UnlockRequested(address indexed user, uint256 indexed spAvaxAmount, uint256 avaxAmount, uint256 unlockTime, uint256 expiryTime);
    event Unstaked(address indexed user, uint256 indexed spAvaxAmount, uint256 avaxAmount);
    event UnlockCancelled(address indexed user, uint256 indexed index, uint256 spAvaxAmount);
    event UnlockExpired(address indexed user, uint256 indexed index, uint256 spAvaxAmount);
    event RewardsAdded(uint256 totalReward, uint256 userReward, uint256 daoFee, uint256 devFee);
    event Withdrawn(address indexed to, uint256 amount);
    event Deposited(address indexed from, uint256 amount);
    event DaoFeesCollected(address indexed to, uint256 amount);
    event DevFeesCollected(address indexed to, uint256 amount);
    event UnlockPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event ClaimWindowUpdated(uint256 oldWindow, uint256 newWindow);
    event FeeStructureUpdated(uint256 protocolFee, uint256 daoFee, uint256 devFee);
    event MinStakeAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event GovernanceTransferInitiated(address indexed from, address indexed to);
    event GovernanceTransferred(address indexed from, address indexed to);
    
    // ============================================
    // INITIALIZATION
    // ============================================
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initialize the contract (replaces constructor for upgradeable contracts)
     * @dev Can only be called once
     */
    function initialize() public initializer {
        __ERC20_init("Sparrow Staked AVAX", "spAVAX");
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        
        // Set governance to deployer initially
        governance = msg.sender;
        
        // Initialize fees
        daoFeeBasisPoints = 500;  // 5%
        devFeeBasisPoints = 300;  // 3%
        protocolFeeBasisPoints = 800; // 8% total
        
        // Initialize parameters
        minStakeAmount = 0.01 ether;
        unlockPeriod = 60;  // 60 seconds for testing
        claimWindow = 7 days;
        totalPooledAVAX = 0;
    }
    
    // ============================================
    // MODIFIERS
    // ============================================
    
    modifier onlyGovernance() {
        require(msg.sender == governance, "Not governance");
        _;
    }
    
    // ============================================
    // USER FUNCTIONS
    // ============================================
    
    /**
     * @notice Stake AVAX and receive spAVAX tokens
     * @return spAvaxAmount Amount of spAVAX minted
     */
    function stake(uint256 minSpAvaxOut) external payable nonReentrant whenNotPaused returns (uint256 spAvaxAmount) {
        require(msg.value >= minStakeAmount, "Below minimum stake");
        
        if (totalSupply() == 0) {
            // First deposit: mint at least 1e6 shares to prevent manipulation
            spAvaxAmount = msg.value;
            require(spAvaxAmount >= 1e6, "First deposit too small");
        } else {
            spAvaxAmount = (msg.value * totalSupply()) / totalPooledAVAX;
            require(spAvaxAmount > 0, "Insufficient shares minted");
        }
        
        // Slippage protection
        require(spAvaxAmount >= minSpAvaxOut, "Slippage too high");
        
        totalPooledAVAX += msg.value;
        _mint(msg.sender, spAvaxAmount);
        
        emit Staked(msg.sender, msg.value, spAvaxAmount);
        return spAvaxAmount;
    }
    
    /**
     * @notice Request to unstake spAVAX (starts unlock timer)
     * @param spAvaxAmount Amount of spAVAX to unstake
     * @return avaxAmount Amount of AVAX you'll receive after unlock period
     */
    function requestUnlock(uint256 spAvaxAmount, uint256 minAvaxOut) external nonReentrant whenNotPaused returns (uint256 avaxAmount) {
        require(spAvaxAmount > 0, "Amount must be > 0");
        require(balanceOf(msg.sender) >= spAvaxAmount, "Insufficient balance");
        require(totalSupply() > 0, "No shares exist");
        require(unlockRequests[msg.sender].length < MAX_UNLOCK_REQUESTS, "Too many pending requests");
        
        // Calculate AVAX to return based on current exchange rate (for preview only)
        avaxAmount = (spAvaxAmount * totalPooledAVAX) / totalSupply();
        require(avaxAmount > 0, "Invalid AVAX amount");
        
        // Slippage protection (based on current rate)
        require(avaxAmount >= minAvaxOut, "Slippage too high");
        
        // Transfer spAVAX to contract (locked during unlock period)
        _transfer(msg.sender, address(this), spAvaxAmount);
        
        // Create unlock request (without storing avaxAmount - will calculate at claim time)
        uint256 unlockTime = block.timestamp + unlockPeriod;
        uint256 expiryTime = unlockTime + claimWindow;
        
        unlockRequests[msg.sender].push(UnlockRequest({
            spAvaxAmount: spAvaxAmount,
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
        
        // Calculate AVAX amount at claim time (current exchange rate)
        uint256 avaxAmount = (request.spAvaxAmount * totalPooledAVAX) / totalSupply();
        require(avaxAmount > 0, "Invalid AVAX amount");
        require(address(this).balance >= avaxAmount, "Insufficient liquidity");
        
        // Remove unlock request (swap with last and pop)
        unlockRequests[msg.sender][requestIndex] = unlockRequests[msg.sender][unlockRequests[msg.sender].length - 1];
        unlockRequests[msg.sender].pop();
        
        // Update state
        totalPooledAVAX -= avaxAmount;
        
        // Burn spAVAX
        _burn(address(this), request.spAvaxAmount);
        
        // Send AVAX to user
        (bool success, ) = msg.sender.call{value: avaxAmount}("");
        require(success, "Transfer failed");
        
        emit Unstaked(msg.sender, request.spAvaxAmount, avaxAmount);
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
        
        // Calculate current AVAX value
        uint256 currentAvaxAmount = 0;
        if (totalSupply() > 0) {
            currentAvaxAmount = (request.spAvaxAmount * totalPooledAVAX) / totalSupply();
        }
        
        return (
            request.spAvaxAmount,
            currentAvaxAmount,  // Return current value, not stored value
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
    function withdraw(uint256 amount) external onlyGovernance nonReentrant {
        require(amount > 0, "Amount must be > 0");
        require(address(this).balance >= amount, "Insufficient balance");
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit Withdrawn(msg.sender, amount);
    }
    
    /**
     * @notice Deposit AVAX back from validators (adds liquidity)
     */
    function deposit() external payable onlyGovernance {
        require(msg.value > 0, "Amount must be > 0");
        emit Deposited(msg.sender, msg.value);
    }
    
    /**
     * @notice Add validator rewards with fee distribution
     * @dev Splits fees: (5% DAO + 3% dev), 92% users
     * @dev Must send AVAX with this transaction
     */
    function addRewards() external payable onlyGovernance {
        require(msg.value > 0, "Reward must be > 0");

        uint256 daoFee = (msg.value * daoFeeBasisPoints) / BASIS_POINTS;
        uint256 devFee = (msg.value * devFeeBasisPoints) / BASIS_POINTS;
        uint256 totalFees = daoFee + devFee;
        uint256 userReward = msg.value - totalFees;
    
        totalPooledAVAX += userReward;
        accumulatedDaoFees += daoFee;
        accumulatedDevFees += devFee;
    
        emit RewardsAdded(msg.value, userReward, daoFee, devFee);
}
    
    /**
     * @notice Collect accumulated DAO treasury fees
     */
    function collectDaoFees() external onlyGovernance nonReentrant {
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
    function collectDevFees() external onlyGovernance nonReentrant {
        uint256 fees = accumulatedDevFees;
        require(fees > 0, "No dev fees to collect");
        require(address(this).balance >= fees, "Insufficient balance");
        
        accumulatedDevFees = 0;
        
        (bool success, ) = msg.sender.call{value: fees}("");
        require(success, "Transfer failed");
        
        emit DevFeesCollected(msg.sender, fees);
    }
    
    /**
     * @notice Update fee structure
     * @param newDaoFee DAO treasury fee in basis points
     * @param newDevFee Development fee in basis points
     * @dev Total fees cannot exceed 10% (1000 basis points)
     */
    function setFeeStructure(
        uint256 newDaoFee,
        uint256 newDevFee
    ) external onlyGovernance {
        uint256 totalFee = newDaoFee + newDevFee;
        require(totalFee <= MAX_TOTAL_FEE, "Total fees too high (max 10%)");
        
        daoFeeBasisPoints = newDaoFee;
        devFeeBasisPoints = newDevFee;
        protocolFeeBasisPoints = newDaoFee + newDevFee; // Combined protocol fee
        
        emit FeeStructureUpdated(protocolFeeBasisPoints, newDaoFee, newDevFee);
    }
    
    /**
     * @notice Update minimum stake amount
     * @param newMinAmount New minimum in wei
     */
    function setMinStakeAmount(uint256 newMinAmount) external onlyGovernance {
        require(newMinAmount > 0, "Min amount must be > 0");
        uint256 oldAmount = minStakeAmount;
        minStakeAmount = newMinAmount;
        emit MinStakeAmountUpdated(oldAmount, newMinAmount);
    }
    
    /**
     * @notice Update unlock period
     * @param newUnlockPeriod New unlock period in seconds
     */
    function setUnlockPeriod(uint256 newUnlockPeriod) external onlyGovernance {
        require(newUnlockPeriod >= MIN_UNLOCK_PERIOD, "Unlock period too short");
        require(newUnlockPeriod <= MAX_UNLOCK_PERIOD, "Unlock period too long");
        uint256 oldPeriod = unlockPeriod;
        unlockPeriod = newUnlockPeriod;
        emit UnlockPeriodUpdated(oldPeriod, newUnlockPeriod);
    }
    
    /**
     * @notice Update claim window
     * @param newClaimWindow New claim window in seconds
     */
    function setClaimWindow(uint256 newClaimWindow) external onlyGovernance {
        require(newClaimWindow >= MIN_CLAIM_WINDOW, "Claim window too short");
        require(newClaimWindow <= MAX_CLAIM_WINDOW, "Claim window too long");
        uint256 oldWindow = claimWindow;
        claimWindow = newClaimWindow;
        emit ClaimWindowUpdated(oldWindow, newClaimWindow);
    }
    
    /**
     * @notice Emergency pause (stops staking/unstaking)
     */
    function pause() external onlyGovernance {
        _pause();
    }
    
    /**
     * @notice Resume operations
     */
    function unpause() external onlyGovernance {
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
        uint256 pendingDaoFees,
        uint256 pendingDevFees,
        uint256 daoFee,
        uint256 devFee
    ) {
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
    // FALLBACK
    // ============================================
    
    /**
     * @notice Allow contract to receive AVAX directly
     * @dev Emits Deposited event for tracking
     */
    receive() external payable {
        // Only allow governance to send AVAX directly
        require(msg.sender == governance, "Use stake() function");
        emit Deposited(msg.sender, msg.value);
    }
    
    // ============================================
    // GOVERNANCE FUNCTIONS
    // ============================================
    
    /**
     * @notice Transfer governance to a new address (2-step process)
     * @param newGovernance New governance address
     */
    function transferGovernance(address newGovernance) external onlyGovernance {
        require(newGovernance != address(0), "Invalid address");
        pendingGovernance = newGovernance;
        emit GovernanceTransferInitiated(governance, newGovernance);
    }
    
    /**
     * @notice Accept governance transfer
     * @dev Must be called by pending governance
     */
    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "Not pending governance");
        address oldGovernance = governance;
        governance = pendingGovernance;
        pendingGovernance = address(0);
        emit GovernanceTransferred(oldGovernance, governance);
    }
    
    /**
     * @notice Authorize contract upgrade
     * @dev Only governance can upgrade
     */
    function _authorizeUpgrade(address newImplementation) 
        internal 
        onlyGovernance 
        override 
    {
        // Intentionally empty - authorization check is in modifier
    }
}