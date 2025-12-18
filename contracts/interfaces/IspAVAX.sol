// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IERC4626.sol";
import "./IWithdrawalQueueNFT.sol";

/**
 * @title IspAVAX
 * @notice Complete interface for spAVAX liquid staking vault
 * @dev Extends IERC4626Like with legacy functions and admin operations
 */
interface IspAVAX is IERC4626 {
    
    // ============================================
    // STRUCTS
    // ============================================
    
    struct UnlockRequest {
        uint256 spAvaxAmount;
        uint256 avaxAmount;
        uint256 unlockTime;
        uint256 expiryTime;
    }
    
    // ============================================
    // EVENTS (LEGACY)
    // ============================================
    
    event Staked(address indexed user, uint256 avaxAmount, uint256 spAvaxAmount);
    event UnlockRequested(address indexed user, uint256 spAvaxAmount, uint256 avaxAmount, uint256 unlockTime, uint256 expiryTime);
    event Unstaked(address indexed user, uint256 spAvaxAmount, uint256 avaxAmount);
    event UnlockCancelled(address indexed user, uint256 index, uint256 spAvaxAmount);
    event UnlockExpired(address indexed user, uint256 index, uint256 spAvaxAmount);
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
    event WithdrawalNFTUpdated(address indexed oldNFT, address indexed newNFT);
    
    // ============================================
    // LEGACY USER FUNCTIONS
    // ============================================
    
    function stake(uint256 minSpAvaxOut) external payable returns (uint256 spAvaxAmount);
    function requestUnlock(uint256 spAvaxAmount, uint256 minAvaxOut) external returns (uint256 avaxAmount);
    function claimUnlock(uint256 requestIndex) external;
    function cancelUnlock(uint256 requestIndex) external;
    function claimExpired(uint256 requestIndex) external;
    
    // ============================================
    // NFT WITHDRAWAL FUNCTIONS
    // ============================================
    
    function claimWithdrawalNFT(uint256 tokenId) external;
    function cancelWithdrawalNFT(uint256 tokenId) external;
    function claimExpiredNFT(uint256 tokenId) external;
    
    // ============================================
    // VIEW FUNCTIONS
    // ============================================
    
    function getUnlockRequestCount(address user) external view returns (uint256);
    function getUnlockRequest(address user, uint256 requestIndex) 
        external 
        view 
        returns (
            uint256 spAvaxAmount,
            uint256 avaxAmount,
            uint256 unlockTime,
            uint256 expiryTime,
            bool isReady,
            bool isExpired
        );
    function getExchangeRate() external view returns (uint256);
    function previewStake(uint256 avaxAmount) external view returns (uint256 spAvaxAmount);
    function previewUnlock(uint256 spAvaxAmount) external view returns (uint256 avaxAmount);
    function getWithdrawalNFTData(uint256 tokenId) 
        external 
        view 
        returns (
            IWithdrawalQueueNFT.WithdrawalRequest memory request,
            bool isReady,
            bool isExpired
        );
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
        );
    
    // ============================================
    // ADMIN FUNCTIONS
    // ============================================
    
    function adminWithdraw(uint256 amount) external;
    function adminDeposit() external payable;
    function addRewards() external payable;
    function collectDaoFees() external;
    function collectDevFees() external;
    function collectAllFees() external;
    function setFeeStructure(uint256 newDaoFee, uint256 newDevFee) external;
    function setMinStakeAmount(uint256 newMinAmount) external;
    function setUnlockPeriod(uint256 newUnlockPeriod) external;
    function setClaimWindow(uint256 newClaimWindow) external;
    function setWithdrawalNFT(address newNFT) external;
    function pause() external;
    function unpause() external;
    
    // ============================================
    // STATE VARIABLES (PUBLIC GETTERS)
    // ============================================
    
    function minStakeAmount() external view returns (uint256);
    function unlockPeriod() external view returns (uint256);
    function claimWindow() external view returns (uint256);
    function totalPooledAVAX() external view returns (uint256);
    function totalLockedInUnlocks() external view returns (uint256);
    function accumulatedDaoFees() external view returns (uint256);
    function accumulatedDevFees() external view returns (uint256);
    function daoFeeBasisPoints() external view returns (uint256);
    function devFeeBasisPoints() external view returns (uint256);
    function protocolFeeBasisPoints() external view returns (uint256);
}