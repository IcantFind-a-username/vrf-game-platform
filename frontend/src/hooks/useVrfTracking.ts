'use client';

import { useMemo } from 'react';

import type { FlowStage } from '@/types/game';

const STEP_ORDER = [
  { key: 'wallet_confirming', label: 'Wallet signature' },
  { key: 'tx_pending', label: 'Transaction inclusion' },
  { key: 'vrf_pending', label: 'VRF callback pending' },
  { key: 'settled', label: 'Settlement completed' },
] as const;

const RANK: Record<FlowStage, number> = {
  idle: 0,
  wallet_confirming: 1,
  tx_pending: 2,
  vrf_pending: 3,
  settled: 4,
  failed: 0,
};

export function useVrfTracking(stage: FlowStage) {
  return useMemo(
    () =>
      STEP_ORDER.map((step, index) => ({
        ...step,
        active: stage !== 'failed' && RANK[stage] === index + 1,
        complete: stage !== 'failed' && RANK[stage] > index + 1,
      })),
    [stage],
  );
}
