// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../src/Treasury.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Unit, integration and fuzz tests for {Treasury}.
contract TreasuryTest is Test {
    Treasury internal treasury;
    MockERC20 internal token;

    address internal constant NATIVE = address(0);
    uint16 internal constant HOUSE_EDGE_BPS = 250; // 2.5%

    address internal game = makeAddr("game");
    address internal player = makeAddr("player");
    address internal stranger = makeAddr("stranger");

    uint256 internal constant ERC20_MIN = 1e18;
    uint256 internal constant ERC20_MAX = 1_000e18;
    uint256 internal constant ETH_MIN = 0.001 ether;
    uint256 internal constant ETH_MAX = 1 ether;

    function setUp() public {
        treasury = new Treasury(address(this), HOUSE_EDGE_BPS);
        token = new MockERC20("Mock USD", "mUSD", 18);

        treasury.setGameAuthorization(game, true);
        treasury.setTokenConfig(address(token), true, ERC20_MIN, ERC20_MAX);
        treasury.setTokenConfig(NATIVE, true, ETH_MIN, ETH_MAX);

        // Fund the house bankroll.
        token.mint(address(this), 100_000e18);
        token.approve(address(treasury), type(uint256).max);
        treasury.depositLiquidity(address(token), 10_000e18);

        vm.deal(address(this), 100 ether);
        treasury.depositLiquidity{value: 50 ether}(NATIVE, 50 ether);

        // Fund the player.
        token.mint(player, 10_000e18);
        vm.prank(player);
        token.approve(address(treasury), type(uint256).max);
        vm.deal(player, 100 ether);
        vm.deal(game, 100 ether);
    }

    /// @dev Allow this contract (the Treasury owner) to receive ETH withdrawals.
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                            CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_RevertsOnExcessiveHouseEdge() public {
        vm.expectRevert(Treasury.Treasury__HouseEdgeTooHigh.selector);
        new Treasury(address(this), treasury.MAX_HOUSE_EDGE_BPS() + 1);
    }

    function test_SetTokenConfig_RevertsOnBadLimits() public {
        vm.expectRevert(Treasury.Treasury__InvalidBetLimits.selector);
        treasury.setTokenConfig(address(token), true, 10, 5);
    }

    function test_OnlyOwnerCanAdminister() public {
        vm.startPrank(stranger);
        vm.expectRevert();
        treasury.setGameAuthorization(stranger, true);
        vm.expectRevert();
        treasury.setHouseEdge(100);
        vm.expectRevert();
        treasury.pause();
        vm.stopPrank();
    }

    function test_QuotePayout_AppliesHouseEdge() public view {
        // 2.5% edge => 1000 gross becomes 975 net.
        assertEq(treasury.quotePayout(1000), 975);
    }

    /*//////////////////////////////////////////////////////////////
                            OPEN BET (ERC20)
    //////////////////////////////////////////////////////////////*/

    function test_OpenBet_ERC20_EscrowsStakeAndLocksPayout() public {
        uint256 stake = 100e18;
        uint256 maxPayout = 190e18;

        uint256 treasuryBefore = token.balanceOf(address(treasury));

        vm.prank(game);
        uint256 betId = treasury.openBet(player, address(token), stake, maxPayout);

        assertEq(token.balanceOf(address(treasury)), treasuryBefore + stake);
        assertEq(treasury.lockedLiquidity(address(token)), maxPayout);

        Treasury.Bet memory bet = treasury.getBet(betId);
        assertEq(bet.player, player);
        assertEq(bet.stake, stake);
        assertEq(bet.reservedPayout, maxPayout);
        assertEq(uint256(bet.status), uint256(Treasury.BetStatus.OPEN));
    }

    function test_OpenBet_RevertsForUnauthorizedGame() public {
        vm.prank(stranger);
        vm.expectRevert(Treasury.Treasury__NotAuthorizedGame.selector);
        treasury.openBet(player, address(token), 100e18, 190e18);
    }

    function test_OpenBet_RevertsOnUnsupportedToken() public {
        MockERC20 other = new MockERC20("Other", "OTH", 18);
        vm.prank(game);
        vm.expectRevert(Treasury.Treasury__TokenNotSupported.selector);
        treasury.openBet(player, address(other), 100e18, 190e18);
    }

    function test_OpenBet_RevertsOnStakeOutOfRange() public {
        vm.startPrank(game);
        vm.expectRevert(Treasury.Treasury__StakeOutOfRange.selector);
        treasury.openBet(player, address(token), ERC20_MIN - 1, 1e18);
        vm.expectRevert(Treasury.Treasury__StakeOutOfRange.selector);
        treasury.openBet(player, address(token), ERC20_MAX + 1, 1e18);
        vm.stopPrank();
    }

    function test_OpenBet_RevertsWhenPayoutExceedsLiquidity() public {
        // House holds 10_000e18; ask to reserve more than is available.
        vm.prank(game);
        vm.expectRevert(Treasury.Treasury__InsufficientLiquidity.selector);
        treasury.openBet(player, address(token), 100e18, 1_000_000e18);
    }

    /*//////////////////////////////////////////////////////////////
                            OPEN BET (ETH)
    //////////////////////////////////////////////////////////////*/

    function test_OpenBet_ETH_EscrowsStake() public {
        uint256 stake = 0.5 ether;
        uint256 maxPayout = 0.95 ether;

        uint256 treasuryBefore = address(treasury).balance;

        vm.prank(game);
        uint256 betId = treasury.openBet{value: stake}(player, NATIVE, stake, maxPayout);

        assertEq(address(treasury).balance, treasuryBefore + stake);
        assertEq(treasury.lockedLiquidity(NATIVE), maxPayout);
        assertEq(treasury.getBet(betId).token, NATIVE);
    }

    function test_OpenBet_ETH_RevertsOnValueMismatch() public {
        vm.prank(game);
        vm.expectRevert(Treasury.Treasury__NativeValueMismatch.selector);
        treasury.openBet{value: 0.4 ether}(player, NATIVE, 0.5 ether, 0.95 ether);
    }

    function test_OpenBet_ERC20_RevertsIfEthSent() public {
        vm.prank(game);
        vm.expectRevert(Treasury.Treasury__UnexpectedNativeValue.selector);
        treasury.openBet{value: 1 wei}(player, address(token), 100e18, 190e18);
    }

    /*//////////////////////////////////////////////////////////////
                              SETTLEMENT
    //////////////////////////////////////////////////////////////*/

    function test_SettleBet_Win_PaysPlayerAndReleasesLock() public {
        uint256 stake = 100e18;
        uint256 maxPayout = 190e18;

        vm.prank(game);
        uint256 betId = treasury.openBet(player, address(token), stake, maxPayout);

        uint256 playerBefore = token.balanceOf(player);

        vm.prank(game);
        treasury.settleBet(betId, maxPayout);

        assertEq(token.balanceOf(player), playerBefore + maxPayout);
        assertEq(treasury.lockedLiquidity(address(token)), 0);
        assertEq(
            uint256(treasury.getBet(betId).status),
            uint256(Treasury.BetStatus.SETTLED)
        );
    }

    function test_SettleBet_Loss_HouseKeepsStake() public {
        uint256 stake = 100e18;
        uint256 maxPayout = 190e18;

        uint256 houseBefore = treasury.availableLiquidity(address(token));

        vm.prank(game);
        uint256 betId = treasury.openBet(player, address(token), stake, maxPayout);

        vm.prank(game);
        treasury.settleBet(betId, 0); // player lost

        // House gained exactly the stake; nothing left locked.
        assertEq(treasury.availableLiquidity(address(token)), houseBefore + stake);
        assertEq(treasury.lockedLiquidity(address(token)), 0);
    }

    function test_SettleBet_ETH_Win() public {
        uint256 stake = 0.5 ether;
        uint256 maxPayout = 0.95 ether;

        vm.prank(game);
        uint256 betId = treasury.openBet{value: stake}(player, NATIVE, stake, maxPayout);

        uint256 playerBefore = player.balance;
        vm.prank(game);
        treasury.settleBet(betId, maxPayout);

        assertEq(player.balance, playerBefore + maxPayout);
        assertEq(treasury.lockedLiquidity(NATIVE), 0);
    }

    function test_SettleBet_RevertsForWrongGame() public {
        treasury.setGameAuthorization(stranger, true);
        vm.prank(game);
        uint256 betId = treasury.openBet(player, address(token), 100e18, 190e18);

        vm.prank(stranger);
        vm.expectRevert(Treasury.Treasury__NotBetOwner.selector);
        treasury.settleBet(betId, 0);
    }

    function test_SettleBet_RevertsIfAlreadySettled() public {
        vm.startPrank(game);
        uint256 betId = treasury.openBet(player, address(token), 100e18, 190e18);
        treasury.settleBet(betId, 0);
        vm.expectRevert(Treasury.Treasury__BetNotOpen.selector);
        treasury.settleBet(betId, 0);
        vm.stopPrank();
    }

    function test_SettleBet_RevertsIfPayoutExceedsReserved() public {
        vm.startPrank(game);
        uint256 betId = treasury.openBet(player, address(token), 100e18, 190e18);
        vm.expectRevert(Treasury.Treasury__PayoutExceedsReserved.selector);
        treasury.settleBet(betId, 190e18 + 1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       LIQUIDITY PROTECTION
    //////////////////////////////////////////////////////////////*/

    function test_WithdrawLiquidity_CannotTouchLockedFunds() public {
        // Lock most of the ERC-20 bankroll behind an open bet.
        vm.prank(game);
        treasury.openBet(player, address(token), 100e18, 9_900e18);

        uint256 available = treasury.availableLiquidity(address(token));
        // Withdrawing exactly the available amount is fine.
        treasury.withdrawLiquidity(address(token), available);
        // One wei more must revert - locked player exposure is protected.
        vm.expectRevert(Treasury.Treasury__InsufficientLiquidity.selector);
        treasury.withdrawLiquidity(address(token), 1);
    }

    function test_WithdrawLiquidity_OnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        treasury.withdrawLiquidity(address(token), 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                           PAUSE BEHAVIOUR
    //////////////////////////////////////////////////////////////*/

    function test_Pause_BlocksNewBetsButNotSettlement() public {
        // Open a bet before pausing.
        vm.prank(game);
        uint256 betId = treasury.openBet(player, address(token), 100e18, 190e18);

        treasury.pause();

        // New bets are blocked.
        vm.prank(game);
        vm.expectRevert(); // Pausable: EnforcedPause
        treasury.openBet(player, address(token), 100e18, 190e18);

        // Settlement of the in-flight bet still works - players can be paid.
        vm.prank(game);
        treasury.settleBet(betId, 190e18);
        assertEq(
            uint256(treasury.getBet(betId).status),
            uint256(Treasury.BetStatus.SETTLED)
        );
    }

    /*//////////////////////////////////////////////////////////////
                                FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_OpenAndSettlePreservesSolvency(
        uint256 stake,
        uint256 maxPayout,
        uint256 payout
    ) public {
        stake = bound(stake, ERC20_MIN, ERC20_MAX);
        uint256 available = treasury.availableLiquidity(address(token));
        maxPayout = bound(maxPayout, 1, available);
        payout = bound(payout, 0, maxPayout);

        token.mint(player, stake);

        vm.prank(game);
        uint256 betId = treasury.openBet(player, address(token), stake, maxPayout);
        // While open, locked liquidity is fully reserved.
        assertEq(treasury.lockedLiquidity(address(token)), maxPayout);

        vm.prank(game);
        treasury.settleBet(betId, payout);

        // After settlement nothing is locked and the house can never be insolvent.
        assertEq(treasury.lockedLiquidity(address(token)), 0);
        assertGe(
            treasury.totalLiquidity(address(token)),
            treasury.lockedLiquidity(address(token))
        );
    }

    function testFuzz_QuotePayoutNeverExceedsGross(uint256 gross) public view {
        gross = bound(gross, 0, 1e30);
        assertLe(treasury.quotePayout(gross), gross);
    }
}
