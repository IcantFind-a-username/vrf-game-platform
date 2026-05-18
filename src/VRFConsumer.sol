// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

import {IVRFConsumer} from "./interfaces/IVRFConsumer.sol";
import {IRandomnessConsumer} from "./interfaces/IRandomnessConsumer.sol";

/**
 * @title VRFConsumer
 * @author SC6107 Group Project - Member 1 (VRF + Treasury Infrastructure)
 * @notice Shared randomness provider for the on-chain game platform. It is the
 *         single point of integration with Chainlink VRF v2.5: it owns the VRF
 *         configuration, routes verifiable random words back to the requesting
 *         game contract, and provides a timeout-based retry path for the rare
 *         case where a subscription runs dry and a request is never fulfilled.
 *
 * @dev    Design notes:
 *         - {VRFConsumerBaseV2Plus} already provides `onlyOwner` (via
 *           ConfirmedOwner) and the upgradable `setCoordinator` hook, so this
 *           contract intentionally does NOT inherit OpenZeppelin `Ownable`.
 *         - The contract must be registered as a consumer on the VRF v2.5
 *           subscription off-chain (vrf.chain.link) or via the coordinator's
 *           `addConsumer`. See `script/Deploy.s.sol` and the README.
 *         - The fulfilment callback to the game is wrapped in try/catch so a
 *           buggy game cannot brick the VRF callback; the words are always
 *           stored for pull-based recovery via {getRandomWords}.
 *
 *         Course topics demonstrated: oracle integration, callback pattern,
 *         request-response timing, failure handling, access control.
 */
contract VRFConsumer is VRFConsumerBaseV2Plus, IVRFConsumer {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error VRFConsumer__NotAuthorized(address caller);
    error VRFConsumer__InvalidNumWords(uint32 numWords);
    error VRFConsumer__RequestNotPending(uint256 requestId);
    error VRFConsumer__RetryTooEarly(uint256 requestId, uint256 readyAt);
    error VRFConsumer__NotRequestOwner(uint256 requestId, address caller);
    error VRFConsumer__ZeroAddress();
    error VRFConsumer__InvalidConfirmations(uint16 confirmations);

    /*//////////////////////////////////////////////////////////////
                            DATA STRUCTURES
    //////////////////////////////////////////////////////////////*/

    /// @notice On-chain record of a randomness request.
    struct RandomnessRequest {
        address consumer; // game contract that requested (and will be called back)
        uint64 requestedAt; // block timestamp of submission (for retry timeout)
        uint32 numWords; // number of words requested
        RequestState state; // lifecycle state
        bool callbackFailed; // true if the consumer callback reverted
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Hard cap on words per request, well below the coordinator limit.
    uint32 public constant MAX_NUM_WORDS = 10;

    /// @notice Lower bound for `requestConfirmations` enforced by the coordinator.
    uint16 public constant MIN_REQUEST_CONFIRMATIONS = 3;

    /*//////////////////////////////////////////////////////////////
                          VRF CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Gas lane key hash; the max gas price the subscription will pay.
    bytes32 public keyHash;

    /// @notice VRF v2.5 subscription id (note: uint256, unlike v2's uint64).
    uint256 public subscriptionId;

    /// @notice Gas forwarded to {fulfillRandomWords}; sized for the game callback.
    uint32 public callbackGasLimit;

    /// @notice Block confirmations the oracle waits before responding.
    uint16 public requestConfirmations;

    /// @notice If true, requests are paid from the subscription's native balance;
    ///         if false, from its LINK balance.
    bool public nativePayment;

    /// @notice Seconds after which an unfulfilled request becomes retryable.
    uint256 public requestTimeout;

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Game contracts permitted to request randomness.
    mapping(address => bool) public authorizedConsumers;

    /// @notice requestId => request record.
    mapping(uint256 => RandomnessRequest) private _requests;

    /// @notice requestId => delivered random words (also kept for pull recovery).
    mapping(uint256 => uint256[]) private _randomWords;

    /// @notice newRequestId => the stale requestId it superseded (0 if none).
    mapping(uint256 => uint256) public retryOf;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ConsumerAuthorizationSet(address indexed consumer, bool authorized);
    event RandomnessRequested(uint256 indexed requestId, address indexed consumer, uint32 numWords);
    event RandomnessFulfilled(uint256 indexed requestId, address indexed consumer);
    event ConsumerCallbackFailed(uint256 indexed requestId, address indexed consumer);
    event RequestRetried(uint256 indexed staleRequestId, uint256 indexed newRequestId);
    event UnexpectedFulfillment(uint256 indexed requestId);
    event VrfConfigUpdated();

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAuthorized() {
        if (!authorizedConsumers[msg.sender]) revert VRFConsumer__NotAuthorized(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param vrfCoordinator    Address of the VRF v2.5 coordinator for the network.
     * @param keyHash_          Gas lane key hash for the network.
     * @param subscriptionId_   Funded VRF v2.5 subscription id.
     * @param callbackGasLimit_ Gas budget for the fulfilment callback.
     */
    constructor(
        address vrfCoordinator,
        bytes32 keyHash_,
        uint256 subscriptionId_,
        uint32 callbackGasLimit_
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        keyHash = keyHash_;
        subscriptionId = subscriptionId_;
        callbackGasLimit = callbackGasLimit_;
        requestConfirmations = MIN_REQUEST_CONFIRMATIONS;
        nativePayment = false; // default: pay in LINK
        requestTimeout = 1 hours;
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN - CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorise / revoke a game contract as a randomness consumer.
    function setConsumerAuthorization(address consumer, bool authorized) external onlyOwner {
        if (consumer == address(0)) revert VRFConsumer__ZeroAddress();
        authorizedConsumers[consumer] = authorized;
        emit ConsumerAuthorizationSet(consumer, authorized);
    }

    /// @notice Update the gas lane key hash.
    function setKeyHash(bytes32 keyHash_) external onlyOwner {
        keyHash = keyHash_;
        emit VrfConfigUpdated();
    }

    /// @notice Point the contract at a new (funded) subscription id.
    function setSubscriptionId(uint256 subscriptionId_) external onlyOwner {
        subscriptionId = subscriptionId_;
        emit VrfConfigUpdated();
    }

    /// @notice Resize the callback gas budget (raise it if game callbacks grow).
    function setCallbackGasLimit(uint32 callbackGasLimit_) external onlyOwner {
        callbackGasLimit = callbackGasLimit_;
        emit VrfConfigUpdated();
    }

    /// @notice Update the number of block confirmations requested from the oracle.
    function setRequestConfirmations(uint16 requestConfirmations_) external onlyOwner {
        if (requestConfirmations_ < MIN_REQUEST_CONFIRMATIONS) {
            revert VRFConsumer__InvalidConfirmations(requestConfirmations_);
        }
        requestConfirmations = requestConfirmations_;
        emit VrfConfigUpdated();
    }

    /// @notice Toggle paying for requests in native tokens (true) or LINK (false).
    function setNativePayment(bool nativePayment_) external onlyOwner {
        nativePayment = nativePayment_;
        emit VrfConfigUpdated();
    }

    /// @notice Update the retry timeout (seconds before a stale request is retryable).
    function setRequestTimeout(uint256 requestTimeout_) external onlyOwner {
        requestTimeout = requestTimeout_;
        emit VrfConfigUpdated();
    }

    /*//////////////////////////////////////////////////////////////
                       RANDOMNESS REQUEST FLOW
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVRFConsumer
    function requestRandomness(uint32 numWords)
        external
        override
        onlyAuthorized
        returns (uint256 requestId)
    {
        if (numWords == 0 || numWords > MAX_NUM_WORDS) {
            revert VRFConsumer__InvalidNumWords(numWords);
        }
        requestId = _submitAndRecord(msg.sender, numWords);
    }

    /// @inheritdoc IVRFConsumer
    function retryRequest(uint256 requestId)
        external
        override
        returns (uint256 newRequestId)
    {
        RandomnessRequest storage req = _requests[requestId];

        if (req.state != RequestState.PENDING) revert VRFConsumer__RequestNotPending(requestId);

        // Only the original requesting game (or the owner) can retry.
        if (msg.sender != req.consumer && msg.sender != owner()) {
            revert VRFConsumer__NotRequestOwner(requestId, msg.sender);
        }

        uint256 readyAt = uint256(req.requestedAt) + requestTimeout;
        if (block.timestamp < readyAt) revert VRFConsumer__RetryTooEarly(requestId, readyAt);

        // Mark the stale request as superseded and submit a fresh one.
        req.state = RequestState.RETRIED;
        newRequestId = _submitAndRecord(req.consumer, req.numWords);
        retryOf[newRequestId] = requestId;

        emit RequestRetried(requestId, newRequestId);
    }

    /**
     * @notice Chainlink VRF callback. Stores the words and forwards them to the
     *         requesting game. A reverting game is contained so the callback
     *         itself always succeeds.
     * @dev    Overrides {VRFConsumerBaseV2Plus}; only callable by the coordinator.
     */
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords)
        internal
        override
    {
        RandomnessRequest storage req = _requests[requestId];

        // Always persist the words first (recovery + auditability).
        _randomWords[requestId] = randomWords;

        // A late fulfilment of an already-retried/unknown request: record only.
        if (req.state != RequestState.PENDING) {
            emit UnexpectedFulfillment(requestId);
            return;
        }

        req.state = RequestState.FULFILLED;
        emit RandomnessFulfilled(requestId, req.consumer);

        // Forward to the game, but never let a buggy game brick the callback.
        try IRandomnessConsumer(req.consumer).onRandomnessFulfilled(requestId, randomWords) {
            // delivered successfully
        } catch {
            req.callbackFailed = true;
            emit ConsumerCallbackFailed(requestId, req.consumer);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Submits a VRF v2.5 request and records it locally.
    function _submitAndRecord(address consumer, uint32 numWords)
        internal
        returns (uint256 requestId)
    {
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: nativePayment})
                )
            })
        );

        _requests[requestId] = RandomnessRequest({
            consumer: consumer,
            requestedAt: uint64(block.timestamp),
            numWords: numWords,
            state: RequestState.PENDING,
            callbackFailed: false
        });

        emit RandomnessRequested(requestId, consumer, numWords);
    }

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Full request record for `requestId`.
    function getRequest(uint256 requestId) external view returns (RandomnessRequest memory) {
        return _requests[requestId];
    }

    /// @inheritdoc IVRFConsumer
    function getRequestState(uint256 requestId) external view override returns (RequestState) {
        return _requests[requestId].state;
    }

    /// @inheritdoc IVRFConsumer
    function getRandomWords(uint256 requestId)
        external
        view
        override
        returns (uint256[] memory)
    {
        return _randomWords[requestId];
    }

    /// @inheritdoc IVRFConsumer
    function isFulfilled(uint256 requestId) external view override returns (bool) {
        return _requests[requestId].state == RequestState.FULFILLED;
    }

    /// @notice True once `requestId` may be retried (pending and past timeout).
    function isRetryable(uint256 requestId) external view returns (bool) {
        RandomnessRequest storage req = _requests[requestId];
        return req.state == RequestState.PENDING
            && block.timestamp >= uint256(req.requestedAt) + requestTimeout;
    }
}
