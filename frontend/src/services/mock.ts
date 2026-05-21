import type { Address } from 'viem';

import { demoTokens } from '@/lib/config';
import { readStorage, removeStorage, writeStorage } from '@/lib/utils/storage';
import type {
  DiceBetInput,
  DiceBetRecord,
  LotteryEntryInput,
  LotteryHistoryRecord,
  LotteryRoundState,
  PendingDiceBetRecord,
  StoredLotteryRoundState,
} from '@/types/game';

const STORAGE_KEYS = {
  diceHistory: 'vrf-demo-dice-history',
  dicePending: 'vrf-demo-dice-pending',
  lotteryState: 'vrf-demo-lottery-state',
  lotteryHistory: 'vrf-demo-lottery-history',
} as const;

function randomHex(length: number) {
  const alphabet = '0123456789abcdef';
  return Array.from({ length }, () => alphabet[Math.floor(Math.random() * alphabet.length)]).join(
    '',
  );
}

function randomHash() {
  return `0x${randomHex(64)}`;
}

function randomWord() {
  const value = BigInt(`0x${randomHex(16)}`);
  return value.toString();
}

function randomAddress() {
  return `0x${randomHex(40)}` as Address;
}

function now() {
  return Date.now();
}

function computeDicePayout(amount: number, won: boolean) {
  if (!won) {
    return '0.00';
  }

  const houseEdge = 0.025;
  return (amount * 6 * (1 - houseEdge)).toFixed(2);
}

function nextRoundId(previousRoundId?: string) {
  const currentValue = previousRoundId ? Number(previousRoundId.replace('ROUND-', '')) : 12;
  return `ROUND-${String(currentValue + 1).padStart(3, '0')}`;
}

function createBaseLotteryRound(previousRoundId?: string): StoredLotteryRoundState {
  const seedParticipants = 12 + Math.floor(Math.random() * 8);
  const entrants = Array.from({ length: seedParticipants }, () => randomAddress());
  const ticketPrice = '10.00';

  return {
    roundId: nextRoundId(previousRoundId),
    tokenSymbol: 'USDC',
    ticketPrice,
    prizePool: (seedParticipants * Number(ticketPrice)).toFixed(2),
    participantCount: seedParticipants,
    closesAt: now() + 1000 * 60 * 18,
    userEntries: 0,
    statusLabel: 'Open',
    canClaimPrize: false,
    userIsWinner: false,
    entrants,
  };
}

function readLotteryState(): StoredLotteryRoundState {
  const stored = readStorage<StoredLotteryRoundState | null>(STORAGE_KEYS.lotteryState, null);

  if (stored) {
    const normalized: StoredLotteryRoundState = {
      ...stored,
      statusLabel: stored.statusLabel ?? 'Open',
      canClaimPrize: stored.canClaimPrize ?? false,
      userIsWinner: stored.userIsWinner ?? false,
    };

    writeStorage(STORAGE_KEYS.lotteryState, normalized);
    return normalized;
  }

  const fresh = createBaseLotteryRound();
  writeStorage(STORAGE_KEYS.lotteryState, fresh);
  return fresh;
}

function writeLotteryState(state: StoredLotteryRoundState) {
  writeStorage(STORAGE_KEYS.lotteryState, state);
}

export function getSupportedTokens() {
  return demoTokens;
}

export function getDiceHistory() {
  return readStorage<DiceBetRecord[]>(STORAGE_KEYS.diceHistory, []);
}

export function getLotteryHistory() {
  return readStorage<LotteryHistoryRecord[]>(STORAGE_KEYS.lotteryHistory, []);
}

export function getCombinedHistory() {
  return [...getDiceHistory(), ...getLotteryHistory()].sort((a, b) => b.createdAt - a.createdAt);
}

export function getPendingDiceBet() {
  return readStorage<PendingDiceBetRecord | null>(STORAGE_KEYS.dicePending, null);
}

function hasAnyMockWin() {
  return getDiceHistory().some((record) => Number(record.payout) > 0);
}

function savePendingDiceBet(record: PendingDiceBetRecord) {
  writeStorage(STORAGE_KEYS.dicePending, record);
}

function finalizeDiceBet(
  pending: PendingDiceBetRecord,
  overrides?: Partial<DiceBetRecord>,
): DiceBetRecord {
  const isWin = overrides?.payout ? Number(overrides.payout) > 0 : Number(pending.payout) > 0;
  const shouldMintAchievement = isWin && !hasAnyMockWin();

  return {
    ...pending,
    stage: 'settled',
    updatedAt: now(),
    achievementMinted: shouldMintAchievement,
    wasForfeited: overrides?.wasForfeited ?? pending.wasForfeited,
    note:
      overrides?.note ??
      (shouldMintAchievement
        ? 'First win achieved. Achievement NFT would mint on the live contract.'
        : pending.note),
    ...overrides,
  };
}

export function createPendingDiceBet(input: DiceBetInput): PendingDiceBetRecord {
  const amount = Number(input.amount);
  const outcome = Math.floor(Math.random() * 6) + 1;
  const won = outcome === input.prediction;
  const isCommitReveal = input.mode === 'commit_reveal';
  const revealDeadline = isCommitReveal ? now() + 1000 * 60 * 5 : undefined;

  const record: PendingDiceBetRecord = {
    id: `dice-${crypto.randomUUID()}`,
    kind: 'dice',
    mode: input.mode,
    tokenSymbol: input.tokenSymbol,
    amount: amount.toFixed(2),
    prediction: input.prediction,
    outcome,
    payout: computeDicePayout(amount, won),
    requestId: randomHash(),
    treasuryBetId: randomHash(),
    txHash: randomHash(),
    settleTxHash: randomHash(),
    randomWord: randomWord(),
    stage: 'vrf_pending',
    createdAt: now(),
    updatedAt: now(),
    resolveAt: now() + 4200,
    commitment: input.commitment ?? randomHash(),
    salt: input.salt,
    revealDeadline,
    achievementMinted: false,
    wasForfeited: false,
    note: isCommitReveal
      ? 'Commit submitted. Wait for randomness, then reveal the original guess to settle.'
      : won
        ? 'Prediction matched. Settlement will credit payout.'
        : 'House wins this roll.',
  };

  savePendingDiceBet(record);
  return record;
}

export function syncPendingDiceBet() {
  const pending = getPendingDiceBet();

  if (!pending) {
    return null;
  }

  if (pending.stage !== 'vrf_pending' || pending.resolveAt > now()) {
    return pending;
  }

  if (pending.mode === 'commit_reveal') {
    const revealReady: PendingDiceBetRecord = {
      ...pending,
      stage: 'reveal_pending',
      updatedAt: now(),
      note: 'Randomness is ready. Submit the reveal transaction before the deadline.',
    };

    savePendingDiceBet(revealReady);
    return revealReady;
  }

  const settled = finalizeDiceBet(pending);
  const history = getDiceHistory();
  writeStorage(STORAGE_KEYS.diceHistory, [settled, ...history]);
  removeStorage(STORAGE_KEYS.dicePending);
  return settled;
}

export function settlePendingDiceBet(id: string) {
  const pending = getPendingDiceBet();

  if (!pending || pending.id !== id) {
    return null;
  }

  const syncedPending = syncPendingDiceBet();

  if (!syncedPending || syncedPending.id !== id) {
    return null;
  }

  if (syncedPending.stage !== 'vrf_pending') {
    return syncedPending.stage === 'settled' ? syncedPending : null;
  }

  const settled = finalizeDiceBet(syncedPending);

  const history = getDiceHistory();
  writeStorage(STORAGE_KEYS.diceHistory, [settled, ...history]);
  removeStorage(STORAGE_KEYS.dicePending);
  return settled;
}

export function revealPendingDiceBet(id: string) {
  const pending = syncPendingDiceBet();

  if (!pending || pending.id !== id || pending.stage !== 'reveal_pending') {
    return null;
  }

  if (pending.revealDeadline && pending.revealDeadline < now()) {
    return null;
  }

  const settled = finalizeDiceBet(pending, {
    note:
      Number(pending.payout) > 0
        ? 'Reveal confirmed. Dice outcome settled and payout released.'
        : 'Reveal confirmed. The dice resolved against the player.',
  });

  const history = getDiceHistory();
  writeStorage(STORAGE_KEYS.diceHistory, [settled, ...history]);
  removeStorage(STORAGE_KEYS.dicePending);
  return settled;
}

export function forfeitPendingDiceBet(id: string) {
  const pending = syncPendingDiceBet();

  if (!pending || pending.id !== id || pending.stage !== 'reveal_pending') {
    return null;
  }

  if (!pending.revealDeadline || pending.revealDeadline > now()) {
    return null;
  }

  const settled = finalizeDiceBet(pending, {
    outcome: 0,
    payout: '0.00',
    wasForfeited: true,
    note: 'Reveal window expired. The bet was forfeited and settled as a loss.',
  });

  const history = getDiceHistory();
  writeStorage(STORAGE_KEYS.diceHistory, [settled, ...history]);
  removeStorage(STORAGE_KEYS.dicePending);
  return settled;
}

export function getLotteryState(): LotteryRoundState {
  const state = syncLotteryRound();
  return state;
}

export function enterLotteryRound(input: LotteryEntryInput, userAddress?: string) {
  const state = readLotteryState();
  const nextParticipantCount = state.participantCount + 1;
  const ticketPrice = Number(state.ticketPrice);

  const updated: StoredLotteryRoundState = {
    ...state,
    tokenSymbol: input.tokenSymbol,
    participantCount: nextParticipantCount,
    prizePool: (Number(state.prizePool) + ticketPrice).toFixed(2),
    userEntries: state.userEntries + 1,
    entrants: [...state.entrants, userAddress ?? randomAddress()],
  };

  writeLotteryState(updated);

  return {
    txHash: randomHash(),
    updatedRound: updated,
  };
}

export function syncLotteryRound() {
  const currentState = readLotteryState();

  if (currentState.closesAt > now()) {
    return currentState;
  }

  const entrantCount = Math.max(1, currentState.entrants.length);
  const winnerIndex = Math.floor(Math.random() * entrantCount);
  const winner = currentState.entrants[winnerIndex] ?? randomAddress();
  const requestId = randomHash();
  const drawRecord: LotteryHistoryRecord = {
    id: `lottery-${crypto.randomUUID()}`,
    kind: 'lottery',
    roundId: currentState.roundId,
    tokenSymbol: currentState.tokenSymbol,
    prizePool: currentState.prizePool,
    participantCount: currentState.participantCount,
    winner,
    requestId,
    txHash: randomHash(),
    settleTxHash: randomHash(),
    randomWord: randomWord(),
    stage: 'settled',
    createdAt: currentState.closesAt,
    updatedAt: now(),
    userWon: winner === currentState.entrants[currentState.entrants.length - 1],
  };

  const lotteryHistory = getLotteryHistory();
  writeStorage(STORAGE_KEYS.lotteryHistory, [drawRecord, ...lotteryHistory]);

  const nextRound = createBaseLotteryRound(currentState.roundId);
  nextRound.lastDraw = drawRecord;
  writeLotteryState(nextRound);

  return nextRound;
}

export function fastForwardLotteryRound() {
  const currentState = readLotteryState();
  const expiredRound: StoredLotteryRoundState = {
    ...currentState,
    closesAt: now() - 1000,
    statusLabel: 'Closed',
  };

  writeLotteryState(expiredRound);
  return syncLotteryRound();
}

export function resetMockData() {
  Object.values(STORAGE_KEYS).forEach(removeStorage);
}

export function getPlatformSnapshot() {
  const diceHistory = getDiceHistory();
  const lotteryHistory = getLotteryHistory();
  const latestDice = diceHistory[0];
  const latestLottery = lotteryHistory[0];

  return {
    totalSettlements: diceHistory.length + lotteryHistory.length,
    latestDicePayout: latestDice?.payout ?? '0.00',
    latestRequestId: latestDice?.requestId ?? latestLottery?.requestId ?? 'Not settled yet',
    activeTokens: getSupportedTokens().map((token) => token.symbol).join(', '),
  };
}
