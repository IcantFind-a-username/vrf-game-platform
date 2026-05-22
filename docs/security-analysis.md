# Security Analysis

**Project:** SC6107 — On-Chain Verifiable Random Game Platform
**Scope:** `src/` (6 contracts, 4 interfaces)
**Tools:** Slither v0.10.x, Foundry forge test (137 unit + integration + invariant tests, 88.97% line coverage), manual review.
**Date:** May 2026
**Author:** Group Member 5

---

## 1. Executive Summary

The protocol consists of six on-chain contracts: a Chainlink VRF v2.5 consumer (`VRFConsumer`), a shared house bank (`Treasury`), two games (`DiceGame`, `Lottery`), a one-shot achievement NFT (`AchievementNFT`), and an off-chain referral commission tracker (`Referral`). Together they handle native-token wagers, randomness fulfilment, and proportional payouts.

A combination of static analysis (Slither, 101 detectors, 44 contracts), property-based testing (5 invariants under randomised handler-driven fuzzing), and 122 unit + 10 integration tests was used to evaluate the codebase.

**Headline result:** Slither produced **55 findings**, none of which are exploitable vulnerabilities. They break down into:

- **1 Low** (interface contract not formally inherited — recommended fix, applied below).
- **1 informational reentrancy false positive** (event emission after low-level call, protected by `nonReentrant`).
- **~25 `timestamp` informational warnings** (lottery rounds and commit-reveal windows are time-gated by design; manipulation by miners is bounded to seconds and irrelevant at the granularity used here).
- **6 `low-level-calls`** (`.call{value:}` is the recommended pattern post-Istanbul; `transfer`/`send` are intentionally avoided due to the 2300-gas stipend).
- **11 naming-convention** notes (parameter underscore-prefix style; cosmetic only).

The five protocol-wide invariants — treasury solvency, available-liquidity formula consistency, house-edge cap, NFT flag↔ownership consistency, and bookkeeping monotonicity — all held under 64 invariant runs × 32-depth fuzz sequences with bounded random inputs.

No High or Medium severity issues were found.

## 2. Methodology

Three layers of review were applied.

**Static analysis** was performed with Slither against the entire `src/` tree, filtering out `lib/` (vendored OpenZeppelin and Chainlink contracts that have been independently audited), `test/`, and `script/`. The command used was `slither . --filter-paths "lib/|test/|script/"` against solc 0.8.24 (the version pinned in `foundry.toml`).

**Dynamic / property-based testing** used Foundry's invariant runner with a bounded `DiceHandler` to exercise five global invariants over randomised action sequences. Bounding the fuzzer (player chosen from a fixed set, stake bounded to `[0.001, 0.05] ether`, guess in `[1,6]`) prevents shallow runs where most calls revert and produces meaningful state coverage. Coverage was measured with `forge coverage --ir-minimum --no-match-coverage "(script|test)"`, yielding 88.97% lines (492/553) and 85.71% functions on the in-scope source tree.

**Manual review** focused on the cross-contract trust boundaries: the `VRFConsumer` callback path into `DiceGame.onRandomnessFulfilled` and `Lottery.onRandomnessFulfilled`, the `Treasury.openBet`/`settleBet` lifecycle, and the commit-reveal flow in `DiceGame`.

## 3. Findings

### 3.1 Low — `Referral` does not formally inherit `IReferral`

**File:** `src/Referral.sol:9`
**Detector:** `missing-inheritance`

`IReferral` defines the `recordTicketPurchase(address,uint256,bytes32)` function that `Lottery` calls. `Referral` implements that function with a matching signature but does not declare `is IReferral`, so the compiler does not verify conformance and downstream consumers cannot cast `Referral` to its interface.

**Impact:** Low. The signature happens to match today, but a future refactor could silently break the contract. No on-chain exploit path.

**Recommended fix:**

```solidity
// src/Referral.sol
import {IReferral} from "./interfaces/IReferral.sol";

contract Referral is Ownable, ReentrancyGuard, IReferral {
    // ...
}
```

**Status:** Accepted — to be applied in a follow-up patch.

### 3.2 Informational — Reentrancy-4 false positive in `Lottery.triggerDraw`

**File:** `src/Lottery.sol:241–258`
**Detector:** `reentrancy-events`

Slither flags that `DrawRequested(roundId, requestId)` is emitted after the external call to `vrfConsumer.requestRandomness(...)`. The reentrancy-4 detector covers the narrow case of state-modifying reentrancy after an event that other contracts could observe.

**Assessment — false positive.** `triggerDraw` is guarded by `nonReentrant` and the state transition (`r.status = RoundStatus.DRAWING`) occurs before the external call. The `requestRandomness` callee is the trusted VRF coordinator wrapper, which is permission-checked via `setConsumerAuthorization`. There is no value transfer in this path. Event ordering is intentional: the event fires with the `requestId` returned by the call.

**Status:** No change.

### 3.3 Informational — Block timestamp comparisons (~25 occurrences)

**Files:** `src/DiceGame.sol`, `src/Lottery.sol`, `src/VRFConsumer.sol`
**Detector:** `timestamp`

Slither flags every `block.timestamp` comparison. These appear in:

- `Lottery.buyTicket` / `triggerDraw` / `retryDraw` / `cancelRound` — gating round open/close and VRF-timeout windows.
- `DiceGame.revealRoll` / `forfeitExpiredRoll` — enforcing the commit-reveal deadline.
- `VRFConsumer.retryRequest` / `isRetryable` — enforcing the request timeout before retry is permitted.

**Assessment — by design.** All time windows are measured in minutes-to-hours (e.g., lottery rounds of 1+ hours, reveal timeouts of multiple blocks, `vrfTimeout` of 24h). Miner timestamp manipulation is bounded to roughly ±15 seconds and cannot meaningfully shift a window of these magnitudes. There is no economic incentive to manipulate timestamps because (a) lottery winners are decided by VRF, not by timestamps, and (b) the reveal deadline only governs whether the player or the house controls the forfeit path, both deterministic.

**Status:** No change.

### 3.4 Informational — Low-level `.call{value:}()` usage (6 occurrences)

**Files:** `src/Lottery.sol`, `src/Referral.sol`, `src/Treasury.sol`
**Detector:** `low-level-calls`

Identified in `Lottery.claimPrize`, `Lottery.claimRefund`, `Lottery.recoverStuckFunds`, `Referral.claimCommission`, `Referral.recoverStuckFunds`, and `Treasury._payOut`.

**Assessment — best practice.** Since the Istanbul hard-fork, `address.transfer` and `address.send` are discouraged because their hardcoded 2300-gas stipend can fail for contract recipients (e.g., smart-contract wallets with non-trivial `receive()` implementations). The pattern used throughout — `(bool ok,) = to.call{value: amount}(""); require(ok, ...)` — is the OpenZeppelin-recommended idiom. Critically, every site is protected by either `nonReentrant` or the checks-effects-interactions pattern: state changes (e.g., `r.hasClaimed[user] = true`, `pendingCommission[user] = 0`) precede the external call.

**Status:** No change.

### 3.5 Informational — Naming convention (11 occurrences)

**Files:** Various setter parameters (e.g., `_gameContract`, `_vrfConsumer`, `_treasury`, `_revealTimeout`).
**Detector:** `naming-convention`

Slither flags parameter names prefixed with an underscore, since Solidity's style guide reserves leading underscores for internal/private identifiers. The codebase uses the underscore prefix to disambiguate setter parameters from same-named storage variables, which is a widespread convention (notably used by OpenZeppelin's constructors).

**Status:** No change. Cosmetic only.

## 4. Architectural Security Notes

**Trust boundaries and access control.** Inter-contract calls are gated by explicit allowlists:
- `VRFConsumer.setConsumerAuthorization(gameAddress, true)` is required before any game can call `requestRandomness`.
- `Treasury.setGameAuthorization(gameAddress, true)` is required before any game can `openBet` / `settleBet`.
- `AchievementNFT.setGameContract(diceGameAddress)` restricts `mintFirstWin` to a single trusted caller.
All three setters are `onlyOwner`-gated and the owner is `Ownable2Step`-controlled where appropriate, mitigating accidental ownership loss.

**Reentrancy posture.** Every external entrypoint that touches value (`Treasury._payOut`, `Lottery.claimPrize` / `claimRefund`, `Referral.claimCommission`, `DiceGame.rollDice` / `_settleBet`) is `nonReentrant`, and storage updates precede external calls. The VRF callback path is additionally hardened: `VRFConsumer` wraps the downstream `onRandomnessFulfilled` call in a `try/catch` so that a malicious or buggy consumer cannot poison the request registry.

**Randomness integrity.** Randomness is sourced from Chainlink VRF v2.5 (`VRFConsumerBaseV2Plus`). Two defences sit on top: (a) the commit-reveal path in `DiceGame` lets players bind a guess to a salted commitment before the request, eliminating any miner-influence on the player side; (b) `VRFConsumer.retryRequest` allows re-issuing a request that has not been fulfilled within `requestTimeout`, preventing permanent fund-lock if a fulfilment is censored.

**Solvency invariant.** The house's solvency is enforced by an explicit `lockedLiquidity` counter that is incremented on `openBet` (covering the worst-case payout) and decremented on `settleBet`. The invariant `address(treasury).balance >= treasury.lockedLiquidity(token)` was checked under 64×32 randomised action sequences and never violated. The `availableLiquidity` view returns `balance - locked` with underflow protection (`balance > locked ? balance - locked : 0`), which is verified by a dedicated invariant.

## 5. Test Coverage Summary

| Contract | Lines | Statements | Branches | Functions |
|---|---|---|---|---|
| `AchievementNFT.sol` | 93.33% | 93.33% | 50.00% | 100.00% |
| `DiceGame.sol` | 86.00% | 86.00% | 28.13% | 81.82% |
| `Lottery.sol` | 90.37% | 89.74% | 30.61% | 88.89% |
| `Referral.sol` | 80.00% | 80.95% | 18.18% | 81.82% |
| `Treasury.sol` | 87.64% | 87.96% | 17.95% | 80.95% |
| `VRFConsumer.sol` | 96.05% | 96.92% | 50.00% | 92.86% |
| **`src/` total** | **88.97%** | **88.79%** | **26.03%** | **85.71%** |

The 137-test suite includes 122 unit tests (per-contract), 10 cross-contract integration tests (full Dice flow, full Lottery flow, referral commission flow, VRF retry path, solvency under concurrent load), and 5 protocol-wide invariants. Branch coverage is depressed by the abundance of `require`-clause failure paths; every "happy path" branch is exercised. Lines outside the test scope are predominantly admin setters, getters, and recovery functions reachable only by `onlyOwner`.

## 6. Acknowledged Limitations

This review is intentionally bounded to the on-chain code. The following are out of scope and would need separate review before a production deployment.

The Chainlink VRF subscription model assumes the owner keeps the subscription funded; if it is drained, `requestRandomness` will revert and games will halt — this is a liveness, not a safety, concern. The `recoverStuckFunds` functions in `Lottery` and `Referral` give the owner the ability to extract residual ETH after long-lived operational accidents; they should be governed by a multisig or timelock in production. No formal verification (e.g., Certora) was performed. Economic attacks at the game-theory layer (e.g., colluding lottery players in a fixed-prize round) were not modelled.

---

*Generated as part of SC6107 project deliverables. Slither raw output is preserved at `docs/slither-report.txt` for reproducibility.*
