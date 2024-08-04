// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../src/IAttributeVerifier.sol";

contract mockVerifier is IAttributeVerifier {
    function verify(
        bytes32,
        bytes32[] calldata,
        uint256,
        uint256
    ) public pure returns (bool) {
        return true;
    }
}
