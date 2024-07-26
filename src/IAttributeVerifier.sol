// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IAttributeVerifier {
    /**
     * @dev Verify the provided Merkle proof for the tokenId and attributes.
     * @param root The root of the Merkle tree.
     * @param proof The Merkle proof for the verification.
     * @param tokenId The token ID for which the proof is provided.
     * @param encodedAttributes The encoded attributes associated with the token ID.
     * @return bool True if the verification is successful, otherwise false.
     */
    function verify(bytes32 root, bytes32[] calldata proof, uint256 tokenId, uint256 encodedAttributes)
        external
        pure
        returns (bool);
}
