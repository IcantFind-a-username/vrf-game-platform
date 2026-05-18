// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRandomnessConsumer} from "../../src/interfaces/IRandomnessConsumer.sol";
import {IVRFConsumer} from "../../src/interfaces/IVRFConsumer.sol";

/**
 * @title MockGame
 * @notice Stand-in for a real game contract (Member 2/3 deliverable). It is the
 *         reference example of how to integrate with {VRFConsumer}: request
 *         randomness, then receive it via {onRandomnessFulfilled}.
 */
contract MockGame is IRandomnessConsumer {
    IVRFConsumer public immutable vrf;

    /// @notice Forces {onRandomnessFulfilled} to revert (tests the catch path).
    bool public shouldRevertOnCallback;

    mapping(uint256 => uint256[]) public receivedWords;
    mapping(uint256 => bool) public fulfilled;
    uint256 public lastRequestId;

    error MockGame__OnlyVRF();
    error MockGame__ForcedRevert();

    constructor(address vrf_) {
        vrf = IVRFConsumer(vrf_);
    }

    function setShouldRevert(bool v) external {
        shouldRevertOnCallback = v;
    }

    /// @notice Example: kick off a randomness request.
    function play(uint32 numWords) external returns (uint256 requestId) {
        requestId = vrf.requestRandomness(numWords);
        lastRequestId = requestId;
    }

    /// @notice Example: retry a stuck request.
    function retry(uint256 requestId) external returns (uint256 newRequestId) {
        newRequestId = vrf.retryRequest(requestId);
        lastRequestId = newRequestId;
    }

    /// @inheritdoc IRandomnessConsumer
    function onRandomnessFulfilled(uint256 requestId, uint256[] calldata randomWords)
        external
        override
    {
        // A real game MUST gate this on the trusted VRF infrastructure address.
        if (msg.sender != address(vrf)) revert MockGame__OnlyVRF();
        if (shouldRevertOnCallback) revert MockGame__ForcedRevert();

        receivedWords[requestId] = randomWords;
        fulfilled[requestId] = true;
    }

    function getReceivedWords(uint256 requestId) external view returns (uint256[] memory) {
        return receivedWords[requestId];
    }
}
