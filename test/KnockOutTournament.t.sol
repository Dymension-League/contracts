// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./fixtures/MockKnockoutTournament.sol";

contract KnockoutTournamentTest is Test {
    MockKnockoutTournament public tournament;
    uint256[] public teamIds;

    function setUp() public {
        tournament = new MockKnockoutTournament();
        teamIds = new uint256[](8);
        for (uint256 i = 0; i < 8; i++) {
            teamIds[i] = i + 1;
        }
    }

    function testInitializeTournament() public {
        uint256 tournamentId = tournament.initializeTournament(teamIds);
        assertEq(tournamentId, 0);
        assertEq(tournament.nextTournamentId(), 1);

        uint256[] memory initialTeams = tournament.getTeamsInRound(tournamentId, 0);
        assertEq(initialTeams.length, 8);
    }

    function testDetermineMatchOutcome() public view {
        (uint256 winner, uint256 loser) = tournament.determineMatchOutcome(0, 1, 2, 0);
        assertEq(winner, 2);
        assertEq(loser, 1);

        (winner, loser) = tournament.determineMatchOutcome(0, 1, 2, 1);
        assertEq(winner, 1);
        assertEq(loser, 2);
    }

    function testProcessNextBatch() public {
        uint256 tournamentId = tournament.initializeTournament(teamIds);
        tournament.processNextBatch(tournamentId, 4, 0);
        assertEq(tournament.getProcessedMatchesCount(tournamentId), 4);

        uint256[] memory teamsInNextRound = tournament.getTeamsInRound(tournamentId, 1);
        assertEq(teamsInNextRound.length, 4);
    }

    function testCompleteTournament() public {
        uint256 tournamentId = tournament.initializeTournament(teamIds);

        // Process all rounds
        tournament.processNextBatch(tournamentId, 4, 0); // Round 1
        tournament.processNextBatch(tournamentId, 2, 1); // Round 2
        tournament.processNextBatch(tournamentId, 1, 2); // Final
        tournament.processNextBatch(tournamentId, 1, 3); // Third place match

        // Check that we can't process any more matches
        vm.expectRevert("No matches to process");
        tournament.processNextBatch(tournamentId, 1, 4);
    }

    function testGetTeamsInRound() public {
        uint256 tournamentId = tournament.initializeTournament(teamIds);

        uint256[] memory teamsInRound = tournament.getTeamsInRound(tournamentId, 0);
        assertEq(teamsInRound.length, 8);

        tournament.processNextBatch(tournamentId, 4, 0);

        teamsInRound = tournament.getTeamsInRound(tournamentId, 1);
        assertEq(teamsInRound.length, 4);
    }

    function testLargeTournament() public {
        uint256[] memory largeTeamIds = new uint256[](512);
        for (uint256 i = 0; i < 512; i++) {
            largeTeamIds[i] = i + 1;
        }

        uint256 tournamentId = tournament.initializeTournament(largeTeamIds);

        // Process first round
        for (uint256 i = 0; i < 16; i++) {
            tournament.processNextBatch(tournamentId, 16, i);
        }

        uint256[] memory teamsInNextRound = tournament.getTeamsInRound(tournamentId, 1);
        assertEq(teamsInNextRound.length, 256);
    }
}
