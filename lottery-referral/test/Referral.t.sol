// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Referral} from "../contracts/src/Referral.sol";

contract ReferralTest is Test {
    Referral public referral;

    address public owner = address(0x1);
    address public referrer1 = address(0x2);
    address public referrer2 = address(0x3);
    address public player = address(0x4);
    address public lottery = address(0x5);

    event ReferralRegistered(address indexed referrer, bytes32 code);
    event CommissionEarned(
        address indexed referrer,
        address indexed buyer,
        address token,
        uint256 ticketPrice,
        uint256 commission
    );
    event CommissionClaimed(address indexed referrer, address indexed token, uint256 amount);

    function setUp() public {
        vm.startPrank(owner);
        referral = new Referral();
        vm.stopPrank();

        vm.deal(lottery, 100 ether);
        vm.deal(referrer1, 100 ether);
        vm.deal(referrer2, 100 ether);
        vm.deal(player, 100 ether);
        vm.deal(address(referral), 100 ether);
    }

    // ========== Constructor & Admin ==========

    function test_constructor() public view {
        assertEq(referral.owner(), owner);
        assertEq(referral.commissionBps(), 100); // 1%
    }

    function test_setLottery() public {
        vm.startPrank(owner);
        referral.setLottery(lottery);
        assertEq(referral.lottery(), lottery);
        vm.stopPrank();
    }

    function test_setLottery_reverts_nonOwner() public {
        vm.startPrank(player);
        vm.expectRevert();
        referral.setLottery(lottery);
        vm.stopPrank();
    }

    function test_setCommissionBps() public {
        vm.startPrank(owner);
        referral.setCommissionBps(500); // 5%
        assertEq(referral.commissionBps(), 500);
        vm.stopPrank();
    }

    function test_setCommissionBps_reverts_tooHigh() public {
        vm.startPrank(owner);
        vm.expectRevert("Max 20%");
        referral.setCommissionBps(2001); // > 20%
        vm.stopPrank();
    }

    // ========== Register Referral ==========

    function test_registerReferral() public {
        bytes32 code = bytes32(uint256(0xABCD1234));
        vm.startPrank(referrer1);
        vm.expectEmit(true, true, false, false);
        emit ReferralRegistered(referrer1, code);
        referral.registerReferral(code);
        vm.stopPrank();

        assertEq(referral.referralCodes(referrer1), code);
        assertEq(referral.codeToReferrer(code), referrer1);
    }

    function test_registerReferral_reverts_duplicateCode() public {
        bytes32 code = bytes32(uint256(0xABCD));
        vm.startPrank(referrer1);
        referral.registerReferral(code);
        vm.stopPrank();

        vm.startPrank(referrer2);
        vm.expectRevert("Code already taken");
        referral.registerReferral(code);
        vm.stopPrank();
    }

    function test_registerReferral_reverts_duplicateRegistrant() public {
        vm.startPrank(referrer1);
        referral.registerReferral(bytes32(uint256(0xAAAA)));
        vm.expectRevert("Already registered");
        referral.registerReferral(bytes32(uint256(0xBBBB)));
        vm.stopPrank();
    }

    function test_registerReferral_reverts_emptyCode() public {
        vm.startPrank(referrer1);
        vm.expectRevert("Code cannot be empty");
        referral.registerReferral(bytes32(0));
        vm.stopPrank();
    }

    // ========== Record Ticket Purchase ==========

    function test_recordTicketPurchase() public {
        vm.startPrank(owner);
        referral.setLottery(lottery);
        vm.stopPrank();

        bytes32 code = bytes32(uint256(0xCAFE));
        vm.startPrank(referrer1);
        referral.registerReferral(code);
        vm.stopPrank();

        uint256 ticketPrice = 0.01 ether;
        uint256 expectedCommission = (ticketPrice * referral.commissionBps()) / 10_000;

        vm.startPrank(lottery);
        vm.expectEmit(true, true, true, true);
        emit CommissionEarned(referrer1, player, address(0), ticketPrice, expectedCommission);
        uint256 commission = referral.recordTicketPurchase(player, ticketPrice, code);
        vm.stopPrank();

        assertEq(commission, expectedCommission);
        assertEq(referral.referredBy(player), referrer1);
        assertEq(referral.pendingCommissions(referrer1, address(0)), expectedCommission);
        assertEq(referral.totalEarned(referrer1, address(0)), expectedCommission);
    }

    function test_recordTicketPurchase_secondReferralIgnored() public {
        vm.startPrank(owner);
        referral.setLottery(lottery);
        vm.stopPrank();

        bytes32 code1 = bytes32(uint256(0xCAFE));
        bytes32 code2 = bytes32(uint256(0xBABE));
        vm.startPrank(referrer1);
        referral.registerReferral(code1);
        vm.stopPrank();
        vm.startPrank(referrer2);
        referral.registerReferral(code2);
        vm.stopPrank();

        vm.startPrank(lottery);
        referral.recordTicketPurchase(player, 0.01 ether, code1); // First referral
        uint256 commission = referral.recordTicketPurchase(player, 0.01 ether, code2); // Second, ignored
        vm.stopPrank();

        assertEq(referral.referredBy(player), referrer1);
        // Second record should still earn commission for the original referrer
        assertTrue(commission > 0);
    }

    function test_recordTicketPurchase_reverts_notLottery() public {
        bytes32 code = bytes32(uint256(0xCAFE));
        vm.startPrank(referrer1);
        referral.registerReferral(code);
        vm.stopPrank();

        vm.startPrank(player);
        vm.expectRevert("Only lottery");
        referral.recordTicketPurchase(player, 0.01 ether, code);
        vm.stopPrank();
    }

    function test_recordTicketPurchase_zeroCode_returnsZero() public {
        vm.startPrank(owner);
        referral.setLottery(lottery);
        vm.stopPrank();

        vm.startPrank(lottery);
        uint256 commission = referral.recordTicketPurchase(player, 0.01 ether, bytes32(0));
        assertEq(commission, 0);
        vm.stopPrank();
    }

    function test_recordTicketPurchase_selfReferral_returnsZero() public {
        vm.startPrank(owner);
        referral.setLottery(lottery);
        vm.stopPrank();

        bytes32 code = bytes32(uint256(0xCAFE));
        vm.startPrank(referrer1);
        referral.registerReferral(code);
        vm.stopPrank();

        vm.startPrank(lottery);
        uint256 commission = referral.recordTicketPurchase(referrer1, 0.01 ether, code);
        assertEq(commission, 0);
        assertEq(referral.referredBy(referrer1), address(0));
        vm.stopPrank();
    }

    // ========== Claim Commission ==========

    function test_claimCommission() public {
        // Setup
        vm.startPrank(owner);
        referral.setLottery(lottery);
        vm.stopPrank();

        bytes32 code = bytes32(uint256(0xCAFE));
        vm.startPrank(referrer1);
        referral.registerReferral(code);
        vm.stopPrank();

        uint256 ticketPrice = 0.01 ether;
        vm.startPrank(lottery);
        uint256 commission = referral.recordTicketPurchase(player, ticketPrice, code);
        vm.stopPrank();

        uint256 balBefore = referrer1.balance;

        vm.startPrank(referrer1);
        vm.expectEmit(true, true, false, false);
        emit CommissionClaimed(referrer1, address(0), commission);
        referral.claimCommission(address(0));
        vm.stopPrank();

        assertEq(referrer1.balance, balBefore + commission);
        assertEq(referral.pendingCommissions(referrer1, address(0)), 0);
        assertEq(referral.totalClaimed(referrer1, address(0)), commission);
    }

    function test_claimCommission_reverts_noPending() public {
        vm.startPrank(referrer1);
        vm.expectRevert("No pending commission");
        referral.claimCommission(address(0));
        vm.stopPrank();
    }

    function test_claimCommission_multiplePurchases() public {
        vm.startPrank(owner);
        referral.setLottery(lottery);
        vm.stopPrank();

        bytes32 code = bytes32(uint256(0xCAFE));
        vm.startPrank(referrer1);
        referral.registerReferral(code);
        vm.stopPrank();

        vm.startPrank(lottery);
        uint256 c1 = referral.recordTicketPurchase(player, 0.01 ether, code);
        uint256 c2 = referral.recordTicketPurchase(player, 0.02 ether, code);
        uint256 totalCommission = c1 + c2;
        vm.stopPrank();

        assertEq(referral.pendingCommissions(referrer1, address(0)), totalCommission);

        uint256 balBefore = referrer1.balance;
        vm.startPrank(referrer1);
        referral.claimCommission(address(0));
        vm.stopPrank();

        assertEq(referrer1.balance, balBefore + totalCommission);
        assertEq(referral.pendingCommissions(referrer1, address(0)), 0);
    }

    // ========== View Functions ==========

    function test_view_getReferralCode() public {
        bytes32 code = bytes32(uint256(0xDEAD));
        vm.startPrank(referrer1);
        referral.registerReferral(code);
        vm.stopPrank();

        assertEq(referral.getReferralCode(referrer1), code);
    }

    function test_view_getReferrer() public {
        bytes32 code = bytes32(uint256(0xBEEF));
        vm.startPrank(referrer1);
        referral.registerReferral(code);
        vm.stopPrank();

        assertEq(referral.getReferrer(code), referrer1);
        assertEq(referral.getReferrer(bytes32(uint256(0xDEAD))), address(0));
    }

    function test_view_getPendingCommission() public {
        vm.startPrank(owner);
        referral.setLottery(lottery);
        vm.stopPrank();

        bytes32 code = bytes32(uint256(0xCAFE));
        vm.startPrank(referrer1);
        referral.registerReferral(code);
        vm.stopPrank();

        vm.startPrank(lottery);
        referral.recordTicketPurchase(player, 0.01 ether, code);
        vm.stopPrank();

        assertGt(referral.getPendingCommission(referrer1, address(0)), 0);
        assertEq(referral.getPendingCommission(player, address(0)), 0);
    }
}
