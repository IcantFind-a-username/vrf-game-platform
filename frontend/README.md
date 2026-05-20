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
- Dice page with full transaction/VRF waiting state machine
- Lottery page with round status, countdown, and entry flow
- History page with proof panel and local event history
- Mock mode that works without deployed contracts
- Live integration boundary for real ABI/address wiring

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
- `live`: intended for Sepolia once contract addresses and ABI fragments are finalized

Set `NEXT_PUBLIC_APP_MODE=mock` during UI development. Switch to `live` only after the Solidity team gives you:

- deployed contract addresses
- final function names and argument order
- final events for `requestId`, settlement, and round draws

## Teammate handoff checklist

You need these before real integration:

- `Treasury` address, supported tokens, decimals, min/max bet, house edge
- `DiceGame` address, `placeBet` signature, payout formula, request and settle events
- `Lottery` address, `enter` signature, round lifecycle reads, draw events
- `VRFConsumer` request status reads or emitted request/fulfill events
- token list for Sepolia testing

## Live integration notes

This scaffold intentionally keeps contract calls behind small hooks/services. Replace placeholder ABI fragments in:

- `src/lib/abis/diceGame.ts`
- `src/lib/abis/lottery.ts`
- `src/lib/abis/treasury.ts`

The `Lottery` ABI has already been aligned to the teammate delivery in [`../3/对接文档.md`](/Users/leis/Desktop/NTU%20Class/soft%20Engineer/On-Chain%20Verifiable%20Random%20Game%20Platform/3/%E5%AF%B9%E6%8E%A5%E6%96%87%E6%A1%A3.md) and [`../3/contracts/src/Lottery.sol`](/Users/leis/Desktop/NTU%20Class/soft%20Engineer/On-Chain%20Verifiable%20Random%20Game%20Platform/3/contracts/src/Lottery.sol).
The `DiceGame` ABI has been aligned to the 2号 handoff document at [`/Users/leis/Desktop/NTU Class/soft Engineer/副本前端对接细节.docx`](/Users/leis/Desktop/NTU%20Class/soft%20Engineer/%E5%89%AF%E6%9C%AC%E5%89%8D%E7%AB%AF%E5%AF%B9%E6%8E%A5%E7%BB%86%E8%8A%82.docx).

Then finish the `live` paths inside:

- `src/hooks/useDiceBet.ts`
- `src/hooks/useLottery.ts`
- `src/hooks/useBetHistory.ts`

Use `docs/contract-handoff-template.md` to collect the missing integration details from the Solidity teammates in one pass.

## Demo path

For presentation, the cleanest flow is:

1. connect wallet
2. place a mock Dice bet
3. show the pending `VRF` status
4. wait for settlement
5. open History and show `requestId`, `txHash`, and random output
