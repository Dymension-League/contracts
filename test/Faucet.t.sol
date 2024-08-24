// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Faucet.sol";

contract FaucetTest is Test {
    Faucet public faucet;
    address public authorizedDripper;
    address public newOwner;
    address public user1;
    address public user2;

    function setUp() public {
        authorizedDripper = address(1);
        newOwner = address(2);
        user1 = address(3);
        user2 = address(4);
        faucet = new Faucet(1, 1, authorizedDripper); // Drip 1 ether, cooldown 1 day
        vm.deal(address(faucet), 10 ether); // Give the faucet 10 ether
    }

    receive() external payable {}

    function test_ClaimDrip() public {
        vm.prank(user1);
        faucet.claimDrip();
        assertEq(address(user1).balance, 1 ether);
    }

    function test_ReClaimDrip() public {
        vm.prank(user1);
        faucet.claimDrip();
        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        faucet.claimDrip();
        assertEq(address(user1).balance, 2 ether);
    }

    function testFail_ClaimDrip_WithinCooldown() public {
        vm.prank(user1);
        faucet.claimDrip();
        vm.prank(user1);
        faucet.claimDrip(); // Should fail as cooldown period is not reached
    }

    function test_SendDrip() public {
        vm.startPrank(authorizedDripper);
        faucet.sendDrip(user1);
        faucet.sendDrip(user2);
        vm.stopPrank();
        assertEq(address(user1).balance, 1 ether);
    }

    function test_ReSendDrip() public {
        vm.startPrank(authorizedDripper);
        faucet.sendDrip(user1);
        faucet.sendDrip(user2);
        vm.warp(block.timestamp + 1 days);
        faucet.sendDrip(user1);
        faucet.sendDrip(user2);
        vm.stopPrank();
        assertEq(address(user1).balance, 2 ether);
        assertEq(address(user2).balance, 2 ether);
    }

    function testFail_SendDrip_WithinCooldown() public {
        vm.prank(authorizedDripper);
        faucet.sendDrip(user1);
        faucet.sendDrip(user1); // Should fail as cooldown period is not reached
    }

    function testFail_SendDrip_NotAuthorized() public {
        vm.prank(user1);
        faucet.sendDrip(user2); // Should fail as user1 is not authorized dripper
    }

    function test_Withdraw() public {
        uint256 initialOwnerBalance = address(this).balance;
        faucet.withdraw();
        assertEq(address(this).balance, initialOwnerBalance + 10 ether);
    }

    function testFail_Withdraw_NotOwner() public {
        vm.prank(user1);
        faucet.withdraw(); // Should fail as user1 is not the owner
    }

    function test_SetDripAmount() public {
        faucet.setDripAmount(2);
        vm.prank(user1);
        faucet.claimDrip();
        assertEq(faucet.dripAmount(), 2 ether);
        assertEq(address(user1).balance, 2 ether);
    }

    function test_SetCooldownPeriod() public {
        faucet.setCooldownPeriod(2);
        assertEq(faucet.cooldownPeriod(), 2 days);
    }

    function test_TransferOwnership() public {
        faucet.transferOwnership(newOwner);
        assertEq(faucet.owner(), newOwner);
    }

    function testFail_TransferOwnership_ToZeroAddress() public {
        faucet.transferOwnership(address(0)); // Should fail as new owner is zero address
    }

    function test_Donate() public {
        vm.deal(address(user1), 10 ether); // Give the user1 10 ether
        vm.prank(user1);
        faucet.donate{value: 1 ether}();
        assertEq(address(faucet).balance, 11 ether);
    }

    function test_ReceiveEther() public {
        vm.deal(address(user1), 10 ether); // Give the user1 10 ether
        payable(address(faucet)).transfer(1 ether);
        assertEq(address(faucet).balance, 11 ether);
    }
}
