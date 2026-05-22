// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {VRFConsumer} from "../../src/VRFConsumer.sol";
import {Treasury} from "../../src/Treasury.sol";
import {DiceGame} from "../../src/DiceGame.sol";
import {AchievementNFT} from "../../src/AchievementNFT.sol";
import {Lottery} from "../../src/Lottery.sol";
import {Referral} from "../../src/Referral.sol";
import {IVRFConsumer} from "../../src/interfaces/IVRFConsumer.sol";
import {MockVRFCoordinator} from "../mocks/MockVRFCoordinator.sol";

/**
 * @title EndToEndTest
 * @author SC6107 Group Project - Member 5 (Testing & QA)
 * @notice Multi-contract integration tests. These exercise the FULL stack
 *         (VRFConsumer + MockVRFCoordinator + Treasury + DiceGame +
 *         AchievementNFT + Lottery + Referral) end-to-end, whereas individual
 *         unit test suites only verify each contract in isolation.
 *
 *         Coverage map:
 *           1.  Dice happy path: bet -> VRF -> win -> NFT minted -> payout
 *           2.  Dice losing path: stake retained, no NFT
 *           3.  Dice commit-reveal happy path
 *           4.  Dice commit-reveal forfeit (player never reveals)
 *           5.  Lottery full lifecycle: round -> tickets -> draw -> claim
 *           6.  Lottery cancellation + refund
 *           7.  Lottery + Referral commission earned and claimed
 *           8.  Cross-game: same player plays Dice and Lottery
 *           9.  Treasury solvency under many concurrent bets
 *          10.  VRF retry after coordinator timeout (Lottery path)
 *
 *         NOTE: long tests delegate to small internal helpers to keep each
 *         test function's local-variable count well under Solidity's
 *         16-slot stack limit (avoids "stack too deep" errors).
 */
contract EndToEndTest is Test {
    address internal constant NATIVE = address(0);
    uint16 internal constant HOUSE_EDGE_BPS = 250; // 2.5%

    // --- Infrastructure ---
    MockVRFCoordinator internal coordinator;
    VRFConsumer internal vrfConsumer;
    Treasury internal treasury;
    AchievementNFT internal achievementNFT;
    Referral internal referral;

    // --- Games ---
    DiceGame internal diceGame;
    Lottery internal lottery;

    // --- Actors ---
    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal referrer = makeAddr("referrer");

    function setUp() public {
        // 1. Deploy shared infrastructure.
        coordinator = new MockVRFCoordinator();
        vrfConsumer = new VRFConsumer(
            address(coordinator),
            bytes32(uint256(1)), // dummy keyHash
            1,                   // dummy subscription id
            500_000              // callback gas limit
        );
        treasury = new Treasury(admin, HOUSE_EDGE_BPS);
        achievementNFT = new AchievementNFT(admin);
        referral = new Referral();

        // 2. Deploy game contracts.
        diceGame = new DiceGame(
            admin,
            address(vrfConsumer),
            address(treasury),
            address(achievementNFT)
        );
        lottery = new Lottery(address(vrfConsumer), address(treasury));

        // 3. Wire up cross-contract authorisations.
        vrfConsumer.setConsumerAuthorization(address(diceGame), true);
        vrfConsumer.setConsumerAuthorization(address(lottery), true);

        treasury.setTokenConfig(NATIVE, true, 0.001 ether, 1 ether);
        treasury.setGameAuthorization(address(diceGame), true);
        // Lottery does not call Treasury.openBet, only depositLiquidity
        // (which is permissionless), so no game-auth needed for Lottery.

        achievementNFT.setGameContract(address(diceGame));

        lottery.setReferral(address(referral));
        referral.setLottery(address(lottery));

        // 4. Fund Treasury house liquidity.
        vm.deal(admin, 10_000 ether);
        treasury.depositLiquidity{value: 500 ether}(NATIVE, 500 ether);

        // 5. Fund actors.
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        vm.deal(referrer, 100 ether);
    }

    // We are admin and may receive ETH (Treasury withdrawals etc.).
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                            BET STATE HELPERS

       DiceGame.bets is a public mapping over a 13-field struct, so we
       use these helpers to pluck individual fields cleanly without
       blowing the function's local-variable budget.
    //////////////////////////////////////////////////////////////*/

    function _isSettled(uint256 requestId) internal view returns (bool s) {
        (, , , , , s, , , , , , , ) = diceGame.bets(requestId);
    }

    function _hasWon(uint256 requestId) internal view returns (bool w) {
        (, , , , , , w, , , , , , ) = diceGame.bets(requestId);
    }

    function _result(uint256 requestId) internal view returns (uint8 r) {
        (, , , , , , , r, , , , , ) = diceGame.bets(requestId);
    }

    function _randomFulfilled(uint256 requestId) internal view returns (bool rf) {
        (, , , , , , , , , , rf, , ) = diceGame.bets(requestId);
    }

    /*//////////////////////////////////////////////////////////////
                          LOTTERY ROUND HELPERS

       Same trick: Lottery.Round has 12 fields, so we pluck what we
       need via tiny accessors rather than copying the whole struct
       into a local memory variable.
    //////////////////////////////////////////////////////////////*/

    function _roundStatus(uint256 roundId)
        internal
        view
        returns (Lottery.RoundStatus)
    {
        return lottery.getRound(roundId).status;
    }

    function _roundEndTime(uint256 roundId) internal view returns (uint256) {
        return lottery.getRound(roundId).endTime;
    }

    function _roundRequestId(uint256 roundId) internal view returns (uint256) {
        return lottery.getRound(roundId).requestId;
    }

    function _roundTotalTickets(uint256 roundId) internal view returns (uint256) {
        return lottery.getRound(roundId).totalTicketsSold;
    }

    function _roundPrizePool(uint256 roundId) internal view returns (uint256) {
        return lottery.getRound(roundId).prizePool;
    }

    function _assertStatus(uint256 roundId, Lottery.RoundStatus expected) internal {
        assertEq(uint256(_roundStatus(roundId)), uint256(expected));
    }

    function _lotBuy(
        address player,
        uint256 roundId,
        uint256 ticketPrice,
        uint256 count
    ) internal {
        vm.prank(player);
        lottery.buyTicket{value: ticketPrice * count}(roundId, count, bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                       1. DICE HAPPY PATH (WIN)
    //////////////////////////////////////////////////////////////*/

    function test_E2E_Dice_Win_MintsFirstWinNFT_AndPaysOut() public {
        uint8 guess = 4;
        uint256 stake = 0.01 ether;
        uint256 aliceBefore = alice.balance;
        uint256 maxPayout = treasury.quotePayout(stake * 6);

        // ROLL
        vm.prank(alice);
        uint256 requestId = diceGame.rollDice{value: stake}(guess);

        // Stake escrowed; maxPayout locked.
        assertEq(treasury.lockedLiquidity(NATIVE), maxPayout, "maxPayout locked");
        assertFalse(_isSettled(requestId), "should not be settled yet");

        // FULFIL with a word that maps to dieResult == guess.
        // dieResult = (word % 6) + 1 = 4  =>  word % 6 = 3
        uint256[] memory words = new uint256[](1);
        words[0] = 3;
        coordinator.fulfillWithWords(requestId, words);

        // Bet settled, alice won, NFT minted, payout transferred.
        assertTrue(_isSettled(requestId), "bet must be settled");
        assertTrue(_hasWon(requestId), "alice should have won");
        assertEq(_result(requestId), guess, "result equals guess");
        assertTrue(achievementNFT.hasFirstWinAchievement(alice), "NFT minted");
        assertEq(achievementNFT.ownerOf(0), alice, "alice owns the NFT");

        // Balance math: alice net = -stake + payout
        assertEq(alice.balance, aliceBefore - stake + maxPayout, "alice payout");
        assertEq(treasury.lockedLiquidity(NATIVE), 0, "lock released after settle");
    }

    /*//////////////////////////////////////////////////////////////
                          2. DICE LOSING PATH
    //////////////////////////////////////////////////////////////*/

    function test_E2E_Dice_Loss_StakeRetained_NoNFT() public {
        uint8 guess = 2;
        uint256 stake = 0.01 ether;
        uint256 aliceBefore = alice.balance;
        uint256 treasuryBefore = address(treasury).balance;

        vm.prank(alice);
        uint256 requestId = diceGame.rollDice{value: stake}(guess);

        // word = 4 -> (4 % 6) + 1 = 5  =>  alice (who guessed 2) loses.
        uint256[] memory words = new uint256[](1);
        words[0] = 4;
        coordinator.fulfillWithWords(requestId, words);

        assertTrue(_isSettled(requestId), "settled");
        assertFalse(_hasWon(requestId), "alice lost");
        assertFalse(achievementNFT.hasFirstWinAchievement(alice), "no NFT on loss");
        assertEq(alice.balance, aliceBefore - stake, "alice paid stake only");
        assertEq(
            address(treasury).balance,
            treasuryBefore + stake,
            "treasury keeps stake"
        );
        assertEq(treasury.lockedLiquidity(NATIVE), 0, "lock released even on loss");
    }

    /*//////////////////////////////////////////////////////////////
                  3. DICE COMMIT-REVEAL HAPPY PATH
    //////////////////////////////////////////////////////////////*/

    function test_E2E_Dice_CommitReveal_Win() public {
        uint8 guess = 6;
        bytes32 salt = keccak256("alice-secret-salt-001");
        uint256 stake = 0.05 ether;
        uint256 aliceBefore = alice.balance;

        // STEP 1 -- commit (guess hidden)
        vm.prank(alice);
        uint256 requestId = diceGame.commitRoll{value: stake}(
            keccak256(abi.encodePacked(alice, guess, salt))
        );
        assertFalse(_randomFulfilled(requestId), "random not yet fulfilled");

        // STEP 2 -- VRF fulfils; word=5 produces dieResult=6
        uint256[] memory words = new uint256[](1);
        words[0] = 5;
        coordinator.fulfillWithWords(requestId, words);
        assertTrue(_randomFulfilled(requestId), "random ready");
        assertFalse(_isSettled(requestId), "not settled until reveal");

        // STEP 3 -- reveal (must come from alice with the original salt)
        vm.prank(alice);
        diceGame.revealRoll(requestId, guess, salt);

        assertTrue(_isSettled(requestId), "settled after reveal");
        assertTrue(_hasWon(requestId), "won");
        assertEq(_result(requestId), guess, "result equals guess");
        assertEq(
            alice.balance,
            aliceBefore - stake + treasury.quotePayout(stake * 6),
            "alice paid out"
        );
    }

    /*//////////////////////////////////////////////////////////////
              4. DICE COMMIT-REVEAL FORFEIT (no reveal)
    //////////////////////////////////////////////////////////////*/

    function test_E2E_Dice_CommitReveal_Forfeit() public {
        uint8 guess = 3;
        bytes32 salt = keccak256("bob-salt");
        uint256 stake = 0.02 ether;

        vm.prank(bob);
        uint256 requestId = diceGame.commitRoll{value: stake}(
            keccak256(abi.encodePacked(bob, guess, salt))
        );

        // Randomness ready, but bob never reveals.
        uint256[] memory words = new uint256[](1);
        words[0] = 2; // would have produced dieResult=3, a winning result
        coordinator.fulfillWithWords(requestId, words);

        // Cannot forfeit before the reveal deadline.
        vm.expectRevert(bytes("Reveal period not expired"));
        diceGame.forfeitExpiredRoll(requestId);

        // Fast-forward past the deadline.
        vm.warp(block.timestamp + diceGame.revealTimeout() + 1);

        // Anyone can call forfeit; bet treated as a loss.
        uint256 treasuryBefore = address(treasury).balance;
        diceGame.forfeitExpiredRoll(requestId);

        assertTrue(_isSettled(requestId), "forfeited bet is settled");
        assertFalse(_hasWon(requestId), "forfeit is a loss");
        assertEq(
            address(treasury).balance,
            treasuryBefore,
            "no payout on forfeit"
        );
        assertEq(treasury.lockedLiquidity(NATIVE), 0, "lock released");
    }

    /*//////////////////////////////////////////////////////////////
                  5. LOTTERY FULL LIFECYCLE (SINGLE WINNER)
    //////////////////////////////////////////////////////////////*/

    function test_E2E_Lottery_FullLifecycle_SingleWinner() public {
        uint256 ticketPrice = 0.01 ether;
        uint256 roundId = lottery.createRound(NATIVE, ticketPrice, 0, 1 days, 1);
        assertEq(roundId, 1);

        // Three players buy a total of 10 tickets.
        _lotBuy(alice, roundId, ticketPrice, 3);
        _lotBuy(bob, roundId, ticketPrice, 5);
        _lotBuy(carol, roundId, ticketPrice, 2);

        assertEq(_roundTotalTickets(roundId), 10);
        assertEq(_roundPrizePool(roundId), ticketPrice * 10);

        // After endTime, trigger draw (callable by anyone).
        vm.warp(_roundEndTime(roundId) + 1);
        lottery.triggerDraw(roundId);
        _assertStatus(roundId, Lottery.RoundStatus.DRAWING);

        // VRF fulfils with a seed; Lottery picks a winner.
        coordinator.fulfillWithSeed(_roundRequestId(roundId), 12345);
        _assertStatus(roundId, Lottery.RoundStatus.COMPLETED);

        // Winner claim flow (delegated so this test stays stack-friendly).
        _claimAndAssertSoleWinner(roundId);
    }

    function _claimAndAssertSoleWinner(uint256 roundId) internal {
        address[] memory winners = lottery.getWinners(roundId);
        assertEq(winners.length, 1, "1 winner");

        address winner = winners[0];
        uint256 winnerBefore = winner.balance;
        vm.prank(winner);
        lottery.claimPrize(roundId);
        assertGt(winner.balance, winnerBefore, "winner received prize");
        assertTrue(lottery.prizeClaimed(roundId, winner), "marked claimed");

        // Winner cannot double-claim.
        vm.prank(winner);
        vm.expectRevert(bytes("Not a winner or already claimed"));
        lottery.claimPrize(roundId);
    }

    /*//////////////////////////////////////////////////////////////
                  6. LOTTERY CANCEL + REFUND
    //////////////////////////////////////////////////////////////*/

    function test_E2E_Lottery_Cancel_Refund() public {
        uint256 ticketPrice = 0.01 ether;
        uint256 roundId = lottery.createRound(NATIVE, ticketPrice, 0, 1 days, 1);

        _lotBuy(alice, roundId, ticketPrice, 5);

        // Owner cancels the round before its end time.
        lottery.cancelRound(roundId);
        _assertStatus(roundId, Lottery.RoundStatus.CANCELLED);

        // Alice claims refund.
        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        lottery.claimRefund(roundId);
        assertEq(alice.balance, aliceBefore + ticketPrice * 5, "refunded");
        assertTrue(lottery.refunded(roundId, alice), "marked refunded");

        // Cannot double-refund.
        vm.prank(alice);
        vm.expectRevert(bytes("Already refunded"));
        lottery.claimRefund(roundId);
    }

    /*//////////////////////////////////////////////////////////////
                  7. LOTTERY + REFERRAL COMMISSION
    //////////////////////////////////////////////////////////////*/

    function test_E2E_Lottery_Referral_CommissionEarnedAndClaimed() public {
        // Referrer registers a unique code.
        bytes32 code = keccak256("REF-MAXINE-2026");
        vm.prank(referrer);
        referral.registerReferral(code);

        // Open a lottery round.
        uint256 ticketPrice = 0.01 ether;
        uint256 roundId = lottery.createRound(NATIVE, ticketPrice, 0, 1 days, 1);

        // Alice buys 5 tickets using the referral code.
        uint256 totalCost = ticketPrice * 5;
        vm.prank(alice);
        lottery.buyTicket{value: totalCost}(roundId, 5, code);

        uint256 expectedCommission = (totalCost * referral.commissionBps()) / 10_000;
        assertEq(
            referral.getPendingCommission(referrer, NATIVE),
            expectedCommission,
            "commission accrued"
        );
        assertEq(referral.referredBy(alice), referrer, "referred-by tracked");

        // Operator funds the Referral contract so it can pay out.
        vm.deal(address(referral), expectedCommission);

        // Referrer claims.
        uint256 refBefore = referrer.balance;
        vm.prank(referrer);
        referral.claimCommission(NATIVE);
        assertEq(referrer.balance, refBefore + expectedCommission, "commission paid");
        assertEq(referral.getPendingCommission(referrer, NATIVE), 0, "zeroed");

        // Cannot double-claim.
        vm.prank(referrer);
        vm.expectRevert(bytes("No pending commission"));
        referral.claimCommission(NATIVE);
    }

    /*//////////////////////////////////////////////////////////////
                  8. CROSS-GAME: SAME PLAYER, BOTH GAMES
    //////////////////////////////////////////////////////////////*/

    function test_E2E_CrossGame_SamePlayer_DiceAndLottery() public {
        // Alice plays Dice and wins.
        vm.prank(alice);
        uint256 diceReq = diceGame.rollDice{value: 0.02 ether}(5);
        uint256[] memory diceWords = new uint256[](1);
        diceWords[0] = 4; // (4 % 6) + 1 = 5  -> win
        coordinator.fulfillWithWords(diceReq, diceWords);
        assertTrue(_hasWon(diceReq));
        assertTrue(achievementNFT.hasFirstWinAchievement(alice));

        // Alice now enters a lottery round (only ticket holder -> must win).
        uint256 ticketPrice = 0.01 ether;
        uint256 roundId = lottery.createRound(NATIVE, ticketPrice, 0, 1 days, 1);
        _lotBuy(alice, roundId, ticketPrice, 1);

        vm.warp(_roundEndTime(roundId) + 1);
        lottery.triggerDraw(roundId);
        coordinator.fulfillWithSeed(_roundRequestId(roundId), 99);

        address[] memory winners = lottery.getWinners(roundId);
        assertEq(winners.length, 1);
        assertEq(winners[0], alice, "sole ticket holder wins");

        // Treasury solvency must hold across both games.
        assertEq(treasury.lockedLiquidity(NATIVE), 0, "no leftover locks");
    }

    /*//////////////////////////////////////////////////////////////
                  9. SOLVENCY UNDER MANY CONCURRENT BETS
    //////////////////////////////////////////////////////////////*/

    function test_E2E_Solvency_ManyConcurrentBets() public {
        uint256 stake = 0.01 ether;
        uint256 maxPayoutPerBet = treasury.quotePayout(stake * 6);

        // Open 10 concurrent dice bets across 3 players.
        uint256[] memory reqIds = new uint256[](10);
        for (uint256 i; i < 10; ++i) {
            address player = i % 3 == 0 ? alice : (i % 3 == 1 ? bob : carol);
            vm.prank(player);
            reqIds[i] = diceGame.rollDice{value: stake}(uint8((i % 6) + 1));
        }

        // Invariant: locked == 10 * maxPayoutPerBet, and treasury still solvent.
        assertEq(treasury.lockedLiquidity(NATIVE), 10 * maxPayoutPerBet);
        assertGe(
            address(treasury).balance,
            treasury.lockedLiquidity(NATIVE),
            "treasury must be solvent under load"
        );

        // Fulfil all 10 with pseudo-random words.
        for (uint256 i; i < 10; ++i) {
            uint256[] memory w = new uint256[](1);
            w[0] = uint256(keccak256(abi.encode("seed", i)));
            coordinator.fulfillWithWords(reqIds[i], w);
        }

        assertEq(treasury.lockedLiquidity(NATIVE), 0, "all locks released");
        assertGe(address(treasury).balance, 0, "still solvent");
    }

    /*//////////////////////////////////////////////////////////////
                  10. VRF RETRY AFTER COORDINATOR TIMEOUT
                  (using Lottery, which routes a new requestId
                   back into its internal mapping)
    //////////////////////////////////////////////////////////////*/

    function test_E2E_VRF_RetryAfterTimeout_Lottery() public {
        uint256 ticketPrice = 0.01 ether;
        uint256 roundId = lottery.createRound(NATIVE, ticketPrice, 0, 1 hours, 1);
        _lotBuy(alice, roundId, ticketPrice, 1);

        vm.warp(_roundEndTime(roundId) + 1);
        lottery.triggerDraw(roundId);
        _assertStatus(roundId, Lottery.RoundStatus.DRAWING);

        uint256 staleReq = _roundRequestId(roundId);

        // Cannot retry before Lottery's vrfTimeout window has elapsed.
        vm.expectRevert(bytes("VRF timeout not reached"));
        lottery.retryDraw(roundId);

        // Warp past Lottery.vrfTimeout (default 24h).
        vm.warp(block.timestamp + lottery.vrfTimeout() + 1);

        lottery.retryDraw(roundId);
        assertGt(_roundRequestId(roundId), staleReq, "fresh requestId issued");
        assertEq(
            uint256(vrfConsumer.getRequestState(staleReq)),
            uint256(IVRFConsumer.RequestState.RETRIED),
            "stale request marked RETRIED"
        );

        // Fulfilling the new request lets the draw complete.
        coordinator.fulfillWithSeed(_roundRequestId(roundId), 42);
        _assertStatus(roundId, Lottery.RoundStatus.COMPLETED);

        // Alice (the only ticket holder) is the winner.
        address[] memory winners = lottery.getWinners(roundId);
        assertEq(winners.length, 1);
        assertEq(winners[0], alice);
    }
}
