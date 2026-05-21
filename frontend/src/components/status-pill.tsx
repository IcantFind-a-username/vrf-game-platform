import type { FlowStage } from '@/types/game';

const LABELS: Record<FlowStage, string> = {
  idle: 'Idle',
  wallet_confirming: 'Wallet signature',
  tx_pending: 'Transaction pending',
  vrf_pending: 'Waiting for VRF',
  reveal_pending: 'Reveal required',
  settled: 'Settled',
  failed: 'Failed',
};

export function StatusPill({ stage }: { stage: FlowStage }) {
  return (
    <span className="status-pill" data-state={stage}>
      {LABELS[stage]}
    </span>
  );
}
