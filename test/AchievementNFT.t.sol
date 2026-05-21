// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {AchievementNFT} from "../src/AchievementNFT.sol";

contract AchievementNFTTest is Test {
    AchievementNFT internal achievementNFT;

    address internal owner = address(this);
    address internal game = makeAddr("game");
    address internal player = makeAddr("player");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        achievementNFT = new AchievementNFT(owner);
    }

    function test_setGameContract() public {
        achievementNFT.setGameContract(game);

        assertEq(achievementNFT.gameContract(), game);
    }

    function test_setGameContract_revertsZeroAddress() public {
        vm.expectRevert("Invalid game contract");
        achievementNFT.setGameContract(address(0));
    }

    function test_onlyOwnerCanSetGameContract() public {
        vm.prank(stranger);
        vm.expectRevert();
        achievementNFT.setGameContract(game);
    }

    function test_mintFirstWin() public {
        achievementNFT.setGameContract(game);

        vm.prank(game);
        uint256 tokenId = achievementNFT.mintFirstWin(player);

        assertEq(tokenId, 0);
        assertTrue(achievementNFT.hasFirstWinAchievement(player));
        assertEq(achievementNFT.ownerOf(tokenId), player);
        assertEq(achievementNFT.balanceOf(player), 1);
    }

    function test_mintFirstWin_revertsIfNotGameContract() public {
        achievementNFT.setGameContract(game);

        vm.prank(stranger);
        vm.expectRevert("Only game contract can mint");
        achievementNFT.mintFirstWin(player);
    }

    function test_mintFirstWin_revertsDuplicateAchievement() public {
        achievementNFT.setGameContract(game);

        vm.startPrank(game);
        achievementNFT.mintFirstWin(player);

        vm.expectRevert("Achievement already minted");
        achievementNFT.mintFirstWin(player);
        vm.stopPrank();
    }

    function test_mintFirstWin_revertsInvalidPlayer() public {
        achievementNFT.setGameContract(game);

        vm.prank(game);
        vm.expectRevert("Invalid player");
        achievementNFT.mintFirstWin(address(0));
    }
}