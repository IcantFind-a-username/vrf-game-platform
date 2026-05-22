# SC6107 Group Project — On-Chain Verifiable Random Game Platform

A two-game gambling protocol built on Foundry and deployed to Ethereum Sepolia, with all randomness sourced from **Chainlink VRF v2.5**. Players can roll a 1d6 dice (instant or commit-reveal) and participate in pari-mutuel lottery rounds; both games share a single house bank (`Treasury`) that enforces a protocol-wide solvency invariant. First-win dice players are minted a one-shot achievement NFT, and lottery referrals earn a 1% commission.

[![Tests](https://img.shields.io/badge/tests-137%20passing-brightgreen)]()
[![Coverage](https://img.shields.io/badge/coverage-88.97%25-brightgreen)]()
[![Slither](https://img.shields.io/badge/slither-0%20critical-brightgreen)]()
[![Solidity](https://img.shields.io/badge/solidity-0.8.24-blue)]()

---

## 1. Contracts

The protocol is organised into a game-agnostic **infrastructure layer** and a game-specific **game layer**, joined by four narrow interfaces.

| Contract | Layer | Responsibility |
|---|---|---|
| `VRFConsumer.sol` | Infra | Single integration point with Chainlink VRF v2.5. Authorises games via `setConsumerAuthorization`, routes random words back through `IRandomnessConsumer`, and exposes a timeout-based retry path. |
| `Treasury.sol` | Infra | House bank. Locks worst-case payouts on `openBet`, releases them on `settleBet`, applies a configurable house edge (default 2.5%, capped at 20%), and supports native ETH plus arbitrary ERC-20 tokens. |
| `DiceGame.sol` | Game | 1d6 dice. Two play modes: instant `rollDice(guess)` and a commit-reveal flow (`commitRoll` → `revealRoll`) that pre-binds the guess for MEV resistance. |
| `Lottery.sol` | Game | Pari-mutuel lottery with multiple winners per round, referral integration, refund-on-cancel, and a 24h VRF-timeout retry path. |
| `AchievementNFT.sol` | Game | ERC-721 NFT minted exactly once per address on a first dice win. |
| `Referral.sol` | Game | Off-chain-style referral commission tracker. Records purchases from referred buyers and pays out 1% commission on `claimCommission`. |

Interfaces in `src/interfaces/` (`IVRFConsumer`, `IRandomnessConsumer`, `ITreasury`, `IReferral`) are the only surface a new game contract should compile against.

For a deep dive into call graphs, sequence diagrams, and design decisions, see **[`docs/architecture.md`](docs/architecture.md)**.

## 2. Project layout

```
vrf-game-platform/
├── src/
│   ├── VRFConsumer.sol            # Chainlink VRF v2.5 consumer (infra)
│   ├── Treasury.sol               # house bank (infra)
│   ├── DiceGame.sol               # 1d6 dice (game)
│   ├── Lottery.sol                # pari-mutuel lottery (game)
│   ├── AchievementNFT.sol         # ERC-721 first-win NFT (game)
│   ├── Referral.sol               # referral commission tracker (game)
│   └── interfaces/
│       ├── IVRFConsumer.sol       # games CALL this to request randomness
│       ├── IRandomnessConsumer.sol# games IMPLEMENT this to receive randomness
│       ├── ITreasury.sol          # games CALL this to escrow / pay out
│       └── IReferral.sol          # Lottery calls this to record purchases
├── script/
│   ├── HelperConfig.s.sol         # per-network parameters (Sepolia vs local)
│   ├── Deploy.s.sol               # infrastructure deploy (VRFConsumer + Treasury)
│   ├── DeployDice.s.sol           # DiceGame + AchievementNFT deploy
│   └── DeployLottery.s.sol        # Lottery + Referral deploy
├── test/
│   ├── *.t.sol                    # 122 unit + fuzz tests
│   ├── integration/EndToEnd.t.sol # 10 cross-contract integration tests
│   ├── invariant/SystemInvariant.t.sol # 5 protocol-wide invariants
│   └── mocks/
│       ├── MockERC20.sol
│       ├── MockGame.sol
│       ├── MockTreasury.sol
│       ├── MockVRFConsumer.sol
│       └── MockVRFCoordinator.sol
├── docs/
│   ├── architecture.md            # system diagrams + design decisions
│   ├── security-analysis.md       # Slither + manual review findings
│   ├── gas-optimization.md        # hot-path analysis + recommendations
│   ├── coverage-report.txt        # forge coverage summary
│   ├── slither-report.txt         # raw Slither output
│   └── gas-report.txt             # raw forge --gas-report output
├── abi-export/                    # frontend-consumable ABIs
├── frontend/                      # web frontend (Member 4)
├── broadcast/                     # Foundry deployment artifacts
├── DEPLOYMENT.md                  # live deployment record + ops guide
├── foundry.toml
├── remappings.txt
├── .env.example
└── README.md
```

## 3. Setup

A [Foundry](https://book.getfoundry.sh/) toolchain is required (`forge`, `cast`, `anvil`).

```bash
# 1. Install Foundry (one-time)
curl -L https://foundry.paradigm.xyz | bash && foundryup

# 2. Clone and install dependencies
git clone https://github.com/IcantFind-a-username/vrf-game-platform.git
cd vrf-game-platform
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0
forge install smartcontractkit/chainlink-brownie-contracts

# 3. Build & test
forge build
forge test -vvv
```

Solc is pinned to `0.8.24` and `via_ir = true` is enabled in `foundry.toml`. The first build is slow (~30s) because `via_ir` routes compilation through Yul; subsequent builds are incremental.

## 4. Testing & Quality

The test suite covers all six contracts and the cross-contract integration paths.

| Layer | Files | Tests |
|---|---|---|
| Unit + fuzz (per-contract) | `test/*.t.sol` | 122 |
| Cross-contract integration | `test/integration/EndToEnd.t.sol` | 10 |
| Protocol-wide invariants (handler-driven fuzz) | `test/invariant/SystemInvariant.t.sol` | 5 |
| **Total** |  | **137** |

Run individual layers:

```bash
forge test                            # full suite
forge test --match-path "test/integration/*"
forge test --match-path "test/invariant/*"
forge coverage --ir-minimum --no-match-coverage "(script|test)"
forge test --gas-report
```

**Coverage** (production source only): 88.97% lines, 88.79% statements, 85.71% functions. See [`docs/coverage-report.txt`](docs/coverage-report.txt) for the per-file breakdown.

**Static analysis** with Slither (v0.10.x, 101 detectors, 44 contracts) produced 55 findings, none of them exploitable. See [`docs/security-analysis.md`](docs/security-analysis.md) for severity classification and the rationale for each acknowledged finding.

**Gas profile** is documented in [`docs/gas-optimization.md`](docs/gas-optimization.md) with hot-path analysis and concrete optimization recommendations.

## 5. Deployment

The protocol is live on **Sepolia** (chain id `11155111`).

| Contract | Sepolia Address |
|---|---|
| `VRFConsumer` | [`0x64754668789Cc46F7d441c09D9293C97d6257E2C`](https://sepolia.etherscan.io/address/0x64754668789Cc46F7d441c09D9293C97d6257E2C) |
| `Treasury`    | [`0x526BD277AF3efc291a98f5958b16783cc9821B75`](https://sepolia.etherscan.io/address/0x526BD277AF3efc291a98f5958b16783cc9821B75) |

The full deployment record, owner addresses, VRF subscription configuration, and reproducibility commands are in **[`DEPLOYMENT.md`](DEPLOYMENT.md)**.

To deploy a fresh local instance against Anvil:

```bash
cp .env.example .env  # fill in any values

# terminal 1
anvil

# terminal 2
forge script script/Deploy.s.sol:DeployInfrastructure \
  --rpc-url http://localhost:8545 --broadcast
forge script script/DeployDice.s.sol:DeployDice \
  --rpc-url http://localhost:8545 --broadcast
forge script script/DeployLottery.s.sol:DeployLottery \
  --rpc-url http://localhost:8545 --broadcast
```

## 6. Documentation Index

| Document | What's in it |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | System diagrams (Mermaid), bet/round lifecycle sequence diagrams, trust boundaries, core design decisions |
| [`docs/security-analysis.md`](docs/security-analysis.md) | Slither findings broken down by severity, manual review notes, acknowledged limitations |
| [`docs/gas-optimization.md`](docs/gas-optimization.md) | Top-5 hot paths, optimizations already applied, recommendations with estimated savings, optimizations deliberately not applied |
| [`docs/coverage-report.txt`](docs/coverage-report.txt) | Per-file `forge coverage` output |
| [`docs/slither-report.txt`](docs/slither-report.txt) | Raw `slither` output for reproducibility |
| [`docs/gas-report.txt`](docs/gas-report.txt) | Raw `forge --gas-report` output |
| [`DEPLOYMENT.md`](DEPLOYMENT.md) | Live Sepolia deployment record, VRF subscription state, post-deploy wiring checklist, troubleshooting |

## 7. Team & Responsibilities

| Member | Deliverable |
|---|---|
| 1 | VRF + Treasury infrastructure, infrastructure deployment to Sepolia |
| 2 | DiceGame contract (instant + commit-reveal modes), AchievementNFT |
| 3 | Lottery contract (pari-mutuel, multi-winner draws), Referral |
| 4 | Web frontend (`frontend/`), ABI export pipeline, demo video |
| 5 | Integration & invariant testing, security review (Slither), gas profiling, architecture documentation, full-project README, expanded deployment guide |

## 8. License

MIT. See `LICENSE`.

---

*SC6107 Group Project — On-Chain Verifiable Random Game Platform.*
