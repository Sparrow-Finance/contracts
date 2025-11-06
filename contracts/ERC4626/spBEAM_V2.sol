// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title spBEAM - Sparrow Staked BEAM (Upgradeable with Governance)
 * @author Sparrow Finance
 * @notice Upgradeable liquid staking token for Beam Network with DAO governance
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
 * Exchange Rate Lock: BEAM amount locked at requestUnlock() time
 *
 * Features:
 * - First liquid staking on Beam (gaming-focused subnet)
 * - Governance controlled (decentralized)
 * - Max 10% total fees (hardcoded)
 * - Unlock period 7-30 days (hardcoded limits)
 * - Upgradeable via DAO vote
 */
contract spBEAM_V2 is
    Initializable,
    ERC20Upgradeable,
    ERC4626Upgradeable,
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

    uint256 public totalLockedInUnlocks;

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant RESERVE_RATIO = 1000; // 10% - Reserved for future validator staking logic
    uint256 public constant MAX_TOTAL_FEE = 1000; // Max 10% total fees
    uint256 public constant MIN_UNLOCK_PERIOD = 7 days;
    uint256 public constant MAX_UNLOCK_PERIOD = 30 days;
    uint256 public constant MIN_CLAIM_WINDOW = 1 hours;
    uint256 public constant MAX_CLAIM_WINDOW = 30 days;
    uint256 public constant MAX_UNLOCK_REQUESTS = 100;

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
        uint256 beamAmount;
        uint256 unlockTime;
        uint256 expiryTime;
    }

    /// @notice Mapping of user addresses to their unlock requests
    mapping(address => UnlockRequest[]) public unlockRequests;

    // ============================================
    // EVENTS
    // ============================================

    event Staked(address indexed user, uint256 beamAmount, uint256 spBeamAmount);
    event UnlockRequested(address indexed user, uint256 spBeamAmount, uint256 beamAmount, uint256 unlockTime, uint256 expiryTime);
    event Unstaked(address indexed user, uint256 spBeamAmount, uint256 beamAmount);
    event UnlockCancelled(address indexed user, uint256 index, uint256 spBeamAmount);
    event UnlockExpired(address indexed user, uint256 index, uint256 spBeamAmount);
    event RewardsAdded(uint256 totalReward, uint256 userReward, uint256 daoFee, uint256 devFee);
    event Withdrawn(address indexed to, uint256 amount);
    event Deposited(address indexed from, uint256 amount);
    event DaoFeesCollected(address indexed to, uint256 amount);
    event DevFeesCollected(address indexed to, uint256 amount);
    event AllFeesCollected(address indexed to, uint256 daoAmount, uint256 devAmount, uint256 totalAmount);
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
        __ERC20_init("Sparrow Staked BEAM", "spBEAM");
        // Note: We don't call __ERC4626_init() because BEAM is native (not ERC20)
        // We override asset() and totalAssets() instead
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        // Set governance to deployer initially
        governance = msg.sender;

        // Initialize fees
        daoFeeBasisPoints = 500; // 5%
        devFeeBasisPoints = 300; // 3%
        protocolFeeBasisPoints = 800; // 8% total

        // Initialize parameters
        minStakeAmount = 0.1 ether;
        unlockPeriod = 60; // 60 seconds for testing
        claimWindow = 7 days;
        totalPooledBEAM = 0;
        totalLockedInUnlocks = 0;
    }

    // ============================================
    // MODIFIERS
    // ============================================

    modifier onlyGovernance() {
        require(msg.sender == governance, "Not governance");
        _;
    }

    // ============================================
    // ERC4626 OVERRIDES
    // ============================================

    /**
     * @notice Returns the address of the underlying asset (BEAM)
     * @dev BEAM is native, so we return address(0) as a special case
     */
    function asset() public view virtual override returns (address) {
        return address(0); // BEAM is native, not an ERC20
    }

    /**
     * @notice Returns total assets under management (total BEAM in vault)
     */
    function totalAssets() public view virtual override returns (uint256) {
        return totalPooledBEAM;
    }

    /**
     * @notice Override decimals to resolve conflict between ERC20 and ERC4626
     */
    function decimals() public view virtual override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
        return 18; // BEAM has 18 decimals
    }

    // ============================================
    // USER FUNCTIONS
    // ============================================

    /**
     * @notice Stake BEAM and receive spBEAM tokens (original function)
     * @param minSpBeamOut Minimum spBEAM to receive (slippage protection)
     * @return spBeamAmount Amount of spBEAM minted
     */
    function stake(uint256 minSpBeamOut) external payable nonReentrant whenNotPaused returns (uint256 spBeamAmount) {
        return _stakeFor(msg.sender, msg.value, minSpBeamOut);
    }

    /**
     * @notice ERC4626 deposit - NOT SUPPORTED for native BEAM
     * @dev Use stake() instead for native BEAM deposits
     * @dev ERC4626 standard expects ERC20 tokens, not native assets
     */
    function deposit(uint256 /* assets */, address /* receiver */) public virtual override nonReentrant whenNotPaused returns (uint256 /* shares */) {
        revert("Use stake() for native BEAM - ERC4626 deposit expects ERC20");
    }

    /**
     * @notice ERC4626 mint - NOT SUPPORTED for native BEAM
     * @dev Use stake() instead for native BEAM deposits
     * @dev ERC4626 standard expects ERC20 tokens, not native assets
     */
    function mint(uint256 /* shares */, address /* receiver */) public virtual override nonReentrant whenNotPaused returns (uint256 /* assets */) {
        revert("Use stake() for native BEAM - ERC4626 mint expects ERC20");
    }

    /**
     * @notice Internal helper - stake BEAM for a specific receiver (DRY principle)
     * @param receiver Address to receive spBEAM tokens
     * @param beamAmount Amount of BEAM to stake
     * @param minSpBeamOut Minimum spBEAM to receive (0 = no check)
     * @return spBeamAmount Amount of spBEAM minted
     */
    function _stakeFor(address receiver, uint256 beamAmount, uint256 minSpBeamOut) internal returns (uint256 spBeamAmount) {
        require(beamAmount >= minStakeAmount, "Below minimum stake");
        require(receiver != address(0), "Invalid receiver");
        
        if (totalSupply() == 0 || totalPooledBEAM == 0) {
            spBeamAmount = beamAmount;
        } else {
            // Clean calculation without redundant precision
            spBeamAmount = (beamAmount * totalSupply()) / totalPooledBEAM;
        }
        
        require(spBeamAmount > 0, "Insufficient shares minted");
        if (minSpBeamOut > 0) {
            require(spBeamAmount >= minSpBeamOut, "Slippage too high");
        }

        totalPooledBEAM += beamAmount;
        _mint(receiver, spBeamAmount);

        emit Staked(receiver, beamAmount, spBeamAmount);
        return spBeamAmount;
    }

    /**
     * @notice ERC4626 withdraw - NOT SUPPORTED due to unlock period
     * @dev Use requestUnlock() then claimUnlock() instead
     */
    function withdraw(uint256 /* assets */, address /* receiver */, address /* owner */) public virtual override returns (uint256 /* shares */) {
        revert("Use requestUnlock() - withdrawals require unlock period");
    }

    /**
     * @notice ERC4626 redeem - NOT SUPPORTED due to unlock period
     * @dev Use requestUnlock() then claimUnlock() instead
     */
    function redeem(uint256 /* shares */, address /* receiver */, address /* owner */) public virtual override returns (uint256 /* assets */) {
        revert("Use requestUnlock() - withdrawals require unlock period");
    }

    /**
     * @notice Request to unstake spBEAM (starts unlock timer)
     * @param spBeamAmount Amount of spBEAM to unstake
     * @param minBeamOut Minimum BEAM to receive (slippage protection)
     * @return beamAmount Amount of BEAM you'll receive after unlock period
     */
    function requestUnlock(uint256 spBeamAmount, uint256 minBeamOut) external nonReentrant whenNotPaused returns (uint256 beamAmount) {
        require(spBeamAmount > 0, "Amount must be > 0");
        require(balanceOf(msg.sender) >= spBeamAmount, "Insufficient balance");
        require(totalSupply() > 0, "No shares exist");
        
        // Gas optimization: cache array length
        uint256 requestCount = unlockRequests[msg.sender].length;
        require(requestCount < MAX_UNLOCK_REQUESTS, "Too many pending requests");

        beamAmount = (spBeamAmount * totalPooledBEAM) / totalSupply();
        require(beamAmount > 0, "Invalid BEAM amount");
        require(beamAmount >= minBeamOut, "Slippage too high");

        _transfer(msg.sender, address(this), spBeamAmount);

        uint256 unlockTime = block.timestamp + unlockPeriod;
        uint256 expiryTime = unlockTime + claimWindow;

        unlockRequests[msg.sender].push(
            UnlockRequest({
                spBeamAmount: spBeamAmount,
                beamAmount: beamAmount,
                unlockTime: unlockTime,
                expiryTime: expiryTime
            })
        );

        totalLockedInUnlocks += beamAmount;

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
        require(request.beamAmount > 0, "Invalid BEAM amount");
        require(
            address(this).balance >= request.beamAmount + accumulatedDaoFees + accumulatedDevFees,
            "Insufficient liquidity"
        );

        uint256 lastIndex = unlockRequests[msg.sender].length - 1;
        if (requestIndex != lastIndex) {
            unlockRequests[msg.sender][requestIndex] = unlockRequests[msg.sender][lastIndex];
        }
        unlockRequests[msg.sender].pop();

        totalPooledBEAM -= request.beamAmount;
        totalLockedInUnlocks -= request.beamAmount;

        _burn(address(this), request.spBeamAmount);

        (bool success, ) = msg.sender.call{value: request.beamAmount}("");
        require(success, "Transfer failed");

        emit Unstaked(msg.sender, request.spBeamAmount, request.beamAmount);
    }

    /**
     * @notice Cancel an unlock request and get spBEAM back (before expiry)
     * @param requestIndex Index of the unlock request to cancel
     */
    function cancelUnlock(uint256 requestIndex) external nonReentrant whenNotPaused {
        require(requestIndex < unlockRequests[msg.sender].length, "Invalid request index");

        UnlockRequest memory request = unlockRequests[msg.sender][requestIndex];
        require(block.timestamp <= request.expiryTime, "Request expired, use claimExpired");

        uint256 lastIndex = unlockRequests[msg.sender].length - 1;
        if (requestIndex != lastIndex) {
            unlockRequests[msg.sender][requestIndex] = unlockRequests[msg.sender][lastIndex];
        }
        unlockRequests[msg.sender].pop();

        totalLockedInUnlocks -= request.beamAmount;

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

        uint256 lastIndex = unlockRequests[msg.sender].length - 1;
        if (requestIndex != lastIndex) {
            unlockRequests[msg.sender][requestIndex] = unlockRequests[msg.sender][lastIndex];
        }
        unlockRequests[msg.sender].pop();

        totalLockedInUnlocks -= request.beamAmount;

        _transfer(address(this), msg.sender, request.spBeamAmount);

        emit UnlockExpired(msg.sender, requestIndex, request.spBeamAmount);
    }

    /**
     * @notice Get number of pending unlock requests for a user
     * @param user User address
     * @return count Number of pending requests
     */
    function getUnlockRequestCount(address user) external view returns (uint256) {
        return unlockRequests[user].length;
    }

    /**
     * @notice Get details of a specific unlock request
     * @param user User address
     * @param requestIndex Index of the request
     * @return spBeamAmount Amount of spBEAM locked
     * @return beamAmount Amount of BEAM to receive (locked rate)
     * @return unlockTime Timestamp when unlock is available
     * @return expiryTime Timestamp when claim window expires
     * @return isReady Whether the unlock period has passed
     * @return isExpired Whether the claim window has expired
     */
    function getUnlockRequest(address user, uint256 requestIndex)
        external
        view
        returns (
            uint256 spBeamAmount,
            uint256 beamAmount,
            uint256 unlockTime,
            uint256 expiryTime,
            bool isReady,
            bool isExpired
        )
    {
        require(requestIndex < unlockRequests[user].length, "Invalid request index");
        UnlockRequest memory request = unlockRequests[user][requestIndex];

        return (
            request.spBeamAmount,
            request.beamAmount,
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
    function previewStake(
        uint256 beamAmount
    ) public view returns (uint256 spBeamAmount) {
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
    function previewUnlock(
        uint256 spBeamAmount
    ) public view returns (uint256 beamAmount) {
        if (totalSupply() == 0) {
            return 0;
        }
        return (spBeamAmount * totalPooledBEAM) / totalSupply();
    }

    // ============================================
    // ADMIN FUNCTIONS (GOVERNANCE ONLY)
    // ============================================

    /**
     * @notice Withdraw BEAM to stake with validators
     * @param amount Amount of BEAM to withdraw
     */
    function withdraw(uint256 amount) external onlyGovernance nonReentrant {
        require(amount > 0, "Amount must be > 0");
        
        uint256 committedBEAM = accumulatedDaoFees + accumulatedDevFees + totalLockedInUnlocks;
        require(address(this).balance >= amount + committedBEAM, "Insufficient liquidity after commitments");

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
     * @notice Collect all accumulated fees at once
     */
    function collectAllFees() external onlyGovernance nonReentrant {
        uint256 totalFees = accumulatedDaoFees + accumulatedDevFees;
        require(totalFees > 0, "No fees to collect");
        require(address(this).balance >= totalFees, "Insufficient balance");

        uint256 daoFees = accumulatedDaoFees;
        uint256 devFees = accumulatedDevFees;

        accumulatedDaoFees = 0;
        accumulatedDevFees = 0;

        (bool success, ) = msg.sender.call{value: totalFees}("");
        require(success, "Transfer failed");

        emit AllFeesCollected(msg.sender, daoFees, devFees, totalFees);
    }

    /**
     * @notice Update fee structure
     * @param newDaoFee DAO treasury fee in basis points
     * @param newDevFee Development fee in basis points
     * @dev Total fees cannot exceed 10% (1000 basis points)
     */
    function setFeeStructure(uint256 newDaoFee, uint256 newDevFee) external onlyGovernance {
        require(newDaoFee <= BASIS_POINTS, "DAO fee too high");
        require(newDevFee <= BASIS_POINTS, "Dev fee too high");
        
        uint256 totalFee = newDaoFee + newDevFee;
        require(totalFee <= MAX_TOTAL_FEE, "Total fees too high (max 10%)");

        daoFeeBasisPoints = newDaoFee;
        devFeeBasisPoints = newDevFee;
        protocolFeeBasisPoints = totalFee;

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
    // FALLBACK
    // ============================================

    /**
     * @notice Allow contract to receive BEAM directly
     * @dev Only governance can send BEAM directly (prevents accidental donations)
     */
    receive() external payable {
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
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyGovernance {
        // Intentionally empty - authorization check is in modifier
    }
}
