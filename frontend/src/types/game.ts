import type { Address } from 'viem';

export type AppMode = 'mock' | 'live';

export type FlowStage =
  | 'idle'
  | 'wallet_confirming'
  | 'tx_pending'
  | 'vrf_pending'
  | 'reveal_pending'
  | 'settled'
  | 'failed';

export type TokenKind = 'native' | 'erc20';
export type DiceMode = 'standard' | 'commit_reveal';

export interface SupportedToken {
  symbol: string;
  label: string;
  address: Address;
  decimals: number;
  kind: TokenKind;
  minBet: number;
  maxBet: number;
  accent: string;
}

export interface DiceBetInput {
  tokenSymbol: string;
  amount: string;
  prediction: number;
  mode: DiceMode;
  commitment?: string;
  salt?: string;
}

export interface DiceBetRecord {
  id: string;
  kind: 'dice';
  mode: DiceMode;
  tokenSymbol: string;
  amount: string;
  prediction: number;
  outcome: number;
  payout: string;
  requestId: string;
  treasuryBetId: string;
  txHash: string;
  settleTxHash?: string;
  randomWord: string;
  stage: Exclude<FlowStage, 'idle' | 'wallet_confirming' | 'tx_pending'>;
  createdAt: number;
  updatedAt: number;
  requestBlockNumber?: string;
  commitment: string;
  salt?: string;
  revealDeadline?: number;
  achievementMinted: boolean;
  wasForfeited: boolean;
  note?: string;
}

export interface PendingDiceBetRecord extends DiceBetRecord {
  resolveAt: number;
}

export interface LotteryEntryInput {
  tokenSymbol: string;
}

export interface LotteryHistoryRecord {
  id: string;
  kind: 'lottery';
  roundId: string;
  tokenSymbol: string;
  prizePool: string;
  participantCount: number;
  winner: string;
  requestId: string;
  txHash: string;
  settleTxHash: string;
  randomWord: string;
  stage: 'settled';
  createdAt: number;
  updatedAt: number;
  userWon: boolean;
  winnerCount?: number;
  claimable?: boolean;
}

export interface LotteryRoundState {
  roundId: string;
  tokenSymbol: string;
  tokenAddress?: Address;
  ticketPrice: string;
  ticketPriceRaw?: string;
  prizePool: string;
  prizePoolRaw?: string;
  participantCount: number;
  closesAt: number;
  userEntries: number;
  requestId?: string;
  numWinners?: number;
  prizesClaimable?: boolean;
  statusCode?: number;
  statusLabel?: string;
  canClaimPrize?: boolean;
  userIsWinner?: boolean;
  referralCode?: string;
  pendingCommission?: string;
  commissionBps?: number;
  lastDraw?: LotteryHistoryRecord;
}

export interface StoredLotteryRoundState extends LotteryRoundState {
  entrants: string[];
}

export type HistoryRecord = DiceBetRecord | LotteryHistoryRecord;

export interface FlowState {
  stage: FlowStage;
  txHash?: string;
  requestId?: string;
  settleTxHash?: string;
  error?: string;
}
