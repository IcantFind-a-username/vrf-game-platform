// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IVRFConsumer
 * @notice The surface that game contracts call to obtain verifiable randomness.
 * @dev    Games depend ONLY on this interface, never on the concrete contract.
 */
interface IVRFConsumer {
    enum RequestState {
        NONE,
        PENDING,
        FULFILLED,
        RETRIED
    }

    /**
     * @notice Request `numWords` verifiable random words.
     * @dev    Caller MUST be an authorised consumer.
     * @param  numWords Number of random words required (1..MAX_NUM_WORDS).
     * @return requestId Identifier used to correlate the later callback.
     */
    function requestRandomness(uint32 numWords) external returns (uint256 requestId);

    /**
     * @notice Re-submit a request that never fulfilled within the timeout.
     * @param  requestId The stale (still PENDING) request id.
     * @return newRequestId The fresh request id that supersedes `requestId`.
     */
    function retryRequest(uint256 requestId) external returns (uint256 newRequestId);

    /// @notice Current lifecycle state of `requestId`.
    function getRequestState(uint256 requestId) external view returns (RequestState);

    /// @notice Random words for a fulfilled `requestId` (empty if not yet fulfilled).
    function getRandomWords(uint256 requestId) external view returns (uint256[] memory);

    /// @notice True once `requestId` has received its random words.
    function isFulfilled(uint256 requestId) external view returns (bool);
}
