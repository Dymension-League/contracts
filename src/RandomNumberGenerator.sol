// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IRandomNumberGenerator.sol";

contract RandomNumberGenerator is IRandomNumberGenerator {
    function getRandomNumber(uint256 seed) external view override returns (uint256) {
        return uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), seed)));
    }
}
