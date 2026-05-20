'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { useAccount } from 'wagmi';

import { appMode, demoTokens } from '@/lib/config';
import { formatCountdown } from '@/lib/utils/format';
import { liveIntegrationMessage } from '@/services/live';
import { enterLotteryRound, getLotteryState, syncLotteryRound } from '@/services/mock';
import type { FlowState, LotteryRoundState } from '@/types/game';

export function useLottery() {
  const { address } = useAccount();
  const [selectedTokenSymbol, setSelectedTokenSymbol] = useState('USDC');
  const [flow, setFlow] = useState<FlowState>({ stage: 'idle' });
  const [round, setRound] = useState<LotteryRoundState | null>(null);
  const [countdown, setCountdown] = useState('--:--');
  const phaseTimers = useRef<number[]>([]);
  const runId = useRef(0);

  const clearPhaseTimers = useCallback(() => {
    phaseTimers.current.forEach((timer) => window.clearTimeout(timer));
    phaseTimers.current = [];
  }, []);

  const refreshRound = useCallback(() => {
    if (appMode !== 'mock') {
      return;
    }

    const nextRound = syncLotteryRound();
    setRound(nextRound);
    setCountdown(formatCountdown(nextRound.closesAt));
  }, []);

  useEffect(() => {
    if (appMode !== 'mock') {
      return;
    }

    const currentRound = getLotteryState();
    setRound(currentRound);
    setCountdown(formatCountdown(currentRound.closesAt));

    const timer = window.setInterval(() => {
      refreshRound();
    }, 1000);

    return () => {
      window.clearInterval(timer);
      clearPhaseTimers();
    };
  }, [clearPhaseTimers, refreshRound]);

  useEffect(() => clearPhaseTimers, [clearPhaseTimers]);

  const enterRound = useCallback(async () => {
    if (appMode === 'live') {
      setFlow({
        stage: 'failed',
        error: liveIntegrationMessage,
      });
      return;
    }

    clearPhaseTimers();
    runId.current += 1;
    setFlow({ stage: 'wallet_confirming' });
    const currentRun = runId.current;

    phaseTimers.current.push(
      window.setTimeout(() => {
        if (runId.current !== currentRun) {
          return;
        }

        setFlow({ stage: 'tx_pending' });
      }, 500),
    );

    phaseTimers.current.push(
      window.setTimeout(() => {
        if (runId.current !== currentRun) {
          return;
        }

        const { txHash, updatedRound } = enterLotteryRound(
          { tokenSymbol: selectedTokenSymbol },
          address,
        );

        setRound(updatedRound);
        setCountdown(formatCountdown(updatedRound.closesAt));
        setFlow({
          stage: 'settled',
          txHash,
        });
      }, 1350),
    );
  }, [address, clearPhaseTimers, selectedTokenSymbol]);

  return {
    flow,
    round,
    countdown,
    enterRound,
    refreshRound,
    selectedTokenSymbol,
    setSelectedTokenSymbol,
    tokens: demoTokens.filter((token) => token.symbol !== 'ETH'),
    liveMode: appMode === 'live',
  };
}
