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
    uint256 public nextTokenIdToMint;
    uint256 public mintPrice;
    IAttributeVerifier public verifier;
    mapping(uint256 => uint256) public attributes;

    event Minted(address minter, uint256 tokenId);

    constructor(
        bytes32 _merkleRoot,
        uint256 _initialShipIdToMint,
        uint256 _mintPrice,
        address _defaultAdmin,
        address _verifier
    ) ERC721("CosmoShips", "CSSS") {
        merkleRoot = _merkleRoot;
        mintPrice = _mintPrice;
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        verifier = IAttributeVerifier(_verifier);
        if (_initialShipIdToMint <= 0) {
            _initialShipIdToMint = 1;
        }
        nextTokenIdToMint = _initialShipIdToMint;
    }

    function updateMerkleRoot(bytes32 _newRoot) external onlyRole(DEFAULT_ADMIN_ROLE) {
        merkleRoot = _newRoot;
    }

    function updateMintPrice(uint256 _newPrice) external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintPrice = _newPrice;
    }

    function maintenance(uint256 tokenId, uint256 _newAttribute) external onlyRole(MAINTENANCE_ROLE) {
        attributes[tokenId] = _newAttribute;
    }

    function mint(uint256 _attributes, bytes32[] calldata _proof) external payable nonReentrant {
        require(msg.value == mintPrice, "Incorrect payment sent");
        require(verifier.verify(merkleRoot, _proof, nextTokenIdToMint, _attributes), "Invalid proof");
        attributes[nextTokenIdToMint] = _attributes;
        _safeMint(msg.sender, nextTokenIdToMint);
        emit Minted(msg.sender, nextTokenIdToMint);
        nextTokenIdToMint += 1;
    }

    function batchMint(uint256[] calldata _attributes, bytes32[][] calldata _proofs, uint256 _count)
        external
        payable
        nonReentrant
    {
        require(_attributes.length == _count && _proofs.length == _count, "Invalid input lengths");
        require(msg.value == mintPrice * _count, "Incorrect payment sent");

        for (uint256 i = 0; i < _count; i++) {
            require(verifier.verify(merkleRoot, _proofs[i], nextTokenIdToMint, _attributes[i]), "Invalid proof");

            attributes[nextTokenIdToMint] = _attributes[i];
            _safeMint(msg.sender, nextTokenIdToMint);
            emit Minted(msg.sender, nextTokenIdToMint);
            nextTokenIdToMint += 1;
        }
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
