// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../src/IRandomNumberGenerator.sol";

contract MockRandomNumberGenerator is IRandomNumberGenerator {
    function getRandomNumber(
        uint256 _seed
    ) external pure override returns (uint256) {
        return _seed;
    }
}
