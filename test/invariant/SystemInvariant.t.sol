// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {VRFConsumer} from "../../src/VRFConsumer.sol";
import {Treasury} from "../../src/Treasury.sol";
import {DiceGame} from "../../src/DiceGame.sol";
import {AchievementNFT} from "../../src/AchievementNFT.sol";
import {MockVRFCoordinator} from "../mocks/MockVRFCoordinator.sol";

/**
 * @title DiceHandler
 * @author SC6107 Group Project - Member 5
 * @notice A "handler" contract for Foundry's invariant runner. The runner
 *         calls these bounded actions in a random sequence with random
 *         arguments; after every call, every `invariant_*` function on the
 *         test contract is re-checked.
 *
 *         Why a handler? Letting the fuzzer call the games directly is
 *         too permissive: it would generate countless reverts (wrong tokens,
 *         out-of-range guesses, etc.) and produce shallow runs. By bounding
 *         inputs here, every action has a high chance of producing real
 *         state changes, so invariants are exercised meaningfully.
 */
contract DiceHandler is Test {
    address internal constant NATIVE = address(0);

    DiceGame public diceGame;
    Treasury public treasury;
    VRFConsumer public vrfConsumer;
    MockVRFCoordinator public coordinator;

    address[] internal _players;
    uint256[] internal _pendingRequests;

    // "Ghost" variables: bookkeeping used by some invariants.
    uint256 public ghost_totalBetsPlaced;
    uint256 public ghost_totalBetsFulfilled;

    constructor(
        DiceGame _diceGame,
        Treasury _treasury,
        VRFConsumer _vrfConsumer,
        MockVRFCoordinator _coordinator,
        address[] memory players
    ) {
        diceGame = _diceGame;
        treasury = _treasury;
        vrfConsumer = _vrfConsumer;
        coordinator = _coordinator;
        for (uint256 i; i < players.length; ++i) {
            _players.push(players[i]);
        }
    }

    // Needed because depositLiquidity is called from this contract.
    receive() external payable {}

    /// @notice Random player rolls a random valid dice with a bounded stake.
    function placeBet(uint256 playerSeed, uint256 guessSeed, uint256 stakeSeed)
        external
    {
        if (_players.length == 0) return;
        address player = _players[playerSeed % _players.length];
        uint8 guess = uint8((guessSeed % 6) + 1);
        uint256 stake = bound(stakeSeed, 0.001 ether, 0.05 ether);

        vm.deal(player, stake);
        vm.prank(player);
        try diceGame.rollDice{value: stake}(guess) returns (uint256 requestId) {
            _pendingRequests.push(requestId);
            ++ghost_totalBetsPlaced;
        } catch {
            // Insolvency or out-of-range -- ignore, just don't push.
        }
    }

    /// @notice Pick a random pending request and fulfil it with a random word.
    function fulfillRandomness(uint256 idx, uint256 word) external {
        if (_pendingRequests.length == 0) return;
        uint256 i = idx % _pendingRequests.length;
        uint256 requestId = _pendingRequests[i];

        // Swap-and-pop to remove this request.
        _pendingRequests[i] = _pendingRequests[_pendingRequests.length - 1];
        _pendingRequests.pop();

        uint256[] memory words = new uint256[](1);
        words[0] = word;
        try coordinator.fulfillWithWords(requestId, words) {
            ++ghost_totalBetsFulfilled;
        } catch {}
    }

    /// @notice Add house liquidity (any actor can; here the handler does it).
    function topUpHouse(uint256 amount) external {
        amount = bound(amount, 0.01 ether, 5 ether);
        vm.deal(address(this), amount);
        try treasury.depositLiquidity{value: amount}(NATIVE, amount) {} catch {}
    }
}

/**
 * @title SystemInvariantTest
 * @notice Property-based tests that verify *invariants* of the protocol:
 *         properties that must hold across ANY sequence of operations.
 *
 *         Invariants checked:
 *           1. Treasury solvency: balance >= lockedLiquidity always.
 *           2. availableLiquidity formula consistency.
 *           3. House edge stays within its configured cap.
 *           4. Per-player NFT uniqueness: if hasFirstWinAchievement[p] is
 *              set, then p owns at least one achievement NFT.
 *           5. ghost_totalBetsFulfilled <= ghost_totalBetsPlaced.
 */
contract SystemInvariantTest is Test {
    address internal constant NATIVE = address(0);
    uint16 internal constant HOUSE_EDGE_BPS = 250;

    DiceHandler public handler;
    DiceGame public diceGame;
    AchievementNFT public achievementNFT;
    Treasury public treasury;
    VRFConsumer public vrfConsumer;
    MockVRFCoordinator public coordinator;

    address internal aliceAddr;
    address internal bobAddr;
    address internal carolAddr;

    function setUp() public {
        coordinator = new MockVRFCoordinator();
        vrfConsumer = new VRFConsumer(
            address(coordinator),
            bytes32(uint256(1)),
            1,
            500_000
        );
        treasury = new Treasury(address(this), HOUSE_EDGE_BPS);
        achievementNFT = new AchievementNFT(address(this));
        diceGame = new DiceGame(
            address(this),
            address(vrfConsumer),
            address(treasury),
            address(achievementNFT)
        );

        vrfConsumer.setConsumerAuthorization(address(diceGame), true);
        treasury.setTokenConfig(NATIVE, true, 0.001 ether, 0.05 ether);
        treasury.setGameAuthorization(address(diceGame), true);
        achievementNFT.setGameContract(address(diceGame));

        // Seed the house with plenty of liquidity so most actions succeed.
        vm.deal(address(this), 10_000 ether);
        treasury.depositLiquidity{value: 100 ether}(NATIVE, 100 ether);

        aliceAddr = makeAddr("alice");
        bobAddr = makeAddr("bob");
        carolAddr = makeAddr("carol");

        address[] memory players = new address[](3);
        players[0] = aliceAddr;
        players[1] = bobAddr;
        players[2] = carolAddr;

        handler = new DiceHandler(diceGame, treasury, vrfConsumer, coordinator, players);

        // Restrict invariant fuzzing to the handler's three actions.
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = DiceHandler.placeBet.selector;
        selectors[1] = DiceHandler.fulfillRandomness.selector;
        selectors[2] = DiceHandler.topUpHouse.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                              INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Core safety property -- the Treasury must always hold at
    ///         least its locked liquidity. If this ever breaks, the house
    ///         is insolvent and some open bet cannot be honoured.
    function invariant_TreasuryRemainsSolvent() public view {
        uint256 total = address(treasury).balance;
        uint256 locked = treasury.lockedLiquidity(NATIVE);
        assertGe(total, locked, "treasury insolvent: balance < locked");
    }

    /// @notice availableLiquidity() must equal balance - locked, with
    ///         underflow protection (defined as 0 if locked > balance).
    function invariant_AvailableLiquidityMatchesFormula() public view {
        uint256 total = address(treasury).balance;
        uint256 locked = treasury.lockedLiquidity(NATIVE);
        uint256 expected = total > locked ? total - locked : 0;
        assertEq(treasury.availableLiquidity(NATIVE), expected);
    }

    /// @notice House edge can never exceed the configured cap.
    function invariant_HouseEdgeWithinCap() public view {
        assertLe(treasury.houseEdgeBps(), treasury.MAX_HOUSE_EDGE_BPS());
    }

    /// @notice For any of our known players, if the FIRST_WIN flag is set
    ///         then the player must actually own at least one NFT.
    function invariant_NFTFlagImpliesOwnership() public view {
        address[3] memory players = [aliceAddr, bobAddr, carolAddr];
        for (uint256 i; i < players.length; ++i) {
            if (achievementNFT.hasFirstWinAchievement(players[i])) {
                assertGe(
                    achievementNFT.balanceOf(players[i]),
                    1,
                    "flag set but player owns no NFT"
                );
            }
        }
    }

    /// @notice The fuzzer can never fulfil more bets than it placed.
    function invariant_FulfilledNeverExceedsPlaced() public view {
        assertLe(
            handler.ghost_totalBetsFulfilled(),
            handler.ghost_totalBetsPlaced()
        );
    }
}
