// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IReferral {
    function recordTicketPurchase(
        address buyer,
        uint256 totalCost,
        bytes32 referralCode
    ) external returns (uint256 commission);
}
