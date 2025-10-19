// Sources flattened with hardhat v2.26.3 https://hardhat.org

// SPDX-License-Identifier: MIT

// File @openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.3.0) (proxy/utils/Initializable.sol)

pragma solidity ^0.8.20;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```solidity
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 *
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Storage of the initializable contract.
     *
     * It's implemented on a custom ERC-7201 namespace to reduce the risk of storage collisions
     * when using with upgradeable contracts.
     *
     * @custom:storage-location erc7201:openzeppelin.storage.Initializable
     */
    struct InitializableStorage {
        /**
         * @dev Indicates that the contract has been initialized.
         */
        uint64 _initialized;
        /**
         * @dev Indicates that the contract is in the process of being initialized.
         */
        bool _initializing;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    /**
     * @dev The contract is already initialized.
     */
    error InvalidInitialization();

    /**
     * @dev The contract is not initializing.
     */
    error NotInitializing();

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint64 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that in the context of a constructor an `initializer` may be invoked any
     * number of times. This behavior in the constructor can be useful during testing and is not expected to be used in
     * production.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        // Cache values to avoid duplicated sloads
        bool isTopLevelCall = !$._initializing;
        uint64 initialized = $._initialized;

        // Allowed calls:
        // - initialSetup: the contract is not in the initializing state and no previous version was
        //                 initialized
        // - construction: the contract is initialized at version 1 (no reinitialization) and the
        //                 current contract is just being deployed
        bool initialSetup = initialized == 0 && isTopLevelCall;
        bool construction = initialized == 1 && address(this).code.length == 0;

        if (!initialSetup && !construction) {
            revert InvalidInitialization();
        }
        $._initialized = 1;
        if (isTopLevelCall) {
            $._initializing = true;
        }
        _;
        if (isTopLevelCall) {
            $._initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: Setting the version to 2**64 - 1 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint64 version) {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing || $._initialized >= version) {
            revert InvalidInitialization();
        }
        $._initialized = version;
        $._initializing = true;
        _;
        $._initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        _checkInitializing();
        _;
    }

    /**
     * @dev Reverts if the contract is not in an initializing state. See {onlyInitializing}.
     */
    function _checkInitializing() internal view virtual {
        if (!_isInitializing()) {
            revert NotInitializing();
        }
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing) {
            revert InvalidInitialization();
        }
        if ($._initialized != type(uint64).max) {
            $._initialized = type(uint64).max;
            emit Initialized(type(uint64).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint64) {
        return _getInitializableStorage()._initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _getInitializableStorage()._initializing;
    }

    /**
     * @dev Pointer to storage slot. Allows integrators to override it with a custom storage location.
     *
     * NOTE: Consider following the ERC-7201 formula to derive storage locations.
     */
    function _initializableStorageSlot() internal pure virtual returns (bytes32) {
        return INITIALIZABLE_STORAGE;
    }

    /**
     * @dev Returns a pointer to the storage namespace.
     */
    // solhint-disable-next-line var-name-mixedcase
    function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
        bytes32 slot = _initializableStorageSlot();
        assembly {
            $.slot := slot
        }
    }
}


// File @openzeppelin/contracts/interfaces/draft-IERC1822.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/draft-IERC1822.sol)

pragma solidity >=0.4.16;

/**
 * @dev ERC-1822: Universal Upgradeable Proxy Standard (UUPS) documents a method for upgradeability through a simplified
 * proxy whose upgrades are fully controlled by the current implementation.
 */
interface IERC1822Proxiable {
    /**
     * @dev Returns the storage slot that the proxiable contract assumes is being used to store the implementation
     * address.
     *
     * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
     * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
     * function revert if invoked through a proxy.
     */
    function proxiableUUID() external view returns (bytes32);
}


// File @openzeppelin/contracts/interfaces/IERC1967.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC1967.sol)

pragma solidity >=0.4.11;

/**
 * @dev ERC-1967: Proxy Storage Slots. This interface contains the events defined in the ERC.
 */
interface IERC1967 {
    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Emitted when the beacon is changed.
     */
    event BeaconUpgraded(address indexed beacon);
}


// File @openzeppelin/contracts/proxy/beacon/IBeacon.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (proxy/beacon/IBeacon.sol)

pragma solidity >=0.4.16;

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IBeacon {
    /**
     * @dev Must return an address that can be used as a delegate call target.
     *
     * {UpgradeableBeacon} will check that this address is a contract.
     */
    function implementation() external view returns (address);
}


// File @openzeppelin/contracts/utils/Errors.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/Errors.sol)

pragma solidity ^0.8.20;

/**
 * @dev Collection of common custom errors used in multiple contracts
 *
 * IMPORTANT: Backwards compatibility is not guaranteed in future versions of the library.
 * It is recommended to avoid relying on the error API for critical functionality.
 *
 * _Available since v5.1._
 */
library Errors {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error InsufficientBalance(uint256 balance, uint256 needed);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedCall();

    /**
     * @dev The deployment failed.
     */
    error FailedDeployment();

    /**
     * @dev A necessary precompile is missing.
     */
    error MissingPrecompile(address);
}


// File @openzeppelin/contracts/utils/Address.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (utils/Address.sol)

pragma solidity ^0.8.20;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert Errors.InsufficientBalance(address(this).balance, amount);
        }

        (bool success, bytes memory returndata) = recipient.call{value: amount}("");
        if (!success) {
            _revert(returndata);
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {Errors.FailedCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert Errors.InsufficientBalance(address(this).balance, value);
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {Errors.FailedCall}) in case
     * of an unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {Errors.FailedCall} error.
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {Errors.FailedCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            assembly ("memory-safe") {
                revert(add(returndata, 0x20), mload(returndata))
            }
        } else {
            revert Errors.FailedCall();
        }
    }
}


// File @openzeppelin/contracts/utils/StorageSlot.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/StorageSlot.sol)
// This file was procedurally generated from scripts/generate/templates/StorageSlot.js.

pragma solidity ^0.8.20;

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC-1967 implementation slot:
 * ```solidity
 * contract ERC1967 {
 *     // Define the slot. Alternatively, use the SlotDerivation library to derive the slot.
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(newImplementation.code.length > 0);
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * TIP: Consider using this library along with {SlotDerivation}.
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct Int256Slot {
        int256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Int256Slot` with member `value` located at `slot`.
     */
    function getInt256Slot(bytes32 slot) internal pure returns (Int256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `StringSlot` with member `value` located at `slot`.
     */
    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` representation of the string storage pointer `store`.
     */
    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }

    /**
     * @dev Returns a `BytesSlot` with member `value` located at `slot`.
     */
    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` representation of the bytes storage pointer `store`.
     */
    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }
}


// File @openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (proxy/ERC1967/ERC1967Utils.sol)

pragma solidity ^0.8.21;




/**
 * @dev This library provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[ERC-1967] slots.
 */
library ERC1967Utils {
    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev The `implementation` of the proxy is invalid.
     */
    error ERC1967InvalidImplementation(address implementation);

    /**
     * @dev The `admin` of the proxy is invalid.
     */
    error ERC1967InvalidAdmin(address admin);

    /**
     * @dev The `beacon` of the proxy is invalid.
     */
    error ERC1967InvalidBeacon(address beacon);

    /**
     * @dev An upgrade function sees `msg.value > 0` that may be lost.
     */
    error ERC1967NonPayable();

    /**
     * @dev Returns the current implementation address.
     */
    function getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Stores a new address in the ERC-1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(newImplementation);
        }
        StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Performs implementation upgrade with additional setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-Upgraded} event.
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit IERC1967.Upgraded(newImplementation);

        if (data.length > 0) {
            Address.functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Returns the current admin.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by ERC-1967) using
     * the https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
     */
    function getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the ERC-1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert ERC1967InvalidAdmin(address(0));
        }
        StorageSlot.getAddressSlot(ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {IERC1967-AdminChanged} event.
     */
    function changeAdmin(address newAdmin) internal {
        emit IERC1967.AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is the keccak-256 hash of "eip1967.proxy.beacon" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Returns the current beacon.
     */
    function getBeacon() internal view returns (address) {
        return StorageSlot.getAddressSlot(BEACON_SLOT).value;
    }

    /**
     * @dev Stores a new beacon in the ERC-1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        if (newBeacon.code.length == 0) {
            revert ERC1967InvalidBeacon(newBeacon);
        }

        StorageSlot.getAddressSlot(BEACON_SLOT).value = newBeacon;

        address beaconImplementation = IBeacon(newBeacon).implementation();
        if (beaconImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(beaconImplementation);
        }
    }

    /**
     * @dev Change the beacon and trigger a setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-BeaconUpgraded} event.
     *
     * CAUTION: Invoking this function has no effect on an instance of {BeaconProxy} since v5, since
     * it uses an immutable beacon without looking at the value of the ERC-1967 beacon slot for
     * efficiency.
     */
    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit IERC1967.BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            Address.functionDelegateCall(IBeacon(newBeacon).implementation(), data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Reverts if `msg.value` is not zero. It can be used to avoid `msg.value` stuck in the contract
     * if an upgrade doesn't perform an initialization call.
     */
    function _checkNonPayable() private {
        if (msg.value > 0) {
            revert ERC1967NonPayable();
        }
    }
}


// File @openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.3.0) (proxy/utils/UUPSUpgradeable.sol)

pragma solidity ^0.8.22;



/**
 * @dev An upgradeability mechanism designed for UUPS proxies. The functions included here can perform an upgrade of an
 * {ERC1967Proxy}, when this contract is set as the implementation behind such a proxy.
 *
 * A security mechanism ensures that an upgrade does not turn off upgradeability accidentally, although this risk is
 * reinstated if the upgrade retains upgradeability but removes the security mechanism, e.g. by replacing
 * `UUPSUpgradeable` with a custom implementation of upgrades.
 *
 * The {_authorizeUpgrade} function must be overridden to include access restriction to the upgrade mechanism.
 */
abstract contract UUPSUpgradeable is Initializable, IERC1822Proxiable {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable __self = address(this);

    /**
     * @dev The version of the upgrade interface of the contract. If this getter is missing, both `upgradeTo(address)`
     * and `upgradeToAndCall(address,bytes)` are present, and `upgradeTo` must be used if no function should be called,
     * while `upgradeToAndCall` will invoke the `receive` function if the second argument is the empty byte string.
     * If the getter returns `"5.0.0"`, only `upgradeToAndCall(address,bytes)` is present, and the second argument must
     * be the empty byte string if no function should be called, making it impossible to invoke the `receive` function
     * during an upgrade.
     */
    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    /**
     * @dev The call is from an unauthorized context.
     */
    error UUPSUnauthorizedCallContext();

    /**
     * @dev The storage `slot` is unsupported as a UUID.
     */
    error UUPSUnsupportedProxiableUUID(bytes32 slot);

    /**
     * @dev Check that the execution is being performed through a delegatecall call and that the execution context is
     * a proxy contract with an implementation (as defined in ERC-1967) pointing to self. This should only be the case
     * for UUPS and transparent proxies that are using the current contract as their implementation. Execution of a
     * function through ERC-1167 minimal proxies (clones) would not normally pass this test, but is not guaranteed to
     * fail.
     */
    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    /**
     * @dev Check that the execution is not being performed through a delegate call. This allows a function to be
     * callable on the implementing contract but not through proxies.
     */
    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    function __UUPSUpgradeable_init() internal onlyInitializing {
    }

    function __UUPSUpgradeable_init_unchained() internal onlyInitializing {
    }
    /**
     * @dev Implementation of the ERC-1822 {proxiableUUID} function. This returns the storage slot used by the
     * implementation. It is used to validate the implementation's compatibility when performing an upgrade.
     *
     * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
     * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
     * function revert if invoked through a proxy. This is guaranteed by the `notDelegated` modifier.
     */
    function proxiableUUID() external view virtual notDelegated returns (bytes32) {
        return ERC1967Utils.IMPLEMENTATION_SLOT;
    }

    /**
     * @dev Upgrade the implementation of the proxy to `newImplementation`, and subsequently execute the function call
     * encoded in `data`.
     *
     * Calls {_authorizeUpgrade}.
     *
     * Emits an {Upgraded} event.
     *
     * @custom:oz-upgrades-unsafe-allow-reachable delegatecall
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) public payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data);
    }

    /**
     * @dev Reverts if the execution is not performed via delegatecall or the execution
     * context is not of a proxy with an ERC-1967 compliant implementation pointing to self.
     */
    function _checkProxy() internal view virtual {
        if (
            address(this) == __self || // Must be called through delegatecall
            ERC1967Utils.getImplementation() != __self // Must be called through an active proxy
        ) {
            revert UUPSUnauthorizedCallContext();
        }
    }

    /**
     * @dev Reverts if the execution is performed via delegatecall.
     * See {notDelegated}.
     */
    function _checkNotDelegated() internal view virtual {
        if (address(this) != __self) {
            // Must not be called through delegatecall
            revert UUPSUnauthorizedCallContext();
        }
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
     * {upgradeToAndCall}.
     *
     * Normally, this function will use an xref:access.adoc[access control] modifier such as {Ownable-onlyOwner}.
     *
     * ```solidity
     * function _authorizeUpgrade(address) internal onlyOwner {}
     * ```
     */
    function _authorizeUpgrade(address newImplementation) internal virtual;

    /**
     * @dev Performs an implementation upgrade with a security check for UUPS proxies, and additional setup call.
     *
     * As a security check, {proxiableUUID} is invoked in the new implementation, and the return value
     * is expected to be the implementation slot in ERC-1967.
     *
     * Emits an {IERC1967-Upgraded} event.
     */
    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data) private {
        try IERC1822Proxiable(newImplementation).proxiableUUID() returns (bytes32 slot) {
            if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
                revert UUPSUnsupportedProxiableUUID(slot);
            }
            ERC1967Utils.upgradeToAndCall(newImplementation, data);
        } catch {
            // The implementation is not UUPS
            revert ERC1967Utils.ERC1967InvalidImplementation(newImplementation);
        }
    }
}


// File @openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.20;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}


// File @openzeppelin/contracts/interfaces/draft-IERC6093.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/draft-IERC6093.sol)
pragma solidity >=0.8.4;

/**
 * @dev Standard ERC-20 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC-20 tokens.
 */
interface IERC20Errors {
    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC20InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC20InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `spender`???s `allowance`. Used in transfers.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     * @param allowance Amount of tokens a `spender` is allowed to operate with.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC20InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `spender` to be approved. Used in approvals.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC20InvalidSpender(address spender);
}

/**
 * @dev Standard ERC-721 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC-721 tokens.
 */
interface IERC721Errors {
    /**
     * @dev Indicates that an address can't be an owner. For example, `address(0)` is a forbidden owner in ERC-20.
     * Used in balance queries.
     * @param owner Address of the current owner of a token.
     */
    error ERC721InvalidOwner(address owner);

    /**
     * @dev Indicates a `tokenId` whose `owner` is the zero address.
     * @param tokenId Identifier number of a token.
     */
    error ERC721NonexistentToken(uint256 tokenId);

    /**
     * @dev Indicates an error related to the ownership over a particular token. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param tokenId Identifier number of a token.
     * @param owner Address of the current owner of a token.
     */
    error ERC721IncorrectOwner(address sender, uint256 tokenId, address owner);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC721InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC721InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `operator`???s approval. Used in transfers.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     * @param tokenId Identifier number of a token.
     */
    error ERC721InsufficientApproval(address operator, uint256 tokenId);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC721InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `operator` to be approved. Used in approvals.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC721InvalidOperator(address operator);
}

/**
 * @dev Standard ERC-1155 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC-1155 tokens.
 */
interface IERC1155Errors {
    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     * @param tokenId Identifier number of a token.
     */
    error ERC1155InsufficientBalance(address sender, uint256 balance, uint256 needed, uint256 tokenId);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC1155InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC1155InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `operator`???s approval. Used in transfers.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     * @param owner Address of the current owner of a token.
     */
    error ERC1155MissingApprovalForAll(address operator, address owner);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC1155InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `operator` to be approved. Used in approvals.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC1155InvalidOperator(address operator);

    /**
     * @dev Indicates an array length mismatch between ids and values in a safeBatchTransferFrom operation.
     * Used in batch transfers.
     * @param idsLength Length of the array of token identifiers
     * @param valuesLength Length of the array of token amounts
     */
    error ERC1155InvalidArrayLength(uint256 idsLength, uint256 valuesLength);
}


// File @openzeppelin/contracts/token/ERC20/IERC20.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/IERC20.sol)

pragma solidity >=0.4.16;

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}


// File @openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/extensions/IERC20Metadata.sol)

pragma solidity >=0.6.2;

/**
 * @dev Interface for the optional metadata functions from the ERC-20 standard.
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}


// File @openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.20;





/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.openzeppelin.com/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * The default value of {decimals} is 18. To change this, you should override
 * this function so it returns a different value.
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC-20
 * applications.
 */
abstract contract ERC20Upgradeable is Initializable, ContextUpgradeable, IERC20, IERC20Metadata, IERC20Errors {
    /// @custom:storage-location erc7201:openzeppelin.storage.ERC20
    struct ERC20Storage {
        mapping(address account => uint256) _balances;

        mapping(address account => mapping(address spender => uint256)) _allowances;

        uint256 _totalSupply;

        string _name;
        string _symbol;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20StorageLocation = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;

    function _getERC20Storage() private pure returns (ERC20Storage storage $) {
        assembly {
            $.slot := ERC20StorageLocation
        }
    }

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * Both values are immutable: they can only be set once during construction.
     */
    function __ERC20_init(string memory name_, string memory symbol_) internal onlyInitializing {
        __ERC20_init_unchained(name_, symbol_);
    }

    function __ERC20_init_unchained(string memory name_, string memory symbol_) internal onlyInitializing {
        ERC20Storage storage $ = _getERC20Storage();
        $._name = name_;
        $._symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual returns (string memory) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual returns (string memory) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the default value returned by this function, unless
     * it's overridden.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /// @inheritdoc IERC20
    function totalSupply() public view virtual returns (uint256) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._totalSupply;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view virtual returns (uint256) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `value`.
     */
    function transfer(address to, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `value` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Skips emitting an {Approval} event indicating an allowance update. This is not
     * required by the ERC. See {xref-ERC20-_approve-address-address-uint256-bool-}[_approve].
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `value`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `value`.
     */
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead.
     */
    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value);
    }

    /**
     * @dev Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
     * (or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
     * this function.
     *
     * Emits a {Transfer} event.
     */
    function _update(address from, address to, uint256 value) internal virtual {
        ERC20Storage storage $ = _getERC20Storage();
        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            $._totalSupply += value;
        } else {
            uint256 fromBalance = $._balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                $._balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                $._totalSupply -= value;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                $._balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    /**
     * @dev Creates a `value` amount of tokens and assigns them to `account`, by transferring it from address(0).
     * Relies on the `_update` mechanism
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead.
     */
    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, value);
    }

    /**
     * @dev Destroys a `value` amount of tokens from `account`, lowering the total supply.
     * Relies on the `_update` mechanism.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead
     */
    function _burn(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        _update(account, address(0), value);
    }

    /**
     * @dev Sets `value` as the allowance of `spender` over the `owner`'s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     *
     * Overrides to this logic should be done to the variant with an additional `bool emitEvent` argument.
     */
    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    /**
     * @dev Variant of {_approve} with an optional flag to enable or disable the {Approval} event.
     *
     * By default (when calling {_approve}) the flag is set to true. On the other hand, approval changes made by
     * `_spendAllowance` during the `transferFrom` operation set the flag to false. This saves gas by not emitting any
     * `Approval` event during `transferFrom` operations.
     *
     * Anyone who wishes to continue emitting `Approval` events on the`transferFrom` operation can force the flag to
     * true using the following override:
     *
     * ```solidity
     * function _approve(address owner, address spender, uint256 value, bool) internal virtual override {
     *     super._approve(owner, spender, value, true);
     * }
     * ```
     *
     * Requirements are the same as {_approve}.
     */
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual {
        ERC20Storage storage $ = _getERC20Storage();
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        $._allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    /**
     * @dev Updates `owner`'s allowance for `spender` based on spent `value`.
     *
     * Does not update the allowance value in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Does not emit an {Approval} event.
     */
    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance < type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}


// File @openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.3.0) (utils/Pausable.sol)

pragma solidity ^0.8.20;


/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract PausableUpgradeable is Initializable, ContextUpgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.Pausable
    struct PausableStorage {
        bool _paused;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Pausable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PausableStorageLocation = 0xcd5ed15c6e187e77e9aee88184c21f4f2182ab5827cb3b7e07fbedcd63f03300;

    function _getPausableStorage() private pure returns (PausableStorage storage $) {
        assembly {
            $.slot := PausableStorageLocation
        }
    }

    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    /**
     * @dev The operation failed because the contract is paused.
     */
    error EnforcedPause();

    /**
     * @dev The operation failed because the contract is not paused.
     */
    error ExpectedPause();

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function __Pausable_init() internal onlyInitializing {
    }

    function __Pausable_init_unchained() internal onlyInitializing {
    }
    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        PausableStorage storage $ = _getPausableStorage();
        return $._paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        PausableStorage storage $ = _getPausableStorage();
        $._paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        PausableStorage storage $ = _getPausableStorage();
        $._paused = false;
        emit Unpaused(_msgSender());
    }
}


// File @openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol@v5.4.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/ReentrancyGuard.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If EIP-1153 (transient storage) is available on the chain you're deploying at,
 * consider using {ReentrancyGuardTransient} instead.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuardUpgradeable is Initializable {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    /// @custom:storage-location erc7201:openzeppelin.storage.ReentrancyGuard
    struct ReentrancyGuardStorage {
        uint256 _status;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ReentrancyGuardStorageLocation = 0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    function _getReentrancyGuardStorage() private pure returns (ReentrancyGuardStorage storage $) {
        assembly {
            $.slot := ReentrancyGuardStorageLocation
        }
    }

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    function __ReentrancyGuard_init() internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        $._status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if ($._status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        $._status = ENTERED;
    }

    function _nonReentrantAfter() private {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        $._status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        return $._status == ENTERED;
    }
}


// File contracts/spBEAM/spBEAM_WithValidatorLogic.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.22;





/**
 * @title spBEAM - Sparrow Staked BEAM (Upgradeable with Governance)
 * @author Sparrow Finance
 * @notice First liquid staking token for Beam Network with DAO governance
 * 
 * How it works:
 * 1. Users stake BEAM ??? receive spBEAM tokens
 * 2. spBEAM value increases as validator rewards are added
 * 3. Users request unlock ??? wait unlock period ??? claim BEAM within claim window
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
