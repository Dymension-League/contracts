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

    enum LeagueState {
        Idle,
        Initiated,
        EnrollmentClosed,
        BetsOpen,
        Running,
        Distribution,
        Concluded
    }
    enum GameType {
        Racing,
        Battle
    }

    struct League {
        uint256 id;
        uint256 prizePool;
        uint256 totalBetsInLeague;
        LeagueState state;
        uint256[] enrolledTeams;
        uint256[] allTeams;
        mapping(uint256 => bool) teamsMap;
        mapping(uint256 => Game) games;
        mapping(uint256 => uint256) totalBetsOnTeam;
        mapping(address => mapping(uint256 => uint256)) userBetsOnTeam;
        mapping(address => uint256[]) userBetTeams;
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

    uint256 public currentLeagueId;
    mapping(uint256 => League) public leagues;
    mapping(uint256 => Team) public teams;
    mapping(address => uint256) public stakes;
    mapping(uint256 => mapping(address => uint256)) public pendingRewards;

    CosmoShips public cosmoShips;
    IRandomNumberGenerator public rng;

    event LeagueCreated(uint256 indexed leagueId, uint256 prizePool);
    event TeamCreated(uint256 indexed teamId, address indexed owner, string name);
    event TeamsEnrolled(uint256 indexed leagueId, uint256[] teamIds);
    event BetPlaced(uint256 indexed leagueId, uint256 indexed teamId, address indexed bettor, uint256 amount);
    event MatchesResolved(uint256 indexed leagueId, uint256[] gameIds, uint256[] winners, uint256[] losers);
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
    event RewardsDistributed(uint256 indexed leagueId, address[] winners, uint256[] amounts);
    event RewardClaimed(uint256 indexed leagueId, address indexed winner, uint256 amount);

    error EnrollmentClosed();
    error NotTeamOwner();
    error InvalidLeagueState();
    error InvalidTeamNumber();
    error ArrayLengthMismatch();
    error NoRewardToClaim();
    error InsufficientBetAmount();
    error TeamNotEnrolled();
    error UnauthorizedAccess();

    constructor(address _nftAddress, address _rng) {
        cosmoShips = CosmoShips(_nftAddress);
        rng = IRandomNumberGenerator(_rng);
    }

    function createTeam(uint256[] calldata nftIds, string calldata teamName) external returns (uint256) {
        if (nftIds.length != 3) revert ArrayLengthMismatch();
        uint256 newTeamId = teamsCounter.current();
        Team storage newTeam = teams[newTeamId];
        for (uint256 i = 0; i < nftIds.length; i++) {
            if (cosmoShips.ownerOf(nftIds[i]) != msg.sender) revert NotTeamOwner();
            cosmoShips.transferFrom(msg.sender, address(this), nftIds[i]);
            newTeam.nftIds.push(nftIds[i]);
        }
        newTeam.owner = msg.sender;
        newTeam.name = teamName;
        teamsCounter.increment();
        emit TeamCreated(newTeamId, msg.sender, teamName);
        return newTeamId;
    }

    function initializeLeague() external payable {
        if (leagues[currentLeagueId].state != LeagueState.Concluded && currentLeagueId != 0) {
            revert InvalidLeagueState();
        }
        currentLeagueId++;
        League storage newLeague = leagues[currentLeagueId];
        newLeague.id = currentLeagueId;
        newLeague.state = LeagueState.Initiated;
        newLeague.prizePool = msg.value;
        emit LeagueCreated(currentLeagueId, msg.value);
    }

    function batchEnrollToLeague(uint256[] calldata teamIds) external {
        if (leagues[currentLeagueId].state != LeagueState.Initiated) revert EnrollmentClosed();
        League storage league = leagues[currentLeagueId];
        for (uint256 i = 0; i < teamIds.length; i++) {
            uint256 teamId = teamIds[i];
            if (teams[teamId].owner != msg.sender) revert NotTeamOwner();
            league.enrolledTeams.push(teamId);
            league.allTeams.push(teamId);
            league.teamsMap[teamId] = true;
        }
        emit TeamsEnrolled(currentLeagueId, teamIds);
    }

    function endEnrollmentAndStartBetting() external {
        League storage league = leagues[currentLeagueId];
        uint256 numTeams = league.enrolledTeams.length;
        if (numTeams < 2 || (numTeams & ((numTeams - 1) % 2)) != 0) revert InvalidTeamNumber();
        if (league.state != LeagueState.Initiated) revert InvalidLeagueState();
        league.state = LeagueState.BetsOpen;
    }

    function placeBet(uint256 leagueId, uint256 teamId) external payable {
        League storage league = leagues[leagueId];
        if (league.state != LeagueState.BetsOpen) revert InvalidLeagueState();
        if (msg.value == 0) revert InsufficientBetAmount();
        if (!league.teamsMap[teamId]) revert TeamNotEnrolled();

        if (league.userBetsOnTeam[msg.sender][teamId] == 0) {
            league.userBetTeams[msg.sender].push(teamId);
        }

        league.userBetsOnTeam[msg.sender][teamId] += msg.value;
        league.totalBetsOnTeam[teamId] += msg.value;
        league.totalBetsInLeague += msg.value;

        emit BetPlaced(leagueId, teamId, msg.sender, msg.value);
    }

    function endBettingAndStartGame() external {
        League storage league = leagues[currentLeagueId];
        if (league.state != LeagueState.BetsOpen) revert InvalidLeagueState();
        league.state = LeagueState.Running;
    }

    function batchSetupMatches(
        uint256 leagueId,
        uint256[] memory team1s,
        uint256[] memory team2s,
        GameType[] memory gameTypes
    ) public {
        League storage league = leagues[leagueId];
        if (league.state != LeagueState.BetsOpen && league.state != LeagueState.Running) revert InvalidLeagueState();
        if (team1s.length != team2s.length || team2s.length != gameTypes.length) revert ArrayLengthMismatch();

        uint256[] memory gameIds = new uint256[](team1s.length);

        for (uint256 i = 0; i < team1s.length; i++) {
            uint256 gameId = league.gameIdCounter.current();
            league.games[gameId] = Game(gameId, team1s[i], team2s[i], type(uint256).max, 0, 0, gameTypes[i]);
            league.gameIdCounter.increment();
            gameIds[i] = gameId;
        }

        emit GamesSetup(leagueId, gameIds, team1s, team2s, gameTypes);
    }

    function batchResolveMatches(uint256 leagueId, uint256[] memory gameIds) public {
        League storage league = leagues[leagueId];
        if (league.state != LeagueState.Running) revert InvalidLeagueState();

        uint256[] memory winners = new uint256[](gameIds.length);
        uint256[] memory losers = new uint256[](gameIds.length);

        for (uint256 i = 0; i < gameIds.length; i++) {
            (winners[i], losers[i]) = determineMatchOutcome(leagueId, gameIds[i]);
        }

        emit MatchesResolved(leagueId, gameIds, winners, losers);
    }

    function determineMatchOutcome(uint256 leagueId, uint256 gameId) public returns (uint256 winner, uint256 loser) {
        League storage league = leagues[leagueId];
        Game storage game = league.games[gameId];
        game.team1Score = calculateTeamScore(game.team1, game.gameType);
        game.team2Score = calculateTeamScore(game.team2, game.gameType);
        uint256 seed = uint256(keccak256(abi.encodePacked(leagueId, gameId)));

        uint256 randomness = rng.getRandomNumber(seed);
        uint256 upsetChance = randomness % 100;

        if (game.team1Score < game.team2Score && upsetChance < 20) {
            game.team1Score += randomness % 20;
        } else if (game.team2Score < game.team1Score && upsetChance < 20) {
            game.team2Score += randomness % 20;
        }

        if (game.team1Score > game.team2Score) {
            game.winner = game.team1;
            loser = game.team2;
        } else if (game.team2Score > game.team1Score) {
            game.winner = game.team2;
            loser = game.team1;
        } else {
            uint256 tieBreaker = randomness % 2;
            game.winner = tieBreaker == 0 ? game.team1 : game.team2;
            loser = tieBreaker == 0 ? game.team2 : game.team1;
        }
        league.teamTotalScore[game.team1] += game.team1Score;
        league.teamTotalScore[game.team2] += game.team2Score;
        league.teamGamesPlayed[game.team1]++;
        league.teamGamesPlayed[game.team2]++;
        return (game.winner, loser);
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
        uint256 teamCount = league.allTeams.length;

        teamIds = new uint256[](teamCount);
        teamNames = new string[](teamCount);
        totalScores = new uint256[](teamCount);
        gamesPlayed = new uint256[](teamCount);
        eliminated = new bool[](teamCount);

        for (uint256 i = 0; i < teamCount; i++) {
            uint256 teamId = league.allTeams[i];
            teamIds[i] = teamId;
            teamNames[i] = teams[teamId].name;
            totalScores[i] = league.teamTotalScore[teamId];
            gamesPlayed[i] = league.teamGamesPlayed[teamId];
            eliminated[i] = league.eliminatedTeams[teamId];
        }

        return (teamIds, teamNames, totalScores, gamesPlayed, eliminated);
    }

    function calculateTeamScore(uint256 teamId, GameType gameType) internal view returns (uint256) {
        Team storage team = teams[teamId];
        uint256 score = 0;
        uint256[] memory nftIds = team.nftIds;
        uint256 nftCount = nftIds.length;

        for (uint256 i = 0; i < nftCount; i++) {
            uint256 attributes = cosmoShips.attributes(nftIds[i]);
            (, uint256 attack, uint256 speed, uint256 shield) = cosmoShips.decodeAttributes(attributes);
            if (gameType == GameType.Battle) {
                score += attack + shield;
            } else if (gameType == GameType.Racing) {
                score += speed;
            }
        }
        return score;
    }

    function updateLeaderboard(
        uint256 leagueId,
        uint256[] calldata teamIds,
        uint256[] calldata totalScores,
        uint256[] calldata gamesPlayed,
        bool[] calldata eliminated
    ) external {
        if (
            teamIds.length != totalScores.length || totalScores.length != gamesPlayed.length
                || gamesPlayed.length != eliminated.length
        ) {
            revert ArrayLengthMismatch();
        }

        League storage league = leagues[leagueId];
        for (uint256 i = 0; i < teamIds.length; i++) {
            league.teamTotalScore[teamIds[i]] = totalScores[i];
            league.teamGamesPlayed[teamIds[i]] = gamesPlayed[i];
            league.eliminatedTeams[teamIds[i]] = eliminated[i];
        }

        emit Leaderboard(leagueId, teamIds, getTeamNames(teamIds), totalScores, gamesPlayed, eliminated);
    }

    function getTeam(uint256 teamId) public view returns (string memory, uint256[] memory, address) {
        Team storage team = teams[teamId];
        return (team.name, team.nftIds, team.owner);
    }

    function isTeamEnrolled(uint256 teamId, uint256 leagueId) external view returns (bool) {
        return leagues[leagueId].teamsMap[teamId];
    }

    function getTeamNames(uint256[] memory teamIds) internal view returns (string[] memory) {
        string[] memory teamNames = new string[](teamIds.length);
        for (uint256 i = 0; i < teamIds.length; i++) {
            teamNames[i] = teams[teamIds[i]].name;
        }
        return teamNames;
    }

    function distributeRewards(uint256 leagueId, address[] calldata winners, uint256[] calldata amounts) external {
        if (leagues[leagueId].state != LeagueState.Distribution) revert InvalidLeagueState();
        if (winners.length != amounts.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < winners.length; i++) {
            pendingRewards[leagueId][winners[i]] += amounts[i];
        }

        leagues[leagueId].state = LeagueState.Concluded;
        emit RewardsDistributed(leagueId, winners, amounts);
    }

    function claimReward(uint256 leagueId) external {
        uint256 reward = pendingRewards[leagueId][msg.sender];
        if (reward == 0) revert NoRewardToClaim();

        pendingRewards[leagueId][msg.sender] = 0;
        payable(msg.sender).transfer(reward);

        emit RewardClaimed(leagueId, msg.sender, reward);
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

    function getUserBets(uint256 leagueId, address user)
        public
        view
        returns (uint256[] memory teamIds, uint256[] memory betAmounts)
    {
        League storage league = leagues[leagueId];
        uint256[] storage betTeams = league.userBetTeams[user];
        uint256 numBets = betTeams.length;
        if (numBets == 0) revert("No bets placed");

        teamIds = new uint256[](numBets);
        betAmounts = new uint256[](numBets);

        for (uint256 i = 0; i < numBets; i++) {
            uint256 teamId = betTeams[i];
            uint256 betAmount = league.userBetsOnTeam[user][teamId];
            if (betAmount > 0) {
                teamIds[i] = teamId;
                betAmounts[i] = betAmount;
            } else {
                revert("Bet data corrupted");
            }
        }

        return (teamIds, betAmounts);
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

    function runGameLeague() external {
        uint256 leagueId = currentLeagueId;
        League storage league = leagues[leagueId];
        if (league.state != LeagueState.Running) revert InvalidLeagueState();

        while (league.enrolledTeams.length > 1) {
            // Setup matches for this round
            setupMatches(league.gameIdCounter.current());

            // Run the games for this round
            uint256 gameCount = league.gameIdCounter.current();
            uint256[] memory gameIds = new uint256[](gameCount);
            for (uint256 i = 0; i < gameCount; i++) {
                gameIds[i] = i;
            }
            batchResolveMatches(leagueId, gameIds);

            // Eliminate losers
            eliminateLosersFromGames(leagueId);

            // Reset counter for the next round
            league.gameIdCounter.reset();
        }

        league.state = LeagueState.Distribution;
    }

    function setupMatches(uint256 seed) public {
        uint256 leagueId = currentLeagueId;
        League storage league = leagues[leagueId];
        uint256 numTeams = league.enrolledTeams.length;
        if (numTeams < 2) revert("Not enough teams");

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
            team1s[i] = league.enrolledTeams[2 * i];
            team2s[i] = league.enrolledTeams[2 * i + 1];
            gameTypes[i] = GameType(rng.getRandomNumber(seed + i) % 2);
        }

        batchSetupMatches(leagueId, team1s, team2s, gameTypes);
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
        assembly {
            mstore(remainingTeams, remainingTeamCount)
        }
        league.enrolledTeams = remainingTeams;
    }

    function eliminateTeam(uint256 leagueId, uint256 teamId) internal {
        League storage league = leagues[leagueId];

        // Return NFTs to the team owner
        Team storage team = teams[teamId];
        for (uint256 j = 0; j < team.nftIds.length; j++) {
            cosmoShips.transferFrom(address(this), team.owner, team.nftIds[j]);
        }

        // Clean up other data structures
        delete league.teamsMap[teamId];
        league.eliminatedTeams[teamId] = true;
    }
}
