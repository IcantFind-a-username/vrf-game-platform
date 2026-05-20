'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { appMode, demoTokens } from '@/lib/config';
import {
  createPendingDiceBet,
  getDiceHistory,
  getPendingDiceBet,
  settlePendingDiceBet,
} from '@/services/mock';
import { liveIntegrationMessage } from '@/services/live';
import type { DiceBetRecord, FlowState, PendingDiceBetRecord } from '@/types/game';

function buildCommitment() {
  return `0x${Array.from({ length: 64 }, () => Math.floor(Math.random() * 16).toString(16)).join('')}`;
}

export function useDiceBet() {
  const [selectedTokenSymbol, setSelectedTokenSymbol] = useState(demoTokens[0].symbol);
  const [amount, setAmount] = useState('25');
  const [prediction, setPrediction] = useState(3);
  const [flow, setFlow] = useState<FlowState>({ stage: 'idle' });
  const [activeRecord, setActiveRecord] = useState<PendingDiceBetRecord | DiceBetRecord | null>(null);
  const [recentRecord, setRecentRecord] = useState<DiceBetRecord | null>(null);
  const settleTimer = useRef<number | null>(null);
  const phaseTimers = useRef<number[]>([]);
  const runId = useRef(0);

  const selectedToken =
    demoTokens.find((token) => token.symbol === selectedTokenSymbol) ?? demoTokens[0];

  const payoutPreview = useMemo(() => {
    const numericAmount = Number(amount);

    if (!Number.isFinite(numericAmount) || numericAmount <= 0) {
      return '0.00';
    }

    return (numericAmount * 6 * (1 - 0.025)).toFixed(2);
  }, [amount]);

  const clearTimer = useCallback(() => {
    if (settleTimer.current) {
      window.clearTimeout(settleTimer.current);
      settleTimer.current = null;
    }
    phaseTimers.current.forEach((timer) => window.clearTimeout(timer));
    phaseTimers.current = [];
  }, []);

  const resolvePending = useCallback(
    (pending: PendingDiceBetRecord) => {
      clearTimer();

      const delay = Math.max(350, pending.resolveAt - Date.now());
      settleTimer.current = window.setTimeout(() => {
        const settled = settlePendingDiceBet(pending.id);

        if (!settled) {
          return;
        }

        setActiveRecord(settled);
        setRecentRecord(settled);
        setFlow({
          stage: 'settled',
          txHash: settled.txHash,
          requestId: settled.requestId,
          settleTxHash: settled.settleTxHash,
        });
      }, delay);
    },
    [clearTimer],
  );

  useEffect(() => {
    const latest = getDiceHistory()[0] ?? null;
    setRecentRecord(latest);

    if (appMode !== 'mock') {
      return;
    }

    const pending = getPendingDiceBet();

    if (!pending) {
      return;
    }

    setActiveRecord(pending);
    setFlow({
      stage: 'vrf_pending',
      txHash: pending.txHash,
      requestId: pending.requestId,
      settleTxHash: pending.settleTxHash,
    });
    resolvePending(pending);

    return clearTimer;
  }, [clearTimer, resolvePending]);

  useEffect(() => clearTimer, [clearTimer]);

  const submitBet = useCallback(async () => {
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
      setFlow({
        stage: 'failed',
        error: liveIntegrationMessage,
      });
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

        const pending = createPendingDiceBet({
          tokenSymbol: selectedToken.symbol,
          amount,
          prediction,
          commitment: buildCommitment(),
        });

        setActiveRecord(pending);
        setFlow({
          stage: 'vrf_pending',
          txHash: pending.txHash,
          requestId: pending.requestId,
          settleTxHash: pending.settleTxHash,
        });
        resolvePending(pending);
      }, 1500),
    );
  }, [amount, clearTimer, prediction, resolvePending, selectedToken]);

  const resetFlow = useCallback(() => {
    clearTimer();
    runId.current += 1;
    setFlow({ stage: 'idle' });
    setActiveRecord(null);
  }, [clearTimer]);

  return {
    amount,
    setAmount,
    prediction,
    setPrediction,
    selectedToken,
    selectedTokenSymbol,
    setSelectedTokenSymbol,
    payoutPreview,
    flow,
    submitBet,
    resetFlow,
    activeRecord,
    recentRecord,
    tokens: demoTokens,
    liveMode: appMode === 'live',
  };
}
