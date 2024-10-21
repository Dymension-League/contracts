// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../src/CosmoShips.sol";
import "../src/LeagueManager.sol";
import "../src/TournamentManager.sol";
import "../src/TeamManager.sol";
import "../src/IAttributeVerifier.sol";
import "./fixtures/mockVerifier.sol";
import "./fixtures/mockRandomGenerator.sol";

contract NewGameLeagueTest is Test {
    LeagueManager leagueManager;
    TournamentManager tournamentManager;
    TeamManager teamManager;
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
        teamManager = new TeamManager(address(cosmoShips));
        tournamentManager = new TournamentManager(address(mockRNG), address(teamManager));
        leagueManager = new LeagueManager(address(tournamentManager), address(teamManager));

        // Mock proof to pass signature requirement
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
    }

    // Helper function to set up a team
    function setupTeam(address user, uint256[] memory attrs, string memory teamName) internal returns (uint256) {
        vm.deal(user, 3 * mintPrice + 100 ether);
        uint256[] memory ids = mintToken(user, attrs);
        vm.startPrank(user);
        cosmoShips.setApprovalForAll(address(teamManager), true);
        uint256 teamId = teamManager.createTeam(ids, teamName);
        vm.stopPrank();
        return teamId;
    }

    // Helper function to set up and enroll a team
    function setupTeamAndEnroll(address user, uint256[] memory attrs, string memory teamName)
        internal
        returns (uint256)
    {
        uint256 teamId = setupTeam(user, attrs, teamName);
        uint256[] memory teamIds = new uint256[](1);
        teamIds[0] = teamId;
        vm.prank(user);
        leagueManager.batchEnrollToLeague(teamIds);
        return teamId;
    }

    // Helper function to mint tokens
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

    // Test case to create a team
    function testCreateTeam() public {
        address user = address(0x1);
        vm.deal(user, 10 ^ 18);

        uint256[] memory nftIds = mintToken(user, aliceAttrs);

        vm.startPrank(user);
        cosmoShips.setApprovalForAll(address(teamManager), true);
        uint256 teamId = teamManager.createTeam(nftIds, "Team Alice");

        // Check that the NFTs are transferred to TeamManager
        assertEq(cosmoShips.ownerOf(nftIds[0]), address(teamManager), "NFT 1 should be staked");
        assertEq(cosmoShips.ownerOf(nftIds[1]), address(teamManager), "NFT 2 should be staked");
        assertEq(cosmoShips.ownerOf(nftIds[2]), address(teamManager), "NFT 3 should be staked");

        // Check team information
        (uint256[] memory nftIdsStored,,,) = teamManager.getTeam(teamId);
        // assertEq(teamName, "Team Alice", "Team name mismatch");
        // assertEq(owner, user, "Owner mismatch");
        assertEq(nftIdsStored.length, 3, "Team should have 3 NFTs");
    }

    // Test to initialize a league
    function testInitializeLeague() public {
        uint256 prizePool = 10 ether;
        vm.deal(deployer, prizePool);

        vm.prank(deployer);
        leagueManager.initializeLeague{value: prizePool}();

        (, LeagueManager.LeagueState state,,) = leagueManager.getLeague(leagueManager.currentLeagueId());
        assertEq(uint256(state), uint256(LeagueManager.LeagueState.Initiated), "League state should be Initiated");

        // Try to start another league without finishing the previous one
        vm.expectRevert();
        leagueManager.initializeLeague{value: prizePool}();
    }

    // Test enrolling a team to the league
    function testEnrollTeamToLeague() public {
        uint256 prizePool = 1 ether;
        vm.deal(deployer, prizePool);

        vm.prank(deployer);
        leagueManager.initializeLeague{value: prizePool}();

        uint256 teamId = setupTeamAndEnroll(bob, bobAttrs, "Team Bob");

        // Check if team is enrolled
        assertTrue(leagueManager.isTeamEnrolled(teamId, leagueManager.currentLeagueId()));
    }

    // Test match setup and outcome resolution
    function testMatchSetupAndResolve() public {
        uint256 prizePool = 1 ether;
        vm.deal(deployer, prizePool);

        vm.prank(deployer);
        leagueManager.initializeLeague{value: prizePool}();

        // Set up teams
        setupTeamAndEnroll(alice, aliceAttrs, "Team Alice");
        setupTeamAndEnroll(bob, bobAttrs, "Team Bob");
        setupTeamAndEnroll(carol, carolAttrs, "Team Carol");

        // Start betting phase and then start the game
        leagueManager.closeEnrollment();
        leagueManager.openBets();

        // Run the game
        leagueManager.run();

        // Verify that the league has concluded
        (, LeagueManager.LeagueState state,,) = leagueManager.getLeague(leagueManager.currentLeagueId());
        assertEq(
            uint256(state), uint256(LeagueManager.LeagueState.Distribution), "League state should be in Distribution"
        );
    }

    // Test eliminating losing teams
    function testEliminateLosers() public {
        uint256 prizePool = 1 ether;
        vm.deal(deployer, prizePool);
        vm.prank(deployer);
        leagueManager.initializeLeague{value: prizePool}();

        setupTeamAndEnroll(alice, aliceAttrs, "Team Alice");
        setupTeamAndEnroll(bob, bobAttrs, "Team Bob");
        setupTeamAndEnroll(carol, carolAttrs, "Team Carol");

        leagueManager.closeEnrollment();
        leagueManager.openBets();

        // Run the league and check if elimination occurs
        leagueManager.run();

        // Get the remaining teams
        uint256[] memory remainingTeams = tournamentManager.getRemainingTeams(leagueManager.currentLeagueId());
        assertEq(remainingTeams.length, 1, "There should be only 1 team remaining");
    }

    // Test claiming rewards
    // function testClaimReward() public {
    //     uint256 prizePool = 10 ether;
    //     vm.deal(deployer, prizePool);
    //     vm.prank(deployer);
    //     leagueManager.initializeLeague{value: prizePool}();
    //
    //     uint256 teamId = setupTeamAndEnroll(bob, bobAttrs, "Team Bob");
    //     setupTeamAndEnroll(alice, aliceAttrs, "Team Alice");
    //
    //     leagueManager.closeEnrollment();
    // leagueManager.openBets();
    //
    //     vm.deal(bob, 5 ether);
    //     vm.prank(bob);
    //     leagueManager.placeBet{value: 5 ether}(leagueManager.currentLeagueId(), teamId);
    //
    //     leagueManager.endBettingAndStartGame();
    //     leagueManager.runGameLeague();
    //
    //     // Assume Bob's team won and distribute rewards
    //     address[] memory winners = new address[](1);
    //     winners[0] = bob;
    //     uint256[] memory amounts = new uint256[](1);
    //     amounts[0] = 15 ether; // 10 ether prize pool + 5 ether bet
    //     leagueManager.distributeRewards(leagueManager.currentLeagueId(), winners, amounts);
    //
    //     uint256 bobBalanceBefore = bob.balance;
    //
    //     vm.prank(bob);
    //     leagueManager.claimReward(leagueManager.currentLeagueId());
    //
    //     uint256 bobBalanceAfter = bob.balance;
    //     assertEq(bobBalanceAfter - bobBalanceBefore, 15 ether, "Bob should have received 15 ether reward");
    // }
}
