// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IRandomnessConsumer
 * @notice Interface that every game contract (dice, lottery, ...) MUST implement
 *         in order to receive verifiable randomness from {VRFConsumer}.
 * @dev    Integration contract for Members 2 & 3:
 *         1. Inherit this interface in your game contract.
 *         2. Implement {onRandomnessFulfilled}.
 *         3. Inside it, REQUIRE that `msg.sender == address(vrfConsumer)` so that
 *            only the trusted infrastructure contract can deliver outcomes.
 */
interface IRandomnessConsumer {
    /**
     * @notice Called by {VRFConsumer} once Chainlink VRF returns the random words.
     * @param requestId   The request id originally returned by `requestRandomness`.
     * @param randomWords The verifiable random words.
     */
    function onRandomnessFulfilled(uint256 requestId, uint256[] calldata randomWords) external;
}
