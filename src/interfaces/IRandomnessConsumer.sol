// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IRandomnessConsumer
 * @author SC6107 Group Project - Member 1 (VRF + Treasury Infrastructure)
 * @notice Interface that every game contract (dice, lottery, ...) MUST implement
 *         in order to receive verifiable randomness from {VRFConsumer}.
 * @dev    Integration contract for Members 2 & 3:
 *         1. Inherit this interface in your game contract.
 *         2. Implement {onRandomnessFulfilled}.
 *         3. Inside it, REQUIRE that `msg.sender == address(vrfConsumer)` so that
 *            only the trusted infrastructure contract can deliver outcomes.
 *         4. Keep the function body LIGHT - it runs inside the VRF callback and
 *            is bounded by `callbackGasLimit`. Do storage writes / payouts here,
 *            but avoid unbounded loops or heavy external calls.
 */
interface IRandomnessConsumer {
    /**
     * @notice Called by {VRFConsumer} once Chainlink VRF returns the random words.
     * @param requestId   The request id originally returned by `requestRandomness`.
     * @param randomWords The verifiable random words. Use modulo to map into ranges,
     *                    e.g. `dieResult = (randomWords[0] % 6) + 1`.
     */
    function onRandomnessFulfilled(uint256 requestId, uint256[] calldata randomWords) external;
}
