// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Lottery} from "../src/Lottery.sol";
import {Referral} from "../src/Referral.sol";
import {MockVRFConsumer} from "./mocks/MockVRFConsumer.sol";
import {MockTreasury} from "./mocks/MockTreasury.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract LotteryTest is Test {
    Lottery public lottery;
    Referral public referral;
    MockVRFConsumer public vrfConsumer;
    MockTreasury public treasury;

    address public owner = address(0x1);
    address public player1 = address(0x2);
    address public player2 = address(0x3);
    address public player3 = address(0x4);
    address public referrer = address(0x5);

    uint256 public constant TICKET_PRICE = 0.01 ether;
    uint256 public constant DURATION = 7 days;

    event RoundCreated(
        uint256 indexed roundId,
        address indexed token,
        uint256 ticketPrice,
        uint256 maxTickets,
        uint256 startTime,
        uint256 endTime,
        uint32  numWinners
    );
    event TicketsPurchased(
        uint256 indexed roundId,
        address indexed buyer,
        uint256 numTickets,
        uint256 totalCost,
        bytes32 referralCode
    );
    event DrawRequested(uint256 indexed roundId, uint256 indexed requestId);
    event DrawCompleted(
        uint256 indexed roundId,
        uint256 indexed requestId,
        uint256[] randomWords,
        address[] winners,
        uint256[] payouts
    );
    event PrizeClaimed(uint256 indexed roundId, address indexed winner, uint256 amount);
    event RoundCancelled(uint256 indexed roundId);
    event RefundClaimed(uint256 indexed roundId, address indexed player, uint256 amount);

    function setUp() public {
        vm.startPrank(owner);

        vrfConsumer = new MockVRFConsumer();
        treasury = new MockTreasury();
        lottery = new Lottery(address(vrfConsumer), address(treasury));
        referral = new Referral();

        lottery.setReferral(address(referral));
        referral.setLottery(address(lottery));

        vm.stopPrank();

        vm.deal(player1, 100 ether);
        vm.deal(player2, 100 ether);
        vm.deal(player3, 100 ether);
        vm.deal(referrer, 100 ether);
    }

    // ========== Constructor Tests ==========

    function test_constructor() public view {
        assertEq(address(lottery.vrfConsumer()), address(vrfConsumer));
        assertEq(address(lottery.treasury()), address(treasury));
        assertEq(lottery.currentRoundId(), 0);
    }

    function test_constructor_reverts_zeroVRF() public {
        vm.expectRevert("Zero VRFConsumer");
        new Lottery(address(0), address(treasury));
    }

    function test_constructor_reverts_zeroTreasury() public {
        vm.expectRevert("Zero Treasury");
        new Lottery(address(vrfConsumer), address(0));
    }

    // ========== createRound Tests ==========

    function test_createRound_ETH() public {
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit RoundCreated(1, address(0), TICKET_PRICE, 100, block.timestamp, block.timestamp + DURATION, 1);
        uint256 roundId = lottery.createRound(address(0), TICKET_PRICE, 100, DURATION, 1);
        assertEq(roundId, 1);
        assertEq(lottery.currentRoundId(), 1);

        Lottery.Round memory r = lottery.getRound(1);
        assertEq(r.id, 1);
        assertEq(r.token, address(0));
        assertEq(r.ticketPrice, TICKET_PRICE);
        assertEq(r.maxTickets, 100);
        assertEq(r.numWinners, 1);
        assertEq(uint256(r.status), 0); // OPEN
        vm.stopPrank();
    }

    function test_createRound_ERC20() public {
        MockERC20 token = new MockERC20("Test", "TST", 18);
        token.mint(owner, 1000 ether);

        vm.startPrank(owner);
        uint256 roundId = lottery.createRound(address(token), 10 ether, 50, DURATION, 3);
        assertEq(roundId, 1);

        Lottery.Round memory r = lottery.getRound(1);
        assertEq(r.token, address(token));
        assertEq(r.ticketPrice, 10 ether);
        assertEq(r.numWinners, 3);
        vm.stopPrank();
    }

    function test_createRound_reverts_zeroPrice() public {
        vm.startPrank(owner);
        vm.expectRevert("Ticket price zero");
        lottery.createRound(address(0), 0, 100, DURATION, 1);
        vm.stopPrank();
    }

    function test_createRound_reverts_zeroWinners() public {
        vm.startPrank(owner);
        vm.expectRevert("Need >= 1 winner");
        lottery.createRound(address(0), TICKET_PRICE, 100, DURATION, 0);
        vm.stopPrank();
    }

    function test_createRound_reverts_tooManyWinners() public {
        vm.startPrank(owner);
        vm.expectRevert("Too many winners");
        lottery.createRound(address(0), TICKET_PRICE, 100, DURATION, 101);
        vm.stopPrank();
    }

    function test_createRound_reverts_belowMinBet() public {
        vm.startPrank(owner);
        treasury.setMinBet(address(0), 0.1 ether);
        vm.expectRevert("Below min bet");
        lottery.createRound(address(0), TICKET_PRICE, 100, DURATION, 1);
        vm.stopPrank();
    }

    function test_createRound_reverts_badDuration() public {
        vm.startPrank(owner);
        vm.expectRevert("Bad duration");
        lottery.createRound(address(0), TICKET_PRICE, 100, 30 minutes, 1);
        vm.stopPrank();
    }

    function test_createRound_reverts_maxTicketsLessThanWinners() public {
        vm.startPrank(owner);
        vm.expectRevert("Max tickets < winners");
        lottery.createRound(address(0), TICKET_PRICE, 2, DURATION, 3);
        vm.stopPrank();
    }

    // ========== buyTicket Tests (ETH) ==========

    function test_buyTicket_single() public {
        _createETHRound();
        vm.startPrank(player1);
        vm.expectEmit(true, true, true, true);
        emit TicketsPurchased(1, player1, 1, TICKET_PRICE, bytes32(0));
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();

        assertEq(lottery.getTicketHolder(1, 0), player1);
        assertEq(lottery.getTicketCount(1, player1), 1);

        Lottery.Round memory r = lottery.getRound(1);
        assertEq(r.totalTicketsSold, 1);
        assertEq(r.prizePool, TICKET_PRICE);
    }

    function test_buyTicket_multiple() public {
        _createETHRound();
        uint256 num = 5;
        uint256 cost = TICKET_PRICE * num;

        vm.startPrank(player1);
        lottery.buyTicket{value: cost}(1, num, bytes32(0));
        vm.stopPrank();

        for (uint256 i = 0; i < num; i++) {
            assertEq(lottery.getTicketHolder(1, i), player1);
        }
        assertEq(lottery.getTicketCount(1, player1), num);

        Lottery.Round memory r = lottery.getRound(1);
        assertEq(r.totalTicketsSold, num);
        assertEq(r.prizePool, cost);
    }

    function test_buyTicket_multiplePlayers() public {
        _createETHRound();
        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE * 3}(1, 3, bytes32(0));
        vm.stopPrank();

        vm.startPrank(player2);
        lottery.buyTicket{value: TICKET_PRICE * 2}(1, 2, bytes32(0));
        vm.stopPrank();

        assertEq(lottery.getTicketHolder(1, 0), player1);
        assertEq(lottery.getTicketHolder(1, 1), player1);
        assertEq(lottery.getTicketHolder(1, 2), player1);
        assertEq(lottery.getTicketHolder(1, 3), player2);
        assertEq(lottery.getTicketHolder(1, 4), player2);

        Lottery.Round memory r = lottery.getRound(1);
        assertEq(r.totalTicketsSold, 5);
        assertEq(r.prizePool, TICKET_PRICE * 5);
    }

    function test_buyTicket_reverts_wrongETH() public {
        _createETHRound();
        vm.startPrank(player1);
        vm.expectRevert("Wrong ETH amount");
        lottery.buyTicket{value: TICKET_PRICE + 1}(1, 1, bytes32(0));
        vm.stopPrank();
    }

    function test_buyTicket_reverts_roundEnded() public {
        _createETHRound();
        vm.warp(block.timestamp + DURATION + 1);
        vm.startPrank(player1);
        vm.expectRevert("Round ended");
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();
    }

    function test_buyTicket_reverts_exceedsMax() public {
        vm.startPrank(owner);
        lottery.createRound(address(0), TICKET_PRICE, 3, DURATION, 1);
        vm.stopPrank();

        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE * 3}(1, 3, bytes32(0));
        vm.expectRevert("Exceeds max tickets");
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();
    }

    function test_buyTicket_withReferral() public {
        _createETHRound();

        bytes32 refCode = bytes32(uint256(0xABCD));
        vm.startPrank(referrer);
        referral.registerReferral(refCode);
        vm.stopPrank();

        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, refCode);
        vm.stopPrank();

        assertEq(referral.referredBy(player1), referrer);
        uint256 expectedCommission = (TICKET_PRICE * referral.commissionBps()) / 10_000;
        assertEq(
            referral.pendingCommissions(referrer, address(0)),
            expectedCommission
        );
    }

    // ========== triggerDraw Tests ==========

    function test_triggerDraw_normal() public {
        _createETHRound();
        _buyTickets(3);

        vm.warp(block.timestamp + DURATION + 1);

        vm.expectEmit(true, true, false, false);
        emit DrawRequested(1, 1);
        lottery.triggerDraw(1);

        Lottery.Round memory r = lottery.getRound(1);
        assertEq(uint256(r.status), 1); // DRAWING
        assertEq(r.requestId, 1);
    }

    function test_triggerDraw_emptyPool_cancels() public {
        _createETHRound();
        vm.warp(block.timestamp + DURATION + 1);

        vm.expectEmit(true, false, false, false);
        emit RoundCancelled(1);
        lottery.triggerDraw(1);

        Lottery.Round memory r = lottery.getRound(1);
        assertEq(uint256(r.status), 3); // CANCELLED
    }

    function test_triggerDraw_reverts_notEnded() public {
        _createETHRound();
        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();

        vm.expectRevert("Round not ended");
        lottery.triggerDraw(1);
    }

    function test_triggerDraw_reverts_notOpen() public {
        _createETHRound();
        _buyTickets(1);
        vm.warp(block.timestamp + DURATION + 1);

        lottery.triggerDraw(1);
        vm.expectRevert("Not open");
        lottery.triggerDraw(1); // Already in DRAWING
    }

    // ========== Draw Completion Tests ==========

    function test_completeDraw_singleWinner() public {
        _createETHRound();
        _buyTickets(5);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.triggerDraw(1);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42;
        vrfConsumer.fulfillRandomWords(1, randomWords);

        Lottery.Round memory r = lottery.getRound(1);
        assertEq(uint256(r.status), 2); // COMPLETED
        assertTrue(r.prizesClaimable);

        address[] memory winners = lottery.getWinners(1);
        uint256[] memory payouts = lottery.getPayouts(1);
        assertEq(winners.length, 1);
        assertEq(payouts.length, 1);
        assertTrue(winners[0] != address(0));
        assertTrue(payouts[0] > 0);
    }

    function test_completeDraw_multipleWinners() public {
        vm.startPrank(owner);
        lottery.createRound(address(0), TICKET_PRICE, 0, DURATION, 3);
        vm.stopPrank();

        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE * 3}(1, 3, bytes32(0));
        vm.stopPrank();
        vm.startPrank(player2);
        lottery.buyTicket{value: TICKET_PRICE * 2}(1, 2, bytes32(0));
        vm.stopPrank();
        vm.startPrank(player3);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();

        vm.warp(block.timestamp + DURATION + 1);
        lottery.triggerDraw(1);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 12345;
        vrfConsumer.fulfillRandomWords(1, randomWords);

        address[] memory winners = lottery.getWinners(1);
        uint256[] memory payouts = lottery.getPayouts(1);
        assertEq(winners.length, 3);
        // All payouts should be equal
        assertEq(payouts[0], payouts[1]);
        assertEq(payouts[1], payouts[2]);
    }

    function test_completeDraw_singleParticipant() public {
        _createETHRound();
        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();

        vm.warp(block.timestamp + DURATION + 1);
        lottery.triggerDraw(1);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 999;
        vrfConsumer.fulfillRandomWords(1, randomWords);

        address[] memory winners = lottery.getWinners(1);
        assertEq(winners.length, 1);
        assertEq(winners[0], player1);
    }

    function test_completeDraw_houseEdgeToTreasury() public {
        _createETHRound();
        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE * 10}(1, 10, bytes32(0));
        vm.stopPrank();

        vm.warp(block.timestamp + DURATION + 1);
        lottery.triggerDraw(1);

        uint256 treasuryBalBefore = address(treasury).balance;

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42;
        vrfConsumer.fulfillRandomWords(1, randomWords);

        // Treasury should receive house edge (2.5% of 0.1 ETH = 0.0025 ETH)
        assertGt(address(treasury).balance, treasuryBalBefore);
    }

    function test_completeDraw_noDuplicateWinners() public {
        vm.startPrank(owner);
        lottery.createRound(address(0), TICKET_PRICE, 0, DURATION, 3);
        vm.stopPrank();

        // 3 players, 3 tickets, 3 winners
        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();
        vm.startPrank(player2);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();
        vm.startPrank(player3);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();

        vm.warp(block.timestamp + DURATION + 1);
        lottery.triggerDraw(1);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42;
        vrfConsumer.fulfillRandomWords(1, randomWords);

        address[] memory winners = lottery.getWinners(1);
        // All 3 tickets should have distinct winners
        assertTrue(winners[0] != winners[1]);
        assertTrue(winners[1] != winners[2]);
        assertTrue(winners[0] != winners[2]);
    }

    // ========== claimPrize Tests ==========

    function test_claimPrize_normal() public {
        _createETHRound();
        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();

        vm.warp(block.timestamp + DURATION + 1);
        lottery.triggerDraw(1);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42;
        vrfConsumer.fulfillRandomWords(1, randomWords);

        address winner = lottery.getWinners(1)[0];
        uint256 payout = lottery.getPayouts(1)[0];
        uint256 balBefore = winner.balance;

        vm.startPrank(winner);
        vm.expectEmit(true, true, false, false);
        emit PrizeClaimed(1, winner, payout);
        lottery.claimPrize(1);
        vm.stopPrank();

        assertEq(winner.balance, balBefore + payout);
        assertTrue(lottery.prizeClaimed(1, winner));
    }

    function test_claimPrize_reverts_notWinner() public {
        _createETHRound();
        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();

        vm.warp(block.timestamp + DURATION + 1);
        lottery.triggerDraw(1);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42;
        vrfConsumer.fulfillRandomWords(1, randomWords);

        vm.startPrank(player2);
        vm.expectRevert("Not a winner or already claimed");
        lottery.claimPrize(1);
        vm.stopPrank();
    }

    function test_claimPrize_reverts_doubleClaim() public {
        _createETHRound();
        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();

        vm.warp(block.timestamp + DURATION + 1);
        lottery.triggerDraw(1);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42;
        vrfConsumer.fulfillRandomWords(1, randomWords);

        address winner = lottery.getWinners(1)[0];

        vm.startPrank(winner);
        lottery.claimPrize(1);
        vm.expectRevert("Not a winner or already claimed");
        lottery.claimPrize(1);
        vm.stopPrank();
    }

    // ========== Cancel & Refund Tests ==========

    function test_cancelRound() public {
        _createETHRound();
        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, false);
        emit RoundCancelled(1);
        lottery.cancelRound(1);
        vm.stopPrank();

        Lottery.Round memory r = lottery.getRound(1);
        assertEq(uint256(r.status), 3); // CANCELLED
    }

    function test_refund() public {
        _createETHRound();
        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE * 2}(1, 2, bytes32(0));
        vm.stopPrank();

        vm.startPrank(owner);
        lottery.cancelRound(1);
        vm.stopPrank();

        uint256 balBefore = player1.balance;
        vm.startPrank(player1);
        vm.expectEmit(true, true, false, false);
        emit RefundClaimed(1, player1, TICKET_PRICE * 2);
        lottery.claimRefund(1);
        vm.stopPrank();

        assertEq(player1.balance, balBefore + TICKET_PRICE * 2);
        assertTrue(lottery.refunded(1, player1));
    }

    function test_refund_reverts_notCancelled() public {
        _createETHRound();
        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();

        vm.expectRevert("Not cancelled");
        lottery.claimRefund(1);
    }

    function test_refund_reverts_doubleRefund() public {
        _createETHRound();
        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();

        vm.startPrank(owner);
        lottery.cancelRound(1);
        vm.stopPrank();

        vm.startPrank(player1);
        lottery.claimRefund(1);
        vm.expectRevert("Already refunded");
        lottery.claimRefund(1);
        vm.stopPrank();
    }

    // ========== VRF Timeout & Retry Tests ==========

    function test_retryDraw() public {
        _createETHRound();
        _buyTickets(2);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.triggerDraw(1);

        // VRF didn't respond in time
        vm.warp(block.timestamp + 25 hours);
        lottery.retryDraw(1);

        // New request ID = 2
        Lottery.Round memory r = lottery.getRound(1);
        assertEq(r.requestId, 2);
    }

    function test_retryDraw_reverts_beforeTimeout() public {
        _createETHRound();
        _buyTickets(2);
        vm.warp(block.timestamp + DURATION + 1);
        lottery.triggerDraw(1);

        vm.expectRevert("VRF timeout not reached");
        lottery.retryDraw(1);
    }

    // ========== ERC-20 Tests ==========

    function test_buyTicket_ERC20() public {
        MockERC20 token = new MockERC20("Test", "TST", 18);

        vm.startPrank(owner);
        token.mint(owner, 1000 ether);
        lottery.createRound(address(token), 10 ether, 100, DURATION, 1);
        vm.stopPrank();

        // Transfer tokens and approve
        token.mint(player1, 100 ether);
        vm.startPrank(player1);
        token.approve(address(lottery), 10 ether);
        lottery.buyTicket(1, 1, bytes32(0));
        vm.stopPrank();

        assertEq(lottery.getTicketHolder(1, 0), player1);
        Lottery.Round memory r = lottery.getRound(1);
        assertEq(r.prizePool, 10 ether);
    }

    function test_claimPrize_ERC20() public {
        MockERC20 token = new MockERC20("Test", "TST", 18);

        vm.startPrank(owner);
        token.mint(owner, 1000 ether);
        lottery.createRound(address(token), 1 ether, 100, DURATION, 1);
        vm.stopPrank();

        token.mint(player1, 10 ether);
        vm.startPrank(player1);
        token.approve(address(lottery), 1 ether);
        lottery.buyTicket(1, 1, bytes32(0));
        vm.stopPrank();

        vm.warp(block.timestamp + DURATION + 1);
        lottery.triggerDraw(1);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42;
        vrfConsumer.fulfillRandomWords(1, randomWords);

        address winner = lottery.getWinners(1)[0];
        uint256 payout = lottery.getPayouts(1)[0];
        uint256 balBefore = token.balanceOf(winner);

        vm.startPrank(winner);
        lottery.claimPrize(1);
        vm.stopPrank();

        assertEq(token.balanceOf(winner), balBefore + payout);
    }

    // ========== View Function Tests ==========

    function test_view_getRound() public {
        _createETHRound();
        Lottery.Round memory r = lottery.getRound(1);
        assertEq(r.ticketPrice, TICKET_PRICE);
        assertEq(r.maxTickets, 100);
    }

    function test_view_isWinner() public {
        _createETHRound();
        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();

        vm.warp(block.timestamp + DURATION + 1);
        lottery.triggerDraw(1);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42;
        vrfConsumer.fulfillRandomWords(1, randomWords);

        address winner = lottery.getWinners(1)[0];
        assertTrue(lottery.isWinner(1, winner));
        assertFalse(lottery.isWinner(1, player2));
    }

    function test_view_canClaimPrize() public {
        _createETHRound();
        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();

        vm.warp(block.timestamp + DURATION + 1);
        lottery.triggerDraw(1);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42;
        vrfConsumer.fulfillRandomWords(1, randomWords);

        address winner = lottery.getWinners(1)[0];
        assertTrue(lottery.canClaimPrize(1, winner));
        assertFalse(lottery.canClaimPrize(1, player2));
    }

    // ========== Boundary & Edge Cases ==========

    function test_unlimitedTickets() public {
        vm.startPrank(owner);
        lottery.createRound(address(0), TICKET_PRICE, 0, DURATION, 1); // maxTickets=0 = unlimited
        vm.stopPrank();

        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE * 50}(1, 50, bytes32(0));
        vm.stopPrank();
    }

    function test_buyTicket_selfReferralPrevented() public {
        _createETHRound();

        bytes32 refCode = bytes32(uint256(0xBEEF));
        vm.startPrank(player1);
        referral.registerReferral(refCode);

        // Player1 buys with their own referral code
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, refCode);
        vm.stopPrank();

        // Should not have self-referral commission
        assertEq(referral.referredBy(player1), address(0));
        assertEq(referral.pendingCommissions(player1, address(0)), 0);
    }

    function test_zeroReferralCode_noEffect() public {
        _createETHRound();
        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();

        assertEq(referral.referredBy(player1), address(0));
    }

    // ========== Admin Tests ==========

    function test_setVRFConsumer() public {
        MockVRFConsumer newVrf = new MockVRFConsumer();
        vm.startPrank(owner);
        lottery.setVRFConsumer(address(newVrf));
        assertEq(address(lottery.vrfConsumer()), address(newVrf));
        vm.stopPrank();
    }

    function test_setTreasury() public {
        MockTreasury newTreasury = new MockTreasury();
        vm.startPrank(owner);
        lottery.setTreasury(address(newTreasury));
        assertEq(address(lottery.treasury()), address(newTreasury));
        vm.stopPrank();
    }

    function test_setVRFTimeout() public {
        vm.startPrank(owner);
        lottery.setVRFTimeout(48 hours);
        vm.stopPrank();
        // No direct getter, test via retryDraw timing
    }

    // ========== Pause Tests ==========

    function test_pause() public {
        _createETHRound();

        vm.startPrank(owner);
        lottery.pause();
        vm.stopPrank();

        vm.startPrank(player1);
        vm.expectRevert(); // Pausable: paused
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();

        vm.startPrank(owner);
        lottery.unpause();
        vm.stopPrank();

        vm.startPrank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1, 1, bytes32(0));
        vm.stopPrank();
    }

    // ========== Receive Tests ==========

    function test_receive_acceptsETH() public {
        vm.startPrank(player1);
        (bool sent,) = address(lottery).call{value: 1 ether}("");
        assertTrue(sent);
        vm.stopPrank();
    }

    // ========== Helpers ==========

    function _createETHRound() internal {
        vm.startPrank(owner);
        lottery.createRound(address(0), TICKET_PRICE, 100, DURATION, 1);
        vm.stopPrank();
    }

    function _buyTickets(uint256 each) internal {
        uint256 cost = TICKET_PRICE * each;
        vm.startPrank(player1);
        lottery.buyTicket{value: cost}(1, each, bytes32(0));
        vm.stopPrank();
    }
}
