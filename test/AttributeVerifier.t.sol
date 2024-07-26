// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../src/AttributeVerifier.sol";

contract AttributeVerifierTest is Test {
    AttributeVerifier verifier;

    function setUp() public {
        verifier = new AttributeVerifier();
    }

    function testVerify() public view {
        // Pre generated sample values
        bytes32 root = bytes32(0xd67e5a7bb77ee4c5e38947df0fd5fd577eb7bd77d03d8e86b4b6adf3c0ad4bc2); // Sample root
        uint256 tokenId = 0; // Sample tokenId
        uint256 encodedAttributes = 1096; // Sample encodedAttributes
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0xedc01e4d375758c57a25a6e5095e5ab59d5c2d87eb305682190981234d81175e;
        proof[1] = 0x1938d33112841f5ee65081f55d342198ab4a089d74cefcd0e7c616d43aad8c6d;

        // Test the verify function
        bool result = verifier.verify(root, proof, tokenId, encodedAttributes);
        assertTrue(result, "The verification should succeed.");
    }

    function testRevertVerifyOnWrongProof() public {
        // Pre generated sample values
        bytes32 root = bytes32(0xd67e5a7bb77ee4c5e38947df0fd5fd577eb7bd77d03d8e86b4b6adf3c0ad4bc2); // Sample root
        uint256 tokenId = 1; // Sample tokenId // in purpose wrong id that doesn't belong to tree
        uint256 encodedAttributes = 1096; // Sample encodedAttributes

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0xedc01e4d375758c57a25a6e5095e5ab59d5c2d87eb305682190981234d81175e;
        proof[1] = 0x1938d33112841f5ee65081f55d342198ab4a089d74cefcd0e7c616d43aad8c6d;
        // Test the verify function
        vm.expectRevert("Invalid proof");
        verifier.verify(root, proof, tokenId, encodedAttributes);
    }
}
