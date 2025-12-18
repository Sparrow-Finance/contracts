// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IERC4626
 * @notice ERC-4626 Tokenized Vault Standard adapted for native assets
 * @dev This IS ERC-4626 compliant, adapted for native AVAX instead of ERC-20
 * 
 * Key adaptations from standard ERC-4626:
 * - asset() returns address(0) for native AVAX
 * - deposit/mint are payable (receive native AVAX via msg.value)
 * - withdraw/redeem mint NFTs for time-locked redemptions
 * 
 * Matches Starknet spSTRK implementation (which uses ERC-20 STRK)
 * This uses native AVAX but maintains same interface pattern
 */
interface IERC4626 {
    
    // ============================================
    // EVENTS
    // ============================================
    
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    
    // ============================================
    // METADATA
    // ============================================
    
    /// @notice Address of underlying asset (address(0) for native AVAX)
    function asset() external view returns (address assetTokenAddress);
    
    /// @notice Total assets under management
    function totalAssets() external view returns (uint256 totalManagedAssets);
    
    // ============================================
    // DEPOSIT/MINT
    // ============================================
    
    /// @notice Deposit assets and receive shares
    function deposit(address receiver) external payable returns (uint256 shares);
    
    /// @notice Mint exact shares by depositing assets
    function mint(uint256 shares, address receiver) external payable returns (uint256 assets);
    
    // ============================================
    // WITHDRAW/REDEEM
    // ============================================
    
    /// @notice Withdraw assets by burning shares
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    
    /// @notice Redeem shares for assets
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    
    // ============================================
    // ACCOUNTING
    // ============================================
    
    function convertToShares(uint256 assets) external view returns (uint256 shares);
    function convertToAssets(uint256 shares) external view returns (uint256 assets);
    
    function previewDeposit(uint256 assets) external view returns (uint256 shares);
    function previewMint(uint256 shares) external view returns (uint256 assets);
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
    
    // ============================================
    // DEPOSIT/WITHDRAWAL LIMITS
    // ============================================
    
    function maxDeposit(address receiver) external view returns (uint256 maxAssets);
    function maxMint(address receiver) external view returns (uint256 maxShares);
    function maxWithdraw(address owner) external view returns (uint256 maxAssets);
    function maxRedeem(address owner) external view returns (uint256 maxShares);
}