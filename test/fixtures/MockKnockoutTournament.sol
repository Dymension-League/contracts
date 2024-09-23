// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../src/KnockoutTournament.sol";

contract MockKnockoutTournament is KnockoutTournament {
    function initializeTournament(uint256[] memory teamIds) public override returns (uint256 tournamentId) {
        return super.initializeTournament(teamIds);
    }

    function determineMatchOutcome(uint256, uint256 team1, uint256 team2, uint256 randomSeed)
        public
        pure
        override
        returns (uint256 winner, uint256 loser)
    {
        // Simple deterministic outcome based on team numbers and random seed
        if ((team1 + randomSeed) % 2 == 0) {
            return (team1, team2);
        } else {
            return (team2, team1);
        }
    }
}
