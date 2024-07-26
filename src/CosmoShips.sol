// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "openzeppelin-contracts/contracts/access/AccessControl.sol";
import "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import "./AttributeEncoder.sol";
import "./IAttributeVerifier.sol";

contract CosmoShips is ERC721, AccessControl, ReentrancyGuard, AttributeEncoder, ERC721Enumerable {
    bytes32 public constant MAINTENANCE_ROLE = keccak256("MAINTENANCE_ROLE");
    bytes32 public merkleRoot;
    uint256 public mintPrice;
    IAttributeVerifier public verifier;
    mapping(uint256 => bool) public tokenMinted;
    mapping(uint256 => uint256) public attributes;

    event Minted(address minter, uint256 tokenId);

    constructor(bytes32 _merkleRoot, uint256 _mintPrice, address _defaultAdmin, address _verifier)
        ERC721("CosmoShips", "CSSS")
    {
        merkleRoot = _merkleRoot;
        mintPrice = _mintPrice;
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        verifier = IAttributeVerifier(_verifier);
    }

    function updateMerkleRoot(bytes32 _newRoot) external onlyRole(DEFAULT_ADMIN_ROLE) {
        merkleRoot = _newRoot;
    }

    function updateMintPrice(uint256 _newPrice) external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintPrice = _newPrice;
    }

    function maintenance(uint256 _tokenId, uint256 _newAttribute) external onlyRole(MAINTENANCE_ROLE) {
        attributes[_tokenId] = _newAttribute;
    }

    function mint(uint256 _tokenId, uint256 _attributes, bytes32[] calldata _proof) external payable nonReentrant {
        require(msg.value == mintPrice, "Incorrect paymen sent");
        require(!tokenMinted[_tokenId], "Token already minted");
        require(verifier.verify(merkleRoot, _proof, _tokenId, _attributes), "Invalid proof");

        tokenMinted[_tokenId] = true;
        attributes[_tokenId] = _attributes;
        _safeMint(msg.sender, _tokenId);
        emit Minted(msg.sender, _tokenId);
    }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        return ERC721Enumerable._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return ERC721.supportsInterface(interfaceId) || ERC721Enumerable.supportsInterface(interfaceId)
            || ERC721Enumerable.supportsInterface(interfaceId);
    }
}
