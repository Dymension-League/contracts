// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IRandomNumberGenerator.sol";
import "./TeamManager.sol";

contract TournamentManager {
    IRandomNumberGenerator public rng;
    TeamManager public teamManager;

    enum GameType {
        Racing,
        Battle
    }

    struct Game {
        uint256 id;
        uint256 team1;
        uint256 team2;
        uint256 winner;
        uint256 scoreTeam1;
        uint256 scoreTeam2;
        GameType gameType;
    }

    mapping(uint256 => mapping(uint256 => Game)) public games; // leagueId => gameId => Game
    mapping(uint256 => uint256[]) public leagueGames; // leagueId => list of gameIds
    mapping(uint256 => uint256[]) public remainingTeams; // leagueId => remaining teams after elimination

    event MatchSetup(uint256 indexed leagueId, uint256 indexed gameId, uint256 team1, uint256 team2, GameType gameType);
    event MatchResolved(
        uint256 indexed leagueId, uint256 indexed gameId, uint256 winner, uint256 team1Score, uint256 team2Score
    );

    constructor(address _rng, address teamManagerAddress) {
        rng = IRandomNumberGenerator(_rng);
        teamManager = TeamManager(teamManagerAddress); // Set the address of the TeamManager contract
    }

    function setupMatches(uint256 leagueId, uint256[] memory enrolledTeams)
        public
        returns (uint256[] memory team1s, uint256[] memory team2s)
    {
        uint256 numTeams = enrolledTeams.length;
        require(numTeams >= 2, "Not enough teams");

        team1s = new uint256[](numTeams / 2);
        team2s = new uint256[](numTeams / 2);

        // Shuffle teams and pair them up
        for (uint256 i = 0; i < numTeams; i++) {
            uint256 n = i + (rng.getRandomNumber(i) % (numTeams - i));
            uint256 temp = enrolledTeams[n];
            enrolledTeams[n] = enrolledTeams[i];
            enrolledTeams[i] = temp;
        }

        for (uint256 i = 0; i < numTeams / 2; i++) {
            uint256 team1 = enrolledTeams[2 * i];
            uint256 team2 = enrolledTeams[2 * i + 1];
            uint256 gameId = leagueGames[leagueId].length;

            // Create and store the game
            Game memory game = Game({
                id: gameId,
                team1: team1,
                team2: team2,
                winner: 0,
                scoreTeam1: 0,
                scoreTeam2: 0,
                gameType: GameType(rng.getRandomNumber(gameId) % 2)
            });

            games[leagueId][gameId] = game;
            leagueGames[leagueId].push(gameId);

            // Emit the setup event
            emit MatchSetup(leagueId, gameId, team1, team2, game.gameType);
        }

        return (team1s, team2s);
    }

    function batchResolveMatches(uint256 leagueId, uint256[] memory gameIds) public {
        for (uint256 i = 0; i < gameIds.length; i++) {
            resolveMatch(leagueId, gameIds[i]);
        }
    }

    function resolveMatch(uint256 leagueId, uint256 gameId) public {
        Game storage game = games[leagueId][gameId];
        // Simulate score calculation (based on gameType)
        game.scoreTeam1 = calculateTeamScore(game.team1, game.gameType);
        game.scoreTeam2 = calculateTeamScore(game.team2, game.gameType);

        uint256 randomness = rng.getRandomNumber(gameId);

        if (game.scoreTeam1 > game.scoreTeam2) {
            game.winner = game.team1;
        } else if (game.scoreTeam2 > game.scoreTeam1) {
            game.winner = game.team2;
        } else {
            game.winner = randomness % 2 == 0 ? game.team1 : game.team2;
        }

        emit MatchResolved(leagueId, gameId, game.winner, game.scoreTeam1, game.scoreTeam2);
    }

    function getLeagueGameIds(uint256 leagueId) external view returns (uint256[] memory) {
        return leagueGames[leagueId];
    }

    /**
     * @dev Calculate the score for a team based on the game type.
     * @param teamId - The ID of the team whose score is being calculated.
     * @param gameType - The type of game being played (Racing or Battle).
     * @return score - The total score of the team based on its NFTs' attributes.
     */
    function calculateTeamScore(uint256 teamId, GameType gameType) public view returns (uint256 score) {
        // Get the team's NFTs and attributes from TeamManager
        (, uint256 attack, uint256 speed, uint256 shield) = teamManager.getTeam(teamId);

        // Calculate score based on the game type
        if (gameType == GameType.Battle) {
            // In Battle, we sum up the attack and shield attributes
            score = attack + shield;
        } else if (gameType == GameType.Racing) {
            // In Racing, we sum up the speed attribute
            score = speed;
        }

        return score; // Return the final score of the team
    }

    /**
     * @dev Eliminate losing teams after each round of games.
     * @param leagueId - The ID of the league.
     */
    function eliminateLosersFromGames(uint256 leagueId) public {
        uint256[] memory winners = new uint256[](leagueGames[leagueId].length);
        uint256 winnerCount = 0;

        // Collect winners from each game
        for (uint256 gameId = 0; gameId < leagueGames[leagueId].length; gameId++) {
            Game storage game = games[leagueId][gameId];
            winners[winnerCount] = game.winner;
            winnerCount++;
        }

        // Update the remaining teams with only the winners
        remainingTeams[leagueId] = winners;
    }

    /**
     * @dev Get the remaining teams after elimination.
     * @param leagueId - The ID of the league.
     * @return remaining - The remaining teams after elimination.
     */
    function getRemainingTeams(uint256 leagueId) external view returns (uint256[] memory remaining) {
        return remainingTeams[leagueId];
    }
}
