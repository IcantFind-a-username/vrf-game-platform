'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  formatEther,
  parseAbiItem,
  parseEther,
  parseEventLogs,
  zeroHash,
  type Address,
} from 'viem';
import { useAccount, usePublicClient, useWriteContract } from 'wagmi';

import { achievementAbi } from '@/lib/abis/achievement';
import { diceGameAbi } from '@/lib/abis/diceGame';
import { vrfConsumerAbi } from '@/lib/abis/vrfConsumer';
import { contractAddresses } from '@/lib/addresses';
import { appConfig, appMode, demoTokens } from '@/lib/config';
import { formatCountdown } from '@/lib/utils/format';
import {
  clearLivePendingDiceBet,
  getLiveDiceHistory,
  getLivePendingDiceBet,
  liveDiceModeMessage,
  setLivePendingDiceBet,
  upsertLiveDiceHistory,
} from '@/services/live';
import {
  createPendingDiceBet,
  forfeitPendingDiceBet,
  getDiceHistory,
  revealPendingDiceBet,
  syncPendingDiceBet,
} from '@/services/mock';
import type {
  DiceBetRecord,
  DiceMode,
  FlowState,
  PendingDiceBetRecord,
} from '@/types/game';

const diceRollSettledEvent = parseAbiItem(
  'event DiceRollSettled(uint256 indexed requestId, uint256 indexed treasuryBetId, address indexed player, uint8 guess, uint8 result, bool won, uint256 payout)',
);

type OnchainDiceBet = {
  player: Address;
  token: Address;
  stake: bigint;
  guess: bigint | number;
  treasuryBetId: bigint;
  settled: boolean;
  won: boolean;
  result: bigint | number;
  isCommitReveal: boolean;
  commitment: `0x${string}`;
  randomFulfilled: boolean;
  randomWord: bigint;
  revealDeadline: bigint;
};

function buildHex(length: number) {
  return Array.from({ length }, () => Math.floor(Math.random() * 16).toString(16)).join('');
}

function createCommitArtifacts() {
  const salt = `0x${buildHex(64)}`;
  const commitment = `0x${buildHex(64)}`;
  return { salt, commitment };
}

function isPendingRecord(
  record: PendingDiceBetRecord | DiceBetRecord,
): record is PendingDiceBetRecord {
  return 'resolveAt' in record;
}

function computeDicePayout(amount: number, won: boolean) {
  if (!won) {
    return '0.00';
  }

  return (amount * 6 * (1 - 0.025)).toFixed(4);
}

function toFace(value: bigint | number) {
  return typeof value === 'bigint' ? Number(value) : value;
}

function toErrorMessage(error: unknown, fallback: string) {
  if (typeof error === 'object' && error && 'shortMessage' in error) {
    const shortMessage = (error as { shortMessage?: unknown }).shortMessage;

    if (typeof shortMessage === 'string' && shortMessage.trim()) {
      return shortMessage;
    }
  }

  if (error instanceof Error && error.message.trim()) {
    return error.message;
  }

  return fallback;
}

export function useDiceBet() {
  const { address, chainId, isConnected } = useAccount();
  const publicClient = usePublicClient({ chainId: appConfig.targetChainId });
  const { writeContractAsync } = useWriteContract();

  const diceTokens = useMemo(
    () => demoTokens.filter((token) => token.kind === 'native'),
    [],
  );
  const [selectedTokenSymbol, setSelectedTokenSymbol] = useState(diceTokens[0]?.symbol ?? 'ETH');
  const [mode, setMode] = useState<DiceMode>('standard');
  const [amount, setAmount] = useState('0.05');
  const [prediction, setPrediction] = useState(3);
  const [flow, setFlow] = useState<FlowState>({ stage: 'idle' });
  const [activeRecord, setActiveRecord] = useState<PendingDiceBetRecord | DiceBetRecord | null>(null);
  const [recentRecord, setRecentRecord] = useState<DiceBetRecord | null>(null);
  const [revealCountdown, setRevealCountdown] = useState<string | null>(null);
  const [isRevealSubmitting, setIsRevealSubmitting] = useState(false);
  const [isForfeitSubmitting, setIsForfeitSubmitting] = useState(false);
  const settleTimer = useRef<number | null>(null);
  const phaseTimers = useRef<number[]>([]);
  const runId = useRef(0);

  const selectedToken =
    diceTokens.find((token) => token.symbol === selectedTokenSymbol) ?? diceTokens[0];

  const payoutPreview = useMemo(() => {
    const numericAmount = Number(amount);

    if (!Number.isFinite(numericAmount) || numericAmount <= 0) {
      return '0.00';
    }

    return computeDicePayout(numericAmount, true);
  }, [amount]);

  const isRevealExpired = Boolean(
    activeRecord?.stage === 'reveal_pending' &&
      activeRecord.revealDeadline &&
      activeRecord.revealDeadline <= Date.now(),
  );

  const clearTimer = useCallback(() => {
    if (settleTimer.current) {
      window.clearTimeout(settleTimer.current);
      settleTimer.current = null;
    }

    phaseTimers.current.forEach((timer) => window.clearTimeout(timer));
    phaseTimers.current = [];
  }, []);

  const commitToState = useCallback((record: PendingDiceBetRecord | DiceBetRecord) => {
    setActiveRecord(record);
    setFlow({
      stage: record.stage,
      txHash: record.txHash,
      requestId: record.requestId,
      settleTxHash: record.settleTxHash,
    });

    if (record.stage === 'settled') {
      setRecentRecord(record);
    }
  }, []);

  const advancePendingRecord = useCallback(
    (record: PendingDiceBetRecord) => {
      clearTimer();

      const delay = Math.max(350, record.resolveAt - Date.now());
      settleTimer.current = window.setTimeout(() => {
        const nextRecord = syncPendingDiceBet();

        if (!nextRecord || nextRecord.id !== record.id) {
          return;
        }

        commitToState(nextRecord);
      }, delay);
    },
    [clearTimer, commitToState],
  );

  const settleLiveDiceBet = useCallback(
    async (record: DiceBetRecord) => {
      if (
        !publicClient ||
        !contractAddresses.diceGame ||
        !contractAddresses.vrfConsumer ||
        record.stage !== 'vrf_pending'
      ) {
        return false;
      }

      const requestId = BigInt(record.requestId);
      const onchainBet = (await publicClient.readContract({
        address: contractAddresses.diceGame,
        abi: diceGameAbi,
        functionName: 'bets',
        args: [requestId],
      })) as unknown as OnchainDiceBet;

      if (!onchainBet.settled) {
        return false;
      }

      const settleLogs = await publicClient.getLogs({
        address: contractAddresses.diceGame,
        event: diceRollSettledEvent,
        args: { requestId },
        fromBlock: record.requestBlockNumber ? BigInt(record.requestBlockNumber) : undefined,
        toBlock: 'latest',
      });

      const settleLog = settleLogs.at(-1);
      const settleTxHash = settleLog?.transactionHash ?? record.settleTxHash ?? record.txHash;
      let randomWord = onchainBet.randomWord.toString();

      try {
        const randomWords = (await publicClient.readContract({
          address: contractAddresses.vrfConsumer,
          abi: vrfConsumerAbi,
          functionName: 'getRandomWords',
          args: [requestId],
        })) as bigint[];

        if (randomWords[0] !== undefined) {
          randomWord = randomWords[0].toString();
        }
      } catch {
        // Keep the DiceGame-side fallback if the VRF read is temporarily unavailable.
      }

      let achievementMinted = false;

      if (contractAddresses.achievement && settleTxHash) {
        try {
          const receipt = await publicClient.getTransactionReceipt({
            hash: settleTxHash,
          });
          const achievementLogs = parseEventLogs({
            abi: achievementAbi,
            logs: receipt.logs,
            eventName: 'AchievementMinted',
            strict: false,
          });

          achievementMinted = achievementLogs.some((log) => {
            const player = log.args.player;
            return (
              typeof player === 'string' && player.toLowerCase() === onchainBet.player.toLowerCase()
            );
          });
        } catch {
          achievementMinted = false;
        }
      }

      const numericStake = Number(formatEther(onchainBet.stake));
      const payout =
        settleLog?.args.payout !== undefined
          ? formatEther(settleLog.args.payout)
          : computeDicePayout(numericStake, onchainBet.won);
      const settledRecord: DiceBetRecord = {
        ...record,
        amount: formatEther(onchainBet.stake),
        prediction: toFace(onchainBet.guess),
        outcome: toFace(onchainBet.result),
        payout,
        settleTxHash,
        randomWord,
        stage: 'settled',
        updatedAt: Date.now(),
        achievementMinted,
        note: achievementMinted
          ? 'AchievementMinted fired in the same settlement transaction.'
          : onchainBet.won
            ? 'DiceRollSettled marked this request as a win.'
            : 'DiceRollSettled marked this request as a loss.',
      };

      clearLivePendingDiceBet();
      upsertLiveDiceHistory(settledRecord);
      commitToState(settledRecord);
      return true;
    },
    [commitToState, publicClient],
  );

  useEffect(() => {
    const latest =
      appMode === 'live' ? getLiveDiceHistory()[0] ?? null : getDiceHistory()[0] ?? null;
    setRecentRecord(latest);

    if (appMode === 'mock') {
      const pending = syncPendingDiceBet();

      if (!pending) {
        return clearTimer;
      }

      commitToState(pending);

      if (isPendingRecord(pending) && pending.stage === 'vrf_pending') {
        advancePendingRecord(pending);
      }
    }

    if (appMode === 'live') {
      const pending = getLivePendingDiceBet();

      if (pending) {
        commitToState(pending);
      }
    }

    return clearTimer;
  }, [advancePendingRecord, clearTimer, commitToState]);

  useEffect(() => clearTimer, [clearTimer]);

  useEffect(() => {
    if (appMode !== 'live' || !activeRecord || activeRecord.stage !== 'vrf_pending') {
      return;
    }

    let cancelled = false;

    const sync = async () => {
      try {
        const settled = await settleLiveDiceBet(activeRecord);

        if (cancelled || !settled) {
          return;
        }
      } catch (error) {
        if (!cancelled) {
          setFlow({
            stage: 'failed',
            txHash: activeRecord.txHash,
            requestId: activeRecord.requestId,
            error: toErrorMessage(error, 'The bet was submitted, but settlement polling failed.'),
          });
        }
      }
    };

    void sync();
    const interval = window.setInterval(() => {
      void sync();
    }, 3500);

    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, [activeRecord, settleLiveDiceBet]);

  useEffect(() => {
    if (activeRecord?.stage !== 'reveal_pending' || !activeRecord.revealDeadline) {
      setRevealCountdown(null);
      return;
    }

    const refresh = () => {
      const remaining = activeRecord.revealDeadline ? formatCountdown(activeRecord.revealDeadline) : null;
      setRevealCountdown(remaining);
    };

    refresh();
    const timer = window.setInterval(refresh, 1000);
    return () => window.clearInterval(timer);
  }, [activeRecord]);

  const submitBet = useCallback(async () => {
    if (!selectedToken) {
      setFlow({
        stage: 'failed',
        error: 'Dice currently expects the native ETH path only.',
      });
      return;
    }

    const numericAmount = Number(amount);

    if (!Number.isFinite(numericAmount) || numericAmount < selectedToken.minBet) {
      setFlow({
        stage: 'failed',
        error: `Bet must be at least ${selectedToken.minBet} ${selectedToken.symbol}.`,
      });
      return;
    }

    if (numericAmount > selectedToken.maxBet) {
      setFlow({
        stage: 'failed',
        error: `Bet cannot exceed ${selectedToken.maxBet} ${selectedToken.symbol}.`,
      });
      return;
    }

    if (appMode === 'live') {
      if (mode !== 'standard') {
        setFlow({
          stage: 'failed',
          error: liveDiceModeMessage,
        });
        return;
      }

      if (!isConnected || !address) {
        setFlow({
          stage: 'failed',
          error: 'Connect a wallet before using the live Dice flow.',
        });
        return;
      }

      if (chainId !== appConfig.targetChainId) {
        setFlow({
          stage: 'failed',
          error: 'Switch the wallet to Sepolia before sending the Dice transaction.',
        });
        return;
      }

      if (!contractAddresses.diceGame || !publicClient) {
        setFlow({
          stage: 'failed',
          error: 'DiceGame address or Sepolia public client is missing from the live configuration.',
        });
        return;
      }

      clearTimer();
      runId.current += 1;
      setFlow({ stage: 'wallet_confirming' });

      try {
        const txHash = await writeContractAsync({
          address: contractAddresses.diceGame,
          abi: diceGameAbi,
          functionName: 'rollDice',
          args: [prediction],
          value: parseEther(amount),
          chainId: appConfig.targetChainId,
        });

        setFlow({ stage: 'tx_pending', txHash });

        const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
        const requestLogs = parseEventLogs({
          abi: diceGameAbi,
          logs: receipt.logs,
          eventName: 'DiceRollRequested',
          strict: false,
        });
        const requestLog = requestLogs.find((log) => {
          const player = log.args.player;
          return typeof player === 'string' && player.toLowerCase() === address.toLowerCase();
        });

        if (
          !requestLog ||
          requestLog.args.requestId === undefined ||
          requestLog.args.treasuryBetId === undefined
        ) {
          setFlow({
            stage: 'failed',
            txHash,
            error: 'Transaction mined, but DiceRollRequested was not found in the receipt logs.',
          });
          return;
        }

        const pendingRecord: DiceBetRecord = {
          id: `dice-live-${requestLog.args.requestId.toString()}`,
          kind: 'dice',
          mode: 'standard',
          tokenSymbol: selectedToken.symbol,
          amount,
          prediction,
          outcome: 0,
          payout: computeDicePayout(numericAmount, true),
          requestId: requestLog.args.requestId.toString(),
          treasuryBetId: requestLog.args.treasuryBetId.toString(),
          txHash,
          randomWord: 'Waiting for VRF fulfillment',
          stage: 'vrf_pending',
          createdAt: Date.now(),
          updatedAt: Date.now(),
          requestBlockNumber: receipt.blockNumber.toString(),
          commitment: zeroHash,
          achievementMinted: false,
          wasForfeited: false,
          note: 'DiceRollRequested emitted. Waiting for VRF callback and DiceRollSettled.',
        };

        setLivePendingDiceBet(pendingRecord);
        commitToState(pendingRecord);
      } catch (error) {
        setFlow({
          stage: 'failed',
          error: toErrorMessage(error, 'Dice transaction failed before the VRF request was created.'),
        });
      }

      return;
    }

    clearTimer();
    runId.current += 1;
    setFlow({ stage: 'wallet_confirming' });

    const currentRun = runId.current;

    phaseTimers.current.push(
      window.setTimeout(() => {
        if (runId.current !== currentRun) {
          return;
        }

        setFlow({ stage: 'tx_pending' });
      }, 650),
    );

    phaseTimers.current.push(
      window.setTimeout(() => {
        if (runId.current !== currentRun) {
          return;
        }

        const commitArtifacts = mode === 'commit_reveal' ? createCommitArtifacts() : null;
        const pending = createPendingDiceBet({
          tokenSymbol: selectedToken.symbol,
          amount,
          prediction,
          mode,
          commitment: commitArtifacts?.commitment,
          salt: commitArtifacts?.salt,
        });

        commitToState(pending);
        advancePendingRecord(pending);
      }, 1500),
    );
  }, [
    address,
    advancePendingRecord,
    amount,
    chainId,
    clearTimer,
    commitToState,
    isConnected,
    mode,
    prediction,
    publicClient,
    selectedToken,
    writeContractAsync,
  ]);

  const revealBet = useCallback(() => {
    if (!activeRecord || activeRecord.stage !== 'reveal_pending') {
      return;
    }

    if (appMode === 'live') {
      setFlow({
        stage: 'failed',
        error: liveDiceModeMessage,
      });
      return;
    }

    clearTimer();
    setIsRevealSubmitting(true);

    phaseTimers.current.push(
      window.setTimeout(() => {
        const settled = revealPendingDiceBet(activeRecord.id);
        setIsRevealSubmitting(false);

        if (!settled) {
          setFlow({
            stage: 'failed',
            error: 'Reveal failed. The reveal window may have expired or the bet is no longer revealable.',
          });
          return;
        }

        commitToState(settled);
      }, 900),
    );
  }, [activeRecord, clearTimer, commitToState]);

  const forfeitBet = useCallback(() => {
    if (!activeRecord || activeRecord.stage !== 'reveal_pending') {
      return;
    }

    if (appMode === 'live') {
      setFlow({
        stage: 'failed',
        error: liveDiceModeMessage,
      });
      return;
    }

    clearTimer();
    setIsForfeitSubmitting(true);

    phaseTimers.current.push(
      window.setTimeout(() => {
        const settled = forfeitPendingDiceBet(activeRecord.id);
        setIsForfeitSubmitting(false);

        if (!settled) {
          setFlow({
            stage: 'failed',
            error: 'Forfeit failed. The reveal deadline has not expired yet.',
          });
          return;
        }

        commitToState(settled);
      }, 900),
    );
  }, [activeRecord, clearTimer, commitToState]);

  const resetFlow = useCallback(() => {
    clearTimer();
    runId.current += 1;
    setFlow({ stage: 'idle' });
    setActiveRecord(null);
    setIsRevealSubmitting(false);
    setIsForfeitSubmitting(false);
  }, [clearTimer]);

  return {
    amount,
    setAmount,
    prediction,
    setPrediction,
    mode,
    setMode,
    selectedToken,
    selectedTokenSymbol,
    setSelectedTokenSymbol,
    payoutPreview,
    flow,
    submitBet,
    revealBet,
    forfeitBet,
    resetFlow,
    activeRecord,
    recentRecord,
    revealCountdown,
    tokens: diceTokens,
    liveMode: appMode === 'live',
    isRevealSubmitting,
    isForfeitSubmitting,
    isRevealExpired,
  };
}
