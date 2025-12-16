// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title WithdrawalQueueNFT
 * @author Sparrow Finance
 * @notice ERC-721 NFT representing withdrawal requests from spAVAX vault
 */
contract WithdrawalQueueNFT is ERC721, Ownable {
    
    // ============================================
    // STATE VARIABLES
    // ============================================
    
    address public vault;
    uint256 private _nextTokenId;
    
    struct WithdrawalRequest {
        uint256 spAvaxAmount;
        uint256 avaxAmount;
        uint256 unlockTime;
        uint256 expiryTime;
    }
    
    mapping(uint256 => WithdrawalRequest) public requests;
    
    // ============================================
    // EVENTS
    // ============================================
    
    event RequestMinted(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 spAvaxAmount,
        uint256 avaxAmount,
        uint256 unlockTime,
        uint256 expiryTime
    );
    
    event RequestBurned(uint256 indexed tokenId);
    event VaultSet(address indexed vault);
    
    // ============================================
    // MODIFIERS
    // ============================================
    
    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    constructor(address initialOwner) 
        ERC721("Sparrow Withdrawal Request", "spWR")
        Ownable(initialOwner)
    {
        _nextTokenId = 1;
    }
    
    // ============================================
    // ADMIN FUNCTIONS
    // ============================================
    
    function setVault(address _vault) external onlyOwner {
        require(vault == address(0), "Vault already set");
        require(_vault != address(0), "Invalid vault address");
        vault = _vault;
        emit VaultSet(_vault);
    }
    
    // ============================================
    // VAULT FUNCTIONS
    // ============================================
    
    function mint(address to, WithdrawalRequest memory request) 
        external 
        onlyVault 
        returns (uint256 tokenId) 
    {
        require(to != address(0), "Cannot mint to zero address");
        require(request.spAvaxAmount > 0, "Invalid spAVAX amount");
        require(request.avaxAmount > 0, "Invalid AVAX amount");
        require(request.unlockTime > block.timestamp, "Invalid unlock time");
        require(request.expiryTime > request.unlockTime, "Invalid expiry time");
        
        tokenId = _nextTokenId++;
        requests[tokenId] = request;
        _safeMint(to, tokenId);
        
        emit RequestMinted(
            tokenId,
            to,
            request.spAvaxAmount,
            request.avaxAmount,
            request.unlockTime,
            request.expiryTime
        );
        
        return tokenId;
    }
    
    function burn(uint256 tokenId) external onlyVault {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        delete requests[tokenId];
        _burn(tokenId);
        emit RequestBurned(tokenId);
    }
    
    // ============================================
    // VIEW FUNCTIONS
    // ============================================
    
    function isClaimable(uint256 tokenId) external view returns (bool) {
        WithdrawalRequest memory request = requests[tokenId];
        return block.timestamp >= request.unlockTime && 
               block.timestamp < request.expiryTime;
    }
    
    function isExpired(uint256 tokenId) external view returns (bool) {
        return block.timestamp >= requests[tokenId].expiryTime;
    }
    
    function getRequest(uint256 tokenId) 
        external 
        view 
        returns (WithdrawalRequest memory) 
    {
        return requests[tokenId];
    }
    
    // ============================================
    // TOKEN URI (Optional: Basic metadata)
    // ============================================
    
    function tokenURI(uint256 tokenId) 
        public 
        view 
        override 
        returns (string memory) 
    {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        
        WithdrawalRequest memory request = requests[tokenId];
        
        // Basic JSON metadata
        string memory json = string(abi.encodePacked(
            '{"name":"Sparrow Withdrawal Request #',
            _toString(tokenId),
            '","description":"Withdrawal request for ',
            _toString(request.avaxAmount / 1e18),
            ' AVAX","attributes":[',
            '{"trait_type":"AVAX Amount","value":"',
            _toString(request.avaxAmount / 1e18),
            '"},',
            '{"trait_type":"Status","value":"',
            _getStatus(tokenId),
            '"}]}'
        ));
        
        return string(abi.encodePacked(
            'data:application/json;base64,',
            _base64Encode(bytes(json))
        ));
    }
    
    // ============================================
    // INTERNAL HELPERS
    // ============================================
    
    function _getStatus(uint256 tokenId) internal view returns (string memory) {
        WithdrawalRequest memory request = requests[tokenId];
        if (block.timestamp >= request.expiryTime) {
            return "Expired";
        } else if (block.timestamp >= request.unlockTime) {
            return "Claimable";
        } else {
            return "Pending";
        }
    }
    
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    function _base64Encode(bytes memory data) internal pure returns (string memory) {
        bytes memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        uint256 len = data.length;
        if (len == 0) return "";
        
        uint256 encodedLen = 4 * ((len + 2) / 3);
        bytes memory result = new bytes(encodedLen);
        
        uint256 i = 0;
        uint256 j = 0;
        
        for (; i + 2 < len; i += 3) {
            uint256 a0 = uint8(data[i]);
            uint256 a1 = uint8(data[i + 1]);
            uint256 a2 = uint8(data[i + 2]);
            
            result[j++] = table[(a0 >> 2) & 0x3F];
            result[j++] = table[((a0 << 4) | (a1 >> 4)) & 0x3F];
            result[j++] = table[((a1 << 2) | (a2 >> 6)) & 0x3F];
            result[j++] = table[a2 & 0x3F];
        }
        
        if (i < len) {
            uint256 a0 = uint8(data[i]);
            if (i + 1 < len) {
                uint256 a1 = uint8(data[i + 1]);
                result[j++] = table[(a0 >> 2) & 0x3F];
                result[j++] = table[((a0 << 4) | (a1 >> 4)) & 0x3F];
                result[j++] = table[(a1 << 2) & 0x3F];
                result[j++] = "=";
            } else {
                result[j++] = table[(a0 >> 2) & 0x3F];
                result[j++] = table[(a0 << 4) & 0x3F];
                result[j++] = "=";
                result[j++] = "=";
            }
        }
        
        return string(result);
    }
}