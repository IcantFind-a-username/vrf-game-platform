// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VRFConsumer} from "../src/VRFConsumer.sol";
import {IVRFConsumer} from "../src/interfaces/IVRFConsumer.sol";
import {MockVRFCoordinator} from "./mocks/MockVRFCoordinator.sol";
import {MockGame} from "./mocks/MockGame.sol";

/// @notice Unit, integration and fuzz tests for {VRFConsumer}.
contract VRFConsumerTest is Test {
    VRFConsumer internal vrf;
    MockVRFCoordinator internal coordinator;
    MockGame internal game;

    bytes32 internal constant KEY_HASH = bytes32(uint256(0xABCD));
    uint256 internal constant SUB_ID = 7;
    uint32 internal constant CALLBACK_GAS = 200_000;

    address internal stranger = makeAddr("stranger");

    function setUp() public {
        coordinator = new MockVRFCoordinator();
        vrf = new VRFConsumer(address(coordinator), KEY_HASH, SUB_ID, CALLBACK_GAS);
        game = new MockGame(address(vrf));
        // owner (this contract) authorises the game as a consumer.
        vrf.setConsumerAuthorization(address(game), true);
    }

    /*//////////////////////////////////////////////////////////////
                            AUTHORIZATION
    //////////////////////////////////////////////////////////////*/

    function test_RequestRandomness_RevertsForUnauthorizedConsumer() public {
        vm.prank(stranger);
        vm.expectRevert(VRFConsumer.VRFConsumer__NotAuthorized.selector);
        vrf.requestRandomness(1);
    }

    function test_SetConsumerAuthorization_OnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        vrf.setConsumerAuthorization(stranger, true);
    }

    function test_RevokedConsumerCannotRequest() public {
        vrf.setConsumerAuthorization(address(game), false);
        vm.prank(address(game));
        vm.expectRevert(VRFConsumer.VRFConsumer__NotAuthorized.selector);
        vrf.requestRandomness(1);
    }

    /*//////////////////////////////////////////////////////////////
                          REQUEST + FULFIL
    //////////////////////////////////////////////////////////////*/

    function test_RequestRandomness_CreatesPendingRequest() public {
        uint256 requestId = game.play(2);

        VRFConsumer.RandomnessRequest memory req = vrf.getRequest(requestId);
        assertEq(req.consumer, address(game));
        assertEq(req.numWords, 2);
        assertEq(uint256(req.state), uint256(IVRFConsumer.RequestState.PENDING));
        assertFalse(req.callbackFailed);
    }

    function test_RequestRandomness_RevertsOnInvalidNumWords() public {
        vm.startPrank(address(game));
        vm.expectRevert(VRFConsumer.VRFConsumer__InvalidNumWords.selector);
        vrf.requestRandomness(0);
        vm.expectRevert(VRFConsumer.VRFConsumer__InvalidNumWords.selector);
        vrf.requestRandomness(vrf.MAX_NUM_WORDS() + 1);
        vm.stopPrank();
    }

    function test_Fulfilment_ForwardsWordsToGame() public {
        uint256 requestId = game.play(3);

        coordinator.fulfillWithSeed(requestId, 42);

        assertTrue(vrf.isFulfilled(requestId));
        assertTrue(game.fulfilled(requestId));

        uint256[] memory delivered = game.getReceivedWords(requestId);
        uint256[] memory stored = vrf.getRandomWords(requestId);
        assertEq(delivered.length, 3);
        assertEq(stored.length, 3);
        assertEq(delivered[0], stored[0]);
    }

    function test_Fulfilment_ContainsRevertingGame() public {
        uint256 requestId = game.play(1);
        game.setShouldRevert(true);

        // The callback must NOT bubble the game's revert.
        coordinator.fulfillWithSeed(requestId, 1);

        VRFConsumer.RandomnessRequest memory req = vrf.getRequest(requestId);
        assertEq(uint256(req.state), uint256(IVRFConsumer.RequestState.FULFILLED));
        assertTrue(req.callbackFailed);
        // Words remain available for pull-based recovery.
        assertEq(vrf.getRandomWords(requestId).length, 1);
        assertFalse(game.fulfilled(requestId));
    }

    /*//////////////////////////////////////////////////////////////
                              RETRY LOGIC
    //////////////////////////////////////////////////////////////*/

    function test_Retry_RevertsBeforeTimeout() public {
        uint256 requestId = game.play(1);
        vm.prank(address(game));
        vm.expectRevert(VRFConsumer.VRFConsumer__RetryTooEarly.selector);
        vrf.retryRequest(requestId);
    }

    function test_Retry_RevertsForNonOwnerNonConsumer() public {
        uint256 requestId = game.play(1);
        vm.warp(block.timestamp + vrf.requestTimeout() + 1);
        vm.prank(stranger);
        vm.expectRevert(VRFConsumer.VRFConsumer__NotRequestOwner.selector);
        vrf.retryRequest(requestId);
    }

    function test_Retry_AfterTimeoutSucceeds() public {
        uint256 staleId = game.play(2);
        vm.warp(block.timestamp + vrf.requestTimeout() + 1);

        uint256 newId = game.retry(staleId);

        assertGt(newId, staleId);
        assertEq(vrf.retryOf(newId), staleId);
        assertEq(
            uint256(vrf.getRequestState(staleId)),
            uint256(IVRFConsumer.RequestState.RETRIED)
        );
        assertEq(
            uint256(vrf.getRequestState(newId)),
            uint256(IVRFConsumer.RequestState.PENDING)
        );

        // The fresh request fulfils normally.
        coordinator.fulfillWithSeed(newId, 99);
        assertTrue(game.fulfilled(newId));
    }

    function test_Retry_OwnerCanRetry() public {
        uint256 staleId = game.play(1);
        vm.warp(block.timestamp + vrf.requestTimeout() + 1);
        // owner == this test contract
        uint256 newId = vrf.retryRequest(staleId);
        assertEq(vrf.retryOf(newId), staleId);
    }

    function test_LateFulfilmentOfRetriedRequest_DoesNotDoubleDeliver() public {
        uint256 staleId = game.play(1);
        vm.warp(block.timestamp + vrf.requestTimeout() + 1);
        uint256 newId = game.retry(staleId);

        // The original (retired) request fulfils late: words are recorded but
        // the game is NOT called back again.
        coordinator.fulfillWithSeed(staleId, 5);
        assertFalse(game.fulfilled(staleId));
        assertEq(vrf.getRandomWords(staleId).length, 1);
        assertEq(
            uint256(vrf.getRequestState(staleId)),
            uint256(IVRFConsumer.RequestState.RETRIED)
        );

        // The fresh request still delivers exactly once.
        coordinator.fulfillWithSeed(newId, 6);
        assertTrue(game.fulfilled(newId));
    }

    function test_Retry_RevertsIfRequestAlreadyFulfilled() public {
        uint256 requestId = game.play(1);
        coordinator.fulfillWithSeed(requestId, 1);
        vm.warp(block.timestamp + vrf.requestTimeout() + 1);
        vm.prank(address(game));
        vm.expectRevert(VRFConsumer.VRFConsumer__RequestNotPending.selector);
        vrf.retryRequest(requestId);
    }

    /*//////////////////////////////////////////////////////////////
                            CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    function test_OnlyOwnerCanUpdateConfig() public {
        vm.startPrank(stranger);
        vm.expectRevert();
        vrf.setKeyHash(bytes32(uint256(1)));
        vm.expectRevert();
        vrf.setSubscriptionId(123);
        vm.expectRevert();
        vrf.setCallbackGasLimit(50_000);
        vm.expectRevert();
        vrf.setNativePayment(true);
        vm.stopPrank();
    }

    function test_SetRequestConfirmations_RevertsBelowMinimum() public {
        vm.expectRevert(VRFConsumer.VRFConsumer__InvalidConfirmations.selector);
        vrf.setRequestConfirmations(2);
    }

    function test_ConfigUpdatesPersist() public {
        vrf.setKeyHash(bytes32(uint256(0xFEED)));
        vrf.setSubscriptionId(555);
        vrf.setCallbackGasLimit(321_000);
        vrf.setNativePayment(true);
        vrf.setRequestConfirmations(5);

        assertEq(vrf.keyHash(), bytes32(uint256(0xFEED)));
        assertEq(vrf.subscriptionId(), 555);
        assertEq(vrf.callbackGasLimit(), 321_000);
        assertTrue(vrf.nativePayment());
        assertEq(vrf.requestConfirmations(), 5);
    }

    /*//////////////////////////////////////////////////////////////
                                FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_RequestAndFulfilAnyValidWordCount(uint32 numWords, uint256 seed) public {
        numWords = uint32(bound(numWords, 1, vrf.MAX_NUM_WORDS()));
        uint256 requestId = game.play(numWords);
        coordinator.fulfillWithSeed(requestId, seed);

        assertTrue(game.fulfilled(requestId));
        assertEq(game.getReceivedWords(requestId).length, numWords);
    }

    function testFuzz_IsRetryableTracksTimeout(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, 30 days);
        uint256 requestId = game.play(1);
        uint256 timeout = vrf.requestTimeout();
        vm.warp(block.timestamp + elapsed);
        assertEq(vrf.isRetryable(requestId), elapsed >= timeout);
    }
}
