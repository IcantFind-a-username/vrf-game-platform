'use client';

import { useMemo } from 'react';

import type { DiceMode, FlowStage } from '@/types/game';

export function useVrfTracking(stage: FlowStage, mode: DiceMode) {
  return useMemo(
    () => {
      const steps =
        mode === 'commit_reveal'
          ? [
              { key: 'wallet_confirming', label: 'Wallet signature' },
              { key: 'tx_pending', label: 'Commit transaction included' },
              { key: 'vrf_pending', label: 'VRF callback pending' },
              { key: 'reveal_pending', label: 'Reveal required' },
              { key: 'settled', label: 'Settlement completed' },
            ]
          : [
              { key: 'wallet_confirming', label: 'Wallet signature' },
              { key: 'tx_pending', label: 'Transaction inclusion' },
              { key: 'vrf_pending', label: 'VRF callback pending' },
              { key: 'settled', label: 'Settlement completed' },
            ];

      const currentIndex = steps.findIndex((step) => step.key === stage);

      return steps.map((step, index) => ({
        ...step,
        active: stage !== 'failed' && stage !== 'settled' && currentIndex === index,
        complete:
          stage !== 'failed' &&
          (stage === 'settled' ? currentIndex >= index : currentIndex > index),
      }));
    },
    [mode, stage],
  );
}
