// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IRandomNumberGenerator {
    /// @notice Generates a pseudo-random number based on a given seed
    /// @param seed A value used to seed the random number generation
    /// @return A pseudo-random number
    function getRandomNumber(uint256 seed) external view returns (uint256);
}
