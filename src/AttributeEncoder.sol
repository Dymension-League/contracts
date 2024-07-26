// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title A contract for encoding and decoding game attributes into a uint256
contract AttributeEncoder {
    /// @notice Checks if an attribute is within the valid range
    /// @param attribute The attribute to check
    /// @return isValid True if the attribute is within range, false otherwise
    function isValidAttribute(uint256 attribute) private pure returns (bool) {
        return attribute >= 2 && attribute <= 17;
    }

    /// @notice Encodes four game attributes into a single uint256
    /// @dev Each attribute is subtracted by 2 to fit in a 4-bit space and then shifted by a set number of bits
    /// @param capacity The capacity attribute of the game item
    /// @param attack The attack attribute of the game item
    /// @param speed The speed attribute of the game item
    /// @param shield The shield attribute of the game item
    /// @return encoded The encoded attributes as a single uint256
    function encodeAttributes(uint256 capacity, uint256 attack, uint256 speed, uint256 shield)
        public
        pure
        returns (uint256 encoded)
    {
        require(isValidAttribute(capacity), "Attributes must be between 2 and 17 inclusive.");
        require(isValidAttribute(attack), "Attributes must be between 2 and 17 inclusive.");
        require(isValidAttribute(speed), "Attributes must be between 2 and 17 inclusive.");
        require(isValidAttribute(shield), "Attributes must be between 2 and 17 inclusive.");

        encoded = 0;
        encoded |= (capacity - 2) << 12; // Adjust by minimum and shift left by 12 bits
        encoded |= (attack - 2) << 8; // Adjust by minimum and shift left by 8 bits
        encoded |= (speed - 2) << 4; // Adjust by minimum and shift left by 4 bits
        encoded |= (shield - 2); // Adjust by minimum and no shift needed
        return encoded;
    }

    /// @notice Decodes a single uint256 into four game attributes
    /// @param encoded The encoded attributes as a uint256
    /// @return capacity The decoded capacity attribute
    /// @return attack The decoded attack attribute
    /// @return speed The decoded speed attribute
    /// @return shield The decoded shield attribute
    function decodeAttributes(uint256 encoded)
        public
        pure
        returns (uint256 capacity, uint256 attack, uint256 speed, uint256 shield)
    {
        capacity = ((encoded >> 12) & 0xF) + 2; // Decode capacity, adjust by minimum
        attack = ((encoded >> 8) & 0xF) + 2; // Decode attack, adjust by minimum
        speed = ((encoded >> 4) & 0xF) + 2; // Decode speed, adjust by minimum
        shield = (encoded & 0xF) + 2; // Decode shield, adjust by minimum
    }
}
