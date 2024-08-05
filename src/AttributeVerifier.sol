// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import "./IAttributeVerifier.sol";

contract AttributeVerifier is IAttributeVerifier {
    function verify(bytes32 root, bytes32[] calldata proof, uint256 tokenId, uint256 encodedAttributes)
        public
        pure
        returns (bool)
    {
        // Construct the leaf from the hash of tokenId and encodedAttributes
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encodePacked(tokenId, encodedAttributes))));

        // Verify the proof against the root and the constructed leaf
        require(MerkleProof.verify(proof, root, leaf), "Invalid proof");

        // Verify success
        return true;
    }
}
