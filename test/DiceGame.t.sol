// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {DiceGame} from "../src/DiceGame.sol";
import {AchievementNFT} from "../src/AchievementNFT.sol";
import {Treasury} from "../src/Treasury.sol";
import {MockVRFConsumer} from "./mocks/MockVRFConsumer.sol";

contract DiceGameTest is Test {
    address internal constant NATIVE = address(0);
    uint16 internal constant HOUSE_EDGE_BPS = 250;

    DiceGame internal diceGame;
    AchievementNFT internal achievementNFT;
    Treasury internal treasury;
    MockVRFConsumer internal vrfConsumer;

    address internal owner = address(this);
    address internal player = makeAddr("player");

    function setUp() public {
        vrfConsumer = new MockVRFConsumer();
        treasury = new Treasury(owner, HOUSE_EDGE_BPS);
        achievementNFT = new AchievementNFT(owner);

        diceGame = new DiceGame(
            owner,
            address(vrfConsumer),
            address(treasury),
            address(achievementNFT)
        );

        achievementNFT.setGameContract(address(diceGame));

        treasury.setTokenConfig(NATIVE, true, 0.001 ether, 1 ether);
        treasury.setGameAuthorization(address(diceGame), true);

        vm.deal(owner, 100 ether);
        treasury.depositLiquidity{value: 50 ether}(NATIVE, 50 ether);

        vm.deal(player, 10 ether);
    }

    receive() external payable {}

    function test_rollDice_createsRequest() public {
        vm.prank(player);
        uint256 requestId = diceGame.rollDice{value: 0.01 ether}(3);

        assertEq(requestId, 1);

        uint256[] memory requests = diceGame.getPlayerRequests(player);
        assertEq(requests.length, 1);
        assertEq(requests[0], requestId);
    }

    function test_rollDice_winningBet_mintsFirstWinNFT() public {
        vm.prank(player);
        uint256 requestId = diceGame.rollDice{value: 0.01 ether}(4);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 3; // 3 % 6 + 1 = 4, so player wins

        vrfConsumer.fulfillRandomWords(requestId, randomWords);

        assertTrue(achievementNFT.hasFirstWinAchievement(player));
        assertEq(achievementNFT.ownerOf(0), player);
    }

    function test_rollDice_losingBet_doesNotMintNFT() public {
        vm.prank(player);
        uint256 requestId = diceGame.rollDice{value: 0.01 ether}(2);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 3; // 3 % 6 + 1 = 4, guess is 2, so player loses

        vrfConsumer.fulfillRandomWords(requestId, randomWords);

        assertFalse(achievementNFT.hasFirstWinAchievement(player));
    }

    function test_commitReveal_winningFlow() public {
        uint8 guess = 5;
        bytes32 salt = keccak256("secret salt");

        bytes32 commitment = diceGame.getCommitmentHash(player, guess, salt);

        vm.prank(player);
        uint256 requestId = diceGame.commitRoll{value: 0.01 ether}(commitment);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 4; // 4 % 6 + 1 = 5, so player wins

        vrfConsumer.fulfillRandomWords(requestId, randomWords);

        vm.prank(player);
        diceGame.revealRoll(requestId, guess, salt);

        assertTrue(achievementNFT.hasFirstWinAchievement(player));
        assertEq(achievementNFT.ownerOf(0), player);
    }

    function test_commitReveal_revertsInvalidReveal() public {
        uint8 guess = 5;
        bytes32 salt = keccak256("secret salt");

        bytes32 commitment = diceGame.getCommitmentHash(player, guess, salt);

        vm.prank(player);
        uint256 requestId = diceGame.commitRoll{value: 0.01 ether}(commitment);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 4;

        vrfConsumer.fulfillRandomWords(requestId, randomWords);

        bytes32 wrongSalt = keccak256("wrong salt");

        vm.prank(player);
        vm.expectRevert("Invalid reveal");
        diceGame.revealRoll(requestId, guess, wrongSalt);
    }
}