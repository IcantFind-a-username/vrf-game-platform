# VRF Game Platform Frontend

Frontend owner deliverable for the "On-Chain Verifiable Random Game Platform" project.

## Stack

- Next.js App Router
- TypeScript
- wagmi + viem
- RainbowKit
- TanStack Query

## What is already built

- Wallet connection and Sepolia network guard
- Dice page with standard roll and commit-reveal transaction states
- Lottery page with round status, countdown, and entry flow
- History page with proof panel and local event history
- Mock mode that works without deployed contracts
- Live Dice integration for the standard Sepolia demo path

## Setup

1. Install dependencies:

```bash
npm install
```

2. Create env file:

```bash
cp .env.example .env.local
```

3. Start development server:

```bash
npm run dev
```

## Modes

- `mock`: fully interactive local demo, no chain required
- `live`: Sepolia Dice and Lottery flows wired for the currently deployed contracts

Set `NEXT_PUBLIC_APP_MODE=mock` during UI development. Switch to `live` once:

- `VRFConsumer` / `Treasury` are deployed and configured
- `DiceGame` / `AchievementNFT` addresses are present in your env file
- your wallet is on Sepolia (`11155111`)
- Lottery deployment handoff is either complete or intentionally out of scope for the current demo

## Teammate handoff checklist

You still need these before the whole frontend is live-complete:

- any round-specific ERC-20 approve path if Lottery stops using the native ETH route
- final claim / refund UX decisions for the Lottery demo

## Live integration notes

This scaffold intentionally keeps contract calls behind small hooks/services. The Dice-side and Lottery-side ABI fragments are aligned to the real handoff artifacts that have been shared so far.

- `src/lib/abis/diceGame.ts`
- `src/lib/abis/lottery.ts`
- `src/lib/abis/treasury.ts`

The `Lottery` ABI has already been aligned to the teammate delivery in [`../3/对接文档.md`](/Users/leis/Desktop/NTU%20Class/soft%20Engineer/On-Chain%20Verifiable%20Random%20Game%20Platform/3/%E5%AF%B9%E6%8E%A5%E6%96%87%E6%A1%A3.md) and [`../3/contracts/src/Lottery.sol`](/Users/leis/Desktop/NTU%20Class/soft%20Engineer/On-Chain%20Verifiable%20Random%20Game%20Platform/3/contracts/src/Lottery.sol).
The `DiceGame` and `AchievementNFT` ABI fragments have been cross-checked against the 2号 artifact JSON handoff.

Then finish the `live` paths inside:

- `src/hooks/useDiceBet.ts`
- `src/hooks/useLottery.ts`
- `src/hooks/useBetHistory.ts`

Use `docs/contract-handoff-template.md` to collect the missing integration details from the Solidity teammates in one pass.

## Current Sepolia infrastructure

Member 1's live infrastructure is already deployed:

- `VRFConsumer`: `0x64754668789Cc46F7d441c09D9293C97d6257E2C`
- `Treasury`: `0x526BD277AF3efc291a98f5958b16783cc9821B75`
- supported token: native ETH only
- native ETH min/max: `0.001 ETH / 1 ETH`
- house edge: `2.5%`

See the shared contract repo's `deployment.md` and `abi-export/` directory for the latest record.

Member 2's Dice stack is also deployed:

- `DiceGame`: `0xc90e921B96dd4a5FFeb9F6b1c127DF52d16129D8`
- `AchievementNFT`: `0x5Cda95708af8Db02E5f9693e3aEA122d2A2e173d`
- `chainId`: `11155111`
- `VRFConsumer` / `Treasury` authorization: confirmed `true`

Member 3's Lottery stack is also deployed:

- `Lottery`: `0x76B471aCD6cC083BDf0EB9684a68D596052cFee7`
- `Referral`: `0x8c2B85bC09C66635031985669937874B9ebbD506`
- `chainId`: `11155111`

## Demo path

For presentation, the cleanest flow is:

1. connect wallet
2. switch to Sepolia and place a standard Dice bet with ETH
3. show the pending `VRF` status
4. wait for settlement
5. open History and show `requestId`, `txHash`, and raw random output
6. mention commit-reveal as the advanced anti-cheating path already supported in the contract and mock UI

For Lottery, the cleanest live walkthrough is:

1. open the Lottery page on Sepolia
2. show the current round status, ticket price, prize pool, and participant count
3. buy a single live ticket
4. point out the request ID / last draw trace and the referral commission snapshot
