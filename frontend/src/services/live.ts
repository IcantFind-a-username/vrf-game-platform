import { readStorage, removeStorage, writeStorage } from '@/lib/utils/storage';
import type { DiceBetRecord, HistoryRecord, LotteryHistoryRecord } from '@/types/game';

const STORAGE_KEYS = {
  diceHistory: 'vrf-live-dice-history',
  dicePending: 'vrf-live-dice-pending',
  lotteryHistory: 'vrf-live-lottery-history',
} as const;

export const liveIntegrationMessage =
  'Live wiring now covers the Sepolia Dice demo path and the Lottery round dashboard. The remaining gaps are mainly optional flows like referral claim UX and any unsupported token approval path.';

export const liveHistoryMessage =
  'Live history reflects Dice settlements and any Lottery draw records that this browser session has already observed on Sepolia.';

export const liveDiceModeMessage =
  'The production demo path is currently the standard rollDice(uint8 guess) flow with native ETH. Commit-reveal stays available in mock mode as an advanced UX path.';

export function getLiveDiceHistory() {
  return readStorage<DiceBetRecord[]>(STORAGE_KEYS.diceHistory, []);
}

export function getLiveLotteryHistory() {
  return readStorage<LotteryHistoryRecord[]>(STORAGE_KEYS.lotteryHistory, []);
}

export function getLivePendingDiceBet() {
  return readStorage<DiceBetRecord | null>(STORAGE_KEYS.dicePending, null);
}

export function setLivePendingDiceBet(record: DiceBetRecord) {
  writeStorage(STORAGE_KEYS.dicePending, record);
}

export function clearLivePendingDiceBet() {
  removeStorage(STORAGE_KEYS.dicePending);
}

export function upsertLiveDiceHistory(record: DiceBetRecord) {
  const history = getLiveDiceHistory().filter((entry) => entry.id !== record.id);
  const nextHistory = [record, ...history].sort((a, b) => b.updatedAt - a.updatedAt);
  writeStorage(STORAGE_KEYS.diceHistory, nextHistory);
  return nextHistory;
}

export function upsertLiveLotteryHistory(record: LotteryHistoryRecord) {
  const history = getLiveLotteryHistory().filter((entry) => entry.id !== record.id);
  const nextHistory = [record, ...history].sort((a, b) => b.updatedAt - a.updatedAt);
  writeStorage(STORAGE_KEYS.lotteryHistory, nextHistory);
  return nextHistory;
}

export function getLiveCombinedHistory() {
  return [...getLiveDiceHistory(), ...getLiveLotteryHistory()].sort(
    (a, b) => b.updatedAt - a.updatedAt,
  ) as HistoryRecord[];
}

export function resetLiveData() {
  removeStorage(STORAGE_KEYS.diceHistory);
  removeStorage(STORAGE_KEYS.dicePending);
  removeStorage(STORAGE_KEYS.lotteryHistory);
}
