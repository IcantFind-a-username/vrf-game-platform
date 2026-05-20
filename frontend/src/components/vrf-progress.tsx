'use client';

import { useVrfTracking } from '@/hooks/useVrfTracking';
import type { FlowStage } from '@/types/game';

export function VrfProgress({ stage }: { stage: FlowStage }) {
  const steps = useVrfTracking(stage);

  return (
    <div className="progress-list">
      {steps.map((step) => (
        <div
          key={step.key}
          className="progress-step"
          data-active={step.active}
          data-complete={step.complete}
        >
          <div className="progress-marker" />
          <div>{step.label}</div>
        </div>
      ))}
    </div>
  );
}
