// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./TournamentManager.sol";

contract LeagueManager {
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
        LeagueState state;
        uint256[] enrolledTeams;
        mapping(uint256 => bool) teamsMap;
        address[] winners;
    }

    uint256 public currentLeagueId;
    mapping(uint256 => League) public leagues;

    TournamentManager public tournamentManager;
    TeamManager public teamManager;

    event LeagueCreated(uint256 indexed leagueId, uint256 prizePool);
    event EnrollmentClosed(uint256 indexed leagueId);
    event LeagueStateChanged(uint256 indexed leagueId, LeagueState newState);
    event TeamsEnrolled(uint256 indexed leagueId, uint256[] teamIds);

    error LeagueInitializeError();
    error EnrollmentClosedError();
    error LeagueOpenBetsError();
    error LeagueRunningError();
    error InvalidTeamsNumberError();

    constructor(address _tournamentManager, address _teamManagerAddress) {
        tournamentManager = TournamentManager(_tournamentManager); // Inject TournamentManager
        teamManager = TeamManager(_teamManagerAddress); // Set the address of the TeamManager contract
    }

    function initializeLeague() external payable {
        if (leagues[currentLeagueId].state != LeagueState.Concluded && currentLeagueId != 0) {
            revert LeagueInitializeError();
        }

        currentLeagueId++;
        League storage newLeague = leagues[currentLeagueId];
        newLeague.id = currentLeagueId;
        newLeague.state = LeagueState.Initiated;
        newLeague.prizePool = msg.value;
        emit LeagueCreated(currentLeagueId, msg.value);
    }

    function closeEnrollment() external {
        if (leagues[currentLeagueId].state != LeagueState.Initiated) revert EnrollmentClosedError();
        League storage league = leagues[currentLeagueId];
        league.state = LeagueState.EnrollmentClosed;
        emit EnrollmentClosed(currentLeagueId);
    }

    function openBets() external {
        League storage league = leagues[currentLeagueId];
        uint256 numTeams = league.enrolledTeams.length;
        if (numTeams < 2 || (numTeams & ((numTeams - 1) % 2)) != 0) revert InvalidTeamsNumberError();
        if (league.state != LeagueState.EnrollmentClosed) revert LeagueOpenBetsError();
        league.state = LeagueState.BetsOpen;
        emit LeagueStateChanged(currentLeagueId, LeagueState.BetsOpen);
    }

    function run() external {
        uint256 leagueId = currentLeagueId;
        League storage league = leagues[leagueId];
        if (league.state != LeagueState.BetsOpen) revert LeagueRunningError();

        while (league.enrolledTeams.length > 1) {
            // Setup matches for this round
            tournamentManager.setupMatches(leagueId, league.enrolledTeams);

            // Run the games for this round
            uint256[] memory gameIds = tournamentManager.getLeagueGameIds(leagueId);
            tournamentManager.batchResolveMatches(leagueId, gameIds);

            // Eliminate losing teams
            tournamentManager.eliminateLosersFromGames(leagueId);

            // Update the enrolled teams with the remaining teams
            league.enrolledTeams = tournamentManager.getRemainingTeams(leagueId);
        }

        league.state = LeagueState.Distribution;
    }

    /**
     * @dev Enroll multiple teams into the current league after validating ownership via TeamManager.
     * @param teamIds - The list of team IDs to enroll.
     */
    function batchEnrollToLeague(uint256[] calldata teamIds) external {
        // Ensure the league is in the Initiated state
        require(leagues[currentLeagueId].state == LeagueState.Initiated, "Enrollment is closed");

        League storage league = leagues[currentLeagueId];

        // Validate team ownership via TeamManager
        uint256[] memory validTeamIds = teamManager.validateTeamOwnership(msg.sender, teamIds);

        // Enroll valid teams into the league
        for (uint256 i = 0; i < validTeamIds.length; i++) {
            uint256 teamId = validTeamIds[i];
            league.enrolledTeams.push(teamId);
            league.teamsMap[teamId] = true;
        }

        // Emit event for team enrollment
        emit TeamsEnrolled(currentLeagueId, validTeamIds);
    }

    function getLeague(uint256 leagueId)
        external
        view
        returns (uint256 id, LeagueState state, uint256 prizePool, uint256[] memory enrolledTeams)
    {
        League storage league = leagues[leagueId];
        return (league.id, league.state, league.prizePool, league.enrolledTeams);
    }

    function isTeamEnrolled(uint256 teamId, uint256 leagueId) external view returns (bool) {
        return leagues[leagueId].teamsMap[teamId];
    }
}
