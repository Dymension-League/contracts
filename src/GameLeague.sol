// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import "openzeppelin-contracts/contracts/utils/Counters.sol";
import "./CosmoShips.sol";
import "./IRandomNumberGenerator.sol";

contract GameLeague is ERC721Holder {
    using Counters for Counters.Counter;

    Counters.Counter private leagueIdCounter;

    Counters.Counter private teamsCounter;

    event Leaderboard(
        uint256 indexed leagueId,
        uint256[] teamIds,
        string[] teamNames,
        uint256[] totalScores,
        uint256[] gamesPlayed,
        bool[] eliminated
    );
    event GamesSetup(
        uint256 indexed leagueId, uint256[] gameIds, uint256[] team1s, uint256[] team2s, GameType[] gameTypes
    );

    enum LeagueState {
        Idle,
        Initiated,
        EnrollmentClosed,
        BetsOpen,
        Running,
        Distribution,
        Concluded
    }

    struct League {
        uint256 id;
        uint256 prizePool;
        uint256 totalBetsInLeague;
        LeagueState state;
        uint256[] enrolledTeams;
        mapping(uint256 => bool) teamsMap;
        mapping(uint256 => Game) games;
        mapping(uint256 => uint256) totalBetsOnTeam;
        mapping(address => mapping(uint256 => uint256)) userBetsOnTeam;
        mapping(address => uint256[]) userBetTeams;
        mapping(address => uint256) claimableRewards;
        mapping(uint256 => uint256) teamTotalScore;
        mapping(uint256 => uint256) teamGamesPlayed;
        Counters.Counter gameIdCounter;
        mapping(uint256 => bool) eliminatedTeams;
    }

    struct Game {
        uint256 id;
        uint256 team1;
        uint256 team2;
        uint256 winner;
        uint256 team1Score;
        uint256 team2Score;
        GameType gameType;
    }

    struct Team {
        uint256[] nftIds;
        address owner;
        string name;
    }

    enum GameType {
        Racing,
        Battle
    }

    uint256 public currentLeagueId;
    mapping(uint256 => League) public leagues;
    mapping(uint256 => Team) public teams;
    mapping(address => uint256) public stakes;

    CosmoShips public cosmoShips;
    IRandomNumberGenerator public rng;

    constructor(address _nftAddress, address _rng) {
        cosmoShips = CosmoShips(_nftAddress);
        rng = IRandomNumberGenerator(_rng);
    }

    function createTeam(uint256[] calldata nftIds, string calldata teamName) external returns (uint256) {
        require(nftIds.length == 3, "Must stake exactly three NFTs");
        uint256 newTeamId = teamsCounter.current();
        Team storage newTeam = teams[newTeamId];
        for (uint256 i = 0; i < nftIds.length; i++) {
            require(cosmoShips.ownerOf(nftIds[i]) == msg.sender, "Not the owner of the NFT");
            cosmoShips.transferFrom(msg.sender, address(this), nftIds[i]);
            newTeam.nftIds.push(nftIds[i]);
        }
        newTeam.owner = msg.sender;
        newTeam.name = teamName;
        teamsCounter.increment();
        return newTeamId;
    }

    function getTeam(uint256 teamId) public view returns (string memory, uint256[] memory, address) {
        Team storage team = teams[teamId];
        return (team.name, team.nftIds, team.owner);
    }

    function getTeamsByOwner(address owner)
        public
        view
        returns (uint256[] memory teamIds, string[] memory teamNames, uint256[][] memory tokenIndexes)
    {
        uint256 totalTeams = teamsCounter.current();
        uint256 count = 0;

        teamIds = new uint256[](count);
        teamNames = new string[](count);
        tokenIndexes = new uint256[][](count);
        count = 0;

        for (uint256 i = 0; i < totalTeams; i++) {
            if (teams[i].owner == owner) {
                teamIds[count] = i;
                teamNames[count] = teams[i].name;
                tokenIndexes[count] = teams[i].nftIds;
                count++;
            }
        }

        return (teamIds, teamNames, tokenIndexes);
    }

    function initializeLeague() external payable {
        require(
            leagues[currentLeagueId].state == LeagueState.Concluded || currentLeagueId == 0,
            "Previous league not concluded"
        );

        currentLeagueId++;
        League storage newLeague = leagues[currentLeagueId];
        newLeague.id = currentLeagueId;
        newLeague.state = LeagueState.Initiated;
        newLeague.prizePool = msg.value;
    }

    function getLeague(uint256 leagueId)
        external
        view
        returns (
            uint256 id,
            LeagueState state,
            uint256 prizePool,
            uint256[] memory enrolledTeams,
            uint256 totalBetsInLeague,
            bool[] memory eliminated
        )
    {
        League storage league = leagues[leagueId];
        bool[] memory eliminatedTeams = new bool[](league.enrolledTeams.length);
        for (uint256 i = 0; i < league.enrolledTeams.length; i++) {
            eliminatedTeams[i] = league.eliminatedTeams[league.enrolledTeams[i]];
        }
        return
            (league.id, league.state, league.prizePool, league.enrolledTeams, league.totalBetsInLeague, eliminatedTeams);
    }

    function getMatch(uint256 leagueId, uint256 matchId)
        external
        view
        returns (uint256 id, uint256 team1, uint256 team2, uint256 winner, GameType gameType)
    {
        Game storage game = leagues[leagueId].games[matchId];
        return (game.id, game.team1, game.team2, game.winner, game.gameType);
    }

    function enrollToLeague(uint256 teamId) external {
        require(leagues[currentLeagueId].state == LeagueState.Initiated, "Enrollment is closed");
        (,, address retrievedOwner) = getTeam(teamId);
        require(msg.sender == retrievedOwner, "Not team owner");
        leagues[currentLeagueId].enrolledTeams.push(teamId);
        leagues[currentLeagueId].teamsMap[teamId] = true;
    }

    function isTeamEnrolled(uint256 teamId, uint256 leagueId) external view returns (bool) {
        return leagues[leagueId].teamsMap[teamId];
    }

    // Function to end team enrollment and start the betting period
    function endEnrollmentAndStartBetting() external {
        uint256 leagueId = currentLeagueId;
        League storage league = leagues[leagueId];
        uint256 numTeams = league.enrolledTeams.length;
        require(numTeams >= 2 && (numTeams & (numTeams % 2)) == 0, "Number of teams must be a power of 2.");
        require(league.state == LeagueState.Initiated, "League is not in enrollment state");
        league.state = LeagueState.BetsOpen;
    }

    function placeBet(uint256 leagueId, uint256 teamId) external payable {
        League storage league = leagues[leagueId];
        require(league.state == LeagueState.BetsOpen, "Betting is not active");
        require(msg.value > 0, "Bet amount must be greater than 0");
        require(league.teamsMap[teamId], "Team does not exist in this league");

        // If it's the first bet on this team by the user for this league, add to the list
        if (league.userBetsOnTeam[msg.sender][teamId] == 0) {
            league.userBetTeams[msg.sender].push(teamId);
        }

        // Update the bet amount
        league.userBetsOnTeam[msg.sender][teamId] += msg.value;

        // Update the total bets for the team and the league
        league.totalBetsOnTeam[teamId] += msg.value;
        league.totalBetsInLeague += msg.value;
    }

    // Function to get all bet details for a user in a specific league
    function getUserBets(uint256 leagueId, address user)
        public
        view
        returns (uint256[] memory teamIds, uint256[] memory betAmounts)
    {
        League storage league = leagues[leagueId];
        uint256[] storage betTeams = league.userBetTeams[user];
        uint256 numBets = betTeams.length;
        require(league.userBetTeams[msg.sender].length > 0, "No bets placed");

        teamIds = new uint256[](numBets);
        betAmounts = new uint256[](numBets);

        for (uint256 i = 0; i < numBets; i++) {
            uint256 teamId = betTeams[i];
            if (league.userBetsOnTeam[user][teamId] > 0) {
                teamIds[i] = teamId;
                betAmounts[i] = league.userBetsOnTeam[user][teamId];
            } else {
                // This else block should theoretically never be hit since teamIds should only be added if a bet is made.
                revert("Bet data corrupted or uninitialized bet found.");
            }
        }

        return (teamIds, betAmounts);
    }

    // Function to end betting and start the game run period
    function endBettingAndStartGame() external {
        uint256 leagueId = currentLeagueId;
        League storage league = leagues[leagueId];
        require(league.state == LeagueState.BetsOpen, "League is not in betting state");
        league.state = LeagueState.Running;
    }

    function setupMatches(uint256 seed) public {
        uint256 leagueId = currentLeagueId;
        League storage league = leagues[leagueId];
        require(
            league.state == LeagueState.BetsOpen || league.state == LeagueState.Running,
            "Invalid league state for setting up matches"
        );
        uint256 numTeams = league.enrolledTeams.length;
        require(numTeams >= 2, "Not enough teams to set up matches");

        uint256[] memory gameIds = new uint256[](numTeams / 2);
        uint256[] memory team1s = new uint256[](numTeams / 2);
        uint256[] memory team2s = new uint256[](numTeams / 2);
        GameType[] memory gameTypes = new GameType[](numTeams / 2);

        // Shuffle teams randomly
        for (uint256 i = 0; i < numTeams; i++) {
            uint256 n = i + rng.getRandomNumber(seed + i) % (numTeams - i);
            uint256 temp = league.enrolledTeams[n];
            league.enrolledTeams[n] = league.enrolledTeams[i];
            league.enrolledTeams[i] = temp;
        }

        // Pair teams to compete
        for (uint256 i = 0; i < numTeams / 2; i++) {
            uint256 team1 = league.enrolledTeams[2 * i];
            uint256 team2 = league.enrolledTeams[2 * i + 1];
            GameType gameType = (rng.getRandomNumber(seed + i) % 2 == 0) ? GameType.Racing : GameType.Battle;
            uint256 gameId = league.gameIdCounter.current();

            league.games[gameId] = Game(gameId, team1, team2, type(uint256).max, 0, 0, gameType);
            league.gameIdCounter.increment();

            // Store the game setup details in the arrays
            gameIds[i] = gameId;
            team1s[i] = team1;
            team2s[i] = team2;
            gameTypes[i] = gameType;
        }

        // Emit the event with all games details after setup
        emit GamesSetup(leagueId, gameIds, team1s, team2s, gameTypes);
    }

    function determineMatchOutcome(uint256 leagueId, uint256 gameId) public returns (uint256 winner, uint256 loser) {
        League storage league = leagues[leagueId];
        Game storage game = league.games[gameId];
        game.team1Score = calculateTeamScore(game.team1, game.gameType);
        game.team2Score = calculateTeamScore(game.team2, game.gameType);
        uint256 seed = uint256(keccak256(abi.encodePacked(leagueId, gameId)));

        uint256 randomness = rng.getRandomNumber(seed);
        uint256 upsetChance = randomness % 100;

        // Add random factor to the underdog's score
        if (game.team1Score < game.team2Score && upsetChance < 20) {
            // 20% upset chance
            game.team1Score += randomness % 20; // Random boost between 0 and 19
        } else if (game.team2Score < game.team1Score && upsetChance < 20) {
            game.team2Score += randomness % 20;
        }

        if (game.team1Score > game.team2Score) {
            game.winner = game.team1;
        } else if (game.team2Score > game.team1Score) {
            game.winner = game.team2;
        } else {
            // In case of a tie, determine the winner randomly
            uint256 tieBreaker = randomness % 2;
            game.winner = tieBreaker == 0 ? game.team1 : game.team2;
        }
        league.teamTotalScore[game.team1] += game.team1Score;
        league.teamTotalScore[game.team2] += game.team2Score;
        league.teamGamesPlayed[game.team1]++;
        league.teamGamesPlayed[game.team2]++;
        return (winner, loser);
    }

    function calculateTeamScore(uint256 teamId, GameType gameType) internal view returns (uint256) {
        Team storage team = teams[teamId];
        uint256 score = 0;
        for (uint256 i = 0; i < team.nftIds.length; i++) {
            uint256 attributes = cosmoShips.attributes(team.nftIds[i]);
            (, uint256 attack, uint256 speed, uint256 shield) = cosmoShips.decodeAttributes(attributes);
            if (gameType == GameType.Battle) {
                score += attack + shield;
            } else if (gameType == GameType.Racing) {
                score += speed;
            }
        }
        return score;
    }

    function runGameLeague() external {
        uint256 leagueId = currentLeagueId;
        League storage league = leagues[leagueId];
        require(league.state == LeagueState.Running, "League is not in running state");

        while (league.enrolledTeams.length > 1) {
            // Setup matches for this round
            setupMatches(league.gameIdCounter.current());

            // Run the games for this round
            for (uint256 gameId = 0; gameId < league.gameIdCounter.current(); gameId++) {
                determineMatchOutcome(leagueId, gameId);
            }

            // Eliminate all losers
            eliminateLosersFromGames(leagueId);

            // Reset counter for the next round
            league.gameIdCounter.reset();
        }

        league.state = LeagueState.Concluded;
    }

    function eliminateLosersFromGames(uint256 leagueId) public {
        League storage league = leagues[leagueId];
        uint256[] memory winners = new uint256[](league.gameIdCounter.current());
        uint256 winnerCount = 0;

        // Collect winners from games
        for (uint256 gameId = 0; gameId < league.gameIdCounter.current(); gameId++) {
            Game storage game = league.games[gameId];
            winners[winnerCount] = game.winner;
            winnerCount++;
        }

        // Mark losers as eliminated
        uint256[] memory remainingTeams = new uint256[](league.enrolledTeams.length);
        uint256 remainingTeamCount = 0;
        for (uint256 i = 0; i < league.enrolledTeams.length; i++) {
            uint256 teamId = league.enrolledTeams[i];
            bool isWinner = false;

            for (uint256 j = 0; j < winnerCount; j++) {
                if (winners[j] == teamId) {
                    isWinner = true;
                    break;
                }
            }

            if (isWinner) {
                remainingTeams[remainingTeamCount] = teamId;
                remainingTeamCount++;
            } else {
                eliminateTeam(leagueId, teamId);
            }
        }

        // Update enrolledTeams with remaining teams
        league.enrolledTeams = new uint256[](remainingTeamCount);
        for (uint256 i = 0; i < remainingTeamCount; i++) {
            league.enrolledTeams[i] = remainingTeams[i];
        }
    }

    function eliminateTeam(uint256 leagueId, uint256 teamId) internal {
        League storage league = leagues[leagueId];

        // Return NFTs to the team owner
        for (uint256 j = 0; j < teams[teamId].nftIds.length; j++) {
            cosmoShips.transferFrom(address(this), teams[teamId].owner, teams[teamId].nftIds[j]);
        }

        // Clean up other data structures
        delete league.teamsMap[teamId];
        delete league.teamTotalScore[teamId];
        delete league.teamGamesPlayed[teamId];
    }

    function emitLeaderboard(uint256 leagueId) internal {
        (
            uint256[] memory teamIds,
            string[] memory teamNames,
            uint256[] memory totalScores,
            uint256[] memory gamesPlayed,
            bool[] memory eliminated
        ) = getLeaderboard(leagueId);

        emit Leaderboard(leagueId, teamIds, teamNames, totalScores, gamesPlayed, eliminated);
    }

    function getLeaderboard(uint256 leagueId)
        public
        view
        returns (
            uint256[] memory teamIds,
            string[] memory teamNames,
            uint256[] memory totalScores,
            uint256[] memory gamesPlayed,
            bool[] memory eliminated
        )
    {
        League storage league = leagues[leagueId];
        uint256 teamCount = league.enrolledTeams.length;

        teamIds = new uint256[](teamCount);
        teamNames = new string[](teamCount);
        totalScores = new uint256[](teamCount);
        gamesPlayed = new uint256[](teamCount);
        eliminated = new bool[](teamCount);

        for (uint256 i = 0; i < teamCount; i++) {
            uint256 teamId = league.enrolledTeams[i];
            teamIds[i] = teamId;
            teamNames[i] = teams[teamId].name;
            totalScores[i] = league.teamTotalScore[teamId];
            gamesPlayed[i] = league.teamGamesPlayed[teamId];
            eliminated[i] = league.eliminatedTeams[league.enrolledTeams[i]];
        }

        return (teamIds, teamNames, totalScores, gamesPlayed, eliminated);
    }

    function eliminateLowestScoringTeams(uint256 leagueId) internal {
        League storage league = leagues[leagueId];
        uint256 numTeams = league.enrolledTeams.length;
        require(numTeams > 1, "Cannot eliminate when only one team remains");

        uint256 lowestAverageScore = type(uint256).max;
        uint256 lowestScoringTeamIndex = 0;

        for (uint256 i = 0; i < numTeams; i++) {
            uint256 teamId = league.enrolledTeams[i];
            uint256 gamesPlayed = league.teamGamesPlayed[teamId];
            if (gamesPlayed == 0) continue; // Skip teams that haven't played any games

            uint256 averageScore = league.teamTotalScore[teamId] / gamesPlayed;
            if (averageScore < lowestAverageScore) {
                lowestAverageScore = averageScore;
                lowestScoringTeamIndex = i;
            }
        }

        // Eliminate the lowest scoring team
        uint256 teamToEliminate = league.enrolledTeams[lowestScoringTeamIndex];

        // Return NFTs to the team owner
        for (uint256 j = 0; j < teams[teamToEliminate].nftIds.length; j++) {
            cosmoShips.transferFrom(address(this), teams[teamToEliminate].owner, teams[teamToEliminate].nftIds[j]);
        }

        // Remove the team from the league
        league.enrolledTeams[lowestScoringTeamIndex] = league.enrolledTeams[numTeams - 1];
        league.enrolledTeams.pop();
        delete league.teamsMap[teamToEliminate];
        delete league.teamTotalScore[teamToEliminate];
        delete league.teamGamesPlayed[teamToEliminate];
    }

    function quickSortTeams(uint256[] storage arr, int256 left, int256 right, uint256 leagueId) internal {
        League storage league = leagues[leagueId];
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        uint256 pivot = league.totalBetsOnTeam[arr[uint256(left + (right - left) / 2)]];
        while (i <= j) {
            while (league.totalBetsOnTeam[arr[uint256(i)]] < pivot) i++;
            while (pivot < league.totalBetsOnTeam[arr[uint256(j)]]) j--;
            if (i <= j) {
                (arr[uint256(i)], arr[uint256(j)]) = (arr[uint256(j)], arr[uint256(i)]);
                i++;
                j--;
            }
        }
        if (left < j) quickSortTeams(arr, left, j, leagueId);
        if (i < right) quickSortTeams(arr, i, right, leagueId);
    }

    function getEnrolledTeams() public view returns (uint256[] memory, string[] memory, address[] memory) {
        uint256[] memory enrolledTeamIds = leagues[currentLeagueId].enrolledTeams;
        uint256 numTeams = enrolledTeamIds.length;
        string[] memory teamNames = new string[](numTeams);
        address[] memory teamOwners = new address[](numTeams);

        for (uint256 i = 0; i < numTeams; i++) {
            Team storage team = teams[enrolledTeamIds[i]];
            teamNames[i] = team.name;
            teamOwners[i] = team.owner;
        }

        return (enrolledTeamIds, teamNames, teamOwners);
    }
}
