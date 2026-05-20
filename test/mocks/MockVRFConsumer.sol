// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRandomnessConsumer} from "../../src/interfaces/IRandomnessConsumer.sol";

contract MockVRFConsumer {
    enum RequestState {
        NONE,
        PENDING,
        FULFILLED,
        RETRIED
    }

    uint256 private _nextRequestId = 1;

    struct RandomnessRequest {
        address consumer;
        RequestState state;
    }

    mapping(uint256 => RandomnessRequest) private _requests;
    mapping(uint256 => uint256[]) public randomWords;

    function requestRandomness(uint32) external returns (uint256 requestId) {
        requestId = _nextRequestId++;
        _requests[requestId] = RandomnessRequest(msg.sender, RequestState.PENDING);
        return requestId;
    }

    function retryRequest(uint256 requestId) external returns (uint256 newRequestId) {
        RandomnessRequest storage req = _requests[requestId];
        require(req.state == RequestState.PENDING, "Not pending");
        require(req.consumer == msg.sender, "Not request owner");

        req.state = RequestState.RETRIED;
        newRequestId = _nextRequestId++;
        _requests[newRequestId] = RandomnessRequest(msg.sender, RequestState.PENDING);
        return newRequestId;
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata _randomWords) external {
        RandomnessRequest storage req = _requests[requestId];
        require(req.consumer != address(0), "Unknown request");

        req.state = RequestState.FULFILLED;
        randomWords[requestId] = _randomWords;
        IRandomnessConsumer(req.consumer).onRandomnessFulfilled(requestId, _randomWords);
    }

    function getRequestState(uint256 requestId) external view returns (RequestState) {
        return _requests[requestId].state;
    }

    function getRandomWords(uint256 requestId) external view returns (uint256[] memory) {
        return randomWords[requestId];
    }

    function isFulfilled(uint256 requestId) external view returns (bool) {
        return _requests[requestId].state == RequestState.FULFILLED;
    }

    function getLastRequestId() external view returns (uint256) {
        return _nextRequestId - 1;
    }
}
