// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ITreasury} from "./interfaces/ITreasury.sol";

/**
 * @title Treasury
 * @author SC6107 Group Project - Member 1 (VRF + Treasury Infrastructure)
 * @notice The house bankroll for the on-chain game platform. It escrows player
 *         stakes, enforces per-token bet limits, applies a configurable house
 *         edge, and pays winners - while guaranteeing it can never promise more
 *         than it can pay.
 *
 * @dev    Core safety property (solvency invariant):
 *
 *             availableLiquidity(token) >= 0   for every supported token
 *
 *         where `availableLiquidity = totalBalance - lockedLiquidity`. Every
 *         {openBet} reserves the bet's WORST-CASE payout out of available
 *         liquidity, so the house can always honour every open bet. The owner
 *         can withdraw house funds only down to the locked amount, so locked
 *         player exposure can never be rugged.
 *
 *         Security measures:
 *         - Checks-Effects-Interactions in {settleBet} (the payout path).
 *         - {ReentrancyGuard} on every fund-moving entry point.
 *         - {Pausable}: pausing blocks NEW bets but never blocks settlement,
 *           so players can always be paid out.
 *         - {SafeERC20} for non-standard tokens; {Ownable2Step} for safer
 *           ownership handover.
 *
 *         Native ETH is represented by the sentinel address `address(0)`.
 *
 *         Course topics demonstrated: treasury management, house edge design,
 *         ERC-20 handling, access control, emergency controls, economic safety.
 */
contract Treasury is ITreasury, Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Treasury__NotAuthorizedGame(address caller);
    error Treasury__TokenNotSupported(address token);
    error Treasury__StakeOutOfRange(uint256 stake, uint256 minBet, uint256 maxBet);
    error Treasury__InvalidMaxPayout();
    error Treasury__InsufficientLiquidity(uint256 required, uint256 available);
    error Treasury__NativeValueMismatch(uint256 sent, uint256 expected);
    error Treasury__UnexpectedNativeValue();
    error Treasury__BetNotOpen(uint256 betId);
    error Treasury__NotBetOwner(uint256 betId, address caller);
    error Treasury__PayoutExceedsReserved(uint256 payout, uint256 reserved);
    error Treasury__HouseEdgeTooHigh(uint16 bps);
    error Treasury__InvalidBetLimits(uint256 minBet, uint256 maxBet);
    error Treasury__ZeroAddress();
    error Treasury__ZeroAmount();
    error Treasury__NativeTransferFailed();

    /*//////////////////////////////////////////////////////////////
                            DATA STRUCTURES
    //////////////////////////////////////////////////////////////*/

    /// @notice Per-token betting parameters.
    struct TokenConfig {
        bool enabled; // accepted for betting
        uint256 minBet; // inclusive minimum stake
        uint256 maxBet; // inclusive maximum stake
    }

    /// @notice Settlement state of a bet.
    enum BetStatus {
        NONE,
        OPEN,
        SETTLED
    }

    /// @notice On-chain record of a single bet.
    struct Bet {
        address game; // game contract that opened the bet
        address player; // beneficiary of any payout
        address token; // wagered token (address(0) == native ETH)
        uint256 stake; // amount escrowed
        uint256 reservedPayout; // worst-case payout locked from liquidity
        BetStatus status; // lifecycle state
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sentinel token address for native ETH.
    address public constant NATIVE = address(0);

    /// @notice Basis-points denominator (10_000 == 100%).
    uint16 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Hard ceiling on the house edge (20%).
    uint16 public constant MAX_HOUSE_EDGE_BPS = 2_000;

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ITreasury
    uint16 public override houseEdgeBps;

    /// @notice Game contracts permitted to open and settle bets.
    mapping(address => bool) public authorizedGames;

    /// @notice token => betting configuration.
    mapping(address => TokenConfig) public tokenConfig;

    /// @notice token => liquidity reserved against currently-open bets.
    mapping(address => uint256) public lockedLiquidity;

    /// @notice betId => bet record.
    mapping(uint256 => Bet) private _bets;

    /// @notice Monotonically increasing bet id counter (ids start at 1).
    uint256 public nextBetId = 1;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event GameAuthorizationSet(address indexed game, bool authorized);
    event TokenConfigured(address indexed token, bool enabled, uint256 minBet, uint256 maxBet);
    event HouseEdgeUpdated(uint16 oldBps, uint16 newBps);
    event LiquidityDeposited(address indexed token, address indexed from, uint256 amount);
    event LiquidityWithdrawn(address indexed token, address indexed to, uint256 amount);
    event BetOpened(
        uint256 indexed betId,
        address indexed game,
        address indexed player,
        address token,
        uint256 stake,
        uint256 reservedPayout
    );
    event BetSettled(uint256 indexed betId, uint256 payoutAmount, bool playerWon);

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAuthorizedGame() {
        if (!authorizedGames[msg.sender]) revert Treasury__NotAuthorizedGame(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param initialOwner   Address that administers the Treasury.
     * @param houseEdgeBps_  Initial house edge in basis points (<= MAX_HOUSE_EDGE_BPS).
     */
    constructor(address initialOwner, uint16 houseEdgeBps_) Ownable(initialOwner) {
        if (houseEdgeBps_ > MAX_HOUSE_EDGE_BPS) revert Treasury__HouseEdgeTooHigh(houseEdgeBps_);
        houseEdgeBps = houseEdgeBps_;
    }

    /// @notice Accept direct ETH transfers as house liquidity top-ups.
    receive() external payable {
        emit LiquidityDeposited(NATIVE, msg.sender, msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                         ADMIN - CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorise / revoke a game contract.
    function setGameAuthorization(address game, bool authorized) external onlyOwner {
        if (game == address(0)) revert Treasury__ZeroAddress();
        authorizedGames[game] = authorized;
        emit GameAuthorizationSet(game, authorized);
    }

    /**
     * @notice Enable a token for betting (or update its limits / disable it).
     * @param  token   ERC-20 address, or `address(0)` for native ETH.
     * @param  enabled Whether the token may be wagered.
     * @param  minBet  Inclusive minimum stake.
     * @param  maxBet  Inclusive maximum stake (must be >= minBet).
     */
    function setTokenConfig(address token, bool enabled, uint256 minBet, uint256 maxBet)
        external
        onlyOwner
    {
        if (enabled) {
            if (minBet == 0 || maxBet < minBet) revert Treasury__InvalidBetLimits(minBet, maxBet);
        }
        tokenConfig[token] = TokenConfig({enabled: enabled, minBet: minBet, maxBet: maxBet});
        emit TokenConfigured(token, enabled, minBet, maxBet);
    }

    /// @notice Update the house edge (basis points, <= MAX_HOUSE_EDGE_BPS).
    function setHouseEdge(uint16 houseEdgeBps_) external onlyOwner {
        if (houseEdgeBps_ > MAX_HOUSE_EDGE_BPS) revert Treasury__HouseEdgeTooHigh(houseEdgeBps_);
        emit HouseEdgeUpdated(houseEdgeBps, houseEdgeBps_);
        houseEdgeBps = houseEdgeBps_;
    }

    /// @notice Emergency stop: blocks NEW bets. Settlement remains available.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Lift the emergency stop.
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                         HOUSE LIQUIDITY MGMT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add house liquidity so the platform can back larger bets.
     * @param  token  ERC-20 address, or `address(0)` for native ETH.
     * @param  amount Amount to deposit (for ETH must equal `msg.value`).
     */
    function depositLiquidity(address token, uint256 amount)
        external
        payable
        nonReentrant
    {
        if (amount == 0) revert Treasury__ZeroAmount();

        if (token == NATIVE) {
            if (msg.value != amount) revert Treasury__NativeValueMismatch(msg.value, amount);
        } else {
            if (msg.value != 0) revert Treasury__UnexpectedNativeValue();
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        emit LiquidityDeposited(token, msg.sender, amount);
    }

    /**
     * @notice Withdraw house profits. Cannot touch liquidity locked behind open
     *         bets, so player exposure is always protected.
     * @param  token  ERC-20 address, or `address(0)` for native ETH.
     * @param  amount Amount to withdraw (<= availableLiquidity(token)).
     */
    function withdrawLiquidity(address token, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        if (amount == 0) revert Treasury__ZeroAmount();

        uint256 available = availableLiquidity(token);
        if (amount > available) revert Treasury__InsufficientLiquidity(amount, available);

        _payOut(token, msg.sender, amount);
        emit LiquidityWithdrawn(token, msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            BET LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ITreasury
    function openBet(address player, address token, uint256 stake, uint256 maxPayout)
        external
        payable
        override
        onlyAuthorizedGame
        whenNotPaused
        nonReentrant
        returns (uint256 betId)
    {
        if (player == address(0)) revert Treasury__ZeroAddress();

        TokenConfig memory cfg = tokenConfig[token];
        if (!cfg.enabled) revert Treasury__TokenNotSupported(token);
        if (stake < cfg.minBet || stake > cfg.maxBet) {
            revert Treasury__StakeOutOfRange(stake, cfg.minBet, cfg.maxBet);
        }
        if (maxPayout == 0) revert Treasury__InvalidMaxPayout();

        // --- Collect the stake into the Treasury ---
        if (token == NATIVE) {
            if (msg.value != stake) revert Treasury__NativeValueMismatch(msg.value, stake);
        } else {
            if (msg.value != 0) revert Treasury__UnexpectedNativeValue();
            IERC20(token).safeTransferFrom(player, address(this), stake);
        }

        // --- Solvency check: the house must be able to cover the worst case ---
        // The stake is already in the balance at this point, so availableLiquidity
        // reflects it. Reserving `maxPayout` keeps the solvency invariant intact.
        uint256 available = availableLiquidity(token);
        if (maxPayout > available) {
            revert Treasury__InsufficientLiquidity(maxPayout, available);
        }
        lockedLiquidity[token] += maxPayout;

        // --- Record the bet ---
        betId = nextBetId++;
        _bets[betId] = Bet({
            game: msg.sender,
            player: player,
            token: token,
            stake: stake,
            reservedPayout: maxPayout,
            status: BetStatus.OPEN
        });

        emit BetOpened(betId, msg.sender, player, token, stake, maxPayout);
    }

    /// @inheritdoc ITreasury
    function settleBet(uint256 betId, uint256 payoutAmount)
        external
        override
        onlyAuthorizedGame
        nonReentrant
    {
        Bet storage bet = _bets[betId];

        if (bet.status != BetStatus.OPEN) revert Treasury__BetNotOpen(betId);
        if (bet.game != msg.sender) revert Treasury__NotBetOwner(betId, msg.sender);
        if (payoutAmount > bet.reservedPayout) {
            revert Treasury__PayoutExceedsReserved(payoutAmount, bet.reservedPayout);
        }

        // --- Effects (before any external interaction) ---
        bet.status = BetStatus.SETTLED;
        lockedLiquidity[bet.token] -= bet.reservedPayout;

        address token = bet.token;
        address player = bet.player;

        // --- Interaction ---
        // On a loss `payoutAmount == 0`; the stake simply remains as house funds.
        if (payoutAmount > 0) {
            _payOut(token, player, payoutAmount);
        }

        emit BetSettled(betId, payoutAmount, payoutAmount > 0);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Sends `amount` of `token` to `to`, native or ERC-20.
    function _payOut(address token, address to, uint256 amount) internal {
        if (token == NATIVE) {
            (bool ok, ) = payable(to).call{value: amount}("");
            if (!ok) revert Treasury__NativeTransferFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Total balance of `token` held by the Treasury (locked + free).
    function totalLiquidity(address token) public view returns (uint256) {
        if (token == NATIVE) return address(this).balance;
        return IERC20(token).balanceOf(address(this));
    }

    /// @inheritdoc ITreasury
    function availableLiquidity(address token) public view override returns (uint256) {
        uint256 total = totalLiquidity(token);
        uint256 locked = lockedLiquidity[token];
        // Defensive: never underflow even if a token is force-fed / rebased down.
        return total > locked ? total - locked : 0;
    }

    /// @inheritdoc ITreasury
    function quotePayout(uint256 grossPayout) external view override returns (uint256) {
        return (grossPayout * (BPS_DENOMINATOR - houseEdgeBps)) / BPS_DENOMINATOR;
    }

    /// @inheritdoc ITreasury
    function isTokenSupported(address token) external view override returns (bool) {
        return tokenConfig[token].enabled;
    }

    /// @inheritdoc ITreasury
    function getBetLimits(address token)
        external
        view
        override
        returns (uint256 minBet, uint256 maxBet)
    {
        TokenConfig memory cfg = tokenConfig[token];
        return (cfg.minBet, cfg.maxBet);
    }

    /// @notice Full bet record for `betId`.
    function getBet(uint256 betId) external view returns (Bet memory) {
        return _bets[betId];
    }
}
