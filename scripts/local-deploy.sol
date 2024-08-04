// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/CosmoShips.sol";
import "../src/GameLeague.sol";
import "../src/IAttributeVerifier.sol";
import "../test/fixtures/mockVerifier.sol";
import "../test/fixtures/mockRandomGenerator.sol";

contract MyScript is Script {
    function run() external {
        uint256 mintPrice = 1_000_000_000_000;
        uint256 deployerPrivateKey = vm.envUint("LOCAL_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        IAttributeVerifier verifier = new mockVerifier();
        CosmoShips cosmoShips = new CosmoShips("0x1", 0, mintPrice, address(this), address(verifier));
        MockRandomNumberGenerator mockRNG = new MockRandomNumberGenerator();
        GameLeague gameLeague = new GameLeague(address(cosmoShips), address(mockRNG));

        vm.stopBroadcast();
    }
}
