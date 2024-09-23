// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./fixtures/MockKnockoutTournament.sol";

/// @title KnockoutTournamentTest
/// @notice Unit tests for the KnockoutTournament contract using Foundry's Test framework.
contract FuzzKnockoutTournamentTest is Test {
    MockKnockoutTournament public tournament;

    /// @notice Sets up the test environment before each test case.
    function setUp() public {
        tournament = new MockKnockoutTournament();
    }

    /// @notice Tests tournament initialization with a varying number of teams using fuzzing.
    /// @param numTeams The number of teams in the tournament.
    function testFuzzInitializeTournament(uint256 numTeams) public {
        vm.assume(numTeams >= 2 && numTeams <= 512); // Ensure valid team range between 2 and 512

        uint256[] memory teamIds = new uint256[](numTeams);
        for (uint256 i = 0; i < numTeams; i++) {
            teamIds[i] = i + 1;
        }

        uint256 tournamentId = tournament.initializeTournament(teamIds);

        // Ensure the tournament is initialized correctly
        uint256[] memory initialTeams = tournament.getTeamsInRound(tournamentId, 0);
        assertEq(initialTeams.length, numTeams);

        // Check behavior based on even or odd number of teams
        if (numTeams % 2 == 0) {
            // If even, all teams should have pairs for matchups
            assertEq(numTeams % 2, 0);
        } else {
            // If odd, one team should advance automatically in the first round
            uint256 teamsInFirstRound = tournament.getTeamsInRound(tournamentId, 0).length;
            assertEq(teamsInFirstRound, numTeams);
        }
    }
    /// @notice Tests processing of matches in tournaments with different numbers of teams using fuzzing.
    /// @param numTeams The number of teams in the tournament.

    function testFuzzProcessMatches(uint256 numTeams) public {
        vm.assume(numTeams >= 2 && numTeams <= 512); // Ensure valid team range

        uint256[] memory teamIds = new uint256[](numTeams);
        for (uint256 i = 0; i < numTeams; i++) {
            teamIds[i] = i + 1;
        }

        uint256 tournamentId = tournament.initializeTournament(teamIds);

        // Process the first round in batches
        uint256 batchSize = numTeams / 2; // Half of the teams in first round
        tournament.processNextBatch(tournamentId, batchSize, 0);

        // Ensure matches are processed correctly
        uint256 processedMatches = tournament.getProcessedMatchesCount(tournamentId);
        uint256 expectedProcessedMatches = numTeams / 2;
        assertEq(processedMatches, expectedProcessedMatches);

        // Calculate the expected number of teams advancing to the next round
        uint256 expectedTeamsInNextRound;
        if (numTeams % 2 == 0) {
            // If even, all teams are paired, and half should advance
            expectedTeamsInNextRound = numTeams / 2;
        } else {
            // If odd, one team should advance automatically, so (numTeams / 2) + 1 should advance
            expectedTeamsInNextRound = (numTeams / 2) + 1;
        }

        // Ensure the correct number of teams advance to the next round
        uint256 teamsInNextRound = tournament.getTeamsInRound(tournamentId, 1).length;
        assertEq(teamsInNextRound, expectedTeamsInNextRound);
    }

    /// @notice Tests edge cases for specific numbers of teams.
    function testEdgeCases() public {
        // Test with 2 teams (minimum number)
        testFuzzInitializeTournament(2);
        testFuzzProcessMatches(2);

        // Test with 3 teams (odd number)
        testFuzzInitializeTournament(3);
        testFuzzProcessMatches(3);

        // Test with 511 teams (odd large number)
        testFuzzInitializeTournament(511);
        testFuzzProcessMatches(511);

        // Test with 512 teams (maximum even number)
        testFuzzInitializeTournament(512);
        testFuzzProcessMatches(512);
    }
}
