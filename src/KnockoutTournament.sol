// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title KnockoutTournament
/// @notice A contract to manage multiple knockout tournaments with support for over 500 teams.
abstract contract KnockoutTournament {
    /// @notice Structure representing the state of a tournament.
    /// @param currentRound The current round of the tournament.
    /// @param teamsInCurrentRound An array of team IDs currently participating in this round.
    /// @param eliminatedTeams A mapping of eliminated teams, where the key is the team ID and value is a boolean.
    /// @param teamsInRound A mapping of rounds to the teams that participated in those rounds.
    /// @param processedMatches A mapping of rounds to the number of processed matches in that round.
    /// @param semiFinalLosers Array of teams that lost in the semi-finals.
    /// @param secondPlace The team ID that finished in second place.
    /// @param isActive A boolean representing whether the tournament is still active.
    struct Tournament {
        uint256 currentRound;
        uint256[] teamsInCurrentRound;
        mapping(uint256 => bool) eliminatedTeams;
        mapping(uint256 => uint256[]) teamsInRound;
        mapping(uint256 => uint256) processedMatches;
        uint256[] semiFinalLosers;
        uint256 secondPlace;
        bool isActive;
    }

    /// @notice Event emitted when a match result is determined.
    /// @param tournamentId The ID of the tournament.
    /// @param round The round in which the match took place.
    /// @param matchIndex The index of the match in the current round.
    /// @param winner The team ID of the match winner.
    /// @param loser The team ID of the match loser.
    event MatchResult(
        uint256 indexed tournamentId, uint256 indexed round, uint256 indexed matchIndex, uint256 winner, uint256 loser
    );

    /// @notice Event emitted when a tournament concludes and winners are determined.
    /// @param tournamentId The ID of the tournament.
    /// @param firstPlace The team ID that won the tournament.
    /// @param secondPlace The team ID that finished in second place.
    /// @param thirdPlace The team ID that finished in third place.
    event TournamentWinner(uint256 indexed tournamentId, uint256 firstPlace, uint256 secondPlace, uint256 thirdPlace);

    /// @notice Next available tournament ID.
    uint256 public nextTournamentId;

    /// @notice Mapping from tournament ID to its state.
    mapping(uint256 => Tournament) private tournaments;

    /// @notice Initializes a new tournament with the given team IDs.
    function initializeTournament(uint256[] calldata teamIds) public virtual returns (uint256 tournamentId) {
        require(teamIds.length > 1, "At least two teams are required");
        tournamentId = nextTournamentId++;
        Tournament storage newTournament = tournaments[tournamentId];
        newTournament.currentRound = 0;
        newTournament.teamsInCurrentRound = teamIds;
        newTournament.teamsInRound[0] = teamIds; // Store initial teams in round 0
        newTournament.isActive = true;
        return tournamentId;
    }

    /// @notice Determines the outcome of a match between two teams based on a random seed.
    /// @param tournamentId The ID of the tournament.
    /// @param team1 The ID of the first team.
    /// @param team2 The ID of the second team.
    /// @param randomSeed A random seed used to determine the match outcome.
    /// @return winner The ID of the winning team.
    /// @return loser The ID of the losing team.
    function determineMatchOutcome(uint256 tournamentId, uint256 team1, uint256 team2, uint256 randomSeed)
        public
        view
        virtual
        returns (uint256 winner, uint256 loser);

    /// @notice Processes a batch of matches for the given tournament and round.
    /// @param tournamentId The ID of the tournament.
    /// @param batchSize The number of matches to process in this batch.
    /// @param randomSeed A random seed used for match outcome determination.
    function processNextBatch(uint256 tournamentId, uint256 batchSize, uint256 randomSeed) public {
        Tournament storage tournament = tournaments[tournamentId];
        require(tournament.isActive, "Tournament is not active");

        uint256 startIndex = tournament.processedMatches[tournament.currentRound];
        uint256 totalMatches = tournament.teamsInCurrentRound.length / 2;
        uint256 matchesToProcess = (totalMatches - startIndex) < batchSize ? (totalMatches - startIndex) : batchSize;

        require(matchesToProcess > 0, "No matches to process");

        uint256[] memory teamsInCurrentRound = tournament.teamsInCurrentRound;

        for (uint256 i = 0; i < matchesToProcess;) {
            _processMatch(tournamentId, tournament, startIndex + i, randomSeed, teamsInCurrentRound);
            unchecked {
                i++;
            }
        }

        tournament.processedMatches[tournament.currentRound] += matchesToProcess;

        if (tournament.processedMatches[tournament.currentRound] >= totalMatches) {
            _advanceToNextRound(tournamentId, tournament);
        }
    }

    /// @dev Internal function to process an individual match.
    /// @param tournamentId The ID of the tournament.
    /// @param tournament The tournament data structure.
    /// @param matchIndex The index of the match in the current round.
    /// @param randomSeed A random seed used for match outcome determination.
    /// @param teams The teams to process
    function _processMatch(
        uint256 tournamentId,
        Tournament storage tournament,
        uint256 matchIndex,
        uint256 randomSeed,
        uint256[] memory teams
    ) internal {
        uint256 team1Index = matchIndex * 2;
        uint256 team2Index = team1Index + 1;

        if (team2Index >= teams.length) return;

        uint256 team1 = teams[team1Index];
        uint256 team2 = teams[team2Index];

        if (tournament.eliminatedTeams[team1] || tournament.eliminatedTeams[team2]) return;

        uint256 random = uint256(keccak256(abi.encode(tournamentId, tournament.currentRound, matchIndex, randomSeed)));
        (uint256 winner, uint256 loser) = determineMatchOutcome(tournamentId, team1, team2, random);

        tournament.eliminatedTeams[loser] = true;
        tournament.teamsInRound[tournament.currentRound + 1].push(winner);

        emit MatchResult(tournamentId, tournament.currentRound, matchIndex, winner, loser);

        if (teams.length == 4) {
            tournament.semiFinalLosers.push(loser);
        } else if (teams.length == 2) {
            tournament.secondPlace = loser;
        }
    }

    /// @dev Advances the tournament to the next round.
    function _advanceToNextRound(uint256 tournamentId, Tournament storage tournament) internal {
        if (tournament.teamsInCurrentRound.length % 2 == 1) {
            uint256 lastTeam = tournament.teamsInCurrentRound[tournament.teamsInCurrentRound.length - 1];
            tournament.teamsInRound[tournament.currentRound + 1].push(lastTeam);
        }

        tournament.currentRound++;
        tournament.teamsInCurrentRound = tournament.teamsInRound[tournament.currentRound];

        if (tournament.teamsInCurrentRound.length == 1 && tournament.semiFinalLosers.length == 2) {
            tournament.teamsInCurrentRound = tournament.semiFinalLosers;
            delete tournament.semiFinalLosers;
        } else if (tournament.currentRound >= 3 && tournament.teamsInRound[tournament.currentRound - 1].length == 2) {
            uint256 firstPlace = tournament.teamsInRound[tournament.currentRound - 2][0];
            uint256 thirdPlace = tournament.teamsInCurrentRound[0];
            emit TournamentWinner(tournamentId, firstPlace, tournament.secondPlace, thirdPlace);
            tournament.isActive = false;
        }

        tournament.processedMatches[tournament.currentRound] = 0;
    }

    /// @notice Returns the number of processed matches in the current or previous round.
    function getProcessedMatchesCount(uint256 tournamentId) public view returns (uint256) {
        Tournament storage tournament = tournaments[tournamentId];

        uint256 roundToCheck = tournament.processedMatches[tournament.currentRound] > 0
            ? tournament.currentRound
            : tournament.currentRound - 1;

        return tournaments[tournamentId].processedMatches[roundToCheck];
    }

    /// @notice Returns the team IDs participating in a given round.
    function getTeamsInRound(uint256 tournamentId, uint256 round) public view returns (uint256[] memory) {
        return tournaments[tournamentId].teamsInRound[round];
    }
}
