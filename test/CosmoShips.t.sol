// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../src/CosmoShips.sol";
import "../src/AttributeVerifier.sol";

contract CosmoShipsTest is Test {
    CosmoShips nft;
    address deployer;
    AttributeVerifier verifier;
    address user = address(0x1);
    bytes32 initialMerkleRoot = bytes32(0xd67e5a7bb77ee4c5e38947df0fd5fd577eb7bd77d03d8e86b4b6adf3c0ad4bc2);
    uint256 initialMintPrice = 1 ether;

    function setUp() public {
        deployer = address(this);
        verifier = new AttributeVerifier();

        nft = new CosmoShips(initialMerkleRoot, initialMintPrice, deployer, address(verifier));
    }

    function testInitialization() public view {
        assertEq(nft.merkleRoot(), initialMerkleRoot, "Incorrect merkle root set");
        assertEq(nft.mintPrice(), 1 ether, "Incorrect mint price set");
        assertTrue(nft.hasRole(nft.DEFAULT_ADMIN_ROLE(), deployer), "Admin role not assigned correctly");
    }

    function testMintingFunctionality() public {
        uint256 tokenId = 0;
        uint256 attributes = 1096;
        bytes32[2] memory t_proof = [
            bytes32(0xedc01e4d375758c57a25a6e5095e5ab59d5c2d87eb305682190981234d81175e),
            0x1938d33112841f5ee65081f55d342198ab4a089d74cefcd0e7c616d43aad8c6d
        ];
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = t_proof[0];
        proof[1] = t_proof[1];

        vm.deal(user, 2 ether); // Provide ETH to user
        vm.prank(user);
        nft.mint{value: 1 ether}(tokenId, attributes, proof);

        assertTrue(nft.tokenMinted(tokenId), "Token should be marked as minted");
        assertEq(nft.ownerOf(tokenId), user, "Owner is not correctly assigned");
        assertEq(nft.attributes(tokenId), attributes, "Attributes not correctly set");
    }

    function testFail_MintWithoutPayment() public {
        uint256 tokenId = 2;
        uint256 attributes = 0xabcdef;
        bytes32[] memory proof = new bytes32[](1); // Assuming a valid proof for simplicity

        vm.prank(deployer);
        nft.mint{value: 0.5 ether}(tokenId, attributes, proof); // Sending less than the mint price
    }

    function testUpdateMintPrice() public {
        uint256 newPrice = 0.5 ether;

        vm.prank(deployer);
        nft.updateMintPrice(newPrice);
        assertEq(nft.mintPrice(), newPrice, "Mint price was not updated correctly");
    }

    function testFail_UpdateMintPriceByNonAdmin() public {
        uint256 newPrice = 0.5 ether;
        address nonAdmin = address(0x1);

        vm.prank(nonAdmin);
        nft.updateMintPrice(newPrice);
    }

    function testUpdateMerkleRoot() public {
        bytes32 newRoot = 0xabcdef1234560000000000000000000000000000000000000000000000000000;

        vm.prank(deployer);
        nft.updateMerkleRoot(newRoot);
        assertEq(nft.merkleRoot(), newRoot, "Merkle root was not updated correctly");
    }

    function testFail_UpdateMerkleRootByNonAdmin() public {
        bytes32 newRoot = 0xabcdef1234560000000000000000000000000000000000000000000000000000;
        address nonAdmin = address(0x1);

        vm.prank(nonAdmin);
        nft.updateMerkleRoot(newRoot);
    }
}
