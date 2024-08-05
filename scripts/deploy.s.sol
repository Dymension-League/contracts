// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/CosmoShips.sol";
import "../src/GameLeague.sol";
import "../src/AttributeVerifier.sol";
import "../src/RandomNumberGenerator.sol";

contract Deploy is Script {
    function run() external {
        uint256 mintPrice = 1_000_000_000_000;
        bytes32 merkleRoot = keccak256(bytes.concat(keccak256(abi.encodePacked("0", "1096"))));
        vm.startBroadcast();

        IAttributeVerifier verifier = new AttributeVerifier();
        CosmoShips cosmoShips = new CosmoShips(merkleRoot, 0, mintPrice, msg.sender, address(verifier));

        RandomNumberGenerator mockRNG = new RandomNumberGenerator();
        GameLeague gameLeague = new GameLeague(address(cosmoShips), address(mockRNG));

        vm.stopBroadcast();
    }
}
