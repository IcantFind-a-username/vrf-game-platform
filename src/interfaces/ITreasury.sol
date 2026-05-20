// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITreasury
 * @author SC6107 Group Project - Member 1 (VRF + Treasury Infrastructure)
 * @notice The surface that game contracts call to escrow stakes and pay winners.
 * @dev    Bet lifecycle for Members 2 & 3:
 *
 *         1. Player approves the Treasury for `stake` (ERC-20 path) OR the game
 *            forwards `msg.value == stake` (native ETH path).
 *         2. Game calls {openBet} with the WORST-CASE payout (`maxPayout`). The
 *            Treasury pulls the stake, verifies solvency, locks `maxPayout` of
 *            house liquidity, and returns a `betId`.
 *         3. Game obtains the outcome (via {IVRFConsumer}).
 *         4. Game calls {settleBet} with the ACTUAL payout (0 on a loss,
 *            <= maxPayout on a win). The Treasury releases the lock and pays
 *            the player.
 *
 *         The native-token sentinel address is `address(0)`.
 */
interface ITreasury {
    /**
     * @notice Escrow a player's stake and reserve the worst-case payout.
     * @param  player    Address that funded the bet and will receive any payout.
     * @param  token     ERC-20 token address, or `address(0)` for native ETH.
     * @param  stake     Amount wagered. Must lie within the token's bet limits.
     * @param  maxPayout Maximum amount the house may owe for this bet. The
     *                   Treasury locks exactly this much liquidity.
     * @return betId     Identifier used to settle the bet later.
     */
    function openBet(address player, address token, uint256 stake, uint256 maxPayout)
        external
        payable
        returns (uint256 betId);

    /**
     * @notice Settle an open bet, releasing the reserved liquidity.
     * @dev    Only the game that opened the bet may settle it.
     * @param  betId        The bet to settle.
     * @param  payoutAmount Amount paid to the player (0..reservedPayout).
     */
    function settleBet(uint256 betId, uint256 payoutAmount) external;

    /**
     * @notice Apply the house edge to a fair (zero-edge) payout.
     * @param  grossPayout The mathematically fair payout.
     * @return netPayout   `grossPayout` reduced by `houseEdgeBps`.
     */
    function quotePayout(uint256 grossPayout) external view returns (uint256 netPayout);

    /// @notice Liquidity available to back NEW bets (total minus locked).
    function availableLiquidity(address token) external view returns (uint256);

    /// @notice Whether `token` is enabled for betting.
    function isTokenSupported(address token) external view returns (bool);

    /// @notice Per-token minimum and maximum stake.
    function getBetLimits(address token) external view returns (uint256 minBet, uint256 maxBet);

    /// @notice The current house edge, expressed in basis points (100 = 1%).
    function houseEdgeBps() external view returns (uint16);

    /**
     * @notice Deposit funds into the Treasury as house liquidity.
     * @param  token  ERC-20 address, or `address(0)` for native ETH.
     * @param  amount Amount to deposit (for ETH must equal `msg.value`).
     */
    function depositLiquidity(address token, uint256 amount) external payable;
}
