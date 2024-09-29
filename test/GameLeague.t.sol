// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/CosmoShips.sol";
import "../src/GameLeague.sol";
import "../src/IAttributeVerifier.sol";
import "./fixtures/mockVerifier.sol";
import "./fixtures/mockRandomGenerator.sol";

contract GameLeagueTest is Test {
    GameLeague gameLeague;
    CosmoShips cosmoShips;
    MockRandomNumberGenerator mockRNG;
    IAttributeVerifier verifier;
    address deployer;
    bytes32[] proof;
    uint256 constant mintPrice = 1;

    address alice = address(0x1);
    uint256[] aliceAttrs = new uint256[](3);

    address bob = address(0x2);
    uint256[] bobAttrs = new uint256[](3);

    address carol = address(0x3);
    uint256[] carolAttrs = new uint256[](3);

    address jane = address(0x4);
    uint256[] janeAttrs = new uint256[](3);

    address george = address(0x5);
    uint256[] georgeAttrs = new uint256[](3);

    address tony = address(0x6);
    uint256[] tonyAttrs = new uint256[](3);

    function setUp() public {
        deployer = address(this);
        verifier = new mockVerifier();
        cosmoShips = new CosmoShips("0x1", 0, mintPrice, address(this), address(verifier));
        mockRNG = new MockRandomNumberGenerator();
        gameLeague = new GameLeague(address(cosmoShips), address(mockRNG));

        // mock proof to pass signature requirement
        proof = new bytes32[](1);
        proof[0] = bytes32(0xabcdef1234560000000000000000000000000000000000000000000000000000);

        aliceAttrs[0] = 1096;
        aliceAttrs[1] = 9768;
        aliceAttrs[2] = 17000;

        carolAttrs[0] = 17442;
        carolAttrs[1] = 18532;
        carolAttrs[2] = 16936;

        bobAttrs[0] = 1096;
        bobAttrs[1] = 9768;
        bobAttrs[2] = 17000;

        janeAttrs[0] = 1096;
        janeAttrs[1] = 9768;
        janeAttrs[2] = 17000;

        georgeAttrs[0] = 1096;
        georgeAttrs[1] = 9768;
        georgeAttrs[2] = 17000;

        tonyAttrs[0] = 1096;
        tonyAttrs[1] = 9768;
        tonyAttrs[2] = 17000;
        assert(address(gameLeague) != address(0));
    }

    function setupTeam(address user, uint256[] memory attrs, string memory teamName) internal returns (uint256) {
        vm.deal(user, 3 * mintPrice + 100 ether);
        uint256[] memory ids = mintToken(user, attrs);
        vm.startPrank(user);
        cosmoShips.setApprovalForAll(address(gameLeague), true);
        uint256 teamId = gameLeague.createTeam(ids, teamName);
        vm.stopPrank();
        return teamId;
    }

    function setupTeamAndEnroll(address user, uint256[] memory attrs, string memory teamName)
        internal
        returns (uint256)
    {
        uint256 teamId = setupTeam(user, attrs, teamName);
        uint256[] memory teamIds = new uint256[](1);
        teamIds[0] = teamId;
        vm.prank(user);
        gameLeague.batchEnrollToLeague(teamIds);
        return teamId;
    }

    function mintToken(address recipient, uint256[] memory attributes) internal returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](attributes.length);
        for (uint256 i = 0; i < attributes.length; i++) {
            vm.startPrank(recipient);
            uint256 currentTokenId = cosmoShips.nextTokenIdToMint();
            cosmoShips.mint{value: mintPrice}(attributes[i], proof);
            vm.stopPrank();
            ids[i] = currentTokenId;
            assertEq(cosmoShips.ownerOf(currentTokenId), recipient, "NFT not minted to correct address");
        }
        return ids;
    }

    function testCreateTeam(string memory teamName, bool approveAll) public {
        address user = address(0x1);
        vm.deal(user, 10 ^ 18);

        vm.startPrank(user);
        // Mint some tokens
        cosmoShips.mint{value: mintPrice}(1096, proof);
        cosmoShips.mint{value: mintPrice}(1096, proof);
        cosmoShips.mint{value: mintPrice}(1096, proof);

        // Approve the GameLeague contract to take NFTs
        // Approval can be one by one or for all at once
        if (!approveAll) {
            cosmoShips.approve(address(gameLeague), 1);
            cosmoShips.approve(address(gameLeague), 2);
            cosmoShips.approve(address(gameLeague), 3);
        } else {
            cosmoShips.setApprovalForAll(address(gameLeague), true);
        }

        // Create team and stake NFTs
        uint256[] memory nftIds = new uint256[](3);
        nftIds[0] = 1;
        nftIds[1] = 2;
        nftIds[2] = 3;

        gameLeague.createTeam(nftIds, teamName);
        vm.stopPrank();

        // Check that the NFTs are transferred to the GameLeague contract
        assertEq(cosmoShips.ownerOf(1), address(gameLeague), "NFT 1 should be staked");
        assertEq(cosmoShips.ownerOf(2), address(gameLeague), "NFT 2 should be staked");
        assertEq(cosmoShips.ownerOf(3), address(gameLeague), "NFT 3 should be staked");
        // Check that team is created with correct values
        (string memory retrievedName, uint256[] memory retrievedNftIds, address retrievedOwner) = gameLeague.getTeam(0);
        assertEq(retrievedName, teamName, "Not correct teamName");
        assertEq(retrievedOwner, user, "Owner of the team does not match");
        assertEq(retrievedNftIds.length, 3, "Number of NFTs in the team should be 3");
        assertEq(retrievedNftIds[0], 1, "NFT ID at index 0 should be 1");
        assertEq(retrievedNftIds[1], 2, "NFT ID at index 1 should be 2");
        assertEq(retrievedNftIds[2], 3, "NFT ID at index 2 should be 3");
    }

    function testInitializeLeague(uint256 _prizePool) public {
        _prizePool = bound(_prizePool, 1 ether, 100000 ether);
        vm.deal(deployer, _prizePool * 2);

        // Initially, we should be able to start a league
        vm.prank(deployer);
        gameLeague.initializeLeague{value: _prizePool}();
        // Check if the league state is correct after initialization
        (, GameLeague.LeagueState state,,,,) = gameLeague.getLeague(gameLeague.currentLeagueId());
        assertEq(uint256(state), uint256(GameLeague.LeagueState.Initiated));

        // Expect revert on trying to initialize another league when one is active
        vm.expectRevert();
        gameLeague.initializeLeague{value: _prizePool}();
        vm.stopPrank();
    }

    function testEnrollToLeague() public {
        vm.deal(deployer, 2 ether);
        vm.prank(deployer);
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 teamId = setupTeamAndEnroll(bob, bobAttrs, "team-a");
        // Check if the team was enrolled
        assertTrue(gameLeague.isTeamEnrolled(teamId, gameLeague.currentLeagueId()));
    }

    function testBatchEnrollToLeague() public {
        vm.deal(deployer, 2 ether);
        vm.prank(deployer);
        gameLeague.initializeLeague{value: 1 ether}();

        uint256[] memory teamIds = new uint256[](3);
        // TODO: This is for a single user. We cant batch for multiple users.
        teamIds[0] = setupTeam(bob, bobAttrs, "team-a");
        teamIds[1] = setupTeam(bob, aliceAttrs, "team-b");
        teamIds[2] = setupTeam(bob, carolAttrs, "team-c");

        vm.prank(bob);
        gameLeague.batchEnrollToLeague(teamIds);

        for (uint256 i = 0; i < teamIds.length; i++) {
            assertTrue(gameLeague.isTeamEnrolled(teamIds[i], gameLeague.currentLeagueId()));
        }
    }

    function testEndEnrollmentAndStartBetting() public {
        // Setup: Assume leagueId of 1 and it is currently in the Enrollment state
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();
        // Setup teams
        setupTeamAndEnroll(alice, aliceAttrs, "Team-Alice");
        setupTeamAndEnroll(bob, bobAttrs, "Team-Bob");

        // Test transition to Betting state
        gameLeague.endEnrollmentAndStartBetting();

        // Check if the state has transitioned to Betting
        (, GameLeague.LeagueState state,,,,) = gameLeague.getLeague(leagueId);
        assert(state == GameLeague.LeagueState.BetsOpen);

        // Try to call the function when the league is not in Enrollment state
        vm.expectRevert();
        gameLeague.endEnrollmentAndStartBetting();
    }

    function testBetPlacing() public {
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();

        // TODO: This is for a single user. We cant batch for multiple users.
        uint256[] memory teamIds = new uint256[](4);
        teamIds[0] = setupTeam(bob, bobAttrs, "Team-Bob");
        teamIds[1] = setupTeam(bob, aliceAttrs, "Team-Alice");
        teamIds[2] = setupTeam(bob, carolAttrs, "Team-Carol");
        teamIds[3] = setupTeam(bob, janeAttrs, "Team-Jane");
        uint256 teamId = teamIds[0];

        vm.prank(bob);
        gameLeague.batchEnrollToLeague(teamIds);

        gameLeague.endEnrollmentAndStartBetting();

        // Alice places a bet
        uint256 betAmountAlice = 1 ether;
        vm.deal(alice, betAmountAlice);
        vm.startPrank(alice);
        gameLeague.placeBet{value: betAmountAlice}(gameLeague.currentLeagueId(), teamId);
        (uint256[] memory betTeamIdsAlice, uint256[] memory betAmountsAlice) = gameLeague.getUserBets(leagueId, alice);
        assertEq(betTeamIdsAlice[0], teamId, "Alice's Team ID should match");
        assertEq(betAmountsAlice[0], betAmountAlice, "Alice's bet amount should match");
        vm.stopPrank();

        // Bob places twice a bet
        uint256 betAmountBob = 2 ether;
        vm.deal(bob, betAmountBob);
        vm.startPrank(bob);
        gameLeague.placeBet{value: betAmountBob / 2}(leagueId, teamId);
        gameLeague.placeBet{value: betAmountBob / 2}(leagueId, teamId);
        (uint256[] memory betTeamIdsBob, uint256[] memory betAmountsBob) = gameLeague.getUserBets(leagueId, bob);
        assertEq(betTeamIdsBob[0], teamId, "Bob's Team ID should match");
        assertEq(betAmountsBob[0], betAmountBob, "Bob's bet amount should match");
        vm.stopPrank();

        // Check total bets in the league
        (,,,, uint256 totalLeagueBets,) = gameLeague.getLeague(leagueId);
        assertEq(
            totalLeagueBets,
            betAmountAlice + betAmountBob,
            "Total league bets should match the sum of Alice's and Bob's bets"
        );
    }

    function testEndBettingAndStartGame() public {
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();

        // Setup teams
        setupTeamAndEnroll(alice, aliceAttrs, "Team-Alice");
        setupTeamAndEnroll(bob, bobAttrs, "Team-Bob");

        // Test transition to Betting state
        gameLeague.endEnrollmentAndStartBetting();

        // Test transition to Running state
        gameLeague.endBettingAndStartGame();

        // Check if the state has transitioned to Running
        (, GameLeague.LeagueState state,,,,) = gameLeague.getLeague(leagueId);
        assert(state == GameLeague.LeagueState.Running);

        // Try to call the function when the league is not in Enrollment state
        vm.expectRevert();
        gameLeague.endBettingAndStartGame();
    }

    function testMatchSetupAndOutcome() public {
        // Initialize league
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();

        // Setup teams
        setupTeamAndEnroll(alice, aliceAttrs, "Team-Alice");
        setupTeamAndEnroll(bob, bobAttrs, "Team-Bob");
        setupTeamAndEnroll(carol, carolAttrs, "Team-Carol");
        setupTeamAndEnroll(jane, janeAttrs, "Team-Jane");

        gameLeague.endEnrollmentAndStartBetting();
        gameLeague.setupMatches(1);

        // Retrieve and assert the state of the league after setting up matches
        (, GameLeague.LeagueState state,, uint256[] memory enrolledTeams,,) = gameLeague.getLeague(leagueId);
        assertEq(uint256(state), uint256(GameLeague.LeagueState.BetsOpen));
        assertTrue(enrolledTeams.length >= 2);

        // Check the match outcome
        gameLeague.determineMatchOutcome(gameLeague.currentLeagueId(), 0);
        (, uint256 team1, uint256 team2, uint256 winner,) = gameLeague.getMatch(leagueId, 0);
        assertTrue(winner == team1 || winner == team2);
    }

    function testSetupMatches() public {
        // Setup league and enroll teams
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();

        uint256[] memory teamIds = new uint256[](4);
        teamIds[0] = setupTeam(bob, aliceAttrs, "Team-Alice");
        teamIds[1] = setupTeam(bob, bobAttrs, "Team-Bob");
        teamIds[2] = setupTeam(bob, carolAttrs, "Team-Carol");
        teamIds[3] = setupTeam(bob, janeAttrs, "Team-Jane");

        vm.prank(bob);
        gameLeague.batchEnrollToLeague(teamIds);

        gameLeague.endEnrollmentAndStartBetting();

        // Test individual match setup
        gameLeague.setupMatches(1);

        // Verify correct number of matches created
        (,,, uint256[] memory enrolledTeams,,) = gameLeague.getLeague(leagueId);
        uint256 expectedMatches = enrolledTeams.length / 2;

        for (uint256 i = 0; i < expectedMatches; i++) {
            (uint256 gameId, uint256 team1, uint256 team2, uint256 winner, GameLeague.GameType gameType) =
                gameLeague.getMatch(leagueId, i);
            assertEq(gameId, i, "Incorrect game ID");
            assertTrue(team1 != team2, "Teams should be different");
            assertEq(winner, type(uint256).max, "Winner should not be set yet");
            assertTrue(
                gameType == GameLeague.GameType.Racing || gameType == GameLeague.GameType.Battle, "Invalid game type"
            );
        }

        // Test batch match setup
        uint256[] memory team1s = new uint256[](2);
        uint256[] memory team2s = new uint256[](2);
        GameLeague.GameType[] memory gameTypes = new GameLeague.GameType[](2);

        team1s[0] = enrolledTeams[0];
        team2s[0] = enrolledTeams[1];
        gameTypes[0] = GameLeague.GameType.Racing;

        team1s[1] = enrolledTeams[2];
        team2s[1] = enrolledTeams[3];
        gameTypes[1] = GameLeague.GameType.Battle;

        gameLeague.batchSetupMatches(leagueId, team1s, team2s, gameTypes);

        // Verify batch setup
        for (uint256 i = 0; i < 2; i++) {
            (
                uint256 gameId,
                uint256 actualTeam1,
                uint256 actualTeam2,
                uint256 winner,
                GameLeague.GameType actualGameType
            ) = gameLeague.getMatch(leagueId, expectedMatches + i);
            assertEq(gameId, expectedMatches + i, "Incorrect game ID for batch setup");
            assertEq(actualTeam1, team1s[i], "Incorrect team1 for batch setup");
            assertEq(actualTeam2, team2s[i], "Incorrect team2 for batch setup");
            assertEq(winner, type(uint256).max, "Winner should not be set yet for batch setup");
            assertEq(uint256(actualGameType), uint256(gameTypes[i]), "Incorrect game type for batch setup");
        }
    }

    function testRunGameLeague() public {
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();
        setupTeamAndEnroll(alice, aliceAttrs, "Team-Alice");
        setupTeamAndEnroll(bob, bobAttrs, "Team-Bob");
        setupTeamAndEnroll(carol, carolAttrs, "Team-Carol");
        setupTeamAndEnroll(jane, janeAttrs, "Team-Jane");

        gameLeague.endEnrollmentAndStartBetting();
        gameLeague.endBettingAndStartGame();

        gameLeague.runGameLeague();
        address[] memory winners = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        gameLeague.distributeRewards(leagueId, winners, amounts);

        // Verify league state
        (, GameLeague.LeagueState state,,,,) = gameLeague.getLeague(leagueId);
        assertEq(uint256(state), uint256(GameLeague.LeagueState.Concluded), "League should be concluded");

        // Verify correct number of teams remaining
        (uint256[] memory remainingTeams,,) = gameLeague.getEnrolledTeams();
        assertEq(remainingTeams.length, 1, "Should have 1 team remaining");
    }

    function testClaimReward() public {
        gameLeague.initializeLeague{value: 10 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();
        uint256 teamId = setupTeamAndEnroll(bob, aliceAttrs, "Team-Alice");
        setupTeamAndEnroll(bob, bobAttrs, "Team-Bob");
        setupTeamAndEnroll(bob, carolAttrs, "Team-Carol");
        setupTeamAndEnroll(bob, tonyAttrs, "Team-Tony");

        gameLeague.endEnrollmentAndStartBetting();

        vm.deal(bob, 5 ether);
        vm.prank(bob);
        gameLeague.placeBet{value: 5 ether}(leagueId, teamId);

        gameLeague.endBettingAndStartGame();

        gameLeague.runGameLeague();

        // Assume Alice's team won
        address[] memory winners = new address[](1);
        winners[0] = bob;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 15 ether; // 10 ether prize pool + 5 ether bet
        gameLeague.distributeRewards(leagueId, winners, amounts);

        uint256 bobBalanceBefore = bob.balance;

        vm.prank(bob);
        gameLeague.claimReward(leagueId);

        uint256 bobBalanceAfter = bob.balance;
        assertEq(bobBalanceAfter - bobBalanceBefore, 15 ether, "Bob should have received 15 ether reward");
    }

    function testGetLeaderboard() public {
        // Setup
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();

        // Create and enroll teams
        setupTeamAndEnroll(alice, aliceAttrs, "Team-Alice");
        setupTeamAndEnroll(bob, bobAttrs, "Team-Bob");
        setupTeamAndEnroll(carol, carolAttrs, "Team-Carol");
        setupTeamAndEnroll(tony, tonyAttrs, "Team-Tony");

        gameLeague.endEnrollmentAndStartBetting();
        gameLeague.endBettingAndStartGame();

        // Simulate some games
        gameLeague.setupMatches(1);
        gameLeague.determineMatchOutcome(leagueId, 0);
        gameLeague.determineMatchOutcome(leagueId, 1);

        // Get the leaderboard
        (
            uint256[] memory teamIds,
            string[] memory teamNames,
            uint256[] memory totalScores,
            uint256[] memory gamesPlayed,
        ) = gameLeague.getLeaderboard(leagueId);

        // Assertions
        assertEq(teamIds.length, 4, "Should have 4 teams on the leaderboard");
        assertEq(teamNames.length, 4, "Should have 4 team names");
        assertEq(totalScores.length, 4, "Should have 4 total scores");
        assertEq(gamesPlayed.length, 4, "Should have 4 games played counts");

        // Check that all teams have played at least one game
        for (uint256 i = 0; i < gamesPlayed.length; i++) {
            console.log("Team", i, "Games Played:", gamesPlayed[i]);
            assertTrue(gamesPlayed[i] > 0, "Each team should have played at least one game");
        }

        // Check that team names are not empty
        for (uint256 i = 0; i < teamNames.length; i++) {
            assertTrue(bytes(teamNames[i]).length > 0, "Team names should not be empty");
        }
    }

    function testLeaderboardAfterInitialization() public {
        // Setup
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();

        // Get the leaderboard
        (
            uint256[] memory teamIds,
            string[] memory teamNames,
            uint256[] memory totalScores,
            uint256[] memory gamesPlayed,
            bool[] memory eliminated
        ) = gameLeague.getLeaderboard(leagueId);

        // Assertions
        assertEq(teamIds.length, 0, "Should have 0 teams on the leaderboard");
        assertEq(teamNames.length, 0, "Should have 0 team names");
        assertEq(totalScores.length, 0, "Should have 0 total scores");
        assertEq(gamesPlayed.length, 0, "Should have 0 games played counts");
        assertEq(eliminated.length, 0, "Should have 0 elimination statuses");
    }

    function testLeaderboardAfterEnrollingTeams() public {
        // Setup
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();

        // Create and enroll teams
        setupTeamAndEnroll(alice, aliceAttrs, "Team-Alice");
        setupTeamAndEnroll(bob, bobAttrs, "Team-Bob");
        setupTeamAndEnroll(carol, carolAttrs, "Team-Carol");
        setupTeamAndEnroll(tony, tonyAttrs, "Team-Tony");

        // Get the leaderboard
        (
            uint256[] memory teamIds,
            string[] memory teamNames,
            uint256[] memory totalScores,
            uint256[] memory gamesPlayed,
            bool[] memory eliminated
        ) = gameLeague.getLeaderboard(leagueId);

        // Assertions
        assertEq(teamIds.length, 4, "Should have 4 teams on the leaderboard");
        assertEq(teamNames.length, 4, "Should have 4 team names");
        assertEq(totalScores.length, 4, "Should have 4 total scores");
        assertEq(gamesPlayed.length, 4, "Should have 4 games played counts");
        assertEq(eliminated.length, 4, "Should have 4 elimination statuses");

        // Check that all teams have not played any games yet
        for (uint256 i = 0; i < gamesPlayed.length; i++) {
            assertEq(gamesPlayed[i], 0, "Each team should have played 0 games");
        }

        // Check that team names are not empty
        for (uint256 i = 0; i < teamNames.length; i++) {
            assertTrue(bytes(teamNames[i]).length > 0, "Team names should not be empty");
        }
    }

    function testLeaderboardAfterSomeGames() public {
        // Setup
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();

        // Create and enroll teams
        setupTeamAndEnroll(alice, aliceAttrs, "Team-Alice");
        setupTeamAndEnroll(bob, bobAttrs, "Team-Bob");
        setupTeamAndEnroll(carol, carolAttrs, "Team-Carol");
        setupTeamAndEnroll(tony, tonyAttrs, "Team-Tony");

        gameLeague.endEnrollmentAndStartBetting();
        gameLeague.endBettingAndStartGame();

        // Simulate some games
        gameLeague.setupMatches(1);
        gameLeague.determineMatchOutcome(leagueId, 0);
        gameLeague.determineMatchOutcome(leagueId, 1);

        // Get the leaderboard
        (
            uint256[] memory teamIds,
            string[] memory teamNames,
            uint256[] memory totalScores,
            uint256[] memory gamesPlayed,
            bool[] memory eliminated
        ) = gameLeague.getLeaderboard(leagueId);

        // Assertions
        assertEq(teamIds.length, 4, "Should have 4 teams on the leaderboard");
        assertEq(teamNames.length, 4, "Should have 4 team names");
        assertEq(totalScores.length, 4, "Should have 4 total scores");
        assertEq(gamesPlayed.length, 4, "Should have 4 games played counts");
        assertEq(eliminated.length, 4, "Should have 4 elimination statuses");

        // Check that all teams have played at least one game
        for (uint256 i = 0; i < gamesPlayed.length; i++) {
            assertTrue(gamesPlayed[i] > 0, "Each team should have played at least one game");
        }

        // Check that team names are not empty
        for (uint256 i = 0; i < teamNames.length; i++) {
            assertTrue(bytes(teamNames[i]).length > 0, "Team names should not be empty");
        }
    }

    function testLeaderboardAfterElimination() public {
        // Setup
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();

        // Create and enroll teams
        setupTeamAndEnroll(alice, aliceAttrs, "Team-Alice");
        setupTeamAndEnroll(bob, bobAttrs, "Team-Bob");
        setupTeamAndEnroll(carol, carolAttrs, "Team-Carol");
        setupTeamAndEnroll(tony, tonyAttrs, "Team-Tony");

        gameLeague.endEnrollmentAndStartBetting();
        gameLeague.endBettingAndStartGame();

        // Simulate some games
        gameLeague.setupMatches(1);
        gameLeague.determineMatchOutcome(leagueId, 0);
        gameLeague.determineMatchOutcome(leagueId, 1);

        // Eliminate losers
        gameLeague.eliminateLosersFromGames(leagueId);

        // Get the leaderboard
        (
            uint256[] memory teamIds,
            string[] memory teamNames,
            uint256[] memory totalScores,
            uint256[] memory gamesPlayed,
            bool[] memory eliminated
        ) = gameLeague.getLeaderboard(leagueId);

        // Assertions
        assertEq(teamIds.length, 4, "Should have 4 teams on the leaderboard");
        assertEq(teamNames.length, 4, "Should have 4 team names");
        assertEq(totalScores.length, 4, "Should have 4 total scores");
        assertEq(gamesPlayed.length, 4, "Should have 4 games played counts");
        assertEq(eliminated.length, 4, "Should have 4 elimination statuses");

        // Check that all teams have played at least one game
        for (uint256 i = 0; i < gamesPlayed.length; i++) {
            assertTrue(gamesPlayed[i] > 0, "Each team should have played at least one game");
        }

        // Check that team names are not empty
        for (uint256 i = 0; i < teamNames.length; i++) {
            assertTrue(bytes(teamNames[i]).length > 0, "Team names should not be empty");
        }

        // Check that at least one team is eliminated
        bool atleastOneEliminated = false;
        for (uint256 i = 0; i < eliminated.length; i++) {
            if (eliminated[i]) {
                atleastOneEliminated = true;
                break;
            }
        }
        assertTrue(atleastOneEliminated, "At least one team should be eliminated");
    }

    function testLeaderboardWithOneTeamRemaining() public {
        // Setup
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();

        // Create and enroll teams
        setupTeamAndEnroll(alice, aliceAttrs, "Team-Alice");
        setupTeamAndEnroll(bob, bobAttrs, "Team-Bob");
        setupTeamAndEnroll(carol, carolAttrs, "Team-Carol");
        setupTeamAndEnroll(tony, tonyAttrs, "Team-Tony");

        gameLeague.endEnrollmentAndStartBetting();
        gameLeague.endBettingAndStartGame();

        // Simulate the entire league
        gameLeague.runGameLeague();

        // Get the leaderboard
        (
            uint256[] memory teamIds,
            string[] memory teamNames,
            uint256[] memory totalScores,
            uint256[] memory gamesPlayed,
            bool[] memory eliminated
        ) = gameLeague.getLeaderboard(leagueId);

        // Assertions
        assertEq(teamIds.length, 4, "Should have 4 teams on the leaderboard");
        assertEq(teamNames.length, 4, "Should have 4 team names");
        assertEq(totalScores.length, 4, "Should have 4 total scores");
        assertEq(gamesPlayed.length, 4, "Should have 4 games played counts");
        assertEq(eliminated.length, 4, "Should have 4 elimination statuses");

        // Check that all teams have played at least one game
        for (uint256 i = 0; i < gamesPlayed.length; i++) {
            assertTrue(gamesPlayed[i] > 0, "Each team should have played at least one game");
        }

        // Check that team names are not empty
        for (uint256 i = 0; i < teamNames.length; i++) {
            assertTrue(bytes(teamNames[i]).length > 0, "Team names should not be empty");
        }

        // Check that all teams except one are eliminated
        uint256 eliminatedCount = 0;
        for (uint256 i = 0; i < eliminated.length; i++) {
            if (eliminated[i]) {
                eliminatedCount++;
            }
        }
        assertEq(eliminatedCount, 3, "Three teams should be eliminated");
    }
}
