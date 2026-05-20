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
