// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IWithdrawalQueueNFT
 * @notice Interface for the Withdrawal Queue NFT contract
 */
interface IWithdrawalQueueNFT {
    
    struct WithdrawalRequest {
        uint256 spAvaxAmount;
        uint256 avaxAmount;
        uint256 unlockTime;
        uint256 expiryTime;
    }
    
    function mint(address to, WithdrawalRequest memory request) 
        external 
        returns (uint256 tokenId);
    
    function burn(uint256 tokenId) external;
    
    function requests(uint256 tokenId) 
        external 
        view 
        returns (
            uint256 spAvaxAmount,
            uint256 avaxAmount,
            uint256 unlockTime,
            uint256 expiryTime
        );
    
    function getRequest(uint256 tokenId) 
        external 
        view 
        returns (WithdrawalRequest memory);
    
    function isClaimable(uint256 tokenId) external view returns (bool);
    
    function isExpired(uint256 tokenId) external view returns (bool);
    
    function ownerOf(uint256 tokenId) external view returns (address);
}