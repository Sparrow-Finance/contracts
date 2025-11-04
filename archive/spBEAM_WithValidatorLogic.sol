// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title spBEAM - Sparrow Staked BEAM (Upgradeable with Governance)
 * @author Sparrow Finance
 * @notice First liquid staking token for Beam Network with DAO governance
 * 
 * How it works:
 * 1. Users stake BEAM → receive spBEAM tokens
 * 2. spBEAM value increases as validator rewards are added
 * 3. Users request unlock → wait unlock period → claim BEAM within claim window
 * 4. Protocol earns fees: 5% DAO treasury + 3% development = 8% total
 * 5. Governance (DAO) controls fees, unlock period, and upgrades
 * 
 * Exchange Rate: 1 spBEAM = totalPooledBEAM / totalSupply()
 * Unlock System: 14 days unlock period + 7 day claim window (DAO adjustable)
 * 
 * Features:
 * - First liquid staking on Beam (gaming-focused subnet)
 * - Governance controlled (decentralized)
 * - Max 10% total fees (hardcoded)
 * - Unlock period 7-30 days (hardcoded limits)
 * - Upgradeable via DAO vote
 */
contract spBEAM is 
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
    
    /// @notice Total BEAM controlled by protocol (includes staked with validators)
    uint256 public totalPooledBEAM;
    
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
        uint256 spBeamAmount;
        uint256 unlockTime;
        uint256 expiryTime;
    }
    
    /// @notice Mapping of user addresses to their unlock requests
    mapping(address => UnlockRequest[]) public unlockRequests;
    
    // ============================================
    // VALIDATOR STAKING STATE
    // ============================================
    
    /// @notice Beam Validator Manager contract address (mainnet)
    address public constant VALIDATOR_MANAGER = 0x2FD428A5484d113294b44E69Cb9f269abC1d5B54;
    
    /// @notice Sparrow Swap Router address (for reward token swaps)
    address public sparrowSwapRouter;
    
    /// @notice Wrapped BEAM address
    address public constant WBEAM = 0xD51BFa777609213A653a2CD067c9A0132a2D316A;
    
    /// @notice Liquidity reserve ratio (10% = 1000 basis points)
    uint256 public reserveRatio;
    
    /// @notice Auto-stake threshold (stake when this much BEAM accumulated)
    uint256 public autoStakeThreshold;
    
    /// @notice Auto-staking enabled flag
    bool public autoStakingEnabled;
    
    /// @notice Current validator ID for auto-staking
    bytes32 public currentValidatorID;
    
    /// @notice Struct to track validator delegations
    struct Delegation {
        bytes32 validationID;
        uint32 delegationID;
        uint256 amount;
        uint256 stakedAt;
        bool active;
    }
    
    /// @notice Array of all delegations
    Delegation[] public delegations;
    
    /// @notice Total BEAM staked with validators
    uint256 public totalStakedWithValidators;
    
    // ============================================
    // EVENTS
    // ============================================
    
    event Staked(address indexed user, uint256 indexed beamAmount, uint256 spBeamAmount);
    event UnlockRequested(address indexed user, uint256 indexed spBeamAmount, uint256 beamAmount, uint256 unlockTime, uint256 expiryTime);
    event Unstaked(address indexed user, uint256 indexed spBeamAmount, uint256 beamAmount);
    event UnlockCancelled(address indexed user, uint256 indexed index, uint256 spBeamAmount);
    event UnlockExpired(address indexed user, uint256 indexed index, uint256 spBeamAmount);
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
    
    // Validator staking events
    event ValidatorStaked(bytes32 indexed validationID, uint256 amount, uint256 delegationIndex);
    event ValidatorUnstaked(bytes32 indexed validationID, uint32 delegationID, uint256 amount);
    event AutoStakingToggled(bool enabled);
    event AutoStakeThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event ReserveRatioUpdated(uint256 oldRatio, uint256 newRatio);
    event CurrentValidatorUpdated(bytes32 indexed oldValidator, bytes32 indexed newValidator);
    
    // Reward conversion events
    event RewardsClaimed(bytes32 indexed validationID, uint32 delegationID);
    event DelegationCompleted(bytes32 indexed validationID, uint32 delegationID, uint256 principalAmount);
    event WBEAMUnwrapped(uint256 amount);
    event RewardTokenSwapped(address indexed tokenAddress, uint256 amountIn, uint256 minAmountOut);
    event SparrowSwapRouterUpdated(address indexed oldRouter, address indexed newRouter);
    event TokensRescued(address indexed tokenAddress, uint256 amount, address indexed to);
    
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
        __ERC20_init("Sparrow Staked BEAM", "spBEAM");
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
        unlockPeriod = 22 days;  // 22 days to match validator unbonding (21 days) + buffer
        claimWindow = 7 days;
        totalPooledBEAM = 0;
        
        // Initialize validator staking parameters
        reserveRatio = 1000; // 10%
        autoStakeThreshold = 1000 ether; // 1000 BEAM
        autoStakingEnabled = false;
        totalStakedWithValidators = 0;
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
     * @notice Stake BEAM and receive spBEAM tokens
     * @return spBeamAmount Amount of spBEAM minted
     */
    function stake(uint256 minSpBeamOut) external payable nonReentrant whenNotPaused returns (uint256 spBeamAmount) {
        require(msg.value >= minStakeAmount, "Below minimum stake");
        
        if (totalSupply() == 0) {
            // First deposit: mint at least 1e6 shares to prevent manipulation
            spBeamAmount = msg.value;
            require(spBeamAmount >= 1e6, "First deposit too small");
        } else {
            require(totalPooledBEAM > 0, "Pool empty");
            spBeamAmount = (msg.value * totalSupply()) / totalPooledBEAM;
            require(spBeamAmount > 0, "Insufficient shares minted");
        }
        
        // Slippage protection
        require(spBeamAmount >= minSpBeamOut, "Slippage too high");
        
        totalPooledBEAM += msg.value;
        _mint(msg.sender, spBeamAmount);
        
        emit Staked(msg.sender, msg.value, spBeamAmount);
        return spBeamAmount;
    }
    
    /**
     * @notice Request to unstake spBEAM (starts unlock timer)
     * @param spBeamAmount Amount of spBEAM to unstake
     * @return beamAmount Amount of BEAM you'll receive after unlock period
     */
    function requestUnlock(uint256 spBeamAmount, uint256 minBeamOut) external nonReentrant whenNotPaused returns (uint256 beamAmount) {
        require(spBeamAmount > 0, "Amount must be > 0");
        require(balanceOf(msg.sender) >= spBeamAmount, "Insufficient balance");
        require(totalSupply() > 0, "No shares exist");
        require(unlockRequests[msg.sender].length < MAX_UNLOCK_REQUESTS, "Too many pending requests");
        
        // Calculate BEAM to return based on current exchange rate (for preview only)
        require(totalPooledBEAM > 0, "Pool empty");
        beamAmount = (spBeamAmount * totalPooledBEAM) / totalSupply();
        require(beamAmount > 0, "Invalid BEAM amount");
        
        // Slippage protection (based on current rate)
        require(beamAmount >= minBeamOut, "Slippage too high");
        
        // Transfer spBEAM to contract (locked during unlock period)
        _transfer(msg.sender, address(this), spBeamAmount);
        
        // Create unlock request (without storing beamAmount - will calculate at claim time)
        uint256 unlockTime = block.timestamp + unlockPeriod;
        uint256 expiryTime = unlockTime + claimWindow;
        
        unlockRequests[msg.sender].push(UnlockRequest({
            spBeamAmount: spBeamAmount,
            unlockTime: unlockTime,
            expiryTime: expiryTime
        }));
        
        emit UnlockRequested(msg.sender, spBeamAmount, beamAmount, unlockTime, expiryTime);
        return beamAmount;
    }
    
    /**
     * @notice Claim unlocked BEAM after unlock period has passed
     * @param requestIndex Index of the unlock request to claim
     */
    function claimUnlock(uint256 requestIndex) external nonReentrant whenNotPaused {
        require(requestIndex < unlockRequests[msg.sender].length, "Invalid request index");
        
        UnlockRequest memory request = unlockRequests[msg.sender][requestIndex];
        require(block.timestamp >= request.unlockTime, "Unlock period not finished");
        require(block.timestamp <= request.expiryTime, "Claim window expired");
        
        // Calculate BEAM amount at claim time (current exchange rate)
        require(totalPooledBEAM > 0, "Pool empty");
        uint256 beamAmount = (request.spBeamAmount * totalPooledBEAM) / totalSupply();
        require(beamAmount > 0, "Invalid BEAM amount");
        require(address(this).balance >= beamAmount, "Insufficient liquidity");
        
        // Remove unlock request (swap with last and pop)
        unlockRequests[msg.sender][requestIndex] = unlockRequests[msg.sender][unlockRequests[msg.sender].length - 1];
        unlockRequests[msg.sender].pop();
        
        // Update state
        totalPooledBEAM -= beamAmount;
        
        // Burn spBEAM
        _burn(address(this), request.spBeamAmount);
        
        // Send BEAM to user
        (bool success, ) = msg.sender.call{value: beamAmount}("");
        require(success, "Transfer failed");
        
        emit Unstaked(msg.sender, request.spBeamAmount, beamAmount);
    }
    
    /**
     * @notice Cancel an unlock request and get spBEAM back (before expiry)
     * @param requestIndex Index of the unlock request to cancel
     */
    function cancelUnlock(uint256 requestIndex) external nonReentrant whenNotPaused {
        require(requestIndex < unlockRequests[msg.sender].length, "Invalid request index");
        
        UnlockRequest memory request = unlockRequests[msg.sender][requestIndex];
        require(block.timestamp <= request.expiryTime, "Request expired, use claimExpired");
        
        // Remove unlock request
        unlockRequests[msg.sender][requestIndex] = unlockRequests[msg.sender][unlockRequests[msg.sender].length - 1];
        unlockRequests[msg.sender].pop();
        
        // Return spBEAM to user
        _transfer(address(this), msg.sender, request.spBeamAmount);
        
        emit UnlockCancelled(msg.sender, requestIndex, request.spBeamAmount);
    }
    
    /**
     * @notice Claim expired unlock request (returns spBEAM after claim window expires)
     * @param requestIndex Index of the expired unlock request
     */
    function claimExpired(uint256 requestIndex) external nonReentrant whenNotPaused {
        require(requestIndex < unlockRequests[msg.sender].length, "Invalid request index");
        
        UnlockRequest memory request = unlockRequests[msg.sender][requestIndex];
        require(block.timestamp > request.expiryTime, "Not expired yet");
        
        // Remove unlock request
        unlockRequests[msg.sender][requestIndex] = unlockRequests[msg.sender][unlockRequests[msg.sender].length - 1];
        unlockRequests[msg.sender].pop();
        
        // Return spBEAM to user
        _transfer(address(this), msg.sender, request.spBeamAmount);
        
        emit UnlockExpired(msg.sender, requestIndex, request.spBeamAmount);
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
     * @return spBeamAmount Amount of spBEAM locked
     * @return beamAmount Amount of BEAM to receive
     * @return unlockTime Timestamp when unlock is available
     * @return expiryTime Timestamp when claim window expires
     * @return isReady Whether the unlock period has passed
     * @return isExpired Whether the claim window has expired
     */
    function getUnlockRequest(address user, uint256 requestIndex) external view returns (
        uint256 spBeamAmount,
        uint256 beamAmount,
        uint256 unlockTime,
        uint256 expiryTime,
        bool isReady,
        bool isExpired
    ) {
        require(requestIndex < unlockRequests[user].length, "Invalid request index");
        UnlockRequest memory request = unlockRequests[user][requestIndex];
        
        // Calculate current BEAM value
        uint256 currentBeamAmount = 0;
        if (totalSupply() > 0) {
            currentBeamAmount = (request.spBeamAmount * totalPooledBEAM) / totalSupply();
        }
        
        return (
            request.spBeamAmount,
            currentBeamAmount,  // Return current value, not stored value
            request.unlockTime,
            request.expiryTime,
            block.timestamp >= request.unlockTime,
            block.timestamp > request.expiryTime
        );
    }
    
    /**
     * @notice Get current exchange rate (how much BEAM 1 spBEAM is worth)
     * @return rate Exchange rate scaled by 1e18 (1e18 = 1:1 ratio)
     */
    function getExchangeRate() public view returns (uint256 rate) {
        if (totalSupply() == 0 || totalPooledBEAM == 0) {
            return 1e18; // 1:1 ratio
        }
        return (totalPooledBEAM * 1e18) / totalSupply();
    }
    
    /**
     * @notice Preview how much spBEAM you'll get for BEAM amount
     * @param beamAmount Amount of BEAM
     * @return spBeamAmount Equivalent spBEAM amount
     */
    function previewStake(uint256 beamAmount) public view returns (uint256 spBeamAmount) {
        if (totalSupply() == 0 || totalPooledBEAM == 0) {
            return beamAmount;
        }
        return (beamAmount * totalSupply()) / totalPooledBEAM;
    }
    
    /**
     * @notice Preview how much BEAM you'll get for spBEAM amount
     * @param spBeamAmount Amount of spBEAM
     * @return beamAmount Equivalent BEAM amount
     */
    function previewUnlock(uint256 spBeamAmount) public view returns (uint256 beamAmount) {
        if (totalSupply() == 0) {
            return 0;
        }
        return (spBeamAmount * totalPooledBEAM) / totalSupply();
    }
    
    // ============================================
    // ADMIN FUNCTIONS (OWNER ONLY)
    // ============================================
    
    /**
     * @notice Withdraw BEAM to stake with validators
     * @param amount Amount of BEAM to withdraw
     */
    function withdraw(uint256 amount) external onlyGovernance nonReentrant {
        require(amount > 0, "Amount must be > 0");
        require(address(this).balance >= amount, "Insufficient balance");
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit Withdrawn(msg.sender, amount);
    }
    
    /**
     * @notice Deposit BEAM back from validators (adds liquidity)
     */
    function deposit() external payable onlyGovernance {
        require(msg.value > 0, "Amount must be > 0");
        emit Deposited(msg.sender, msg.value);
    }
    
    /**
     * @notice Add validator rewards with fee distribution
     * @dev Splits fees: (5% DAO + 3% dev), 92% users
     * @dev Must send BEAM with this transaction
     */
    function addRewards() external payable onlyGovernance {
        require(msg.value > 0, "Reward must be > 0");

        uint256 daoFee = (msg.value * daoFeeBasisPoints) / BASIS_POINTS;
        uint256 devFee = (msg.value * devFeeBasisPoints) / BASIS_POINTS;
        uint256 totalFees = daoFee + devFee;
        uint256 userReward = msg.value - totalFees;
    
        totalPooledBEAM += userReward;
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
            totalPooledBEAM,
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
    // VALIDATOR STAKING FUNCTIONS
    // ============================================
    
    /**
     * @notice Stake BEAM to a validator (manual)
     * @param validationID Validator ID to stake to
     * @param amount Amount of BEAM to stake
     */
    function stakeToValidator(bytes32 validationID, uint256 amount) 
        external 
        onlyGovernance 
        nonReentrant 
    {
        require(amount > 0, "Amount must be > 0");
        require(address(this).balance >= amount, "Insufficient balance");
        require(validationID != bytes32(0), "Invalid validator ID");
        
        // Call Beam Validator Manager
        (bool success, bytes memory returnData) = VALIDATOR_MANAGER.call{value: amount}(
            abi.encodeWithSignature("initializeDelegatorRegistration(bytes32)", validationID)
        );
        
        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            }
            revert("Validator staking failed");
        }
        
        // Store delegation info
        delegations.push(Delegation({
            validationID: validationID,
            delegationID: 0, // Will be updated when known
            amount: amount,
            stakedAt: block.timestamp,
            active: true
        }));
        
        totalStakedWithValidators += amount;
        
        emit ValidatorStaked(validationID, amount, delegations.length - 1);
    }
    
    /**
     * @notice Unstake BEAM from a validator
     * @param delegationIndex Index in delegations array
     */
    function unstakeFromValidator(uint256 delegationIndex) 
        external 
        onlyGovernance 
        nonReentrant 
    {
        require(delegationIndex < delegations.length, "Invalid delegation index");
        Delegation storage delegation = delegations[delegationIndex];
        require(delegation.active, "Delegation not active");
        
        // Call Beam Validator Manager to unstake
        (bool success, bytes memory returnData) = VALIDATOR_MANAGER.call(
            abi.encodeWithSignature(
                "initializeEndDelegation(bytes32,uint32)", 
                delegation.validationID,
                delegation.delegationID
            )
        );
        
        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            }
            revert("Validator unstaking failed");
        }
        
        delegation.active = false;
        totalStakedWithValidators -= delegation.amount;
        
        emit ValidatorUnstaked(delegation.validationID, delegation.delegationID, delegation.amount);
    }
    
    /**
     * @notice Check and auto-stake if conditions are met
     * @dev Called internally or externally to trigger auto-staking
     */
    function checkAndAutoStake() public {
        if (!autoStakingEnabled) return;
        if (currentValidatorID == bytes32(0)) return;
        
        uint256 liquid = address(this).balance;
        uint256 requiredReserve = (totalPooledBEAM * reserveRatio) / BASIS_POINTS;
        
        if (liquid > requiredReserve + autoStakeThreshold) {
            uint256 toStake = liquid - requiredReserve;
            _stakeToValidator(currentValidatorID, toStake);
        }
    }
    
    /**
     * @notice Internal function to stake to validator
     */
    function _stakeToValidator(bytes32 validationID, uint256 amount) internal {
        require(amount > 0, "Amount must be > 0");
        require(address(this).balance >= amount, "Insufficient balance");
        
        (bool success, bytes memory returnData) = VALIDATOR_MANAGER.call{value: amount}(
            abi.encodeWithSignature("initializeDelegatorRegistration(bytes32)", validationID)
        );
        
        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            }
            revert("Validator staking failed");
        }
        
        delegations.push(Delegation({
            validationID: validationID,
            delegationID: 0,
            amount: amount,
            stakedAt: block.timestamp,
            active: true
        }));
        
        totalStakedWithValidators += amount;
        
        emit ValidatorStaked(validationID, amount, delegations.length - 1);
    }
    
    /**
     * @notice Toggle auto-staking on/off
     */
    function setAutoStaking(bool enabled) external onlyGovernance {
        autoStakingEnabled = enabled;
        emit AutoStakingToggled(enabled);
    }
    
    /**
     * @notice Set auto-stake threshold
     */
    function setAutoStakeThreshold(uint256 newThreshold) external onlyGovernance {
        require(newThreshold > 0, "Threshold must be > 0");
        uint256 oldThreshold = autoStakeThreshold;
        autoStakeThreshold = newThreshold;
        emit AutoStakeThresholdUpdated(oldThreshold, newThreshold);
    }
    
    /**
     * @notice Set reserve ratio
     */
    function setReserveRatio(uint256 newRatio) external onlyGovernance {
        require(newRatio <= 5000, "Reserve ratio too high (max 50%)");
        uint256 oldRatio = reserveRatio;
        reserveRatio = newRatio;
        emit ReserveRatioUpdated(oldRatio, newRatio);
    }
    
    /**
     * @notice Set current validator for auto-staking
     */
    function setCurrentValidator(bytes32 validatorID) external onlyGovernance {
        require(validatorID != bytes32(0), "Invalid validator ID");
        bytes32 oldValidator = currentValidatorID;
        currentValidatorID = validatorID;
        emit CurrentValidatorUpdated(oldValidator, validatorID);
    }
    
    /**
     * @notice Update delegation ID after staking
     * @dev Called by governance after delegation is confirmed
     */
    function updateDelegationID(uint256 delegationIndex, uint32 delegationID) external onlyGovernance {
        require(delegationIndex < delegations.length, "Invalid delegation index");
        delegations[delegationIndex].delegationID = delegationID;
    }
    
    /**
     * @notice Get delegation count
     */
    function getDelegationCount() external view returns (uint256) {
        return delegations.length;
    }
    
    /**
     * @notice Get required reserve amount
     */
    function getRequiredReserve() public view returns (uint256) {
        return (totalPooledBEAM * reserveRatio) / BASIS_POINTS;
    }
    
    /**
     * @notice Get available balance for staking (liquid - reserve)
     */
    function getAvailableForStaking() public view returns (uint256) {
        uint256 liquid = address(this).balance;
        uint256 reserve = getRequiredReserve();
        if (liquid <= reserve) return 0;
        return liquid - reserve;
    }
    
    // ============================================
    // REWARD CONVERSION FUNCTIONS
    // ============================================
    
    /**
     * @notice Claim delegation rewards WITHOUT unstaking
     * @param validationID Validator ID
     * @param delegationID Delegation ID
     * @param rewardTokens Array of reward token addresses to claim (e.g., [WBEAM, ATH])
     * @dev This claims accumulated rewards while keeping stake active
     */
    function claimDelegationRewards(
        bytes32 validationID, 
        uint32 delegationID,
        address[] calldata rewardTokens
    ) 
        external 
        onlyGovernance 
        nonReentrant 
    {
        require(validationID != bytes32(0), "Invalid validation ID");
        require(rewardTokens.length > 0, "No reward tokens specified");
        
        // Claim rewards from Beam Validator Manager
        // Function signature based on actual Beam transaction: 0x94e840d5
        // Rewards come as multiple tokens (ATH, WBEAM, etc.)
        (bool success, bytes memory returnData) = VALIDATOR_MANAGER.call(
            abi.encodeWithSelector(
                bytes4(0x94e840d5), // claimDelegationFees selector
                validationID,
                delegationID,
                rewardTokens,
                address(this) // recipient
            )
        );
        
        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            }
            revert("Claim rewards failed");
        }
        
        // NOTE: Rewards received as multiple tokens (ATH, WBEAM, etc.)
        // Stake remains active
        // Call swapRewardTokenForBEAM() and unwrapWBEAM() to convert
        
        emit RewardsClaimed(validationID, delegationID);
    }
    
    /**
     * @notice Complete delegator removal and receive principal back
     * @param delegationIndex Index in delegations array
     * @dev This ends the delegation and returns principal
     */
    function completeDelegatorRemoval(uint256 delegationIndex) 
        external 
        onlyGovernance 
        nonReentrant 
    {
        require(delegationIndex < delegations.length, "Invalid delegation index");
        Delegation storage delegation = delegations[delegationIndex];
        require(delegation.active, "Delegation not active");
        
        // Complete removal - returns principal
        (bool success, bytes memory returnData) = VALIDATOR_MANAGER.call(
            abi.encodeWithSignature(
                "completeDelegatorRemoval(bytes32,uint32)", 
                delegation.validationID,
                delegation.delegationID
            )
        );
        
        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            }
            revert("Complete removal failed");
        }
        
        delegation.active = false;
        totalStakedWithValidators -= delegation.amount;
        
        emit DelegationCompleted(delegation.validationID, delegation.delegationID, delegation.amount);
    }
    
    /**
     * @notice Unwrap WBEAM to native BEAM
     * @param amount Amount of WBEAM to unwrap
     */
    function unwrapWBEAM(uint256 amount) external onlyGovernance nonReentrant {
        require(amount > 0, "Amount must be > 0");
        
        // Call WBEAM.withdraw(amount)
        (bool success,) = WBEAM.call(
            abi.encodeWithSignature("withdraw(uint256)", amount)
        );
        require(success, "WBEAM unwrap failed");
        
        emit WBEAMUnwrapped(amount);
    }
    
    /**
     * @notice Swap reward tokens for WBEAM via Sparrow Swap
     * @param tokenAddress Address of reward token (e.g., ATH)
     * @param amount Amount to swap
     * @param minWBEAMOut Minimum WBEAM to receive (slippage protection)
     * @param path Swap path [tokenAddress, WBEAM] or [tokenAddress, intermediary, WBEAM]
     * @param deadline Transaction deadline
     */
    function swapRewardTokenForBEAM(
        address tokenAddress,
        uint256 amount,
        uint256 minWBEAMOut,
        address[] calldata path,
        uint256 deadline
    ) external onlyGovernance nonReentrant {
        require(tokenAddress != address(0), "Invalid token");
        require(amount > 0, "Amount must be > 0");
        require(sparrowSwapRouter != address(0), "Router not set");
        require(path[0] == tokenAddress, "Invalid path");
        require(path[path.length - 1] == WBEAM, "Path must end with WBEAM");
        
        // Approve Sparrow Swap router to spend tokens
        (bool approveSuccess,) = tokenAddress.call(
            abi.encodeWithSignature("approve(address,uint256)", sparrowSwapRouter, amount)
        );
        require(approveSuccess, "Approval failed");
        
        // Swap tokens for WBEAM via Sparrow Swap
        // Note: Sparrow Router will transferFrom this contract, so tokens must be here first
        (bool swapSuccess, bytes memory returnData) = sparrowSwapRouter.call(
            abi.encodeWithSignature(
                "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
                amount,
                minWBEAMOut,
                path,
                address(this),
                deadline
            )
        );
        
        if (!swapSuccess) {
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            }
            revert("Swap failed");
        }
        
        emit RewardTokenSwapped(tokenAddress, amount, minWBEAMOut);
    }
    
    /**
     * @notice Set Sparrow Swap router address
     * @param newRouter New router address
     */
    function setSparrowSwapRouter(address newRouter) external onlyGovernance {
        require(newRouter != address(0), "Invalid address");
        address oldRouter = sparrowSwapRouter;
        sparrowSwapRouter = newRouter;
        emit SparrowSwapRouterUpdated(oldRouter, newRouter);
    }
    
    /**
     * @notice Rescue any ERC20 tokens sent to contract
     * @param tokenAddress Token to rescue
     * @param amount Amount to rescue
     * @param to Address to send tokens to
     */
    function rescueTokens(
        address tokenAddress,
        uint256 amount,
        address to
    ) external onlyGovernance nonReentrant {
        require(tokenAddress != address(0), "Invalid token");
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be > 0");
        
        (bool success,) = tokenAddress.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        require(success, "Transfer failed");
        
        emit TokensRescued(tokenAddress, amount, to);
    }
    
    // ============================================
    // FALLBACK
    // ============================================
    
    /**
     * @notice Allow contract to receive BEAM directly
     * @dev Emits Deposited event for tracking
     */
    receive() external payable {
        // Only allow governance to send BEAM directly
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