// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import "openzeppelin-contracts/contracts/utils/Counters.sol";
import "./CosmoShips.sol";
import "./IRandomNumberGenerator.sol";
import "forge-std/console.sol";

contract GameLeague is ERC721Holder {
    using Counters for Counters.Counter;

    Counters.Counter private leagueIdCounter;

    Counters.Counter private teamsCounter;

    event Leaderboard(uint256 indexed leagueId, uint256[] leaderboard);
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
        LeagueState state;
        uint256 prizePool;
        uint256[] enrolledTeams;
        mapping(uint256 => bool) teamsMap;
        mapping(uint256 => Game) games;
        mapping(uint256 => uint256) totalBetsOnTeam;
        mapping(address => mapping(uint256 => uint256)) userBetsOnTeam;
        mapping(address => uint256[]) userBetTeams;
        mapping(address => uint256) claimableRewards;
        uint256 totalBetsInLeague;
        Counters.Counter gameIdCounter;
    }

    struct Game {
        uint256 id;
        uint256 team1;
        uint256 team2;
        uint256 winner;
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
        teamIds = new uint256[](totalTeams);
        teamNames = new string[](totalTeams);
        tokenIndexes = new uint256[][](totalTeams);
        uint256 count = 0;

        for (uint256 i = 0; i < totalTeams; i++) {
            if (teams[i].owner == owner) {
                teamIds[count] = i;
                teamNames[count] = teams[i].name;
                tokenIndexes[count] = teams[i].nftIds;
                count++;
            }
        }

        // Resize the arrays to include only the count of teams owned by the owner
        uint256[] memory filteredTeamIds = new uint256[](count);
        string[] memory filteredTeamNames = new string[](count);
        uint256[][] memory filteredTokenIndexes = new uint256[][](count);

        for (uint256 j = 0; j < count; j++) {
            filteredTeamIds[j] = teamIds[j];
            filteredTeamNames[j] = teamNames[j];
            filteredTokenIndexes[j] = tokenIndexes[j];
        }

        return (filteredTeamIds, filteredTeamNames, filteredTokenIndexes);
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
            uint256 totalBetsInLeague
        )
    {
        League storage league = leagues[leagueId];
        return (league.id, league.state, league.prizePool, league.enrolledTeams, league.totalBetsInLeague);
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

    function placeBet(uint256 leagueId, uint256 teamId, uint256 amount) external {
        League storage league = leagues[leagueId];
        require(league.state == LeagueState.BetsOpen, "Betting is not active");
        require(amount > 0, "Bet amount must be greater than 0");
        require(league.teamsMap[teamId], "Team does not exist in this league");

        // If it's the first bet on this team by the user for this league, add to the list
        if (league.userBetsOnTeam[msg.sender][teamId] == 0) {
            league.userBetTeams[msg.sender].push(teamId);
        }

        // Update the bet amount
        league.userBetsOnTeam[msg.sender][teamId] += amount;

        // Update the total bets for the team and the league
        league.totalBetsOnTeam[teamId] += amount;
        league.totalBetsInLeague += amount;
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

            league.games[gameId] = Game(gameId, team1, team2, type(uint256).max, gameType);
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

    function determineMatchOutcome(uint256 leagueId, uint256 gameId) public {
        League storage league = leagues[leagueId];
        Game storage game = league.games[gameId];
        uint256 team1Score = calculateTeamScore(game.team1, game.gameType);
        uint256 team2Score = calculateTeamScore(game.team2, game.gameType);
        uint256 seed = uint256(keccak256(abi.encodePacked(leagueId, gameId)));

        uint256 randomness = rng.getRandomNumber(seed);
        uint256 upsetChance = randomness % 100;

        // Add random factor to the underdog's score
        if (team1Score < team2Score && upsetChance < 20) {
            // 20% upset chance
            team1Score += randomness % 20; // Random boost between 0 and 19
        } else if (team2Score < team1Score && upsetChance < 20) {
            team2Score += randomness % 20;
        }

        if (team1Score > team2Score) {
            game.winner = game.team1;
        } else if (team2Score > team1Score) {
            game.winner = game.team2;
        } else {
            // In case of a tie, the team with the lower ID wins
            game.winner = game.team1 < game.team2 ? game.team1 : game.team2;
        }
    }

    function calculateTeamScore(uint256 teamId, GameType gameType) internal view returns (uint256) {
        Team storage team = teams[teamId];
        uint256 score = 0;
        require(team.nftIds.length == 3, "Each team must have exactly 3 NFTs.");
        for (uint256 i = 0; i < 3; i++) {
            uint256 attributes = cosmoShips.attributes(team.nftIds[i]);
            (, uint256 attack, uint256 speed, uint256 shield) = cosmoShips.decodeAttributes(attributes);
            if (gameType == GameType.Battle) {
                score += attack + shield;
            } else if (gameType == GameType.Racing) {
                score += speed;
            }
        }
        return score > 100 ? 100 : score;
    }

    function runGameLeague() external {
        uint256 leagueId = currentLeagueId;
        League storage league = leagues[leagueId];
        require(league.state == LeagueState.Running, "League is not in running state");

        // Run the game until only 4 teams remain
        while (league.enrolledTeams.length > 4) {
            // Setup matches for this turn
            setupMatches(league.gameIdCounter.current());

            // Run the games for this turn
            for (uint256 gameId = 0; gameId < league.gameIdCounter.current(); gameId++) {
                determineMatchOutcome(leagueId, gameId);
            }

            // Reset counter for the next round
            league.gameIdCounter.reset();

            // Emit leaderboard and eliminate lowest-scoring teams
            emitLeaderboard(leagueId);
            eliminateLowestScoringTeams(leagueId);
        }

        league.state = LeagueState.Concluded;
    }

    function emitLeaderboard(uint256 leagueId) internal {
        League storage league = leagues[leagueId];
        uint256 numTeams = league.enrolledTeams.length;

        // Sort teams based on their scores
        quickSortTeams(league.enrolledTeams, 0, int256(numTeams) - 1, leagueId);

        // Emit leaderboard
        uint256[] memory leaderboard = new uint256[](numTeams);
        for (uint256 i = 0; i < numTeams; i++) {
            leaderboard[i] = league.enrolledTeams[i];
        }
        emit Leaderboard(leagueId, leaderboard);
    }

    function eliminateLowestScoringTeams(uint256 leagueId) internal {
        League storage league = leagues[leagueId];
        uint256 numTeams = league.enrolledTeams.length;

        if (numTeams <= 4) {
            return; // Don't eliminate if we're down to the final 4 teams
        }

        uint256 teamsToKeep = numTeams / 2;
        if (teamsToKeep % 2 != 0) {
            teamsToKeep--; // Ensure we keep an even number of teams
        }

        // Create a new array to keep only the top teams
        uint256[] memory remainingTeams = new uint256[](teamsToKeep);
        for (uint256 i = 0; i < teamsToKeep; i++) {
            remainingTeams[i] = league.enrolledTeams[i];
        }

        // Remove eliminated teams
        for (uint256 i = teamsToKeep; i < numTeams; i++) {
            uint256 teamId = league.enrolledTeams[i];
            for (uint256 j = 0; j < teams[teamId].nftIds.length; j++) {
                cosmoShips.transferFrom(address(this), teams[teamId].owner, teams[teamId].nftIds[j]);
            }
            delete league.teamsMap[teamId];
        }

        league.enrolledTeams = remainingTeams;
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
