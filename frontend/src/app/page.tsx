'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

import { NetworkGuard } from '@/components/network-guard';
import { StatChip } from '@/components/stat-chip';
import { WalletPanel } from '@/components/wallet-panel';
import { diceLiveReady, infrastructureReady, lotteryLiveReady } from '@/lib/addresses';
import { appConfig, appMode, uiCopy } from '@/lib/config';
import { getPlatformSnapshot } from '@/services/mock';
import { getLiveCombinedHistory } from '@/services/live';

export default function OverviewPage() {
  const [snapshot, setSnapshot] = useState({
    totalSettlements: 0,
    latestDicePayout: '0.00',
    latestRequestId: 'Not settled yet',
    activeTokens: 'ETH',
  });

  useEffect(() => {
    const refresh = () => {
      if (appMode === 'live') {
        const liveHistory = getLiveCombinedHistory();
        const latestDice = liveHistory.find((record) => record.kind === 'dice');

        setSnapshot({
          totalSettlements: liveHistory.length,
          latestDicePayout: latestDice?.kind === 'dice' ? latestDice.payout : '0.00',
          latestRequestId: latestDice?.requestId ?? 'No live settlement yet',
          activeTokens: 'ETH',
        });
        return;
      }

      setSnapshot(getPlatformSnapshot());
    };

    refresh();
    const interval = window.setInterval(refresh, 1500);
    return () => window.clearInterval(interval);
  }, []);

  return (
    <>
      <div className="hero-grid">
        <section className="panel hero-card">
          <div className="eyebrow">Frontend showcase</div>
          <h1 className="hero-title">We built this frontend around the flow the marker can verify.</h1>
          <p className="hero-copy">
            {appConfig.description} We designed the frontend around the full demo path: connect a
            wallet, place a bet or enter the lottery, wait for VRF, and then inspect the proof of
            the final outcome.
          </p>

          <div className="stat-grid">
            <StatChip label="Mode" value={appMode.toUpperCase()} />
            <StatChip label="Target chain" value={appConfig.targetChainName} />
            <StatChip label="Tracked tokens" value={snapshot.activeTokens} />
          </div>

          <div className="cta-row">
            <Link className="button" href="/dice">
              Open Dice flow
            </Link>
            <Link className="button-secondary" href="/lottery">
              Open Lottery flow
            </Link>
            <Link className="button-ghost" href="/history">
              Review proof history
            </Link>
          </div>
        </section>

        <section className="panel hero-card">
          <div className="eyebrow">Demo checklist</div>
          <h2 className="section-title">What this frontend already covers</h2>
          <div className="feature-list">
            <div className="feature-row">
              <span className="feature-label">Wallet onboarding</span>
              <span className="feature-value">RainbowKit + wagmi</span>
            </div>
            <div className="feature-row">
              <span className="feature-label">VRF waiting UX</span>
              <span className="feature-value">Explicit multi-step progress</span>
            </div>
            <div className="feature-row">
              <span className="feature-label">Proof visibility</span>
              <span className="feature-value">Request ID, tx links, random word</span>
            </div>
            <div className="feature-row">
              <span className="feature-label">Live infra status</span>
              <span className="feature-value">
                {infrastructureReady ? 'VRFConsumer + Treasury configured' : 'Waiting for infra addresses'}
              </span>
            </div>
            <div className="feature-row">
              <span className="feature-label">Bonus surface</span>
              <span className="feature-value">ENS lookup included</span>
            </div>
          </div>
        </section>
      </div>

      <NetworkGuard />

      <div className="dashboard-grid">
        <section className="panel section-card">
          <div className="eyebrow">Snapshot</div>
          <h2 className="section-title">Live dashboard metrics</h2>
          <p className="section-subtitle">
            In mock mode we use generated local history to test the UI. In live mode this section
            reflects the Dice settlements that this browser session has already observed on Sepolia.
          </p>
          <div className="alert">{uiCopy.infraHint}</div>
          <div className="stat-grid">
            <StatChip label="Settlements" value={String(snapshot.totalSettlements)} />
            <StatChip label="Latest payout" value={snapshot.latestDicePayout} />
            <StatChip label="Last request" value={snapshot.latestRequestId.slice(0, 12)} />
          </div>
        </section>

        <section className="panel section-card">
          <div className="eyebrow">Integration</div>
          <h2 className="section-title">What still blocks full live coverage</h2>
          <div className="feature-list">
            <div className="feature-row">
              <span className="feature-label">Infrastructure</span>
              <span className="feature-value">Deployed and verified on Sepolia</span>
            </div>
            <div className="feature-row">
              <span className="feature-label">Dice deployment</span>
              <span className="feature-value">
                {diceLiveReady ? 'DiceGame + AchievementNFT configured for live Dice' : 'Waiting for Dice stack handoff'}
              </span>
            </div>
            <div className="feature-row">
              <span className="feature-label">Lottery deployment</span>
              <span className="feature-value">
                {lotteryLiveReady
                  ? 'Lottery + Referral configured for live round reads and entry'
                  : 'Need Lottery + Referral addresses and final ABI exports'}
              </span>
            </div>
            <div className="feature-row">
              <span className="feature-label">Authorization</span>
              <span className="feature-value">
                Dice authorization confirmed true; Lottery authorization now depends on the deployed round lifecycle only
              </span>
            </div>
            <div className="feature-row">
              <span className="feature-label">Remaining polish</span>
              <span className="feature-value">
                ERC-20 approval UX, referral claim write flow, and richer Lottery claim/refund actions
              </span>
            </div>
          </div>
        </section>

        <WalletPanel />
      </div>
    </>
  );
}
