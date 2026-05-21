'use client';

import Link from 'next/link';

import { LotteryPanel } from '@/components/lottery-panel';
import { NetworkGuard } from '@/components/network-guard';
import { WalletPanel } from '@/components/wallet-panel';
import { useLottery } from '@/hooks/useLottery';
import { contractAddresses, lotteryLiveReady } from '@/lib/addresses';
import { formatAddress } from '@/lib/utils/format';

export default function LotteryPage() {
  const lottery = useLottery();

  return (
    <>
      <section className="panel hero-card" style={{ marginTop: '1rem' }}>
        <div className="eyebrow">Lottery gameplay</div>
        <h1 className="page-title">Round-based lottery with pool visibility and draw traceability.</h1>
        <p className="page-subtitle">
          We keep the round state, participant count, prize pool, and latest draw on one screen so
          the fairness story is easy to explain. In live mode, this page reads the current round
          directly from Sepolia and supports a native ETH ticket entry.
        </p>
        <div className="cta-row">
          <Link className="button-secondary" href="/history">
            Inspect draw history
          </Link>
        </div>
      </section>

      <NetworkGuard />

      <div className="content-grid">
        <LotteryPanel lottery={lottery} />

        <div className="detail-stack">
          <WalletPanel />

          <section className="panel section-card">
            <div className="eyebrow">Round model</div>
            <h2 className="section-title">What the page expects from the contract</h2>
            <div className="feature-list">
              <div className="feature-row">
                <span className="feature-label">Entry write</span>
                <span className="feature-value">buyTicket(roundId, 1, bytes32(0))</span>
              </div>
              <div className="feature-row">
                <span className="feature-label">Current round reads</span>
                <span className="feature-value">currentRoundId, getRound, getUserTicketCount</span>
              </div>
              <div className="feature-row">
                <span className="feature-label">Draw event</span>
                <span className="feature-value">DrawCompleted(roundId, requestId, randomWords, winners, payouts)</span>
              </div>
              <div className="feature-row">
                <span className="feature-label">Live status</span>
                <span className="feature-value">
                  {lotteryLiveReady
                    ? `Configured at ${formatAddress(contractAddresses.lottery ?? '0x', 6)}`
                    : 'Waiting for Lottery + Referral addresses'}
                </span>
              </div>
              <div className="feature-row">
                <span className="feature-label">Referral bonus</span>
                <span className="feature-value">Reads code + pending commission from Referral</span>
              </div>
            </div>
          </section>
        </div>
      </div>
    </>
  );
}
