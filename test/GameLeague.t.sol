// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

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

    function setupTeamAndEnroll(address user, uint256[] memory attrs, string memory teamName)
        internal
        returns (uint256, uint256[] memory)
    {
        vm.deal(user, 3 * mintPrice + 100 ether); // Ensure user has enough ether
        uint256[] memory ids = mintToken(user, attrs); // Mint tokens for the user
        vm.startPrank(user);
        cosmoShips.setApprovalForAll(address(gameLeague), true); // Set approval for all tokens
        uint256 teamId = gameLeague.createTeam(ids, teamName); // Create the team
        gameLeague.enrollToLeague(teamId); // Enroll the team to the league
        vm.stopPrank();

        return (teamId, ids);
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
        (, GameLeague.LeagueState state,,,) = gameLeague.getLeague(gameLeague.currentLeagueId());
        assertEq(uint256(state), uint256(GameLeague.LeagueState.Initiated));

        // Expect revert on trying to initialize another league when one is active
        vm.expectRevert(bytes("Previous league not concluded"));
        gameLeague.initializeLeague{value: _prizePool}();
        vm.stopPrank();
    }

    function testEnrollToLeague() public {
        vm.deal(deployer, 2 ether);
        vm.prank(deployer);
        gameLeague.initializeLeague{value: 1 ether}();
        (uint256 teamId,) = setupTeamAndEnroll(bob, bobAttrs, "team-a");
        // Check if the team was enrolled
        assertTrue(gameLeague.isTeamEnrolled(teamId, gameLeague.currentLeagueId()));
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
        (, GameLeague.LeagueState state,,,) = gameLeague.getLeague(leagueId);
        assert(state == GameLeague.LeagueState.BetsOpen);

        // Try to call the function when the league is not in Enrollment state
        vm.expectRevert("League is not in enrollment state");
        gameLeague.endEnrollmentAndStartBetting();
    }

    function testBetPlacing() public {
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();
        // Team bob
        (uint256 teamId,) = setupTeamAndEnroll(bob, bobAttrs, "Team-Bob");
        // Team alice
        setupTeamAndEnroll(alice, aliceAttrs, "Team-Alice");
        // Team carol
        setupTeamAndEnroll(carol, carolAttrs, "Team-Carol");
        // Team jane
        setupTeamAndEnroll(jane, janeAttrs, "Team-Jane");

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
        (,,,, uint256 totalLeagueBets) = gameLeague.getLeague(leagueId);
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
        (, GameLeague.LeagueState state,,,) = gameLeague.getLeague(leagueId);
        assert(state == GameLeague.LeagueState.Running);

        // Try to call the function when the league is not in Enrollment state
        vm.expectRevert("League is not in betting state");
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
        (, GameLeague.LeagueState state,, uint256[] memory enrolledTeams,) = gameLeague.getLeague(leagueId);
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
        setupTeamAndEnroll(alice, aliceAttrs, "Team-Alice");
        setupTeamAndEnroll(bob, bobAttrs, "Team-Bob");
        setupTeamAndEnroll(carol, carolAttrs, "Team-Carol");
        setupTeamAndEnroll(jane, janeAttrs, "Team-Jane");

        gameLeague.endEnrollmentAndStartBetting();
        gameLeague.setupMatches(gameLeague.currentLeagueId());

        // Verify correct number of matches created
        (,,, uint256[] memory enrolledTeams,) = gameLeague.getLeague(leagueId);
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
    }

    function testRunGameLeague() public {
        gameLeague.initializeLeague{value: 1 ether}();
        gameLeague.currentLeagueId();
        setupTeamAndEnroll(alice, aliceAttrs, "Team-Alice");
        setupTeamAndEnroll(bob, bobAttrs, "Team-Bob");
        setupTeamAndEnroll(carol, carolAttrs, "Team-Carol");
        setupTeamAndEnroll(jane, janeAttrs, "Team-Jane");
        setupTeamAndEnroll(george, georgeAttrs, "Team-George");
        setupTeamAndEnroll(tony, tonyAttrs, "Team-Tony");

        gameLeague.endEnrollmentAndStartBetting();
        gameLeague.endBettingAndStartGame();
        gameLeague.runGameLeague();

        // Verify league state
        (, GameLeague.LeagueState state,,,) = gameLeague.getLeague(gameLeague.currentLeagueId());
        assertEq(uint256(state), uint256(GameLeague.LeagueState.Concluded), "League should be concluded");

        // Verify correct number of teams remaining
        (uint256[] memory remainingTeams,,) = gameLeague.getEnrolledTeams();
        assertEq(remainingTeams.length, 1, "Should have 1 team remaining");
    }
}
