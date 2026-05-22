# Gas Optimization Report

**Project:** SC6107 — On-Chain Verifiable Random Game Platform
**Compiler:** solc 0.8.24, optimizer enabled with `runs = 200`, `via_ir = true`, EVM target `cancun`
**Source:** `forge test --gas-report` over 137 tests
**Raw report:** `docs/gas-report.txt`
**Date:** May 2026
**Author:** Group Member 5

---

## 1. Executive Summary

The gas-report exercises all 6 production contracts over realistic call sequences (unit tests, 10 integration scenarios, and 64×32 invariant fuzzing). This report identifies the top hot-paths, documents the optimizations already applied to the codebase, recommends further savings with concrete estimates, and lists optimizations explicitly avoided for safety or maintainability reasons.

Top-level numbers:

| Contract | Deployment Cost | Runtime Size | Most-Called Hot Path |
|---|---:|---:|---|
| `Lottery` | 2,514,991 | 11,329 B | `buyTicket` (171k avg) |
| `DiceGame` | 1,608,712 | 7,204 B | `rollDice` (441k avg, 3,446 calls) |
| `Treasury` | 1,230,914 | 5,361 B | `openBet` (212k avg, 275 calls) |
| `VRFConsumer` | 1,192,718 | 5,085 B | `requestRandomness` (24k avg) |
| `AchievementNFT` | 1,075,935 | 5,302 B | `mintFirstWin` (63k avg) |
| `Referral` | 791,359 | 3,225 B | `recordTicketPurchase` (65k avg) |

`Lottery` occupies ~46% of the EIP-170 24,576-byte contract code-size budget. None of the contracts are near the hard limit today, but `Lottery` is the one to watch as features accrete.

## 2. Hot-Path Analysis

The five paths below dominate the protocol's per-action gas cost. They are ordered by impact — a fixed-percent saving on `Treasury.openBet` saves more gas across the protocol's lifetime than the same saving on a rarely-called admin function.

### 2.1 `Treasury.openBet` — 212,596 avg (worst hot-path)

Called once for every bet in both `DiceGame` and `Lottery`. The cost is dominated by the SSTOREs writing the 13-field `Bet` struct (`player`, `token`, `stake`, `potentialPayout`, `requestId`, `settled`, `won`, `result`, `commitment`, `revealDeadline`, `isCommitReveal`, `randomFulfilled`, `guess`). With 32-byte slot granularity, that struct currently occupies five or six storage slots depending on field ordering. Each cold SSTORE is 22,100 gas; collapsing one slot saves roughly that.

### 2.2 `DiceGame.rollDice` — 441,664 avg / 481,258 max

`rollDice` is the user-visible cost of playing the dice game. It encapsulates `Treasury.openBet` (#2.1) + `VRFConsumer.requestRandomness` (~24k) + `AchievementNFT.hasFirstWinAchievement` read (~2.8k) + DiceGame's own per-bet bookkeeping. The 40k spread between min and max comes from cold-slot warm-up: the first bet in any test setup pays the higher rate.

### 2.3 `DiceGame.commitRoll` — 472,610 avg

Notably **more expensive than `rollDice`** despite both writing a single `Bet` struct. The extra ~30k cost is the commitment hash storage and the additional `revealDeadline` write. This is the price of the commit-reveal MEV-defence path; a player who does not need pre-roll commitment should call `rollDice` directly.

### 2.4 `Lottery.buyTicket` — 171,116 avg, **29,389 min / 1,229,698 max**

The most extreme variance in the entire report. The min represents a warm second-ticket purchase; the max represents the first ticket of a round where the buyer is referred (cold `Referral` storage write + cold `Round.tickets` array first element + cold `referredBy` lookup all collide in one tx). Subsequent tickets are an order of magnitude cheaper. This pattern is acceptable for a lottery — the high first-purchase cost is paid once per (round, player) combination — but is worth highlighting.

### 2.5 `Lottery.createRound` — 175,754 avg

Called once at the start of every round. Cost is the 12-field `Round` struct SSTOREs plus the `currentRoundId` increment. The variance (27k → 219k) reflects whether `currentRoundId` is a cold slot for that specific test.

## 3. Optimizations Already Applied

The following optimizations are already in place in the codebase and `foundry.toml`. They are worth mentioning in the project write-up because they reflect deliberate engineering choices.

The compiler is configured with `optimizer = true`, `optimizer_runs = 200`, and `via_ir = true`. The 200-run setting biases the optimizer toward smaller deployed bytecode rather than slightly cheaper runtime execution; this is the right trade-off because most functions are called only a handful of times in a typical session. Enabling `via_ir` routes compilation through Yul IR, which produces better stack scheduling and is what allowed the 13-field `Bet` struct to be returned from a public getter at all (without it, the integration tests failed with "stack too deep").

`address(0)` is used as the sentinel for the native token throughout `Treasury`. This eliminates an ERC20 `transfer` round-trip on the dominant code path (native ETH wagers), saving ~30k gas per bet versus a uniform ERC20 abstraction. The `transfer/transferFrom` paths exist for future multi-token support but are gated behind a `token != address(0)` branch.

`Treasury` exposes `lockedLiquidity` as a public mapping rather than re-deriving it from per-bet sums. The 3,016-gas constant read seen across 786 invocations in the report would otherwise require iterating every open bet — unfeasible on-chain.

`Ownable2Step` is used on `Treasury` (the most security-critical contract) rather than plain `Ownable`, accepting the ~5k extra gas on ownership transfer in exchange for protection against transferring to a wrong address.

OpenZeppelin v5's `ReentrancyGuard` uses transient storage (EIP-1153) on Cancun-class EVMs, which makes the `nonReentrant` modifier roughly 16k gas cheaper per call than the legacy slot-based implementation. The `evm_version = "cancun"` setting in `foundry.toml` enables this automatically.

## 4. Recommended Optimizations

The following are recommendations that have been identified but **not yet applied**, with estimated savings.

### 4.1 Pack the `Bet` struct (≈22k gas / bet, highest priority)

The `Bet` struct currently fits in five or six 32-byte slots. By packing the small fields together, it should fit in four. Specifically: `settled`, `won`, `randomFulfilled`, `isCommitReveal` are all `bool` (1 byte each); `result`, `guess` are `uint8` (1 byte each); `revealDeadline` could safely be `uint48` (sufficient until year 8.9 million). These eight fields total 12 bytes and pack with `address player` (20 bytes) into a single slot.

```solidity
struct Bet {
    address player;        // 20 bytes ┐
    uint48 revealDeadline; //  6 bytes │
    uint8 result;          //  1 byte  │ slot 0 (28 bytes used)
    uint8 guess;           //  1 byte  ┘
    bool settled;          //  1 byte  ┐
    bool won;              //  1 byte  │
    bool randomFulfilled;  //  1 byte  │
    bool isCommitReveal;   //  1 byte  ┘  (still slot 0 if budget remains)
    address token;         // 20 bytes — slot 1
    uint256 stake;         // 32 bytes — slot 2
    uint256 potentialPayout; // slot 3
    uint256 requestId;     // slot 4
    bytes32 commitment;    // slot 5
}
```

**Estimated saving:** one SSTORE eliminated on every `Treasury.openBet` call → roughly 22,100 gas per bet (cold) or 5,000 (warm). At 275 bets per typical test run that is ~6M gas; in production, it scales linearly with usage.

### 4.2 Replace `require(..., "string")` with custom errors (≈1KB code size, plus runtime gas)

A search of the source tree shows roughly 40 `require(condition, "message")` statements across `Lottery.sol` and `DiceGame.sol`. Each string literal occupies ~32 bytes of deployed bytecode plus the ABI-encoding overhead at revert time (~50 gas/revert). Custom errors compile to a 4-byte selector and skip the encoding step.

```solidity
// before
require(r.status == RoundStatus.OPEN, "Round not open");

// after
error RoundNotOpen();
if (r.status != RoundStatus.OPEN) revert RoundNotOpen();
```

**Estimated saving:** ~1 KB of `Lottery` runtime size (out of 11.3 KB, a ~9% reduction in deployment cost), and ~50 gas per reverting call. The deployment-cost saving is meaningful because `Lottery` deployment is already 2.5M gas.

### 4.3 Cache `Round` storage reads in `claimPrize` / `triggerDraw` (≈4k gas / call)

`Lottery.claimPrize` reads `r.status`, `r.prizesClaimable`, `r.totalTicketsSold`, `r.winners.length`, and `r.payouts[msg.sender]` in sequence. Each `SLOAD` after the first on the same slot is 100 gas (warm), but cold reads across distinct slots compound. Loading the round once with `Round storage r = rounds[roundId];` (already done) is good; copying the immutable subset to a memory struct before the multi-read block would save 2-4k on hot paths.

**Estimated saving:** 2k-4k gas per `claimPrize`. At avg 57k currently, that is a 4-7% reduction.

### 4.4 Use `calldata` instead of `memory` for read-only array parameters (≈300 gas / element)

`Lottery.createRound` and `VRFConsumer.requestRandomness` currently accept `memory` parameters that are never mutated. Switching to `calldata` avoids the copy-to-memory cost (≈3 gas per byte plus expansion costs).

**Estimated saving:** ~300 gas per element on touched arrays. Minor for current usage but free to apply.

### 4.5 Pre-warm `referredBy` slot on round creation (mitigates the 1.2M max)

The 1.2M-gas `buyTicket` outlier is the cold-slot first-touch case. Initialising `referredBy[buyer]` to `address(this)` (a sentinel) during round creation would not be cheaper overall, but emitting a deterministic non-zero value at registration time would let the hot path avoid a branch. This is a workload-shape change rather than a pure optimization; it may or may not be worth the contract-size cost.

**Estimated saving:** Variable. Reduces variance, not the average.

## 5. Optimizations Deliberately Not Applied

The following are common Solidity gas tricks that **have been considered and rejected** for this codebase. Documenting these explicitly is a security best practice.

**Removing `nonReentrant` from external entrypoints.** The OZ `nonReentrant` modifier with transient storage costs ~2.3k gas per call. Removing it from `claimPrize`, `claimRefund`, or `claimCommission` would save that gas but reintroduce the classic withdrawal-pattern reentrancy. The cost is paid willingly.

**Inline-assembly for the `.call{value:}` blocks.** Hand-tuned Yul can shave ~100 gas off each external transfer, but the readability cost is severe and the safety regression risk is non-trivial. The current `(bool ok,) = to.call{value: amount}(""); require(ok, "..."`) pattern is the OpenZeppelin-recommended idiom and was unanimously endorsed during the security review.

**Packing `revealDeadline` down to `uint32`.** Saves a few bits but caps at year 2106. The protocol intends to be deployable indefinitely; `uint48` is a better trade-off and is what is proposed in §4.1.

**Replacing `_safeMint` with `_mint` in `AchievementNFT.mintFirstWin`.** `_mint` is ~5k cheaper but skips the `ERC721Receiver` check, which would silently send NFTs to contracts that cannot receive them. The receiver check is a documented user-protection feature.

**Lazy-emitting events to save log gas.** Each indexed event topic costs ~375 gas, and the project emits comprehensive events on every state transition. These events are the only reliable mechanism for off-chain indexers (and the front-end) to reconstruct game state; dropping them would break observability for marginal savings.

## 6. Verification Workflow

To verify the recommended optimizations against this baseline:

```bash
# baseline (this report)
forge test --gas-report > docs/gas-report.txt

# apply a single optimization (e.g., struct packing in §4.1)
# then re-run and diff
forge test --gas-report > docs/gas-report-after.txt
diff docs/gas-report.txt docs/gas-report-after.txt
```

The 137-test suite is comprehensive enough that any regression introduced by an optimization will be caught — the invariant suite in particular re-verifies the solvency property after each fuzzed action, which catches subtle changes to the bet-accounting math.

---

*Generated as part of SC6107 project deliverables. Raw `forge test --gas-report` output preserved at `docs/gas-report.txt` for reproducibility.*
