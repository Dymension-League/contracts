// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./CosmoShips.sol";
import "openzeppelin-contracts/contracts/utils/Counters.sol";

contract TeamManager {
    using Counters for Counters.Counter;

    CosmoShips public cosmoShips; // Interface to interact with the CosmoShips contract
    Counters.Counter private teamsCounter; // Counter for team IDs

    struct Team {
        uint256[] nftIds;
        address owner;
        string name;
    }

    mapping(uint256 => Team) public teams; // Mapping from team ID to Team struct

    event TeamCreated(uint256 indexed teamId, address indexed owner, string name);

    error ShipsNeededError();

    constructor(address cosmoShipsAddress) {
        cosmoShips = CosmoShips(cosmoShipsAddress);
    }

    /**
     * @dev Create a new team with 3 NFTs.
     * @param nftIds - Array of 3 NFT IDs to form the team.
     * @param teamName - The name of the team.
     */
    function createTeam(uint256[] calldata nftIds, string calldata teamName) external returns (uint256) {
        if (nftIds.length != 3) revert ShipsNeededError();

        uint256 newTeamId = teamsCounter.current();
        Team storage newTeam = teams[newTeamId];

        for (uint256 i = 0; i < nftIds.length; i++) {
            require(cosmoShips.ownerOf(nftIds[i]) == msg.sender, "Not the owner of this NFT");
            cosmoShips.transferFrom(msg.sender, address(this), nftIds[i]);
            newTeam.nftIds.push(nftIds[i]);
        }

        newTeam.owner = msg.sender;
        newTeam.name = teamName;
        teamsCounter.increment();

        emit TeamCreated(newTeamId, msg.sender, teamName);

        return newTeamId;
    }

    /**
     * @dev Get the attributes of a team's NFTs.
     * @param teamId - The ID of the team.
     * @return nftIds - The NFTs in the team.
     * @return attack - The combined attack attributes.
     * @return speed - The combined speed attributes.
     * @return shield - The combined shield attributes.
     */
    function getTeam(uint256 teamId)
        external
        view
        returns (uint256[] memory nftIds, uint256 attack, uint256 speed, uint256 shield)
    {
        Team storage team = teams[teamId];
        nftIds = team.nftIds;
        uint256 nftCount = nftIds.length;

        for (uint256 i = 0; i < nftCount; i++) {
            uint256 attributes = cosmoShips.attributes(nftIds[i]);
            (, uint256 nftAttack, uint256 nftSpeed, uint256 nftShield) = cosmoShips.decodeAttributes(attributes);

            attack += nftAttack;
            speed += nftSpeed;
            shield += nftShield;
        }
    }

    function getTeamNames(uint256[] memory teamIds) internal view returns (string[] memory) {
        string[] memory teamNames = new string[](teamIds.length);
        for (uint256 i = 0; i < teamIds.length; i++) {
            teamNames[i] = teams[teamIds[i]].name;
        }
        return teamNames;
    }

    /**
     * @dev Validate that the caller owns all the teams in the provided list.
     * @param teamIds The list of team IDs to validate.
     * @return validTeamIds The list of team IDs owned by the caller.
     */
    function validateTeamOwnership(address caller, uint256[] calldata teamIds)
        external
        view
        returns (uint256[] memory validTeamIds)
    {
        uint256[] memory ownedTeams = new uint256[](teamIds.length);
        uint256 ownedCount = 0;

        for (uint256 i = 0; i < teamIds.length; i++) {
            if (teams[teamIds[i]].owner == caller) {
                ownedTeams[ownedCount] = teamIds[i];
                ownedCount++;
            }
        }

        // Resize the array to the actual number of valid teams
        uint256[] memory result = new uint256[](ownedCount);
        for (uint256 j = 0; j < ownedCount; j++) {
            result[j] = ownedTeams[j];
        }

        return result;
    }
}
