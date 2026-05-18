// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";

/**
 * @title MockVRFCoordinator
 * @notice Minimal stand-in for the Chainlink VRF v2.5 coordinator, used for local
 *         unit/fuzz tests. It implements only the `requestRandomWords` selector
 *         that {VRFConsumerBaseV2Plus} calls, plus test helpers that simulate the
 *         oracle delivering (or never delivering) random words.
 * @dev    NOT for production. The consumer stores the coordinator as
 *         `IVRFCoordinatorV2Plus`, but only the `requestRandomWords` selector is
 *         exercised at runtime, so a full interface implementation is unnecessary.
 */
contract MockVRFCoordinator {
    uint256 public lastRequestId;
    mapping(uint256 => address) public requesterOf;
    mapping(uint256 => uint32) public numWordsOf;

    event RandomWordsRequested(uint256 indexed requestId, address indexed requester);

    /// @notice Selector called by VRFConsumerBaseV2Plus when a consumer requests.
    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req)
        external
        returns (uint256 requestId)
    {
        requestId = ++lastRequestId;
        requesterOf[requestId] = msg.sender;
        numWordsOf[requestId] = req.numWords;
        emit RandomWordsRequested(requestId, msg.sender);
    }

    /// @notice Test helper: deliver caller-chosen random words for `requestId`.
    function fulfillWithWords(uint256 requestId, uint256[] calldata words) external {
        address consumer = requesterOf[requestId];
        VRFConsumerBaseV2Plus(consumer).rawFulfillRandomWords(requestId, words);
    }

    /// @notice Test helper: deliver pseudo-random words derived from a seed.
    function fulfillWithSeed(uint256 requestId, uint256 seed) external {
        address consumer = requesterOf[requestId];
        uint32 n = numWordsOf[requestId];
        uint256[] memory words = new uint256[](n);
        for (uint32 i; i < n; ++i) {
            words[i] = uint256(keccak256(abi.encode(seed, requestId, i)));
        }
        VRFConsumerBaseV2Plus(consumer).rawFulfillRandomWords(requestId, words);
    }
}
