# Sepolia Deployment — VRF + Treasury Infrastructure

Live deployment record for Member 1's infrastructure (VRFConsumer + Treasury).
Members 2 & 3 wire their game contracts against the **interface addresses**
listed below; Member 4 (frontend) reads the ABIs from `abi-export/`.

---

## 1. Live contract addresses (Sepolia, chain id `11155111`)

| Contract | Address | Etherscan |
|---|---|---|
| `VRFConsumer` | `0x64754668789Cc46F7d441c09D9293C97d6257E2C` | [view](https://sepolia.etherscan.io/address/0x64754668789Cc46F7d441c09D9293C97d6257E2C) |
| `Treasury`    | `0x526BD277AF3efc291a98f5958b16783cc9821B75` | [view](https://sepolia.etherscan.io/address/0x526BD277AF3efc291a98f5958b16783cc9821B75) |

Both contracts are source-verified on Etherscan (compiler `0.8.24`, evm
`cancun`, optimizer 200 runs). Click "Read Contract" / "Write Contract" on
Etherscan to inspect or interact without a frontend.

Deployment block: **10887318**  ·  Time: **2026-05-21 03:02 +0800**.
Deployment tx hashes (in order):

| # | Tx | What |
|---|---|---|
| 1 | [`0x7365…d287f`](https://sepolia.etherscan.io/tx/0x7365d98507738251d265a00e197aa9b8c169ad3b303ed581fe3ab933f2cd287f) | `new VRFConsumer(...)` |
| 2 | [`0x7064…6f537a`](https://sepolia.etherscan.io/tx/0x7064ba74b1f4782d5cad82054919c4aae4505b04b49eaa9eeae7be24fe6f537a) | `new Treasury(burner, 250)` |
| 3 | [`0x9d6e…9562`](https://sepolia.etherscan.io/tx/0x9d6ef8fd598f11f734c3e899b4d551502cedcef6dd7504d3d183ac7f8aea9562) | `treasury.setTokenConfig(native, true, 0.001e18, 1e18)` |

Total gas paid: ~0.00333 ETH (at ~1.14 gwei). Full broadcast record is at
`broadcast/Deploy.s.sol/11155111/run-latest.json`.

---

## 2. Owners and roles

| Role | Address | Notes |
|---|---|---|
| `VRFConsumer` owner | `0x1D67990A03516faCB2d0Ac1A1032b2B2c2E8efB2` | Burner, controlled by Member 1's keystore (`sc6107-burner`). Authorises games. |
| `Treasury` owner | `0x1D67990A03516faCB2d0Ac1A1032b2B2c2E8efB2` | Same burner. Funds liquidity, authorises games, pauses. |
| VRF subscription owner | `0xF5Dde46166841C378e103407a9359CaA15c4c567` | Member 1's MetaMask main account. Controls subscription funding and consumer list at <https://vrf.chain.link>. |

The split is intentional: short-lived burner holds the contracts (low blast
radius if compromised); long-lived main account holds the LINK subscription.

---

## 3. Chainlink VRF v2.5 wiring

| Field | Value |
|---|---|
| Coordinator | `0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B` (Sepolia VRF v2.5) |
| Key hash (500 gwei lane) | `0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae` |
| Callback gas limit | `200000` |
| Min request confirmations | `3` (contract default) |
| LINK token (Sepolia) | `0x779877A7B0D9E8603169DdbD7836e478b4624789` |
| Subscription ID | `29173988086987794818438618165995115150286917712747714981239241593185491730107` |
| Current LINK balance | `5 LINK` (top up at <https://vrf.chain.link> when low) |
| Registered consumers | `[VRFConsumer]` |

Subscription dashboard:
<https://vrf.chain.link/sepolia/29173988086987794818438618165995115150286917712747714981239241593185491730107>

---

## 4. Treasury default configuration

| Setting | Value |
|---|---|
| House edge | `250 bps` (2.5%) |
| Pause status | `false` |
| Supported tokens | native ETH only (ERC-20 disabled by default) |
| Native ETH min bet | `0.001 ETH` |
| Native ETH max bet | `1 ETH` |
| House liquidity | `0` (Member 1 to top up before any real-money play) |

To enable an ERC-20 (e.g. mUSDC) later:
```bash
cast send $TREASURY "setTokenConfig(address,bool,uint256,uint256)" \
  $TOKEN true $MIN_BET_WEI $MAX_BET_WEI \
  --rpc-url $SEPOLIA_RPC_URL --account sc6107-burner
```

To deposit house liquidity (native ETH example):
```bash
cast send $TREASURY "depositLiquidity(address,uint256)" \
  0x0000000000000000000000000000000000000000 1000000000000000000 \
  --value 1ether \
  --rpc-url $SEPOLIA_RPC_URL --account sc6107-burner
```

---

## 5. Wiring game contracts (Members 2 & 3, when ready)

After a game contract (e.g. `DiceGame`, `Lottery`) is deployed at address
`$GAME`, Member 1 (burner) runs these two calls so the game can request
randomness and escrow stakes:

```bash
# 1. Allow the game to call VRFConsumer.requestRandomness
cast send 0x64754668789Cc46F7d441c09D9293C97d6257E2C \
  "setConsumerAuthorization(address,bool)" $GAME true \
  --rpc-url $SEPOLIA_RPC_URL --account sc6107-burner

# 2. Allow the game to open / settle bets on Treasury
cast send 0x526BD277AF3efc291a98f5958b16783cc9821B75 \
  "setGameAuthorization(address,bool)" $GAME true \
  --rpc-url $SEPOLIA_RPC_URL --account sc6107-burner
```

To revoke later, pass `false` instead of `true`.

The VRF subscription's consumer list is **independent** from
`VRFConsumer.setConsumerAuthorization` — only `VRFConsumer` itself needs to
be on the subscription. Adding the game contract to the subscription is
neither needed nor possible.

---

## 6. ABIs for the frontend (Member 4)

ABIs for the live contracts are committed under `abi-export/`:

```
abi-export/
├── VRFConsumer.abi.json          # 30 functions, 10 events, 10 custom errors
├── Treasury.abi.json             # 29 functions, 11 events, 21 custom errors
├── IVRFConsumer.abi.json         # games call this (5 functions)
├── IRandomnessConsumer.abi.json  # games implement this (1 function)
└── ITreasury.abi.json            # games call this (8 functions)
```

The interface ABIs (`I*.json`) are smaller and stable; prefer them when the
frontend only needs read/write methods, not internal events. To pull updated
ABIs after a recompile:

```bash
forge build
for C in VRFConsumer Treasury IVRFConsumer IRandomnessConsumer ITreasury; do
  jq '.abi' "out/${C}.sol/${C}.json" > "abi-export/${C}.abi.json"
done
```

---

## 7. Reproducing this deployment from scratch

```bash
# clone + install deps
git clone https://github.com/IcantFind-a-username/vrf-game-platform.git
cd vrf-game-platform
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0
forge install smartcontractkit/chainlink-brownie-contracts

# build + test
forge build
forge test -vvv

# fill in your own SUBSCRIPTION_ID and ETHERSCAN_API_KEY
cp .env.example .env

# import a burner keystore (do this in a real Terminal, not an IDE shell)
cast wallet import my-burner --interactive

# deploy
source .env && forge script script/Deploy.s.sol:DeployInfrastructure \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account my-burner \
  --broadcast \
  --verify
```

---

## 8. Quick health checks

```bash
RPC=https://ethereum-sepolia.publicnode.com
VRF=0x64754668789Cc46F7d441c09D9293C97d6257E2C
TREASURY=0x526BD277AF3efc291a98f5958b16783cc9821B75

# Owners
cast call $VRF      "owner()(address)" --rpc-url $RPC
cast call $TREASURY "owner()(address)" --rpc-url $RPC

# VRF wiring
cast call $VRF "subscriptionId()(uint256)"     --rpc-url $RPC
cast call $VRF "keyHash()(bytes32)"            --rpc-url $RPC
cast call $VRF "callbackGasLimit()(uint32)"    --rpc-url $RPC

# Treasury config
cast call $TREASURY "houseEdgeBps()(uint16)" --rpc-url $RPC
cast call $TREASURY "paused()(bool)"         --rpc-url $RPC
cast call $TREASURY "tokenConfig(address)(bool,uint256,uint256)" \
  0x0000000000000000000000000000000000000000 --rpc-url $RPC
```

If any of these returns an unexpected value, something has been changed since
the deployment block (10887318) — check Etherscan tx history to see what.

---

## 9. Deploying the Dice game layer (Members 2)

The dice layer comprises two contracts: `DiceGame` and `AchievementNFT`. Both
are bundled into `script/DeployDice.s.sol`, which reads the
`VRFConsumer` / `Treasury` addresses from environment variables (or
`HelperConfig`) and wires the contracts together at deploy time.

### 9.1 Prerequisites

```bash
# These must already be set in .env (or exported in shell)
export VRF_CONSUMER=0x64754668789Cc46F7d441c09D9293C97d6257E2C
export TREASURY=0x526BD277AF3efc291a98f5958b16783cc9821B75
export SEPOLIA_RPC_URL=https://ethereum-sepolia.publicnode.com
export ETHERSCAN_API_KEY=<your key>
```

### 9.2 Deploy

```bash
source .env && forge script script/DeployDice.s.sol:DeployDice \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account sc6107-burner \
  --broadcast \
  --verify
```

The script performs these on-chain actions in a single broadcast:

1. `new AchievementNFT(owner)` — deploys the NFT contract.
2. `new DiceGame(owner, vrfConsumer, treasury, achievementNFT)` — deploys the dice game with all four dependencies wired into immutable state.
3. `achievementNFT.setGameContract(diceGame)` — grants the dice game exclusive minting authority.

The broadcast record will be written to `broadcast/DeployDice.s.sol/11155111/run-latest.json`.

### 9.3 Post-deploy wiring (run by Member 1 / Treasury owner)

After the script returns, capture `$DICE_GAME` from the broadcast record (or
the script's console output) and authorise it on the infrastructure layer:

```bash
DICE_GAME=<address from script output>

cast send $VRF_CONSUMER "setConsumerAuthorization(address,bool)" $DICE_GAME true \
  --rpc-url $SEPOLIA_RPC_URL --account sc6107-burner

cast send $TREASURY "setGameAuthorization(address,bool)" $DICE_GAME true \
  --rpc-url $SEPOLIA_RPC_URL --account sc6107-burner
```

Verify with:

```bash
cast call $VRF_CONSUMER "isAuthorizedConsumer(address)(bool)" $DICE_GAME --rpc-url $SEPOLIA_RPC_URL
cast call $TREASURY "isAuthorizedGame(address)(bool)" $DICE_GAME --rpc-url $SEPOLIA_RPC_URL
# both should print true
```

---

## 10. Deploying the Lottery layer (Member 3)

The lottery layer comprises `Lottery` and `Referral`. They are deployed
together by `script/DeployLottery.s.sol`.

### 10.1 Deploy

```bash
source .env && forge script script/DeployLottery.s.sol:DeployLottery \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account sc6107-burner \
  --broadcast \
  --verify
```

The script performs:

1. `new Referral(owner, commissionBps = 100)` — 1% commission tracker.
2. `new Lottery(owner, vrfConsumer, treasury)` — deploys the lottery.
3. `lottery.setReferral(referral)` — links lottery → referral.
4. `referral.setLottery(lottery)` — links referral → lottery (only the lottery can call `recordTicketPurchase`).

### 10.2 Post-deploy wiring (run by Member 1 / Treasury owner)

```bash
LOTTERY=<address from script output>

cast send $VRF_CONSUMER "setConsumerAuthorization(address,bool)" $LOTTERY true \
  --rpc-url $SEPOLIA_RPC_URL --account sc6107-burner

cast send $TREASURY "setGameAuthorization(address,bool)" $LOTTERY true \
  --rpc-url $SEPOLIA_RPC_URL --account sc6107-burner
```

### 10.3 Funding the house

Before opening a lottery round (or accepting dice bets at non-trivial size),
the `Treasury` must have enough liquidity to cover the worst-case payout of
all open bets simultaneously. Top up:

```bash
cast send $TREASURY "depositLiquidity(address,uint256)" \
  0x0000000000000000000000000000000000000000 5000000000000000000 \
  --value 5ether \
  --rpc-url $SEPOLIA_RPC_URL --account sc6107-burner
```

This deposits 5 ETH of house liquidity. Confirm with:

```bash
cast call $TREASURY "availableLiquidity(address)(uint256)" \
  0x0000000000000000000000000000000000000000 \
  --rpc-url $SEPOLIA_RPC_URL
# should return 5000000000000000000 (= 5 ether)
```

---

## 11. Post-deployment wiring checklist

When deploying the full stack to a fresh network, run this checklist top-to-bottom and tick each box.

- [ ] `Deploy.s.sol` ran successfully; `VRFConsumer` and `Treasury` addresses recorded.
- [ ] Both contracts verified on Etherscan (`--verify` flag, or `forge verify-contract` manually).
- [ ] `VRFConsumer` registered as a consumer on the VRF v2.5 subscription dashboard.
- [ ] LINK balance on the subscription is ≥ 5 LINK (or equivalent) for testing headroom.
- [ ] `Treasury.setTokenConfig(NATIVE, true, minBet, maxBet)` executed.
- [ ] `Treasury.depositLiquidity(NATIVE, amount)` executed with at least `maxBet × 10`.
- [ ] `DeployDice.s.sol` ran; `DiceGame` and `AchievementNFT` addresses recorded.
- [ ] `AchievementNFT.setGameContract(diceGame)` confirmed (the deploy script does this, but verify).
- [ ] `VRFConsumer.setConsumerAuthorization(diceGame, true)` executed.
- [ ] `Treasury.setGameAuthorization(diceGame, true)` executed.
- [ ] `DeployLottery.s.sol` ran; `Lottery` and `Referral` addresses recorded.
- [ ] `Lottery.setReferral(referral)` and `Referral.setLottery(lottery)` confirmed.
- [ ] `VRFConsumer.setConsumerAuthorization(lottery, true)` executed.
- [ ] `Treasury.setGameAuthorization(lottery, true)` executed.
- [ ] All six addresses added to `abi-export/addresses.json` (or equivalent) for the frontend.
- [ ] Smoke test: place a dummy dice bet of the minimum stake and confirm it settles within ~2 minutes.
- [ ] Smoke test: create a 10-minute lottery round with 5 tickets max, buy one ticket from a different account, wait for the round to end, trigger the draw, claim the prize.

---

## 12. Troubleshooting

**`VRFConsumer.requestRandomness` reverts with `OnlyAuthorizedConsumer`.**
The game contract was not added to the consumer allowlist. Run
`cast send $VRF_CONSUMER "setConsumerAuthorization(address,bool)" $GAME true`
from the VRFConsumer owner account.

**`Treasury.openBet` reverts with `UnauthorizedGame`.**
The game contract is not on the Treasury allowlist. Run
`cast send $TREASURY "setGameAuthorization(address,bool)" $GAME true`
from the Treasury owner account.

**`Treasury.openBet` reverts with `InsufficientLiquidity`.**
`availableLiquidity(token) < maxPayout` for the requested bet. Either reduce
the stake (which reduces `maxPayout = stake × 6 × (1 - houseEdge)` on dice) or
top up liquidity with `depositLiquidity`.

**`VRFConsumer.requestRandomness` reverts with a Chainlink error.**
The subscription is out of LINK, or `VRFConsumer` has not been added as a
consumer on the subscription dashboard. Visit
<https://vrf.chain.link/sepolia/<subId>> and check both.

**VRF callback never arrives (request stuck in `PENDING`).**
After `requestTimeout` (default 1 hour), call `VRFConsumer.retryRequest(requestId)`
to re-submit the request to Chainlink. The original request stays marked as
`RETRIED`; the new requestId is emitted in the `RequestRetried` event.

**Deploy script aborts with `Error: Failed to get nonce`.**
The keystore was not unlocked or `$SEPOLIA_RPC_URL` is unreachable. Verify
with `cast wallet ls` and `cast block-number --rpc-url $SEPOLIA_RPC_URL`.

**Etherscan verification fails with "Already verified" but UI shows unverified.**
Etherscan has cached the wrong source. Wait 5 minutes and reload, or
manually re-verify with `forge verify-contract --watch`.

**`forge build` fails with "stack too deep".**
`via_ir = true` should be set in `foundry.toml`. If you forked from an old
revision, copy the setting from the current `foundry.toml` and retry.

**Tests pass locally but `forge coverage` errors out.**
Use `forge coverage --ir-minimum --no-match-coverage "(script|test)"`. The
`--ir-minimum` flag is required when `via_ir` is enabled; the
`--no-match-coverage` filter excludes deploy scripts and test helpers from
the total.

---

*SC6107 Group Project — Deployment record and operational guide.*
