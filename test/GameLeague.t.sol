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

    function setUp() public {
        deployer = address(this);
        verifier = new mockVerifier();
        cosmoShips = new CosmoShips("0x1", 0, mintPrice, address(this), address(verifier));
        mockRNG = new MockRandomNumberGenerator();
        gameLeague = new GameLeague(address(cosmoShips), address(mockRNG));

        // mock proof to pass signature requirement
        proof = new bytes32[](1);
        proof[0] = bytes32(0xabcdef1234560000000000000000000000000000000000000000000000000000);
        assert(address(gameLeague) != address(0));
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
        _prizePool = bound(_prizePool, 10 ^ 18, 10 ^ 23);
        vm.deal(deployer, _prizePool + 10 ether);

        // Initially, we should be able to start a league
        vm.prank(deployer);
        gameLeague.initializeLeague{value: _prizePool}();
        (, GameLeague.LeagueState state,,,) = gameLeague.getLeague(1);
        assertEq(uint256(state), uint256(GameLeague.LeagueState.Initiated));

        // Expect revert on trying to initialize another league when one is active
        vm.expectRevert("Previous league not concluded");
        gameLeague.initializeLeague{value: _prizePool}();
        vm.stopPrank();
    }

    function tokenMint(address recipient, uint256[] memory tokenIds, uint256[] memory attributes) internal {
        require(tokenIds.length == attributes.length, "Token IDs and attributes length mismatch");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            vm.prank(recipient);
            cosmoShips.mint{value: mintPrice}(attributes[i], proof);
            assertEq(cosmoShips.attributes(tokenIds[i]), attributes[i], "Attributes not correctly set");
        }
    }

    function testEnrollToLeague() public {
        vm.deal(deployer, 2 ether);
        vm.prank(deployer);
        gameLeague.initializeLeague{value: 1 ether}();

        // mint some tokens to user so that it can create a team
        address user = address(0x1);
        vm.deal(user, (3 * mintPrice + 100) ^ 18);
        uint256[] memory ids = new uint256[](3);
        uint256[] memory attrs = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        attrs[0] = 1096;
        attrs[1] = 9768;
        attrs[2] = 17000;
        tokenMint(user, ids, attrs);

        vm.startPrank(user);
        cosmoShips.setApprovalForAll(address(gameLeague), true);
        // create a team
        uint256 teamId = gameLeague.createTeam(ids, "Team-A");
        // enroll team to league
        gameLeague.enrollToLeague(teamId);
        vm.stopPrank();

        // Check if the team was enrolled
        assertTrue(gameLeague.isTeamEnrolled(teamId, gameLeague.currentLeagueId()));
    }

    function testEndEnrollmentAndStartBetting() public {
        // Setup: Assume leagueId of 1 and it is currently in the Enrollment state
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();

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

        address alice = address(0x1);
        address bob = address(0x2);
        address carol = address(0x3);

        // mint some tokens to user so that it can create a team
        vm.deal(carol, 3 * mintPrice + 100 ** 18);
        uint256[] memory ids = new uint256[](3);
        uint256[] memory attrs = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        attrs[0] = 1096;
        attrs[1] = 9768;
        attrs[2] = 17000;
        tokenMint(carol, ids, attrs);

        vm.startPrank(carol);
        cosmoShips.setApprovalForAll(address(gameLeague), true);
        // create a team
        uint256 teamId = gameLeague.createTeam(ids, "Team-A");
        // enroll team to league
        gameLeague.enrollToLeague(teamId);
        vm.stopPrank();

        gameLeague.endEnrollmentAndStartBetting();

        // Alice places a bet
        uint256 betAmountAlice = 1 ether;
        vm.deal(alice, betAmountAlice);
        vm.startPrank(alice);
        gameLeague.placeBet(leagueId, teamId, betAmountAlice);
        (uint256[] memory betTeamIdsAlice, uint256[] memory betAmountsAlice) = gameLeague.getUserBets(leagueId, alice);
        assertEq(betTeamIdsAlice[0], teamId, "Alice's Team ID should match");
        assertEq(betAmountsAlice[0], betAmountAlice, "Alice's bet amount should match");
        vm.stopPrank();

        // Bob places twice a bet
        uint256 betAmountBob = 2 ether;
        vm.deal(bob, betAmountBob);
        vm.startPrank(bob);
        gameLeague.placeBet(leagueId, teamId, betAmountBob / 2);
        gameLeague.placeBet(leagueId, teamId, betAmountBob / 2);
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

    function testEndBettingAndStartGames() public {
        gameLeague.initializeLeague{value: 1 ether}();
        uint256 leagueId = gameLeague.currentLeagueId();

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
        uint256 seed = 1;

        // Setup teams
        // temp variables
        uint256[] memory ids = new uint256[](3);
        uint256[] memory attrs = new uint256[](3);
        // Team alice
        address alice = address(0x1);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        attrs[0] = 1096;
        attrs[1] = 9768;
        attrs[2] = 17000;
        setupTeamAndEnroll(alice, ids, attrs, "Team-Alice");
        // end Team alice

        // Team bob
        address bob = address(0x2);
        ids[0] = 4;
        ids[1] = 5;
        ids[2] = 6;
        attrs[0] = 17442;
        attrs[1] = 18532;
        attrs[2] = 16936;
        setupTeamAndEnroll(bob, ids, attrs, "Team-Bob");
        // end Team bob

        // // Start betting period and then games
        gameLeague.endEnrollmentAndStartBetting();
        gameLeague.setupMatches(seed);

        // Retrieve and assert the state of the league after setting up matches
        (, GameLeague.LeagueState state,, uint256[] memory enrolledTeams,) = gameLeague.getLeague(leagueId);
        assertEq(uint256(state), uint256(GameLeague.LeagueState.BetsOpen));
        assertTrue(enrolledTeams.length >= 2);

        // TODO: complete the test
    }

    function setupTeamAndEnroll(address user, uint256[] memory ids, uint256[] memory attrs, string memory teamName)
        public
        returns (uint256)
    {
        vm.deal(user, 3 * mintPrice + 100 ether); // Ensure user has enough ether
        tokenMint(user, ids, attrs); // Mint tokens for the user

        vm.startPrank(user);
        cosmoShips.setApprovalForAll(address(gameLeague), true); // Set approval for all tokens
        uint256 teamId = gameLeague.createTeam(ids, teamName); // Create the team
        gameLeague.enrollToLeague(teamId); // Enroll the team to the league
        vm.stopPrank();

        return teamId;
    }
}
