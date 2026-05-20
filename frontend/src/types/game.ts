import type { Address } from 'viem';

export type AppMode = 'mock' | 'live';

export type FlowStage =
  | 'idle'
  | 'wallet_confirming'
  | 'tx_pending'
  | 'vrf_pending'
  | 'settled'
  | 'failed';

export type TokenKind = 'native' | 'erc20';

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
  commitment?: string;
}

export interface DiceBetRecord {
  id: string;
  kind: 'dice';
  tokenSymbol: string;
  amount: string;
  prediction: number;
  outcome: number;
  payout: string;
  requestId: string;
  txHash: string;
  settleTxHash?: string;
  randomWord: string;
  stage: Exclude<FlowStage, 'idle' | 'wallet_confirming' | 'tx_pending'>;
  createdAt: number;
  updatedAt: number;
  commitment: string;
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
}

export interface LotteryRoundState {
  roundId: string;
  tokenSymbol: string;
  ticketPrice: string;
  prizePool: string;
  participantCount: number;
  closesAt: number;
  userEntries: number;
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
