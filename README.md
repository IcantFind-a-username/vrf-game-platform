# SC6107 Group Project — On-Chain Verifiable Random Game Platform

## Member 1 Deliverable: VRF + Treasury Infrastructure

This repository contains the **shared infrastructure layer** that every game
contract on the platform depends on. It is deliberately self-contained: Members
2 & 3 build their game contracts (dice, lottery, …) *on top of* the three
interfaces exported here and never need to touch the infrastructure internals.

| Contract | Responsibility |
|----------|----------------|
| `VRFConsumer.sol` | Single integration point with **Chainlink VRF v2.5**. Owns the VRF subscription config, routes verifiable random words back to the requesting game, and exposes a timeout-based retry path. |
| `Treasury.sol` | The **house bank**. Escrows player stakes, reserves worst-case payouts, pays winners, applies the house edge, and supports native ETH plus arbitrary ERC-20 tokens. |
| `interfaces/` | `IVRFConsumer`, `IRandomnessConsumer`, `ITreasury` — the **only** surface Members 2 & 3 should compile against. |

---

## 1. Project layout

```
contracts/
├── src/
│   ├── VRFConsumer.sol            # Chainlink VRF v2.5 consumer
│   ├── Treasury.sol               # house fund pool
│   └── interfaces/
│       ├── IVRFConsumer.sol       # games CALL this to request randomness
│       ├── IRandomnessConsumer.sol# games IMPLEMENT this to receive randomness
│       └── ITreasury.sol          # games CALL this to escrow / pay out
├── script/
│   ├── HelperConfig.s.sol         # per-network parameters (Sepolia vs local)
│   └── Deploy.s.sol               # deploys VRFConsumer + Treasury
├── test/
│   ├── VRFConsumer.t.sol          # unit + fuzz tests
│   ├── Treasury.t.sol             # unit + fuzz tests
│   └── mocks/
│       ├── MockERC20.sol
│       ├── MockVRFCoordinator.sol # lets tests fulfil VRF synchronously
│       └── MockGame.sol           # reference game implementation
├── foundry.toml
├── remappings.txt
├── .env.example
└── README.md
```

---

## 2. Setup

This is a [Foundry](https://book.getfoundry.sh/) project.

```bash
# 1. Install Foundry (one-time, if not already installed)
curl -L https://foundry.paradigm.xyz | bash && foundryup

# 2. Install dependencies into lib/
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-commit
forge install smartcontractkit/chainlink-brownie-contracts --no-commit

# 3. Build & test
forge build
forge test -vvv
```

The import remappings (`remappings.txt` / `foundry.toml`) assume the directory
names produced by the commands above. If `forge install` checks a dependency
out under a different folder name, update the remapping accordingly.

---

## 3. Deployment

```bash
cp .env.example .env      # then fill in real values

# Local (Anvil) — deploys a MockVRFCoordinator automatically
anvil &
forge script script/Deploy.s.sol:DeployInfrastructure --rpc-url http://localhost:8545 --broadcast

# Sepolia testnet
forge script script/Deploy.s.sol:DeployInfrastructure \
  --rpc-url $SEPOLIA_RPC_URL --account <keystore> --broadcast --verify
```

**Sepolia prerequisite:** create a VRF v2.5 subscription at
<https://vrf.chain.link>, fund it with LINK, and put its id in `SUBSCRIPTION_ID`.
After deployment, register the deployed `VRFConsumer` address as a *consumer* on
that subscription (the deploy script prints this as a next step).

---

## 4. Integration guide for Members 2 & 3

Your game contract talks to the infrastructure through **two interfaces only**.

### 4.1 Receiving randomness

```solidity
import {IVRFConsumer} from "src/interfaces/IVRFConsumer.sol";
import {IRandomnessConsumer} from "src/interfaces/IRandomnessConsumer.sol";

contract DiceGame is IRandomnessConsumer {
    IVRFConsumer public immutable vrf;

    constructor(address vrfConsumer) {
        vrf = IVRFConsumer(vrfConsumer);
    }

    // STEP 1 — ask for randomness; store requestId -> bet mapping
    function roll() external {
        uint256 requestId = vrf.requestRandomness(1); // 1 random word
        // ... record requestId so the callback can find this bet
    }

    // STEP 2 — VRFConsumer calls you back here once Chainlink fulfils
    function onRandomnessFulfilled(uint256 requestId, uint256[] calldata words)
        external
        override
    {
        require(msg.sender == address(vrf), "only VRF");   // MANDATORY guard
        uint256 die = (words[0] % 6) + 1;
        // ... resolve the bet and call Treasury.settleBet(...)
    }
}
```

Rules:
- **Member 1 must authorise your game** before it can request: the infra owner
  calls `VRFConsumer.setConsumerAuthorization(yourGame, true)`. Tell Member 1
  your deployed address.
- `onRandomnessFulfilled` runs inside the VRF callback — keep it light (storage
  writes and a Treasury call are fine; no unbounded loops).
- If a request is never fulfilled (subscription ran dry), the game or the infra
  owner can call `vrf.retryRequest(requestId)` after the timeout.
- The callback is wrapped in `try/catch` on our side: a bug in your game cannot
  brick the VRF pipeline, and words are always retrievable via
  `vrf.getRandomWords(requestId)`.

### 4.2 Escrowing stakes and paying winners

```solidity
import {ITreasury} from "src/interfaces/ITreasury.sol";

ITreasury treasury = ITreasury(treasuryAddress);

// OPEN — pull the stake and reserve the worst-case payout.
// Native ETH: pass token = address(0) and forward msg.value == stake.
// ERC-20:     player must approve the Treasury for `stake` first.
uint256 betId = treasury.openBet{value: stake}(player, address(0), stake, maxPayout);

// SETTLE — release the reservation; payoutAmount is 0 on a loss.
treasury.settleBet(betId, payoutAmount);   // payoutAmount <= maxPayout
```

Rules:
- `maxPayout` is the **worst case** the house could owe — the Treasury locks
  exactly that much liquidity, so pass the true ceiling.
- Use `treasury.quotePayout(grossPayout)` to apply the house edge consistently.
- Only the game that opened a bet may settle it.
- Check `treasury.availableLiquidity(token)` and `getBetLimits(token)` before
  accepting a wager so the player gets a clean revert reason.

---

## 5. Network parameters (Sepolia, VRF v2.5)

| Parameter | Value |
|-----------|-------|
| VRF Coordinator | `0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B` |
| Key hash (500 gwei) | `0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae` |
| LINK token | `0x779877A7B0D9E8603169DdbD7836e478b4624789` |

These are wired into `script/HelperConfig.s.sol`; local runs use the mock
coordinator instead.

---

## 6. Testing

```bash
forge test -vvv            # all unit + fuzz tests
forge test --match-contract VRFConsumerTest
forge test --match-contract TreasuryTest
forge coverage             # coverage report
```

`MockVRFCoordinator` lets tests fulfil randomness synchronously, and `MockGame`
is a minimal reference implementation of `IRandomnessConsumer` (including a
`setShouldRevert` flag used to prove a faulty game cannot break the callback).

---

*SC6107 Group Project — Member 1 (VRF + Treasury Infrastructure).*
