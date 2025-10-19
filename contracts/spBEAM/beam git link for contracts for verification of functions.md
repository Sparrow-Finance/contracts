https://github.com/BuildOnBeam/beam-nodes-staking-contracts/tree/develop/contracts

Validator manager



// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {ValidatorMessages} from "./ValidatorMessages.sol";
import {ValidatorChurnPeriod, ValidatorManagerSettings} from "./ValidatorManager.sol";
import {
    ACP99Manager,
    InitialValidator,
    PChainOwner,
    ConversionData,
    Validator,
    ValidatorStatus
} from "./ACP99Manager.sol";
import {
    IWarpMessenger,
    WarpMessage
} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable@5.0.2/access/OwnableUpgradeable.sol";
import {Initializable} from
    "@openzeppelin/contracts-upgradeable@5.0.2/proxy/utils/Initializable.sol";
import {ICMInitializable} from "@utilities/ICMInitializable.sol";

/**
 * @dev Describes the current churn period
 */
struct ValidatorChurnPeriod {
    uint256 startTime;
    uint64 initialWeight;
    uint64 totalWeight;
    uint64 churnAmount;
}

/**
 * @notice Validator Manager settings, used to initialize the Validator Manager
 * @param The subnetID is the ID of the L1 that the Validator Manager is managing
 * @param The churnPeriodSeconds is the duration of the churn period in seconds
 * @param The maximumChurnPercentage is the maximum percentage of the total weight that can be added or removed in a single churn period
 */
struct ValidatorManagerSettings {
    address admin;
    bytes32 subnetID;
    uint64 churnPeriodSeconds;
    uint8 maximumChurnPercentage;
}

/**
 * @dev Implementation of the {ACP99Manager} abstract contract.
 *
 * @custom:security-contact https://github.com/ava-labs/icm-contracts/blob/main/SECURITY.md
 */
contract ValidatorManager is Initializable, OwnableUpgradeable, ACP99Manager {
    // solhint-disable private-vars-leading-underscore
    /// @custom:storage-location erc7201:avalanche-icm.storage.ValidatorManager
    struct ValidatorManagerStorage {
        /// @notice The subnetID associated with this validator manager.
        bytes32 _subnetID;
        /// @notice The number of seconds after which to reset the churn tracker.
        uint64 _churnPeriodSeconds;
        /// @notice The maximum churn rate allowed per churn period.
        uint8 _maximumChurnPercentage;
        /// @notice The churn tracker used to track the amount of stake added or removed in the churn period.
        ValidatorChurnPeriod _churnTracker;
        /// @notice Maps the validationID to the registration message such that the message can be re-sent if needed.
        mapping(bytes32 => bytes) _pendingRegisterValidationMessages;
        /// @notice Maps the validationID to the validator information.
        mapping(bytes32 => Validator) _validationPeriods;
        /// @notice Maps the nodeID to the validationID for validation periods that have not ended.
        mapping(bytes => bytes32) _registeredValidators;
        /// @notice Boolean that indicates if the initial validator set has been set.
        bool _initializedValidatorSet;
    }
    // solhint-enable private-vars-leading-underscore

    // keccak256(abi.encode(uint256(keccak256("avalanche-icm.storage.ValidatorManager")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 public constant VALIDATOR_MANAGER_STORAGE_LOCATION =
        0xe92546d698950ddd38910d2e15ed1d923cd0a7b3dde9e2a6a3f380565559cb00;

    uint8 public constant MAXIMUM_CHURN_PERCENTAGE_LIMIT = 20;
    uint64 public constant MAXIMUM_REGISTRATION_EXPIRY_LENGTH = 2 days;
    uint32 public constant ADDRESS_LENGTH = 20; // This is only used as a packed uint32
    uint32 public constant NODE_ID_LENGTH = 20;
    uint8 public constant BLS_PUBLIC_KEY_LENGTH = 48;
    bytes32 public constant P_CHAIN_BLOCKCHAIN_ID = bytes32(0);

    error InvalidValidatorManagerAddress(address validatorManagerAddress);
    error InvalidWarpOriginSenderAddress(address senderAddress);
    error InvalidValidatorManagerBlockchainID(bytes32 blockchainID);
    error InvalidWarpSourceChainID(bytes32 sourceChainID);
    error InvalidRegistrationExpiry(uint64 registrationExpiry);
    error InvalidInitializationStatus();
    error InvalidMaximumChurnPercentage(uint8 maximumChurnPercentage);
    error InvalidBLSKeyLength(uint256 length);
    error InvalidNodeID(bytes nodeID);
    error InvalidConversionID(bytes32 encodedConversionID, bytes32 expectedConversionID);
    error InvalidTotalWeight(uint64 weight);
    error InvalidValidationID(bytes32 validationID);
    error InvalidValidatorStatus(ValidatorStatus status);
    error InvalidNonce(uint64 nonce);
    error InvalidWarpMessage();
    error MaxChurnRateExceeded(uint64 churnAmount);
    error NodeAlreadyRegistered(bytes nodeID);
    error UnexpectedRegistrationStatus(bool validRegistration);
    error InvalidPChainOwnerThreshold(uint256 threshold, uint256 addressesLength);
    error PChainOwnerAddressesNotSorted();
    error UnauthorizedCaller(address caller);

    // solhint-disable ordering
    /**
     * @dev This storage is visible to child contracts for convenience.
     *      External getters would be better practice, but code size limitations are preventing this.
     *      Child contracts should probably never write to this storage.
     */
    function _getValidatorManagerStorage()
        internal
        pure
        returns (ValidatorManagerStorage storage $)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := VALIDATOR_MANAGER_STORAGE_LOCATION
        }
    }

    /**
     * @notice Warp precompile used for sending and receiving Warp messages.
     */
    IWarpMessenger public constant WARP_MESSENGER =
        IWarpMessenger(0x0200000000000000000000000000000000000005);

    constructor(
        ICMInitializable init
    ) {
        if (init == ICMInitializable.Disallowed) {
            _disableInitializers();
        }
    }

    function initialize(
        ValidatorManagerSettings calldata settings
    ) external reinitializer(3) {
        __ValidatorManager_init(settings);
    }

    // solhint-disable-next-line func-name-mixedcase
    function __ValidatorManager_init(
        ValidatorManagerSettings calldata settings
    ) internal onlyInitializing {
        __Ownable_init(settings.admin);
        __ValidatorManager_init_unchained(settings);
    }

    // solhint-disable-next-line func-name-mixedcase
    function __ValidatorManager_init_unchained(
        ValidatorManagerSettings calldata settings
    ) internal onlyInitializing {
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();
        $._subnetID = settings.subnetID;

        if (
            settings.maximumChurnPercentage > MAXIMUM_CHURN_PERCENTAGE_LIMIT
                || settings.maximumChurnPercentage == 0
        ) {
            revert InvalidMaximumChurnPercentage(settings.maximumChurnPercentage);
        }

        $._maximumChurnPercentage = settings.maximumChurnPercentage;
        $._churnPeriodSeconds = settings.churnPeriodSeconds;
    }

    modifier initializedValidatorSet() {
        if (!_getValidatorManagerStorage()._initializedValidatorSet) {
            revert InvalidInitializationStatus();
        }
        _;
    }

    /**
     * @notice See {ACP99Manager-initializeValidatorSet}.
     */
    function initializeValidatorSet(
        ConversionData calldata conversionData,
        uint32 messageIndex
    ) public virtual override {
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();
        if ($._initializedValidatorSet) {
            revert InvalidInitializationStatus();
        }
        // Check that the blockchainID and validator manager address in the ConversionData correspond to this contract.
        // Other validation checks are done by the P-Chain when converting the L1, so are not required here.
        if (conversionData.validatorManagerBlockchainID != WARP_MESSENGER.getBlockchainID()) {
            revert InvalidValidatorManagerBlockchainID(conversionData.validatorManagerBlockchainID);
        }
        if (address(conversionData.validatorManagerAddress) != address(this)) {
            revert InvalidValidatorManagerAddress(address(conversionData.validatorManagerAddress));
        }

        uint256 numInitialValidators = conversionData.initialValidators.length;

        uint64 totalWeight;
        for (uint32 i; i < numInitialValidators; ++i) {
            InitialValidator memory initialValidator = conversionData.initialValidators[i];
            if ($._registeredValidators[initialValidator.nodeID] != bytes32(0)) {
                revert NodeAlreadyRegistered(initialValidator.nodeID);
            }
            if (initialValidator.nodeID.length != NODE_ID_LENGTH) {
                revert InvalidNodeID(initialValidator.nodeID);
            }

            // Validation ID of the initial validators is the sha256 hash of the
            // convert subnet to L1 tx ID and the index of the initial validator.
            bytes32 validationID = sha256(abi.encodePacked(conversionData.subnetID, i));

            // Save the initial validator as an active validator.
            $._registeredValidators[initialValidator.nodeID] = validationID;
            $._validationPeriods[validationID].status = ValidatorStatus.Active;
            $._validationPeriods[validationID].nodeID = initialValidator.nodeID;
            $._validationPeriods[validationID].startingWeight = initialValidator.weight;
            $._validationPeriods[validationID].sentNonce = 0;
            $._validationPeriods[validationID].weight = initialValidator.weight;
            $._validationPeriods[validationID].startTime = uint64(block.timestamp);
            $._validationPeriods[validationID].endTime = 0;
            totalWeight += initialValidator.weight;

            emit RegisteredInitialValidator(
                validationID, _fixedNodeID(initialValidator.nodeID), initialValidator.weight
            );
        }
        $._churnTracker.totalWeight = totalWeight;

        // Rearranged equation for totalWeight < (100 / $._maximumChurnPercentage)
        // Total weight must be above this value in order to not trigger churn limits with an added/removed weight of 1.
        if (totalWeight * $._maximumChurnPercentage < 100) {
            revert InvalidTotalWeight(totalWeight);
        }

        // Verify that the sha256 hash of the L1 conversion data matches with the Warp message's conversionID.
        bytes32 conversionID = ValidatorMessages.unpackSubnetToL1ConversionMessage(
            _getPChainWarpMessage(messageIndex).payload
        );
        bytes memory encodedConversion = ValidatorMessages.packConversionData(conversionData);
        bytes32 encodedConversionID = sha256(encodedConversion);
        if (encodedConversionID != conversionID) {
            revert InvalidConversionID(encodedConversionID, conversionID);
        }

        $._initializedValidatorSet = true;
    }

    function _validatePChainOwner(
        PChainOwner memory pChainOwner
    ) internal pure {
        // If threshold is 0, addresses must be empty.
        if (pChainOwner.threshold == 0 && pChainOwner.addresses.length != 0) {
            revert InvalidPChainOwnerThreshold(pChainOwner.threshold, pChainOwner.addresses.length);
        }
        // Threshold must be less than or equal to the number of addresses.
        if (pChainOwner.threshold > pChainOwner.addresses.length) {
            revert InvalidPChainOwnerThreshold(pChainOwner.threshold, pChainOwner.addresses.length);
        }
        // Addresses must be sorted in ascending order
        for (uint256 i = 1; i < pChainOwner.addresses.length; i++) {
            // Compare current address with the previous one
            if (pChainOwner.addresses[i] < pChainOwner.addresses[i - 1]) {
                revert PChainOwnerAddressesNotSorted();
            }
        }
    }

    function initiateValidatorRegistration(
        bytes memory nodeID,
        bytes memory blsPublicKey,
        uint64 registrationExpiry,
        PChainOwner memory remainingBalanceOwner,
        PChainOwner memory disableOwner,
        uint64 weight
    ) public onlyOwner returns (bytes32) {
        return _initiateValidatorRegistration({
            nodeID: nodeID,
            blsPublicKey: blsPublicKey,
            registrationExpiry: registrationExpiry,
            remainingBalanceOwner: remainingBalanceOwner,
            disableOwner: disableOwner,
            weight: weight
        });
    }

    /**
     * @notice See {ACP99Manager-_initiateValidatorRegistration}.
     * @dev This function modifies the validator's state. Callers should ensure that any references are updated.
     */
    function _initiateValidatorRegistration(
        bytes memory nodeID,
        bytes memory blsPublicKey,
        uint64 registrationExpiry,
        PChainOwner memory remainingBalanceOwner,
        PChainOwner memory disableOwner,
        uint64 weight
    ) internal virtual override initializedValidatorSet returns (bytes32) {
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();

        if (
            registrationExpiry <= block.timestamp
                || registrationExpiry >= block.timestamp + MAXIMUM_REGISTRATION_EXPIRY_LENGTH
        ) {
            revert InvalidRegistrationExpiry(registrationExpiry);
        }

        // Ensure the new validator doesn't overflow the total weight
        if (uint256(weight) + uint256($._churnTracker.totalWeight) > type(uint64).max) {
            revert InvalidTotalWeight(weight);
        }

        _validatePChainOwner(remainingBalanceOwner);
        _validatePChainOwner(disableOwner);

        // Ensure the nodeID is not the zero address, and is not already an active validator.

        if (blsPublicKey.length != BLS_PUBLIC_KEY_LENGTH) {
            revert InvalidBLSKeyLength(blsPublicKey.length);
        }
        if (nodeID.length != NODE_ID_LENGTH) {
            revert InvalidNodeID(nodeID);
        }
        if ($._registeredValidators[nodeID] != bytes32(0)) {
            revert NodeAlreadyRegistered(nodeID);
        }

        // Check that adding this validator would not exceed the maximum churn rate.
        _checkAndUpdateChurnTracker(weight, 0);

        (bytes32 validationID, bytes memory registerL1ValidatorMessage) = ValidatorMessages
            .packRegisterL1ValidatorMessage(
            ValidatorMessages.ValidationPeriod({
                subnetID: $._subnetID,
                nodeID: nodeID,
                blsPublicKey: blsPublicKey,
                remainingBalanceOwner: remainingBalanceOwner,
                disableOwner: disableOwner,
                registrationExpiry: registrationExpiry,
                weight: weight
            })
        );
        $._pendingRegisterValidationMessages[validationID] = registerL1ValidatorMessage;
        $._registeredValidators[nodeID] = validationID;

        // Submit the message to the Warp precompile.
        bytes32 messageID = WARP_MESSENGER.sendWarpMessage(registerL1ValidatorMessage);
        $._validationPeriods[validationID].status = ValidatorStatus.PendingAdded;
        $._validationPeriods[validationID].nodeID = nodeID;
        $._validationPeriods[validationID].startingWeight = weight;
        $._validationPeriods[validationID].sentNonce = 0;
        $._validationPeriods[validationID].weight = weight;
        $._validationPeriods[validationID].startTime = 0; // The validation period only starts once the registration is acknowledged.
        $._validationPeriods[validationID].endTime = 0;

        emit InitiatedValidatorRegistration(
            validationID, _fixedNodeID(nodeID), messageID, registrationExpiry, weight
        );

        return validationID;
    }

    /**
     * @notice Resubmits a validator registration message to be sent to the P-Chain.
     * Only necessary if the original message can't be delivered due to validator churn.
     * @param validationID The ID of the validation period being registered.
     */
    function resendRegisterValidatorMessage(
        bytes32 validationID
    ) external {
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();
        // The initial validator set must have been set already to have pending register validation messages.
        if ($._pendingRegisterValidationMessages[validationID].length == 0) {
            revert InvalidValidationID(validationID);
        }
        if ($._validationPeriods[validationID].status != ValidatorStatus.PendingAdded) {
            revert InvalidValidatorStatus($._validationPeriods[validationID].status);
        }

        // Submit the message to the Warp precompile.
        WARP_MESSENGER.sendWarpMessage($._pendingRegisterValidationMessages[validationID]);
    }

    /**
     * @notice See {ACP99Manager-completeValidatorRegistration}.
     */
    function completeValidatorRegistration(
        uint32 messageIndex
    ) public virtual override onlyOwner returns (bytes32) {
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();
        (bytes32 validationID, bool validRegistration) = ValidatorMessages
            .unpackL1ValidatorRegistrationMessage(_getPChainWarpMessage(messageIndex).payload);

        if (!validRegistration) {
            revert UnexpectedRegistrationStatus(validRegistration);
        }
        // The initial validator set must have been set already to have pending register validation messages.
        if ($._pendingRegisterValidationMessages[validationID].length == 0) {
            revert InvalidValidationID(validationID);
        }
        if ($._validationPeriods[validationID].status != ValidatorStatus.PendingAdded) {
            revert InvalidValidatorStatus($._validationPeriods[validationID].status);
        }

        delete $._pendingRegisterValidationMessages[validationID];
        $._validationPeriods[validationID].status = ValidatorStatus.Active;
        $._validationPeriods[validationID].startTime = uint64(block.timestamp);
        emit CompletedValidatorRegistration(validationID, $._validationPeriods[validationID].weight);

        return validationID;
    }

    /**
     * @notice Returns a validation ID registered to the given nodeID
     * @param nodeID ID of the node associated with the validation ID
     */
    function registeredValidators(
        bytes calldata nodeID
    ) public view returns (bytes32) {
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();
        return $._registeredValidators[nodeID];
    }

    /**
     * @notice See {ACP99Manager-getValidator}.
     */
    function getValidator(
        bytes32 validationID
    ) public view virtual override returns (Validator memory) {
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();
        return $._validationPeriods[validationID];
    }

    /**
     * @notice See {ACP99Manager-l1TotalWeight}.
     */
    function l1TotalWeight() public view virtual override returns (uint64) {
        return _getValidatorManagerStorage()._churnTracker.totalWeight;
    }

    /**
     * @notice See {ACP99Manager-subnetID}.
     */
    function subnetID() public view virtual override returns (bytes32) {
        return _getValidatorManagerStorage()._subnetID;
    }

    /**
     * @notice See {ACP99Manager-completeValidatorWeightUpdate}.
     */
    function completeValidatorWeightUpdate(
        uint32 messageIndex
    ) public virtual override onlyOwner returns (bytes32, uint64) {
        WarpMessage memory warpMessage = _getPChainWarpMessage(messageIndex);
        (bytes32 validationID, uint64 nonce, uint64 weight) =
            ValidatorMessages.unpackL1ValidatorWeightMessage(warpMessage.payload);

        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();

        // The received nonce should be no greater than the highest sent nonce to ensure
        // that weight changes are only initiated by this contract.
        if ($._validationPeriods[validationID].sentNonce < nonce) {
            revert InvalidNonce(nonce);
        }

        $._validationPeriods[validationID].receivedNonce = nonce;

        emit CompletedValidatorWeightUpdate(validationID, nonce, weight);

        return (validationID, nonce);
    }

    function initiateValidatorRemoval(
        bytes32 validationID
    ) public onlyOwner {
        _initiateValidatorRemoval(validationID);
    }

    /**
     * @notice See {ACP99Manager-_initiateValidatorRemoval}.
     * @dev This function modifies the validator's state. Callers should ensure that any references are updated.
     */
    function _initiateValidatorRemoval(
        bytes32 validationID
    ) internal virtual override {
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();

        // Ensure the validation period is active.
        // The initial validator set must have been set already to have active validators.
        Validator memory validator = $._validationPeriods[validationID];
        if (validator.status != ValidatorStatus.Active) {
            revert InvalidValidatorStatus($._validationPeriods[validationID].status);
        }

        // Update the validator status to pending removal.
        // They are not removed from the active validators mapping until the P-Chain acknowledges the removal.
        validator.status = ValidatorStatus.PendingRemoved;

        // Set the end time of the validation period, since it is no longer known to be an active validator
        // on the P-Chain.
        validator.endTime = uint64(block.timestamp);

        // Save the validator updates.
        $._validationPeriods[validationID] = validator;

        (, bytes32 messageID) = _initiateValidatorWeightUpdate(validationID, 0);

        // Emit the event to signal the start of the validator removal process.
        emit InitiatedValidatorRemoval(
            validationID, messageID, validator.weight, uint64(block.timestamp)
        );
    }

    /**
     * @notice Resubmits a validator end message to be sent to the P-Chain.
     * Only necessary if the original message can't be delivered due to validator churn.
     * @param validationID The ID of the validation period being ended.
     */
    function resendEndValidatorMessage(
        bytes32 validationID
    ) external {
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();
        Validator memory validator = $._validationPeriods[validationID];

        // The initial validator set must have been set already to have pending end validation messages.
        if (validator.status != ValidatorStatus.PendingRemoved) {
            revert InvalidValidatorStatus($._validationPeriods[validationID].status);
        }

        WARP_MESSENGER.sendWarpMessage(
            ValidatorMessages.packL1ValidatorWeightMessage(validationID, validator.sentNonce, 0)
        );
    }

    /**
     * @notice See {ACP99Manager-completeValidatorRemoval}.
     */
    function completeValidatorRemoval(
        uint32 messageIndex
    ) public virtual override onlyOwner returns (bytes32) {
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();

        // Get the Warp message.
        (bytes32 validationID, bool validRegistration) = ValidatorMessages
            .unpackL1ValidatorRegistrationMessage(_getPChainWarpMessage(messageIndex).payload);
        if (validRegistration) {
            revert UnexpectedRegistrationStatus(validRegistration);
        }

        Validator memory validator = $._validationPeriods[validationID];

        // The validation status is PendingRemoved if validator removal was initiated with a call to {initiateValidatorRemoval}.
        // The validation status is PendingAdded if the validator was never registered on the P-Chain.
        // The initial validator set must have been set already to have pending validation messages.
        if (
            validator.status != ValidatorStatus.PendingRemoved
                && validator.status != ValidatorStatus.PendingAdded
        ) {
            revert InvalidValidatorStatus(validator.status);
        }

        if (validator.status == ValidatorStatus.PendingRemoved) {
            validator.status = ValidatorStatus.Completed;
        } else {
            validator.status = ValidatorStatus.Invalidated;
        }
        // Remove the validator from the registered validators mapping.
        delete $._registeredValidators[validator.nodeID];

        // Update the validator.
        $._validationPeriods[validationID] = validator;

        // Emit event.
        emit CompletedValidatorRemoval(validationID);

        return validationID;
    }

    function _incrementSentNonce(
        bytes32 validationID
    ) internal returns (uint64) {
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();
        return ++$._validationPeriods[validationID].sentNonce;
    }

    function _getPChainWarpMessage(
        uint32 messageIndex
    ) internal view returns (WarpMessage memory) {
        (WarpMessage memory warpMessage, bool valid) =
            WARP_MESSENGER.getVerifiedWarpMessage(messageIndex);
        if (!valid) {
            revert InvalidWarpMessage();
        }
        // Must match to P-Chain blockchain id, which is 0.
        if (warpMessage.sourceChainID != P_CHAIN_BLOCKCHAIN_ID) {
            revert InvalidWarpSourceChainID(warpMessage.sourceChainID);
        }
        if (warpMessage.originSenderAddress != address(0)) {
            revert InvalidWarpOriginSenderAddress(warpMessage.originSenderAddress);
        }

        return warpMessage;
    }

    function initiateValidatorWeightUpdate(
        bytes32 validationID,
        uint64 newWeight
    ) public onlyOwner returns (uint64, bytes32) {
        return _initiateValidatorWeightUpdate(validationID, newWeight);
    }

    /**
     * @notice See {ACP99Manager-_initiateValidatorWeightUpdate}.
     * @dev This function modifies the validator's state. Callers should ensure that any references are updated.
     */
    function _initiateValidatorWeightUpdate(
        bytes32 validationID,
        uint64 newWeight
    ) internal virtual override returns (uint64, bytes32) {
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();
        uint64 validatorWeight = $._validationPeriods[validationID].weight;

        // Check that changing the validator weight would not exceed the maximum churn rate.
        _checkAndUpdateChurnTracker(newWeight, validatorWeight);

        uint64 nonce = _incrementSentNonce(validationID);

        $._validationPeriods[validationID].weight = newWeight;

        // Submit the message to the Warp precompile.
        bytes32 messageID = WARP_MESSENGER.sendWarpMessage(
            ValidatorMessages.packL1ValidatorWeightMessage(validationID, nonce, newWeight)
        );

        emit InitiatedValidatorWeightUpdate({
            validationID: validationID,
            nonce: nonce,
            weightUpdateMessageID: messageID,
            weight: newWeight
        });

        return (nonce, messageID);
    }

    function getChurnPeriodSeconds() public view returns (uint64) {
        return _getValidatorManagerStorage()._churnPeriodSeconds;
    }

    /**
     * @dev Helper function to check if the stake weight to be added or removed would exceed the maximum stake churn
     * rate for the past churn period. If the churn rate is exceeded, the function will revert. If the churn rate is
     * not exceeded, the function will update the churn tracker with the new weight.
     */
    function _checkAndUpdateChurnTracker(
        uint64 newValidatorWeight,
        uint64 oldValidatorWeight
    ) private {
        ValidatorManagerStorage storage $ = _getValidatorManagerStorage();

        uint64 weightChange;
        if (newValidatorWeight > oldValidatorWeight) {
            weightChange = newValidatorWeight - oldValidatorWeight;
        } else {
            weightChange = oldValidatorWeight - newValidatorWeight;
        }

        uint256 currentTime = block.timestamp;
        ValidatorChurnPeriod memory churnTracker = $._churnTracker;

        if (
            churnTracker.startTime == 0
                || currentTime >= churnTracker.startTime + $._churnPeriodSeconds
        ) {
            churnTracker.churnAmount = weightChange;
            churnTracker.startTime = currentTime;
            churnTracker.initialWeight = churnTracker.totalWeight;
        } else {
            // Churn is always additive whether the weight is being added or removed.
            churnTracker.churnAmount += weightChange;
        }

        // Rearranged equation of maximumChurnPercentage >= currentChurnPercentage to avoid integer division truncation.
        if ($._maximumChurnPercentage * churnTracker.initialWeight < churnTracker.churnAmount * 100)
        {
            revert MaxChurnRateExceeded(churnTracker.churnAmount);
        }

        // Two separate calculations because we're using uints and (newValidatorWeight - oldValidatorWeight) could underflow.
        churnTracker.totalWeight += newValidatorWeight;
        churnTracker.totalWeight -= oldValidatorWeight;

        // Rearranged equation for totalWeight < (100 / $._maximumChurnPercentage)
        // Total weight must be above this value in order to not trigger churn limits with an added/removed weight of 1.
        if (churnTracker.totalWeight * $._maximumChurnPercentage < 100) {
            revert InvalidTotalWeight(churnTracker.totalWeight);
        }

        $._churnTracker = churnTracker;
    }

    /**
     * @notice Converts a nodeID to a fixed length of 20 bytes.
     * @param nodeID The nodeID to convert.
     * @return The fixed length nodeID.
     */
    function _fixedNodeID(
        bytes memory nodeID
    ) private pure returns (bytes20) {
        bytes20 fixedID;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            fixedID := mload(add(nodeID, 32))
        }
        return fixedID;
    }
}




Stakign manager below ***********************************************************************************************



// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {ValidatorManager} from "./ValidatorManager.sol";
import {ValidatorMessages} from "./ValidatorMessages.sol";
import {
    Delegator,
    DelegatorStatus,
    IStakingManager,
    PoSValidatorInfo,
    StakingManagerSettings
} from "./interfaces/IStakingManager.sol";
import {Validator, ValidatorStatus, PChainOwner} from "./ACP99Manager.sol";
import {
    IWarpMessenger,
    WarpMessage
} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin/contracts-upgradeable@5.0.2/utils/ReentrancyGuardUpgradeable.sol";
import {ContextUpgradeable} from
    "@openzeppelin/contracts-upgradeable@5.0.2/utils/ContextUpgradeable.sol";

/**
 * @dev Implementation of the {IStakingManager} interface.
 *
 * @custom:security-contact https://github.com/ava-labs/icm-contracts/blob/main/SECURITY.md
 */
abstract contract StakingManager is
    IStakingManager,
    ContextUpgradeable,
    ReentrancyGuardUpgradeable
{
    // solhint-disable private-vars-leading-underscore
    /// @custom:storage-location erc7201:avalanche-icm.storage.StakingManager
    struct StakingManagerStorage {
        ValidatorManager _manager;
        /// @notice The minimum amount of stake required to be a validator.
        uint256 _minimumStakeAmount;
        /// @notice The maximum amount of stake allowed to be a validator.
        uint256 _maximumStakeAmount;
        /// @notice The minimum amount of time in seconds a validator must be staked for. Must be at least {_churnPeriodSeconds}.
        uint64 _minimumStakeDuration;
        /// @notice The maximum amount of staked NFTs allowed to be a validator.
        uint256 _maximumNFTAmount;
        /// @notice The minimum delegation amount
        uint256 _minimumDelegationAmount;
        /// @notice The minimum delegation fee percentage, in basis points, required to delegate to a validator.
        uint16 _minimumDelegationFeeBips;
        /// @notice The factor used to convert between weight and value.
        uint256 _weightToValueFactor;
        /// @notice The ID of the blockchain that submits uptime proofs. This must be a blockchain validated by the subnetID that this contract manages.
        bytes32 _uptimeBlockchainID;
        /// @notice admin address
        address _admin;
        /// @notice The duration of an epoch in seconds
        uint64 _epochDuration;
        /// @notice The duration of the unlock period in seconds
        uint64 _unlockDuration;
        /// @notice Maps the validation ID to its requirements.
        mapping(bytes32 validationID => PoSValidatorInfo) _posValidatorInfo;
        /// @notice Maps the delegation ID to the delegator information.
        mapping(bytes32 delegationID => Delegator) _delegatorStakes;
        mapping(bytes32 delegationID => uint256[]) _lockedNFTs;
        mapping(uint64 epoch => uint256) _totalRewardWeight;
        mapping(uint64 epoch => uint256) _totalRewardWeightNFT;
        mapping(uint64 epoch => mapping(address account => uint256)) _accountRewardWeight;
        mapping(uint64 epoch => mapping(address account => uint256)) _accountRewardWeightNFT;
        mapping(uint64 epoch => mapping(address account => mapping(address token => uint256)))
            _rewardWithdrawn;
        mapping(uint64 epoch => mapping(address account => mapping(address token => uint256)))
            _rewardWithdrawnNFT;
        mapping(uint64 epoch => mapping(address token => uint256)) _rewardPools;
        mapping(uint64 epoch => mapping(address token => uint256)) _rewardPoolsNFT;
        uint64 _epochOffset;
        mapping(bytes32 ID => bool) _unlocked;
        mapping(uint64 epoch => mapping(bytes32 validationID => uint256)) _validationUptimes;
        address _uptimeKeeper;
    }
    // solhint-enable private-vars-leading-underscore

    // keccak256(abi.encode(uint256(keccak256("avalanche-icm.storage.StakingManager")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 public constant STAKING_MANAGER_STORAGE_LOCATION =
        0xafe6c4731b852fc2be89a0896ae43d22d8b24989064d841b2a1586b4d39ab600;

    uint16 public constant MAXIMUM_DELEGATION_FEE_BIPS = 10000;

    uint16 public constant BIPS_CONVERSION_FACTOR = 10000;

    bytes32 public constant P_CHAIN_BLOCKCHAIN_ID = bytes32(0);

    IWarpMessenger public constant WARP_MESSENGER =
        IWarpMessenger(0x0200000000000000000000000000000000000005);

    error InvalidDelegationFee(uint16 delegationFeeBips);
    error InvalidDelegationID(bytes32 delegationID);
    error InvalidDelegatorStatus(DelegatorStatus status);
    error InvalidStakeAmount(uint256 stakeAmount);
    error InvalidMinStakeDuration(uint64 minStakeDuration);
    error MaxWeightExceeded(uint64 newValidatorWeight);
    error MinStakeDurationNotPassed(uint64 endTime);
    error UnauthorizedOwner(address sender);
    error ValidatorNotPoS(bytes32 validationID);
    error ZeroWeightToValueFactor();
    error InvalidUptimeBlockchainID(bytes32 uptimeBlockchainID);
    error UnlockDurationNotPassed(uint64 endTime);
    error InvalidWarpOriginSenderAddress(address senderAddress);
    error InvalidWarpSourceChainID(bytes32 sourceChainID);
    error UnexpectedValidationID(bytes32 validationID, bytes32 expectedValidationID);
    error InvalidValidatorStatus(ValidatorStatus status);
    error InvalidNonce(uint64 nonce);
    error InvalidWarpMessage();

    // solhint-disable ordering
    /**
     * @dev This storage is visible to child contracts for convenience.
     *      External getters would be better practice, but code size limitations are preventing this.
     *      Child contracts should probably never write to this storage.
     */
    function _getStakingManagerStorage() internal pure returns (StakingManagerStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := STAKING_MANAGER_STORAGE_LOCATION
        }
    }

    // solhint-disable-next-line func-name-mixedcase
    function __StakingManager_init(
        StakingManagerSettings calldata settings
    ) internal onlyInitializing {
        __ReentrancyGuard_init();
        __StakingManager_init_unchained({
            manager: settings.manager,
            minimumStakeAmount: settings.minimumStakeAmount,
            maximumStakeAmount: settings.maximumStakeAmount,
            minimumStakeDuration: settings.minimumStakeDuration,
            minimumDelegationAmount: settings.minimumDelegationAmount,
            minimumDelegationFeeBips: settings.minimumDelegationFeeBips,
            admin: settings.admin,
            weightToValueFactor: settings.weightToValueFactor,
            uptimeBlockchainID: settings.uptimeBlockchainID,
            unlockDuration: settings.unlockDuration,
            epochDuration: settings.epochDuration,
            maximumNFTAmount: settings.maximumNFTAmount,
            uptimeKeeper: settings.uptimeKeeper,
            epochOffset: settings.epochOffset
        });
    }

    // solhint-disable-next-line func-name-mixedcase
    function __StakingManager_init_unchained(
        ValidatorManager manager,
        uint256 minimumStakeAmount,
        uint256 maximumStakeAmount,
        uint256 maximumNFTAmount,
        uint64 minimumStakeDuration,
        uint256 minimumDelegationAmount,
        uint16 minimumDelegationFeeBips,
        address admin,
        uint256 weightToValueFactor,
        bytes32 uptimeBlockchainID,
        uint64 unlockDuration,
        uint64 epochDuration,
        address uptimeKeeper,
        uint64 epochOffset
    ) internal onlyInitializing {
        StakingManagerStorage storage $ = _getStakingManagerStorage();
        if (minimumDelegationFeeBips == 0 || minimumDelegationFeeBips > MAXIMUM_DELEGATION_FEE_BIPS)
        {
            revert InvalidDelegationFee(minimumDelegationFeeBips);
        }
        if (minimumStakeAmount > maximumStakeAmount) {
            revert InvalidStakeAmount(minimumStakeAmount);
        }
        // Minimum stake duration should be at least one churn period in order to prevent churn tracker abuse.
        if (minimumStakeDuration < manager.getChurnPeriodSeconds()) {
            revert InvalidMinStakeDuration(minimumStakeDuration);
        }
        if (weightToValueFactor == 0) {
            revert ZeroWeightToValueFactor();
        }
        if (uptimeBlockchainID == bytes32(0)) {
            revert InvalidUptimeBlockchainID(uptimeBlockchainID);
        }

        $._manager = manager;
        $._minimumStakeAmount = minimumStakeAmount;
        $._maximumStakeAmount = maximumStakeAmount;
        $._maximumNFTAmount = maximumNFTAmount;
        $._minimumStakeDuration = minimumStakeDuration;
        $._minimumDelegationAmount = minimumDelegationAmount;
        $._minimumDelegationFeeBips = minimumDelegationFeeBips;
        $._admin = admin;
        $._weightToValueFactor = weightToValueFactor;
        $._uptimeBlockchainID = uptimeBlockchainID;
        $._unlockDuration = unlockDuration;
        $._epochDuration = epochDuration;
        $._uptimeKeeper = uptimeKeeper;
        $._epochOffset = epochOffset;
    }

    /**
     * @notice See {IStakingManager-submitUptimeProof}.
     */
    function submitUptimeProof(bytes32 validationID, uint32 messageIndex) external {
        if (!_isPoSValidator(validationID)) {
            revert ValidatorNotPoS(validationID);
        }

        // Uptime proofs include the absolute number of seconds the validator has been active.
        _updateUptime(validationID, messageIndex);
    }

    /**
     * @notice See {IStakingManager-initiateValidatorRemoval}.
     * Extends the functionality of {ACP99Manager-initiateValidatorRemoval} updating staker state.
     */
    function initiateValidatorRemoval(
        bytes32 validationID,
        bool includeUptimeProof,
        uint32 messageIndex
    ) external {
        _initiatePoSValidatorRemoval(validationID);
    }

    /**
     * @dev Helper function that initiates the end of a PoS validation period.
     */
    function _initiatePoSValidatorRemoval(
        bytes32 validationID
    ) internal {
        StakingManagerStorage storage $ = _getStakingManagerStorage();

        $._manager.initiateValidatorRemoval(validationID);

        // The validator must be fetched after the removal has been initiated, since the above call modifies
        // the validator's state.
        Validator memory validator = $._manager.getValidator(validationID);

        // Non-PoS validators are required to boostrap the network, but are not eligible for rewards.
        if (!_isPoSValidator(validationID)) {
            // Initial Validators can only be removed by the removal admin
            if ($._admin != _msgSender()) {
                revert UnauthorizedOwner(_msgSender());
            }
            return;
        }

        // PoS validations can only be ended by their owners.
        if ($._posValidatorInfo[validationID].owner != _msgSender()) {
            revert UnauthorizedOwner(_msgSender());
        }

        // Check that minimum stake duration has passed.
        if (
            validator.endTime
                < validator.startTime + $._posValidatorInfo[validationID].minStakeDuration
        ) {
            revert MinStakeDurationNotPassed(validator.endTime);
        }

        return;
    }

    /**
     * @notice See {IStakingManager-completeValidatorRemoval}.
     * Extends the functionality of {ACP99Manager-completeValidatorRemoval} by unlocking staking rewards.
     */
    function completeValidatorRemoval(
        uint32 messageIndex
    ) external virtual nonReentrant returns (bytes32) {
        StakingManagerStorage storage $ = _getStakingManagerStorage();

        // Check if the validator has been already been removed from the validator manager.
        bytes32 validationID = $._manager.completeValidatorRemoval(messageIndex);

        return validationID;
    }

    /**
     * @dev Helper function that extracts the uptime from a ValidationUptimeMessage Warp message
     * If the uptime is greater than the stored uptime, update the stored uptime.
     */
    function _updateUptime(
        bytes32 validationID,
        uint32 messageIndex
    ) internal virtual returns (uint64) {
        (WarpMessage memory warpMessage, bool valid) =
            WARP_MESSENGER.getVerifiedWarpMessage(messageIndex);
        if (!valid) {
            revert InvalidWarpMessage();
        }

        StakingManagerStorage storage $ = _getStakingManagerStorage();
        // The uptime proof must be from the specifed uptime blockchain
        if (warpMessage.sourceChainID != $._uptimeBlockchainID) {
            revert InvalidWarpSourceChainID(warpMessage.sourceChainID);
        }

        // The sender is required to be the zero address so that we know the validator node
        // signed the proof directly, rather than as an arbitrary on-chain message
        if (warpMessage.originSenderAddress != address(0)) {
            revert InvalidWarpOriginSenderAddress(warpMessage.originSenderAddress);
        }
        if (warpMessage.originSenderAddress != address(0)) {
            revert InvalidWarpOriginSenderAddress(warpMessage.originSenderAddress);
        }

        (bytes32 uptimeValidationID, uint64 uptime) =
            ValidatorMessages.unpackValidationUptimeMessage(warpMessage.payload);
        if (validationID != uptimeValidationID) {
            revert UnexpectedValidationID(uptimeValidationID, validationID);
        }

        if (uptime > $._posValidatorInfo[validationID].uptimeSeconds) {
            $._posValidatorInfo[validationID].uptimeSeconds = uptime;
            emit UptimeUpdated(validationID, uptime, 0);
        } else {
            uptime = $._posValidatorInfo[validationID].uptimeSeconds;
        }

        return uptime;
    }

    /**
     * @notice Initiates validator registration. Extends the functionality of {ACP99Manager-_initiateValidatorRegistration}
     * by locking stake and setting staking and delegation parameters.
     * @param delegationFeeBips The delegation fee in basis points.
     * @param minStakeDuration The minimum stake duration in seconds.
     * @param stakeAmount The amount of stake to lock.
     */
    function _initiateValidatorRegistration(
        bytes memory nodeID,
        bytes memory blsPublicKey,
        uint64 registrationExpiry,
        PChainOwner memory remainingBalanceOwner,
        PChainOwner memory disableOwner,
        uint16 delegationFeeBips,
        uint64 minStakeDuration,
        uint256 stakeAmount
    ) internal virtual returns (bytes32) {
        StakingManagerStorage storage $ = _getStakingManagerStorage();
        // Validate and save the validator requirements
        if (
            delegationFeeBips < $._minimumDelegationFeeBips
                || delegationFeeBips > MAXIMUM_DELEGATION_FEE_BIPS
        ) {
            revert InvalidDelegationFee(delegationFeeBips);
        }

        if (minStakeDuration < $._minimumStakeDuration) {
            revert InvalidMinStakeDuration(minStakeDuration);
        }

        // Ensure the weight is within the valid range.
        if (stakeAmount < $._minimumStakeAmount || stakeAmount > $._maximumStakeAmount) {
            revert InvalidStakeAmount(stakeAmount);
        }

        // Lock the stake in the contract.
        uint256 lockedValue = _lock(stakeAmount);

        uint64 weight = valueToWeight(lockedValue);
        bytes32 validationID = $._manager.initiateValidatorRegistration({
            nodeID: nodeID,
            blsPublicKey: blsPublicKey,
            registrationExpiry: registrationExpiry,
            remainingBalanceOwner: remainingBalanceOwner,
            disableOwner: disableOwner,
            weight: weight
        });

        address owner = _msgSender();

        $._posValidatorInfo[validationID].owner = owner;
        $._posValidatorInfo[validationID].delegationFeeBips = delegationFeeBips;
        $._posValidatorInfo[validationID].minStakeDuration = minStakeDuration;
        $._posValidatorInfo[validationID].uptimeSeconds = 0;

        return validationID;
    }

    /**
     * @notice See {IStakingManager-completeValidatorRegistration}.
     */
    function completeValidatorRegistration(
        uint32 messageIndex
    ) external returns (bytes32) {
        return _getStakingManagerStorage()._manager.completeValidatorRegistration(messageIndex);
    }

    /**
     * @notice Converts a token value to a weight.
     * @param value Token value to convert.
     */
    function valueToWeight(
        uint256 value
    ) public view returns (uint64) {
        uint256 weight = value / _getStakingManagerStorage()._weightToValueFactor;
        if (weight == 0 || weight > type(uint64).max) {
            revert InvalidStakeAmount(value);
        }
        return uint64(weight);
    }

    /**
     * @notice Converts a weight to a token value.
     * @param weight weight to convert.
     */
    function weightToValue(
        uint64 weight
    ) public view returns (uint256) {
        return uint256(weight) * _getStakingManagerStorage()._weightToValueFactor;
    }

    /**
     * @notice Locks tokens in this contract.
     * @param value Number of tokens to lock.
     */
    function _lock(
        uint256 value
    ) internal virtual returns (uint256);

    /**
     * @notice Unlocks token to a specific address.
     * @param to Address to send token to.
     * @param value Number of tokens to lock.
     */
    function _unlock(address to, uint256 value) internal virtual;

    /**
     * @notice Initiates delegator registration by updating the validator's weight and storing the delegation information.
     * Extends the functionality of {ACP99Manager-initiateValidatorWeightUpdate} by locking delegation stake.
     * @param validationID The ID of the validator to delegate to.
     * @param delegatorAddress The address of the delegator.
     * @param delegationAmount The amount of stake to delegate.
     */
    function _initiateDelegatorRegistration(
        bytes32 validationID,
        address delegatorAddress,
        uint256 delegationAmount
    ) internal returns (bytes32) {
        StakingManagerStorage storage $ = _getStakingManagerStorage();
        uint64 weight = valueToWeight(_lock(delegationAmount));

        // Ensure the validation period is active
        Validator memory validator = $._manager.getValidator(validationID);
        // Check that the validation ID is a PoS validator
        if (!_isPoSValidator(validationID)) {
            revert ValidatorNotPoS(validationID);
        }
        if (validator.status != ValidatorStatus.Active) {
            revert InvalidValidatorStatus(validator.status);
        }

        if (delegationAmount < $._minimumDelegationAmount) {
            revert InvalidStakeAmount(delegationAmount);
        }
        // Update the validator weight
        uint64 newValidatorWeight = validator.weight + weight;
        if (newValidatorWeight > valueToWeight($._maximumStakeAmount)) {
            revert MaxWeightExceeded(newValidatorWeight);
        }

        (uint64 nonce, bytes32 messageID) =
            $._manager.initiateValidatorWeightUpdate(validationID, newValidatorWeight);

        bytes32 delegationID = keccak256(abi.encodePacked(validationID, nonce));

        // Store the delegation information. Set the delegator status to pending added,
        // so that it can be properly started in the complete step, even if the delivered
        // nonce is greater than the nonce used to initiate registration.
        $._delegatorStakes[delegationID].status = DelegatorStatus.PendingAdded;
        $._delegatorStakes[delegationID].owner = delegatorAddress;
        $._delegatorStakes[delegationID].validationID = validationID;
        $._delegatorStakes[delegationID].weight = weight;
        $._delegatorStakes[delegationID].startTime = 0;
        $._delegatorStakes[delegationID].startingNonce = nonce;
        $._delegatorStakes[delegationID].endingNonce = 0;

        emit InitiatedDelegatorRegistration({
            delegationID: delegationID,
            validationID: validationID,
            delegatorAddress: delegatorAddress,
            nonce: nonce,
            validatorWeight: newValidatorWeight,
            delegatorWeight: weight,
            setWeightMessageID: messageID
        });
        return delegationID;
    }

    /**
     * @notice See {IStakingManager-completeDelegatorRegistration}.
     * Extends the functionality of {ACP99Manager-completeValidatorWeightUpdate} by updating the delegation status.
     */
    function completeDelegatorRegistration(bytes32 delegationID, uint32 messageIndex) external {
        StakingManagerStorage storage $ = _getStakingManagerStorage();

        Delegator memory delegator = $._delegatorStakes[delegationID];
        bytes32 validationID = delegator.validationID;
        Validator memory validator = $._manager.getValidator(validationID);

        // Ensure the delegator is pending added. Since anybody can call this function once
        // delegator registration has been initiated, we need to make sure that this function is only
        // callable after that has been done.
        if (delegator.status != DelegatorStatus.PendingAdded) {
            revert InvalidDelegatorStatus(delegator.status);
        }

        // In the case where the validator has completed its validation period, we can no
        // longer stake and should move our status directly to completed and return the stake.
        if (validator.status == ValidatorStatus.Completed) {
            return _completeDelegatorRemoval(delegationID);
        }

        // If we've already received a weight update with a nonce greater than the delegation's starting nonce,
        // then there's no requirement to include an ICM message in this function call.
        if (validator.receivedNonce < delegator.startingNonce) {
            (bytes32 messageValidationID, uint64 nonce) =
                $._manager.completeValidatorWeightUpdate(messageIndex);

            if (validationID != messageValidationID) {
                revert UnexpectedValidationID(messageValidationID, validationID);
            }
            if (nonce < delegator.startingNonce) {
                revert InvalidNonce(nonce);
            }
        }

        // Update the delegation status
        $._delegatorStakes[delegationID].status = DelegatorStatus.Active;
        $._delegatorStakes[delegationID].startTime = uint64(block.timestamp);

        emit CompletedDelegatorRegistration({
            delegationID: delegationID,
            validationID: validationID,
            startTime: uint64(block.timestamp)
        });
    }

    /**
     * @notice See {IStakingManager-initiateRedelegation}.
     */
    function initiateRedelegation(
        bytes32 delegationID,
        bytes32 validationID
    ) external returns (bytes32) {
        StakingManagerStorage storage $ = _getStakingManagerStorage();
        Delegator memory delegator = $._delegatorStakes[delegationID];

        // Ensure the delegator is removed and tokens are not unlocked yet
        if (delegator.status != DelegatorStatus.Removed || $._unlocked[delegationID]) {
            revert InvalidDelegatorStatus(delegator.status);
        }

        $._unlocked[delegationID] = true;
        emit UnlockedDelegation(delegationID);

        // Ensure the validation period is active
        Validator memory validator = $._manager.getValidator(validationID);
        // Check that the validation ID is a PoS validator
        if (!_isPoSValidator(validationID)) {
            revert ValidatorNotPoS(validationID);
        }
        if (validator.status != ValidatorStatus.Active) {
            revert InvalidValidatorStatus(validator.status);
        }

        // Update the validator weight
        uint64 newValidatorWeight = validator.weight + delegator.weight;
        if (newValidatorWeight > valueToWeight($._maximumStakeAmount)) {
            revert MaxWeightExceeded(newValidatorWeight);
        }

        (uint64 nonce, bytes32 messageID) =
            $._manager.initiateValidatorWeightUpdate(validationID, newValidatorWeight);

        delegationID = keccak256(abi.encodePacked(validationID, nonce));

        // Store the delegation information. Set the delegator status to pending added,
        // so that it can be properly started in the complete step, even if the delivered
        // nonce is greater than the nonce used to initiate registration.
        $._delegatorStakes[delegationID].status = DelegatorStatus.PendingAdded;
        $._delegatorStakes[delegationID].owner = delegator.owner;
        $._delegatorStakes[delegationID].validationID = validationID;
        $._delegatorStakes[delegationID].weight = delegator.weight;
        $._delegatorStakes[delegationID].startTime = 0;
        $._delegatorStakes[delegationID].startingNonce = nonce;
        $._delegatorStakes[delegationID].endingNonce = 0;

        emit InitiatedDelegatorRegistration({
            delegationID: delegationID,
            validationID: validationID,
            delegatorAddress: delegator.owner,
            nonce: nonce,
            validatorWeight: newValidatorWeight,
            delegatorWeight: delegator.weight,
            setWeightMessageID: messageID
        });
        return delegationID;
    }

    /**
     * @notice See {IStakingManager-initiateDelegatorRemoval}.
     */
    function initiateDelegatorRemoval(
        bytes32 delegationID,
        bool includeUptimeProof,
        uint32 messageIndex
    ) external {
        _initiateDelegatorRemoval(delegationID);
    }

    /**
     * @notice Initiates the process of ending an delegation for a given delegation ID.
     * @dev This function ensures that the delegation is active and validates that the caller is authorized to end it.
     *      If the validator status is valid, the delegation status is updated to `PendingRemoved`. If the validator
     *      is complete, then removal is completed directly. Status is updated to `Completed` and initate
     *      `InitiatedDelegatorRemoval` is not emitted.
     * @param delegationID The unique identifier of the delegation to be ended.
     *
     */
    function _initiateDelegatorRemoval(
        bytes32 delegationID
    ) internal {
        StakingManagerStorage storage $ = _getStakingManagerStorage();

        Delegator memory delegator = $._delegatorStakes[delegationID];
        bytes32 validationID = delegator.validationID;
        Validator memory validator = $._manager.getValidator(validationID);

        // Ensure the delegator is active
        if (delegator.status != DelegatorStatus.Active) {
            revert InvalidDelegatorStatus(delegator.status);
        }

        if (delegator.owner != _msgSender()) {
            revert UnauthorizedOwner(_msgSender());
        }

        if (validator.status == ValidatorStatus.Active) {
            // Check that minimum stake duration has passed.
            if (block.timestamp < delegator.startTime + $._minimumStakeDuration) {
                revert MinStakeDurationNotPassed(uint64(block.timestamp));
            }

            // Set the delegator status to pending removed, so that it can be properly removed in
            // the complete step, even if the delivered nonce is greater than the nonce used to
            // initiate the removal.
            $._delegatorStakes[delegationID].status = DelegatorStatus.PendingRemoved;
            $._delegatorStakes[delegationID].endTime = uint64(block.timestamp);

            ($._delegatorStakes[delegationID].endingNonce,) = $
                ._manager
                .initiateValidatorWeightUpdate(validationID, validator.weight - delegator.weight);

            emit InitiatedDelegatorRemoval({delegationID: delegationID, validationID: validationID});
            return;
        } else if (validator.status == ValidatorStatus.Completed) {
            $._delegatorStakes[delegationID].endTime = validator.endTime;
            _completeDelegatorRemoval(delegationID);
            // If the validator has completed, then no further uptimes may be submitted, so we always
            // end the delegation.
            return;
        } else {
            revert InvalidValidatorStatus(validator.status);
        }
    }

    /**
     * @notice See {IStakingManager-resendUpdateDelegator}.
     * @dev Resending the latest validator weight with the latest nonce is safe because all weight changes are
     * cumulative, so the latest weight change will always include the weight change for any added delegators.
     */
    function resendUpdateDelegator(
        bytes32 delegationID
    ) external {
        StakingManagerStorage storage $ = _getStakingManagerStorage();
        Delegator memory delegator = $._delegatorStakes[delegationID];
        if (
            delegator.status != DelegatorStatus.PendingAdded
                && delegator.status != DelegatorStatus.PendingRemoved
        ) {
            revert InvalidDelegatorStatus(delegator.status);
        }

        Validator memory validator = $._manager.getValidator(delegator.validationID);
        if (validator.sentNonce == 0) {
            // Should be unreachable.
            revert InvalidDelegationID(delegationID);
        }

        // Submit the message to the Warp precompile.
        WARP_MESSENGER.sendWarpMessage(
            ValidatorMessages.packL1ValidatorWeightMessage(
                delegator.validationID, validator.sentNonce, validator.weight
            )
        );
    }

    /**
     * @notice See {IStakingManager-completeDelegatorRemoval}.
     * Extends the functionality of {ACP99Manager-completeValidatorWeightUpdate} by updating the delegation status and unlocking delegation rewards.
     */
    function completeDelegatorRemoval(
        bytes32 delegationID,
        uint32 messageIndex
    ) external nonReentrant {
        StakingManagerStorage storage $ = _getStakingManagerStorage();
        Delegator memory delegator = $._delegatorStakes[delegationID];

        // Ensure the delegator is pending removed. Since anybody can call this function once
        // end delegation has been initiated, we need to make sure that this function is only
        // callable after that has been done.
        if (delegator.status != DelegatorStatus.PendingRemoved) {
            revert InvalidDelegatorStatus(delegator.status);
        }
        Validator memory validator = $._manager.getValidator(delegator.validationID);

        // We only expect an ICM message if we haven't received a weight update with a nonce greater than the delegation's ending nonce
        if (
            $._manager.getValidator(delegator.validationID).status != ValidatorStatus.Completed
                && validator.receivedNonce < delegator.endingNonce
        ) {
            (bytes32 validationID, uint64 nonce) =
                $._manager.completeValidatorWeightUpdate(messageIndex);
            if (delegator.validationID != validationID) {
                revert UnexpectedValidationID(validationID, delegator.validationID);
            }

            // The received nonce should be at least as high as the delegation's ending nonce. This allows a weight
            // update using a higher nonce (which implicitly includes the delegation's weight update) to be used to
            // complete delisting for an earlier delegation. This is necessary because the P-Chain is only willing
            // to sign the latest weight update.
            if (delegator.endingNonce > nonce) {
                revert InvalidNonce(nonce);
            }
        }

        _completeDelegatorRemoval(delegationID);
    }

    /**
     * @notice unlocks the validator stake, to be called after removal and passing of unlock duration
     * @param validationID The unique identifier of the validator to unlock.
     */
    function unlockValidator(
        bytes32 validationID
    ) external virtual nonReentrant {
        _unlockValidator(validationID);
    }

    /**
     * @notice unlocks the delegator stake, to be called after removal and passing of unlock duration
     * @param delegationID The unique identifier of the delegator to unlock.
     */
    function unlockDelegator(
        bytes32 delegationID
    ) external nonReentrant {
        StakingManagerStorage storage $ = _getStakingManagerStorage();
        Delegator memory delegator = $._delegatorStakes[delegationID];

        if (delegator.status != DelegatorStatus.Removed || $._unlocked[delegationID]) {
            revert InvalidDelegatorStatus(delegator.status);
        }

        if (delegator.startTime != 0 && block.timestamp < delegator.endTime + $._unlockDuration) {
            revert UnlockDurationNotPassed(uint64(block.timestamp));
        }

        $._unlocked[delegationID] = true;

        emit UnlockedDelegation(delegationID);
        // Unlock the delegator's stake.
        _unlock(delegator.owner, weightToValue(delegator.weight));
    }

    function _unlockValidator(
        bytes32 validationID
    ) internal {
        StakingManagerStorage storage $ = _getStakingManagerStorage();
        Validator memory validator = $._manager.getValidator(validationID);

        if (
            (
                validator.status != ValidatorStatus.Completed
                    && validator.status != ValidatorStatus.Invalidated
            ) || $._unlocked[validationID]
        ) {
            revert InvalidValidatorStatus(validator.status);
        }

        if (!_isPoSValidator(validationID)) {
            revert ValidatorNotPoS(validationID);
        }

        if (validator.startTime != 0 && block.timestamp < validator.endTime + $._unlockDuration) {
            revert UnlockDurationNotPassed(uint64(block.timestamp));
        }

        $._unlocked[validationID] = true;

        emit UnlockedValidation(validationID);
        // The stake is unlocked whether the validation period is completed or invalidated.
        _unlock($._posValidatorInfo[validationID].owner, weightToValue(validator.startingWeight));
    }

    function _completeDelegatorRemoval(
        bytes32 delegationID
    ) internal {
        StakingManagerStorage storage $ = _getStakingManagerStorage();

        Delegator memory delegator = $._delegatorStakes[delegationID];
        bytes32 validationID = delegator.validationID;

        // To prevent churn tracker abuse, check that one full churn period has passed,
        // so a delegator may not stake twice in the same churn period.
        if (block.timestamp < delegator.startTime + $._manager.getChurnPeriodSeconds()) {
            revert MinStakeDurationNotPassed(uint64(block.timestamp));
        }

        $._delegatorStakes[delegationID].status = DelegatorStatus.Removed;

        emit CompletedDelegatorRemoval(delegationID, validationID, 0, 0);
    }

    /**
     * @dev This function must be implemented to mint rewards to validators and delegators.
     */
    function _reward(address account, uint256 amount) internal virtual;

    /**
     * @dev Return true if this is a PoS validator with locked stake. Returns false if this was originally a PoA
     * validator that was later migrated to this PoS manager, or the validator was part of the initial validator set.
     */
    function _isPoSValidator(
        bytes32 validationID
    ) internal view returns (bool) {
        StakingManagerStorage storage $ = _getStakingManagerStorage();
        return $._posValidatorInfo[validationID].owner != address(0);
    }
}


















Native 721 ************************************************************************

// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.25;

import {StakingManagerSettings} from "./interfaces/IStakingManager.sol";
import {StakingManager} from "./StakingManager.sol";
import {
    Delegator,
    DelegatorStatus,
    IStakingManager,
    PoSValidatorInfo,
    StakingManagerSettings
} from "./interfaces/IStakingManager.sol";
import {Math} from "@openzeppelin/contracts@5.0.2/utils/math/Math.sol";
import {INative721TokenStakingManager} from "./interfaces/INative721TokenStakingManager.sol";
import {IERC721} from "@openzeppelin/contracts@5.0.2/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts@5.0.2/utils/Address.sol";
import {ICMInitializable} from "@utilities/ICMInitializable.sol";
import {Initializable} from
    "@openzeppelin/contracts-upgradeable@5.0.2/proxy/utils/Initializable.sol";
import {WarpMessage} from
    "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {ValidatorMessages} from "./ValidatorMessages.sol";
import {IERC721Receiver} from "@openzeppelin/contracts@5.0.2/token/ERC721/IERC721Receiver.sol";

import {Validator, ValidatorStatus, PChainOwner} from "./ACP99Manager.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable@5.0.2/access/OwnableUpgradeable.sol";
/**
 * @dev Implementation of the {INative721TokenStakingManager} interface.
 *
 * @custom:security-contact https://github.com/ava-labs/icm-contracts/blob/main/SECURITY.md
 */

contract Native721TokenStakingManager is
    Initializable,
    StakingManager,
    OwnableUpgradeable,
    INative721TokenStakingManager,
    IERC721Receiver
{
    using Address for address payable;

    // solhint-disable private-vars-leading-underscore
    /// @custom:storage-location erc7201:avalanche-icm.storage.Native721TokenStakingManager
    struct Native721TokenStakingManagerStorage {
        IERC721 _token;
    }
    // solhint-enable private-vars-leading-underscore

    // keccak256(abi.encode(uint256(keccak256("avalanche-icm.storage.Native721TokenStakingManager")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 public constant ERC721_STAKING_MANAGER_STORAGE_LOCATION =
        0xf2d79c30881febd0da8597832b5b1bf1f4d4b2209b19059420303eb8fcab8a00;

    uint8 public constant UPTIME_REWARDS_THRESHOLD_PERCENTAGE = 80;
    uint64 public constant REWARD_CLAIM_DELAY = 7 days;

    error InvalidNFTAmount(uint256 nftAmount);
    error InvalidTokenAddress(address tokenAddress);
    error InvalidInputLengths(uint256 inputLength1, uint256 inputLength2);
    error TooEarly(uint256 actualTime, uint256 expectedTime);
    error TooLate(uint256 actualTime, uint256 expectedTime);

    // solhint-disable ordering
    function _getERC721StakingManagerStorage()
        private
        pure
        returns (Native721TokenStakingManagerStorage storage $)
    {
        assembly {
            $.slot := ERC721_STAKING_MANAGER_STORAGE_LOCATION
        }
    }

    constructor(
        ICMInitializable init
    ) {
        if (init == ICMInitializable.Disallowed) {
            _disableInitializers();
        }
    }

    /**
     * @notice Initialize the ERC721 token staking manager
     * @dev Uses reinitializer(2) on the PoS staking contracts to make sure after migration from PoA, the PoS contracts can reinitialize with its needed values.
     * @param settings Initial settings for the PoS validator manager
     * @param stakingToken The ERC721 token to be staked
     */
    function initialize(
        StakingManagerSettings calldata settings,
        IERC721 stakingToken
    ) external reinitializer(10) {
        __Ownable_init(settings.admin);
        __StakingManager_init(settings);

        Native721TokenStakingManagerStorage storage $ = _getERC721StakingManagerStorage();

        if (address(stakingToken) == address(0)) {
            revert InvalidTokenAddress(address(stakingToken));
        }

        $._token = stakingToken;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @notice See {INative721TokenStakingManager-initiateValidatorRegistration}.
     */
    function initiateValidatorRegistration(
        bytes memory nodeID,
        bytes memory blsPublicKey,
        uint64 registrationExpiry,
        PChainOwner memory remainingBalanceOwner,
        PChainOwner memory disableOwner,
        uint16 delegationFeeBips,
        uint64 minStakeDuration,
        uint256[] memory tokenIDs
    ) external payable nonReentrant returns (bytes32) {
        return _initiateValidatorRegistration({
            nodeID: nodeID,
            blsPublicKey: blsPublicKey,
            registrationExpiry: registrationExpiry,
            remainingBalanceOwner: remainingBalanceOwner,
            disableOwner: disableOwner,
            delegationFeeBips: delegationFeeBips,
            minStakeDuration: minStakeDuration,
            stakeAmount: msg.value,
            tokenIDs: tokenIDs
        });
    }

    /**
     * @notice See {INative721TokenStakingManager-initiateDelegatorRegistration}.
     */
    function initiateDelegatorRegistration(
        bytes32 validationID
    ) external payable nonReentrant returns (bytes32) {
        return _initiateDelegatorRegistration(validationID, _msgSender(), msg.value);
    }

    /**
     * @notice See {INative721TokenStakingManager-registerNFTDelegation}.
     *
     */
    function registerNFTDelegation(
        bytes32 validationID,
        uint256[] memory tokenIDs
    ) external nonReentrant returns (bytes32) {
        _lockNFTs(tokenIDs);
        return _registerNFTDelegation(validationID, _msgSender(), tokenIDs);
    }

    /**
     * @notice See {INative721TokenStakingManager-initializeEndNFTDelegation}.
     *
     */
    function initiateNFTDelegatorRemoval(
        bytes32 delegationID
    ) external nonReentrant {
        _initiateNFTDelegatorRemoval(delegationID);
    }

    /**
     * @notice See {INative721TokenStakingManager-completeEndNFTDelegation}.
     *
     */
    function completeNFTDelegatorRemoval(
        bytes32 delegationID
    ) external nonReentrant {
        StakingManagerStorage storage $ = _getStakingManagerStorage();
        Delegator memory delegator = $._delegatorStakes[delegationID];

        // Ensure the delegator is pending removed. Since anybody can call this function once
        // end delegation has been initialized, we need to make sure that this function is only
        // callable after that has been done.
        if (delegator.status != DelegatorStatus.PendingRemoved) {
            revert InvalidDelegatorStatus(delegator.status);
        }

        if (block.timestamp < delegator.endTime + $._unlockDuration) {
            revert UnlockDurationNotPassed(uint64(block.timestamp));
        }

        _unlockNFTs(delegator.owner, _completeNFTDelegatorRemoval(delegationID));
    }

    /**
     * @notice See {INative721TokenStakingManager-registerNFTRedelegation}.
     */
    function registerNFTRedelegation(
        bytes32 delegationID,
        bytes32 nextValidationID
    ) external nonReentrant {
        StakingManagerStorage storage $ = _getStakingManagerStorage();
        Delegator memory delegator = $._delegatorStakes[delegationID];

        _initiateNFTDelegatorRemoval(delegationID);
        uint256[] memory tokenIDs = _completeNFTDelegatorRemoval(delegationID);
        _registerNFTDelegation(nextValidationID, delegator.owner, tokenIDs);
    }

    /**
     * @notice unlocks the validator stake, to be called after removal and passing of unlock duration
     * @param validationID The unique identifier of the validator to unlock.
     */
    function unlockValidator(
        bytes32 validationID
    ) external override nonReentrant {
        StakingManagerStorage storage $ = _getStakingManagerStorage();

        _unlockValidator(validationID);
        _unlockNFTs(
            $._posValidatorInfo[validationID].owner, $._posValidatorInfo[validationID].tokenIDs
        );
    }

    /**
     * @notice See {INative721TokenStakingManager-submitUptimeProofs}.
     */
    function submitUptimeProofs(
        bytes32[] memory validationIDs,
        uint32[] memory messageIndexes
    ) external {
        if (validationIDs.length != messageIndexes.length) {
            revert InvalidInputLengths(validationIDs.length, messageIndexes.length);
        }
        for (uint256 i = 0; i < validationIDs.length; i++) {
            _updateUptime(validationIDs[i], messageIndexes[i]);
        }
    }

    /**
     * @notice Calculates the rewards for the caller in a given epoch for the specified tokens.
     * @dev This function determines the available rewards based on the user's weight in the staking system.
     *      It supports both primary and NFT-based reward pools.
     * @param primary A boolean indicating whether to retrieve rewards from the primary pool (true) or the NFT pool (false).
     * @param epoch The staking epoch for which to retrieve rewards.
     * @param token An array of token addresses for which to check the rewards.
     * @param account The account for which the rewards are being queried.
     * @return rewards An array of reward amounts corresponding to the provided token addresses.
     *
     * Requirements:
     * - The caller must have participated in staking or NFT delegation during the given epoch.
     * - The function calculates rewards based on the caller’s recorded weight and subtracts any already withdrawn rewards.
     */
    function getRewards(
        bool primary,
        uint64 epoch,
        address token,
        address account
    ) public view returns (uint256) {
        StakingManagerStorage storage $ = _getStakingManagerStorage();

        uint256 reward;

        if (primary && $._totalRewardWeight[epoch] == 0) return reward;
        if (!primary && $._totalRewardWeightNFT[epoch] == 0) return reward;

        if (primary) {
            reward = (
                ($._rewardPools[epoch][token] * $._accountRewardWeight[epoch][account])
                    / $._totalRewardWeight[epoch]
            ) - $._rewardWithdrawn[epoch][account][token];
        } else {
            reward = (
                ($._rewardPoolsNFT[epoch][token] * $._accountRewardWeightNFT[epoch][account])
                    / $._totalRewardWeightNFT[epoch]
            ) - $._rewardWithdrawnNFT[epoch][account][token];
        }
        return reward;
    }

    /**
     * @notice See {INative721TokenStakingManager-claimRewards}.
     */
    function claimRewards(
        bool primary,
        uint64 epoch,
        address[] memory tokens,
        address recipient
    ) external nonReentrant {
        StakingManagerStorage storage $ = _getStakingManagerStorage();

        uint64 claimStart = (epoch + 1) * $._epochDuration + REWARD_CLAIM_DELAY - $._epochOffset;
        if (block.timestamp < claimStart) {
            revert TooEarly(block.timestamp, claimStart);
        }

        address sender = _msgSender();
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 reward = getRewards(primary, epoch, tokens[i], sender);
            if (primary) {
                $._rewardWithdrawn[epoch][sender][tokens[i]] += reward;
            } else {
                $._rewardWithdrawnNFT[epoch][sender][tokens[i]] += reward;
            }
            if (reward != 0) {
                emit RewardClaimed(primary, epoch, sender, tokens[i], reward);
                IERC20(tokens[i]).transfer(recipient, reward);
            }
        }
    }

    /**
     * @notice See {INative721TokenStakingManager-registerRewards}.
     */
    function registerRewards(
        bool primary,
        uint64 epoch,
        address token,
        uint256 amount
    ) external onlyOwner nonReentrant {
        StakingManagerStorage storage $ = _getStakingManagerStorage();

        if (primary) {
            $._rewardPools[epoch][token] += amount;
        } else {
            $._rewardPoolsNFT[epoch][token] += amount;
        }
        IERC20(token).transferFrom(_msgSender(), address(this), amount);
        emit RewardRegistered(primary, epoch, token, amount);
    }

    /**
     * @notice See {INative721TokenStakingManager-cancelRewards}.
     */
    function cancelRewards(
        bool primary,
        uint64 epoch,
        address token
    ) external onlyOwner nonReentrant {
        StakingManagerStorage storage $ = _getStakingManagerStorage();

        uint64 claimStart = (epoch + 1) * $._epochDuration + REWARD_CLAIM_DELAY - $._epochOffset;
        if (block.timestamp >= claimStart) {
            revert TooLate(block.timestamp, claimStart);
        }

        if (primary) {
            IERC20(token).transfer(_msgSender(), $._rewardPools[epoch][token]);
            $._rewardPools[epoch][token] = 0;
        } else {
            IERC20(token).transfer(_msgSender(), $._rewardPoolsNFT[epoch][token]);
            $._rewardPoolsNFT[epoch][token] = 0;
        }
        emit RewardCancelled(primary, epoch, token);
    }

    /**
     * @notice Allows the contract owner to recover ERC20 tokens that may have been accidentally sent to the contract.
     * @dev This function allows the contract owner to recover ERC20 tokens that may have been accidentally sent to the contract.
     * @param token The address of the ERC20 token to recover.
     * @param to The address to which the recovered tokens will be sent.
     * @param amount The amount of tokens to recover.
     *
     * Requirements:
     * - Only the contract owner can call this function.
     */
    function recoverERC20(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        IERC20(token).transfer(to, amount);
    }

    /**
     * @notice See {INative721TokenStakingManager-erc721}.
     */
    function erc721() external view returns (IERC721) {
        return _getERC721StakingManagerStorage()._token;
    }

    /**
     * @notice See {StakingManager-_lock}
     */
    function _lock(
        uint256 value
    ) internal virtual override returns (uint256) {
        return value;
    }

    /**
     * @notice See {StakingManager-_unlock}
     * Note: Must be guarded with reentrancy guard for safe transfer.
     */
    function _unlock(address to, uint256 value) internal virtual override {
        payable(to).sendValue(value);
    }

    /**
     * @notice Locks a list of ERC-721 tokens by transferring them to the contract.
     * @dev Transfers each token in `tokenIDs` from the caller to the contract.
     * This function is used to stake NFTs as part of the staking mechanism.
     * @param tokenIDs The array of token IDs to be locked.
     * @return The number of tokens successfully locked.
     */
    function _lockNFTs(
        uint256[] memory tokenIDs
    ) internal returns (uint256) {
        for (uint256 i = 0; i < tokenIDs.length; i++) {
            _getERC721StakingManagerStorage()._token.safeTransferFrom(
                _msgSender(), address(this), tokenIDs[i]
            );
        }
        return tokenIDs.length;
    }

    /**
     * @notice Unlocks a list of ERC-721 tokens by transferring them back to the specified address.
     * @dev Transfers each token in `tokenIDs` from the contract to the recipient.
     * This function is used when unstaking NFTs from the staking mechanism.
     * @param to The address that will receive the unlocked NFTs.
     * @param tokenIDs The array of token IDs to be unlocked and transferred.
     */
    function _unlockNFTs(address to, uint256[] memory tokenIDs) internal virtual {
        for (uint256 i = 0; i < tokenIDs.length; i++) {
            _getERC721StakingManagerStorage()._token.transferFrom(address(this), to, tokenIDs[i]);
        }
    }

    /**
     * @notice See {StakingManager-_reward}
     * @dev Distributes ERC20 rewards to stakers
     */
    function _reward(address account, uint256 amount) internal virtual override {}

    /**
     * @notice See {INative721TokenStakingManager-getEpoch}.
     */
    function getEpoch() public view virtual returns (uint64) {
        StakingManagerStorage storage $ = _getStakingManagerStorage();
        return uint64((block.timestamp + $._epochOffset) / $._epochDuration);
    }

    /**
     * @notice Initiates validator registration. Extends the functionality of {ACP99Manager-_initiateValidatorRegistration}
     * by locking stake and setting staking and delegation parameters.
     * @param delegationFeeBips The delegation fee in basis points.
     * @param minStakeDuration The minimum stake duration in seconds.
     * @param stakeAmount The amount of stake to lock.
     */
    function _initiateValidatorRegistration(
        bytes memory nodeID,
        bytes memory blsPublicKey,
        uint64 registrationExpiry,
        PChainOwner memory remainingBalanceOwner,
        PChainOwner memory disableOwner,
        uint16 delegationFeeBips,
        uint64 minStakeDuration,
        uint256 stakeAmount,
        uint256[] memory tokenIDs
    ) internal virtual returns (bytes32) {
        StakingManagerStorage storage $ = _getStakingManagerStorage();
        // Validate and save the validator requirements
        if (
            delegationFeeBips < $._minimumDelegationFeeBips
                || delegationFeeBips > MAXIMUM_DELEGATION_FEE_BIPS
        ) {
            revert InvalidDelegationFee(delegationFeeBips);
        }

        if (minStakeDuration < $._minimumStakeDuration) {
            revert InvalidMinStakeDuration(minStakeDuration);
        }

        // Ensure the weight is within the valid range.
        if (stakeAmount < $._minimumStakeAmount || stakeAmount > $._maximumStakeAmount) {
            revert InvalidStakeAmount(stakeAmount);
        }

        if (tokenIDs.length < 1 || tokenIDs.length > $._maximumNFTAmount) {
            revert InvalidNFTAmount(tokenIDs.length);
        }

        // Lock the stake in the contract.
        uint64 weight = valueToWeight(_lock(stakeAmount));
        _lockNFTs(tokenIDs);

        bytes32 validationID = $._manager.initiateValidatorRegistration({
            nodeID: nodeID,
            blsPublicKey: blsPublicKey,
            registrationExpiry: registrationExpiry,
            remainingBalanceOwner: remainingBalanceOwner,
            disableOwner: disableOwner,
            weight: weight
        });

        address owner = _msgSender();

        $._posValidatorInfo[validationID].owner = owner;
        $._posValidatorInfo[validationID].delegationFeeBips = delegationFeeBips;
        $._posValidatorInfo[validationID].minStakeDuration = minStakeDuration;
        $._posValidatorInfo[validationID].uptimeSeconds = 0;
        $._posValidatorInfo[validationID].tokenIDs = tokenIDs;
        $._posValidatorInfo[validationID].totalTokens = tokenIDs.length;

        return validationID;
    }

    /**
     * @notice Registers an NFT-based delegation to a PoS validator.
     * @dev This function records the delegation details, ensures the validator is active,
     *      updates the staking records, and emits relevant events.
     * @param validationID The identifier of the PoS validator to delegate to.
     * @param delegatorAddress The address of the user delegating NFTs.
     * @param tokenIDs The array of NFT token IDs being delegated.
     * @return delegationID A unique identifier for this delegation.
     *
     * Requirements:
     * - The validator must be a valid PoS validator.
     * - The validator must be in an active status.
     * - The function generates a unique delegation ID based on the validation ID and nonce.
     *
     * Emits:
     * - `InitiatedDelegatorRegistration` upon starting the delegation process.
     * - `CompletedDelegatorRegistration` once the delegation is successfully recorded.
     * - `DelegatedNFTs` containing the delegated NFT token IDs.
     */
    function _registerNFTDelegation(
        bytes32 validationID,
        address delegatorAddress,
        uint256[] memory tokenIDs
    ) internal returns (bytes32) {
        StakingManagerStorage storage $ = _getStakingManagerStorage();
        uint64 weight = uint64(tokenIDs.length * 1e6);

        // Ensure the validation period is active
        Validator memory validator = $._manager.getValidator(validationID);
        // Check that the validation ID is a PoS validator
        if (!_isPoSValidator(validationID)) {
            revert ValidatorNotPoS(validationID);
        }
        if (validator.status != ValidatorStatus.Active) {
            revert InvalidValidatorStatus(validator.status);
        }

        if ($._posValidatorInfo[validationID].totalTokens + tokenIDs.length > $._maximumNFTAmount) {
            revert InvalidNFTAmount(
                uint64($._posValidatorInfo[validationID].totalTokens + tokenIDs.length)
            );
        }

        uint64 nonce = ++$._posValidatorInfo[validationID].tokenNonce;

        // Update the delegation status
        bytes32 delegationID = keccak256(abi.encodePacked(validationID, nonce, "ERC721"));
        $._delegatorStakes[delegationID].owner = delegatorAddress;
        $._delegatorStakes[delegationID].validationID = validationID;
        $._delegatorStakes[delegationID].weight = weight;
        $._delegatorStakes[delegationID].status = DelegatorStatus.Active;
        $._delegatorStakes[delegationID].startTime = uint64(block.timestamp);
        $._lockedNFTs[delegationID] = tokenIDs;

        $._posValidatorInfo[validationID].totalTokens += tokenIDs.length;

        emit InitiatedDelegatorRegistration({
            delegationID: delegationID,
            validationID: validationID,
            delegatorAddress: delegatorAddress,
            nonce: nonce,
            validatorWeight: validator.weight,
            delegatorWeight: weight,
            setWeightMessageID: 0
        });

        emit CompletedDelegatorRegistration({
            delegationID: delegationID,
            validationID: validationID,
            startTime: uint64(block.timestamp)
        });

        emit DelegatedNFTs(delegationID, tokenIDs);

        return delegationID;
    }

    /**
     * @notice Initiates the process of ending an NFT delegation for a given delegation ID.
     * @dev This function ensures that the delegation is active and validates that the caller is authorized to end it.
     *      If the validator status is valid, the delegation status is updated to `PendingRemoved`. If the validator
     *      is complete, then removal is completed directly. Status is updated to `Completed` and initate
     *      `InitiatedDelegatorRemoval` is not emitted.
     * @param delegationID The unique identifier of the NFT delegation to be ended.
     *
     * Reverts if:
     * - The delegation is not active (`InvalidDelegatorStatus`).
     * - The caller is not authorized to end the delegation (`UnauthorizedOwner`).
     * - The minimum stake duration has not passed for the validator or the delegator (`MinStakeDurationNotPassed`).
     * - The validator is not in a valid state to end the delegation (`InvalidValidatorStatus`).
     */
    function _initiateNFTDelegatorRemoval(
        bytes32 delegationID
    ) internal {
        StakingManagerStorage storage $ = _getStakingManagerStorage();

        Delegator memory delegator = $._delegatorStakes[delegationID];
        bytes32 validationID = delegator.validationID;

        Validator memory validator = $._manager.getValidator(validationID);

        // Ensure the delegator is active
        if (delegator.status != DelegatorStatus.Active) {
            revert InvalidDelegatorStatus(delegator.status);
        }

        if (delegator.owner != _msgSender()) {
            revert UnauthorizedOwner(_msgSender());
        }

        if (
            validator.status == ValidatorStatus.Active
                || validator.status == ValidatorStatus.Completed
        ) {
            // Check that minimum stake duration has passed.
            if (
                validator.status != ValidatorStatus.Completed
                    && block.timestamp < delegator.startTime + $._minimumStakeDuration
            ) {
                revert MinStakeDurationNotPassed(uint64(block.timestamp));
            }

            $._delegatorStakes[delegationID].status = DelegatorStatus.PendingRemoved;
            $._delegatorStakes[delegationID].endTime = uint64(block.timestamp);
            if (validator.status == ValidatorStatus.Completed) {
                $._delegatorStakes[delegationID].endTime = validator.endTime;
            }
            emit InitiatedDelegatorRemoval(delegationID, validationID);
        } else {
            revert InvalidValidatorStatus(validator.status);
        }
    }

    /**
     * @notice Completes the process of ending an NFT delegation and returns the associated token IDs.
     * @dev This function removes the delegation from the validator and account, retrieves the associated NFTs,
     *      and clears the delegation data from storage. It emits a `DelegationEnded` event upon completion.
     * @param delegationID The unique identifier of the NFT delegation to be completed.
     * @return tokenIDs An array of token IDs associated with the completed delegation.
     *
     * Emits:
     * - `DelegationEnded` when the delegation is successfully completed and removed from storage.
     */
    function _completeNFTDelegatorRemoval(
        bytes32 delegationID
    ) internal returns (uint256[] memory tokenIDs) {
        StakingManagerStorage storage $ = _getStakingManagerStorage();

        Delegator memory delegator = $._delegatorStakes[delegationID];
        bytes32 validationID = delegator.validationID;

        tokenIDs = $._lockedNFTs[delegationID];

        $._posValidatorInfo[validationID].totalTokens -= tokenIDs.length;
        $._delegatorStakes[delegationID].status = DelegatorStatus.Removed;

        emit CompletedDelegatorRemoval(delegationID, validationID, 0, 0);

        return tokenIDs;
    }

    /**
     * @notice Updates the uptime of a validator based on a verified ValidationUptimeMessage received via Warp.
     * @dev This function extracts the uptime from a Warp message, validates its authenticity, and updates the
     *      stored uptime for the specified validator if the provided uptime is greater than the currently stored uptime.
     *      It also updates the validator's epoch information and balance trackers for both standard and NFT delegations.
     * @param validationID The unique identifier of the validator whose uptime is being updated.
     * @param messageIndex The index of the Warp message in the Warp messenger to validate and process.
     * @return The updated uptime for the specified validator, or the current uptime if no update is performed.
     *
     * Reverts if:
     * - The Warp message is invalid.
     * - The source chain ID in the Warp message does not match the expected uptime blockchain ID.
     * - The origin sender address in the Warp message is not the zero address.
     * - The `validationID` in the Warp message payload does not match the provided `validationID`.
     *
     * Emits:
     * - `UptimeUpdated` event when the uptime is successfully updated for a validator.
     */
    function _updateUptime(
        bytes32 validationID,
        uint32 messageIndex
    ) internal override returns (uint64) {
        StakingManagerStorage storage $ = _getStakingManagerStorage();

        uint64 uptime = _validateUptime(validationID, messageIndex);
        uint64 epoch = getEpoch();
        uint64 dur = $._epochDuration;

        PoSValidatorInfo storage validatorInfo = $._posValidatorInfo[validationID];

        if (validatorInfo.uptimeSeconds >= uptime) {
            return validatorInfo.uptimeSeconds;
        }

        uint256 validationUptime = uptime - validatorInfo.uptimeSeconds;
        if (validationUptime * 100 / dur >= UPTIME_REWARDS_THRESHOLD_PERCENTAGE) {
            validationUptime = dur;
        }

        // Calculate validator weights
        uint256 valWeight =
            $._manager.getValidator(validationID).startingWeight * validationUptime / dur;
        uint256 valWeightNFT = (validatorInfo.tokenIDs.length * 1e6) * validationUptime / dur;

        // Update reward weights for validator owner
        $._accountRewardWeight[epoch][validatorInfo.owner] += valWeight;
        $._accountRewardWeightNFT[epoch][validatorInfo.owner] += valWeightNFT;
        $._totalRewardWeight[epoch] += valWeight;
        $._totalRewardWeightNFT[epoch] += valWeightNFT;

        validatorInfo.uptimeSeconds = uptime;

        $._validationUptimes[epoch][validationID] += validationUptime;

        emit UptimeUpdated(validationID, uptime, epoch);
        return uptime;
    }

    /**
     * @notice Calculated and updates the reward weight of the given delegations for the previous epoch after successfully
     *         submitting the uptime of the respective validators
     * @param delegationIDs An array of delegation IDs associated with the staking process.
     */
    function resolveRewards(
        bytes32[] memory delegationIDs
    ) external {
        StakingManagerStorage storage $ = _getStakingManagerStorage();

        if ($._uptimeKeeper != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }

        uint64 epoch = getEpoch() - 1;
        uint64 dur = $._epochDuration;

        for (uint256 i = 0; i < delegationIDs.length; i++) {
            Delegator memory delegator = $._delegatorStakes[delegationIDs[i]];
            PoSValidatorInfo storage validatorInfo = $._posValidatorInfo[delegator.validationID];

            uint64 epochStart = epoch * dur;
            uint64 epochEnd = epochStart + dur;

            uint64 delegationUptime;
            {
                uint64 delegationStart = uint64(Math.max(delegator.startTime, epochStart));
                uint64 delegationEnd = delegator.endTime != 0 ? delegator.endTime : epochEnd;
                if (epochStart > delegationEnd) continue;
                delegationUptime = uint64(
                    Math.min(
                        delegationEnd - delegationStart,
                        $._validationUptimes[epoch][delegator.validationID]
                    )
                );

                if (delegationUptime * 100 / dur >= UPTIME_REWARDS_THRESHOLD_PERCENTAGE) {
                    delegationUptime = dur;
                }
            }
            uint256 delWeight = (delegator.weight * delegationUptime) / dur;
            uint256 feeWeight =
                (delWeight * validatorInfo.delegationFeeBips) / BIPS_CONVERSION_FACTOR;

            if ($._lockedNFTs[delegationIDs[i]].length == 0) {
                $._accountRewardWeight[epoch][validatorInfo.owner] += feeWeight;
                $._accountRewardWeight[epoch][delegator.owner] += delWeight - feeWeight;
                $._totalRewardWeight[epoch] += delWeight;
            } else {
                $._accountRewardWeightNFT[epoch][validatorInfo.owner] += feeWeight;
                $._accountRewardWeightNFT[epoch][delegator.owner] += delWeight - feeWeight;
                $._totalRewardWeightNFT[epoch] += delWeight;
            }
            emit RewardResolved(delegationIDs[i], epoch);
        }
    }

    /**
     * @notice Validates the uptime proof for a given validator.
     * @dev This function checks whether the provided validation ID corresponds to a PoS validator,
     *      verifies the associated warp message, and extracts the uptime value.
     * @param validationID The unique identifier of the validator whose uptime is being validated.
     * @param messageIndex The index of the warp message to retrieve and validate.
     * @return uptime The validated uptime value extracted from the warp message.
     *
     * Requirements:
     * - The validation ID must belong to a PoS validator.
     * - The referenced warp message must be valid and verified.
     * - The source chain ID of the warp message must match the expected uptime blockchain ID.
     * - The origin sender address of the warp message must be the zero address, ensuring direct validator signing.
     * - The extracted validation ID from the warp message must match the provided `validationID`.
     *
     * Reverts:
     * - `ValidatorNotPoS` if the validator is not a PoS validator.
     * - `InvalidWarpMessage` if the warp message is not valid.
     * - `InvalidWarpSourceChainID` if the message originates from an incorrect blockchain.
     * - `InvalidWarpOriginSenderAddress` if the sender is not the zero address.
     * - `UnexpectedValidationID` if the extracted validation ID does not match the provided one.
     */
    function _validateUptime(
        bytes32 validationID,
        uint32 messageIndex
    ) internal view returns (uint64) {
        if (!_isPoSValidator(validationID)) {
            revert ValidatorNotPoS(validationID);
        }

        (WarpMessage memory warpMessage, bool valid) =
            WARP_MESSENGER.getVerifiedWarpMessage(messageIndex);
        if (!valid) {
            revert InvalidWarpMessage();
        }

        StakingManagerStorage storage $ = _getStakingManagerStorage();
        // The uptime proof must be from the specifed uptime blockchain
        if (warpMessage.sourceChainID != $._uptimeBlockchainID) {
            revert InvalidWarpSourceChainID(warpMessage.sourceChainID);
        }

        // The sender is required to be the zero address so that we know the validator node
        // signed the proof directly, rather than as an arbitrary on-chain message
        if (warpMessage.originSenderAddress != address(0)) {
            revert InvalidWarpOriginSenderAddress(warpMessage.originSenderAddress);
        }

        (bytes32 uptimeValidationID, uint64 uptime) =
            ValidatorMessages.unpackValidationUptimeMessage(warpMessage.payload);
        if (validationID != uptimeValidationID) {
            revert UnexpectedValidationID(uptimeValidationID, validationID);
        }

        return uptime;
    }
}