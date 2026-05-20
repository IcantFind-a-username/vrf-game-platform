'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

import { NetworkGuard } from '@/components/network-guard';
import { StatChip } from '@/components/stat-chip';
import { WalletPanel } from '@/components/wallet-panel';
import { appConfig, appMode } from '@/lib/config';
import { getPlatformSnapshot } from '@/services/mock';

export default function OverviewPage() {
  const [snapshot, setSnapshot] = useState({
    totalSettlements: 0,
    latestDicePayout: '0.00',
    latestRequestId: 'Not settled yet',
    activeTokens: 'ETH, USDC, LINK',
  });

  useEffect(() => {
    if (appMode !== 'mock') {
      return;
    }

    const refresh = () => setSnapshot(getPlatformSnapshot());

    refresh();
    const interval = window.setInterval(refresh, 1500);
    return () => window.clearInterval(interval);
  }, []);

  return (
    <>
      <div className="hero-grid">
        <section className="panel hero-card">
          <div className="eyebrow">Frontend owner workspace</div>
          <h1 className="hero-title">Build the flow the marker can actually verify.</h1>
          <p className="hero-copy">
            {appConfig.description} This frontend is optimized around the demo-critical path:
            wallet connection, bet or lottery entry, visible pending states, and transparent proof
            of outcome.
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
            In mock mode these values update from local history. In live mode this same section is
            where on-chain event queries should feed your analytics cards.
          </p>
          <div className="stat-grid">
            <StatChip label="Settlements" value={String(snapshot.totalSettlements)} />
            <StatChip label="Latest payout" value={snapshot.latestDicePayout} />
            <StatChip label="Last request" value={snapshot.latestRequestId.slice(0, 12)} />
          </div>
        </section>

        <section className="panel section-card">
          <div className="eyebrow">Integration</div>
          <h2 className="section-title">What you still need from the Solidity team</h2>
          <div className="feature-list">
            <div className="feature-row">
              <span className="feature-label">Dice ABI</span>
              <span className="feature-value">Bet function + settle event</span>
            </div>
            <div className="feature-row">
              <span className="feature-label">Lottery ABI</span>
              <span className="feature-value">Entry function + draw event</span>
            </div>
            <div className="feature-row">
              <span className="feature-label">Treasury reads</span>
              <span className="feature-value">min/max bet + supported tokens</span>
            </div>
          </div>
        </section>

        <WalletPanel />
      </div>
    </>
  );
}
