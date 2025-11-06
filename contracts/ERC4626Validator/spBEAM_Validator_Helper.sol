// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title spBeam_Validator_Helper - Multi-Validator Management for spBEAM
 * @author Sparrow Finance
 * @notice Manages BEAM delegation to multiple Beam validators (like spSTRK V2)
 *
 * Architecture:
 * - spBEAM_V2.sol: User-facing contract (stake/unstake, no expiry on claims)
 * - This contract: Backend validator management
 * - Beam Staking: Native Beam validator staking
 *
 * Features:
 * - Add/activate/deactivate validators
 * - Delegate to specific validators
 * - Track per-validator delegations
 * - Claim rewards and send to spBEAM
 * - Validators are permanent (can't delete, only deactivate)
 * - 21-day unlock period, no claim expiry
 */

// ============================================
// INTERFACES
// ============================================

/**
 * @notice Interface for Beam's native staking contract
 * @dev Based on beam_ABI_testnet.json
 */
interface IBeamStaking {
    // Delegation functions
    function initiateDelegatorRegistration(
        bytes32 validationID
    ) external payable returns (bytes32);
    
    function completeDelegatorRegistration(
        bytes32 validationID,
        uint32 delegationID
    ) external;
    
    function initiateDelegatorRemoval(
        bytes32 validationID,
        uint32 delegationID
    ) external;
    
    function completeDelegatorRemoval(
        bytes32 validationID,
        uint32 delegationID
    ) external;
    
    // Reward functions
    function claimRewards(
        bytes32 validationID,
        uint32 delegationID
    ) external;
    
    function getRewards(
        bytes32 validationID,
        uint32 delegationID
    ) external view returns (uint256);
    
    // Utility functions
    function valueToWeight(
        uint256 value,
        uint64 weightToValueFactor
    ) external pure returns (uint64);
    
    function weightToValue(
        uint64 weight,
        uint64 weightToValueFactor
    ) external pure returns (uint256);
}

/**
 * @notice Interface for spBEAM contract
 */
interface IspBEAM {
    function addRewards() external payable;
    function governance() external view returns (address);
}

// ============================================
// MAIN CONTRACT
// ============================================

contract spBeam_Validator_Helper is
    Initializable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice spBEAM contract address
    address public spBEAM;
    
    /// @notice Beam native staking contract
    IBeamStaking public beamStaking;
    
    /// @notice Validator information
    struct ValidatorInfo {
        bytes32 validationID;      // Beam validator ID
        string name;               // Human-readable name
        bool active;               // Can delegate to this validator
        uint256 delegatedAmount;   // Total BEAM delegated
        uint64 weight;             // Validator weight
        uint32 delegationID;       // Beam delegation ID (0 if not delegated)
        uint64 weightToValueFactor; // Conversion factor
    }
    
    /// @notice Mapping of validator ID to validator info
    mapping(uint256 => ValidatorInfo) public validators;
    
    /// @notice Total number of validators (never decreases)
    uint256 public validatorCount;
    
    /// @notice Check if validator exists
    mapping(uint256 => bool) public validatorExists;
    
    /// @notice List of active validator IDs
    uint256[] public activeValidatorIds;

    // ============================================
    // EVENTS
    // ============================================

    event ValidatorAdded(
        uint256 indexed validatorId,
        bytes32 validationID,
        string name
    );
    
    event ValidatorActivated(uint256 indexed validatorId);
    event ValidatorDeactivated(uint256 indexed validatorId);
    
    event DelegationInitiated(
        uint256 indexed validatorId,
        uint256 amount,
        uint64 weight
    );
    
    event DelegationCompleted(
        uint256 indexed validatorId,
        uint32 delegationID
    );
    
    event UndelegationInitiated(
        uint256 indexed validatorId,
        uint32 delegationID
    );
    
    event UndelegationCompleted(
        uint256 indexed validatorId,
        uint256 amount
    );
    
    event RewardsClaimed(
        uint256 indexed validatorId,
        uint256 amount
    );
    
    event RewardsSentToSpBEAM(uint256 amount);

    // ============================================
    // INITIALIZATION
    // ============================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the ValidatorHelper contract
     * @param _spBEAM Address of spBEAM contract
     * @param _beamStaking Address of Beam native staking contract
     */
    function initialize(
        address _spBEAM,
        address _beamStaking
    ) public initializer {
        require(_spBEAM != address(0), "Invalid spBEAM address");
        require(_beamStaking != address(0), "Invalid staking address");
        
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        spBEAM = _spBEAM;
        beamStaking = IBeamStaking(_beamStaking);
        validatorCount = 0;
    }

    // ============================================
    // MODIFIERS
    // ============================================

    modifier onlyGovernance() {
        require(
            msg.sender == IspBEAM(spBEAM).governance(),
            "Not governance"
        );
        _;
    }

    // ============================================
    // VALIDATOR MANAGEMENT
    // ============================================

    /**
     * @notice Add a new validator (governance only)
     * @param validationID Beam validator ID
     * @param name Human-readable validator name
     * @param weightToValueFactor Weight conversion factor
     */
    function addValidator(
        bytes32 validationID,
        string memory name,
        uint64 weightToValueFactor
    ) external onlyGovernance {
        require(validationID != bytes32(0), "Invalid validation ID");
        require(bytes(name).length > 0, "Name required");
        require(weightToValueFactor > 0, "Invalid factor");
        
        uint256 validatorId = validatorCount;
        
        validators[validatorId] = ValidatorInfo({
            validationID: validationID,
            name: name,
            active: true,  // Active by default
            delegatedAmount: 0,
            weight: 0,
            delegationID: 0,  // Not delegated yet
            weightToValueFactor: weightToValueFactor
        });
        
        validatorExists[validatorId] = true;
        activeValidatorIds.push(validatorId);
        validatorCount++;
        
        emit ValidatorAdded(validatorId, validationID, name);
    }

    /**
     * @notice Activate a validator (governance only)
     * @param validatorId Validator ID to activate
     */
    function activateValidator(uint256 validatorId) external onlyGovernance {
        require(validatorExists[validatorId], "Validator doesn't exist");
        require(!validators[validatorId].active, "Already active");
        
        validators[validatorId].active = true;
        activeValidatorIds.push(validatorId);
        
        emit ValidatorActivated(validatorId);
    }

    /**
     * @notice Deactivate a validator (governance only)
     * @param validatorId Validator ID to deactivate
     */
    function deactivateValidator(uint256 validatorId)
        external
        onlyGovernance
    {
        require(validatorExists[validatorId], "Validator doesn't exist");
        require(validators[validatorId].active, "Already inactive");
        
        validators[validatorId].active = false;
        
        // Remove from active list
        for (uint256 i = 0; i < activeValidatorIds.length; i++) {
            if (activeValidatorIds[i] == validatorId) {
                activeValidatorIds[i] = activeValidatorIds[
                    activeValidatorIds.length - 1
                ];
                activeValidatorIds.pop();
                break;
            }
        }
        
        emit ValidatorDeactivated(validatorId);
    }

    // ============================================
    // DELEGATION FUNCTIONS
    // ============================================

    /**
     * @notice Initiate delegation to a validator
     * @param validatorId Validator to delegate to
     * @param amount Amount of BEAM to delegate
     */
    function initiateDelegation(uint256 validatorId, uint256 amount)
        external
        payable
        onlyGovernance
        nonReentrant
    {
        require(validatorExists[validatorId], "Validator doesn't exist");
        require(validators[validatorId].active, "Validator not active");
        require(msg.value == amount, "Amount mismatch");
        require(amount > 0, "Amount must be > 0");
        
        ValidatorInfo storage validator = validators[validatorId];
        
        // Initiate delegation with Beam
        beamStaking.initiateDelegatorRegistration{value: amount}(
            validator.validationID
        );
        
        // Track delegation
        validator.delegatedAmount += amount;
        
        emit DelegationInitiated(validatorId, amount, uint64(0));
    }

    /**
     * @notice Delegate BEAM from helper's balance (not requiring msg.value)
     * @param validatorId Validator ID
     * @param amount Amount to delegate
     */
    function delegateFromBalance(uint256 validatorId, uint256 amount)
        external
        onlyGovernance
        nonReentrant
    {
        require(validatorExists[validatorId], "Validator doesn't exist");
        require(validators[validatorId].active, "Validator not active");
        require(address(this).balance >= amount, "Insufficient balance");
        require(amount > 0, "Amount must be > 0");
        
        ValidatorInfo storage validator = validators[validatorId];
        
        // Initiate delegation with Beam using contract's balance
        beamStaking.initiateDelegatorRegistration{value: amount}(
            validator.validationID
        );
        
        // Track delegation
        validator.delegatedAmount += amount;
        
        emit DelegationInitiated(validatorId, amount, uint64(0));
    }

    /**
     * @notice Complete delegation registration
     * @param validatorId Validator ID
     * @param delegationID Delegation ID from Beam
     */
    function completeDelegation(uint256 validatorId, uint32 delegationID)
        external
        onlyGovernance
    {
        require(validatorExists[validatorId], "Validator doesn't exist");
        require(delegationID > 0, "Invalid delegation ID");
        
        ValidatorInfo storage validator = validators[validatorId];
        
        // Complete delegation with Beam
        beamStaking.completeDelegatorRegistration(
            validator.validationID,
            delegationID
        );
        
        validator.delegationID = delegationID;
        
        emit DelegationCompleted(validatorId, delegationID);
    }

    /**
     * @notice Initiate undelegation from a validator
     * @param validatorId Validator to undelegate from
     */
    function initiateUndelegation(uint256 validatorId)
        external
        onlyGovernance
        nonReentrant
    {
        require(validatorExists[validatorId], "Validator doesn't exist");
        
        ValidatorInfo storage validator = validators[validatorId];
        require(validator.delegationID > 0, "Not delegated");
        
        // Initiate removal with Beam
        beamStaking.initiateDelegatorRemoval(
            validator.validationID,
            validator.delegationID
        );
        
        emit UndelegationInitiated(validatorId, validator.delegationID);
    }

    /**
     * @notice Complete undelegation from a validator
     * @param validatorId Validator to complete undelegation from
     */
    function completeUndelegation(uint256 validatorId)
        external
        onlyGovernance
        nonReentrant
    {
        require(validatorExists[validatorId], "Validator doesn't exist");
        
        ValidatorInfo storage validator = validators[validatorId];
        require(validator.delegationID > 0, "Not delegated");
        
        uint256 balanceBefore = address(this).balance;
        
        // Complete removal with Beam
        beamStaking.completeDelegatorRemoval(
            validator.validationID,
            validator.delegationID
        );
        
        uint256 balanceAfter = address(this).balance;
        uint256 returned = balanceAfter - balanceBefore;
        
        // Reset validator state
        validator.delegatedAmount = 0;
        validator.weight = 0;
        validator.delegationID = 0;
        
        emit UndelegationCompleted(validatorId, returned);
        
        // Send BEAM back to spBEAM
        if (returned > 0) {
            (bool success, ) = spBEAM.call{value: returned}("");
            require(success, "Transfer to spBEAM failed");
        }
    }

    // ============================================
    // REWARD FUNCTIONS
    // ============================================

    /**
     * @notice Claim rewards from a validator
     * @param validatorId Validator to claim from
     * @return rewards Amount of rewards claimed
     */
    function claimRewards(uint256 validatorId)
        external
        onlyGovernance
        nonReentrant
        returns (uint256 rewards)
    {
        require(validatorExists[validatorId], "Validator doesn't exist");
        
        ValidatorInfo storage validator = validators[validatorId];
        require(validator.delegationID > 0, "Not delegated");
        
        uint256 balanceBefore = address(this).balance;
        
        // Claim rewards from Beam
        beamStaking.claimRewards(
            validator.validationID,
            validator.delegationID
        );
        
        uint256 balanceAfter = address(this).balance;
        rewards = balanceAfter - balanceBefore;
        
        if (rewards > 0) {
            // Send rewards to spBEAM contract
            IspBEAM(spBEAM).addRewards{value: rewards}();
            
            emit RewardsClaimed(validatorId, rewards);
            emit RewardsSentToSpBEAM(rewards);
        }
        
        return rewards;
    }

    /**
     * @notice Get pending rewards for a validator
     * @param validatorId Validator ID
     * @return rewards Pending rewards amount
     */
    function getPendingRewards(uint256 validatorId)
        external
        view
        returns (uint256 rewards)
    {
        require(validatorExists[validatorId], "Validator doesn't exist");
        
        ValidatorInfo storage validator = validators[validatorId];
        
        if (validator.delegationID == 0) {
            return 0;
        }
        
        return beamStaking.getRewards(
            validator.validationID,
            validator.delegationID
        );
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get validator stats
     * @param validatorId Validator ID
     */
    function getValidatorStats(uint256 validatorId)
        external
        view
        returns (
            bytes32 validationID,
            string memory name,
            bool active,
            uint256 delegatedAmount,
            uint64 weight,
            uint32 delegationID
        )
    {
        require(validatorExists[validatorId], "Validator doesn't exist");
        
        ValidatorInfo storage validator = validators[validatorId];
        
        return (
            validator.validationID,
            validator.name,
            validator.active,
            validator.delegatedAmount,
            validator.weight,
            validator.delegationID
        );
    }

    /**
     * @notice Get all active validators
     */
    function getActiveValidators() external view returns (uint256[] memory) {
        return activeValidatorIds;
    }

    /**
     * @notice Get total delegated across all validators
     */
    function getTotalDelegated() external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < validatorCount; i++) {
            if (validatorExists[i]) {
                total += validators[i].delegatedAmount;
            }
        }
        return total;
    }

    // ============================================
    // UPGRADE AUTHORIZATION
    // ============================================

    /**
     * @notice Authorize contract upgrade
     * @dev Only governance can upgrade
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyGovernance
    {
        // Intentionally empty - authorization check is in modifier
    }

    // ============================================
    // FALLBACK
    // ============================================

    /**
     * @notice Allow contract to receive BEAM
     */
    receive() external payable {
        // Accept BEAM from Beam staking contract
    }
}
