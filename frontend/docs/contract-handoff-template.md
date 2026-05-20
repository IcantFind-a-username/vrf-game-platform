# Contract Handoff Template

Send this template to the Solidity teammates and ask them to fill it before you switch the frontend from `mock` to `live`.

## 1. Deployment

- Network:
- Deployment date:
- Explorer base URL:
- Treasury address:
- DiceGame address:
- Lottery address:
- VRFConsumer address:
- Achievement address:

## 2. Supported tokens

For each token, provide:

- symbol
- token address
- decimals
- native or ERC-20
- min bet
- max bet
- if `approve` is required before interaction

## 3. Dice contract

- Write function name:
- Exact argument order:
- Which argument carries commitment:
- Is the bet payable for ETH mode:
- Read functions needed by UI:
- Bet placed event name:
- Bet settled event name:
- Which event carries `requestId`:
- Which event carries `randomWord`:
- Which event carries `payout`:
- Revert reasons the UI should map:

## 4. Lottery contract

- Write function name:
- Exact argument order:
- Current round read functions:
- Prize pool read function:
- Countdown or close time read function:
- Round entered event name:
- Round drawn event name:
- Which event carries `requestId`:
- Which event carries `winner`:
- Which event carries `prizePool`:
- Revert reasons the UI should map:

## 5. Treasury / payout rules

- House edge in basis points:
- Does payout happen inside the game contract or via Treasury:
- Is there a withdraw/claim flow:
- Does the frontend need to show treasury balance:

## 6. VRF details

- Request event name:
- Fulfill event name:
- Is request status queryable on-chain:
- Is retry visible as a different event:
- Should the frontend poll a view function or watch events:

## 7. Final integration checks

- Example Sepolia test wallet:
- Example successful Dice tx hash:
- Example successful Lottery tx hash:
- Example failed tx hash:
- ABI file path or JSON artifact:
