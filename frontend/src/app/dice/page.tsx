'use client';

import Link from 'next/link';

import { DiceForm } from '@/components/dice-form';
import { NetworkGuard } from '@/components/network-guard';
import { WalletPanel } from '@/components/wallet-panel';
import { useDiceBet } from '@/hooks/useDiceBet';
import { formatAddress } from '@/lib/utils/format';

export default function DicePage() {
  const dice = useDiceBet();

  return (
    <>
      <section className="panel hero-card" style={{ marginTop: '1rem' }}>
        <div className="eyebrow">Dice gameplay</div>
        <h1 className="page-title">VRF-backed Dice with visible settlement states.</h1>
        <p className="page-subtitle">
          This page is intentionally built around the highest-risk UX path in your project: a user
          submits a bet, waits through asynchronous randomness fulfillment, and can still understand
          what is happening.
        </p>
        <div className="cta-row">
          <Link className="button-secondary" href="/history">
            Open history proof panel
          </Link>
        </div>
      </section>

      <NetworkGuard />

      <div className="content-grid">
        <DiceForm dice={dice} />

        <div className="detail-stack">
          <WalletPanel />

          <section className="panel section-card">
            <div className="eyebrow">Contract handshake</div>
            <h2 className="section-title">Dice integration fields</h2>
            <div className="feature-list">
              <div className="feature-row">
                <span className="feature-label">Required write</span>
                <span className="feature-value">rollDice(guess) with native ETH value</span>
              </div>
              <div className="feature-row">
                <span className="feature-label">Required event</span>
                <span className="feature-value">
                  DiceRollRequested(requestId, treasuryBetId, player, guess, stake)
                </span>
              </div>
              <div className="feature-row">
                <span className="feature-label">Settlement event</span>
                <span className="feature-value">
                  DiceRollSettled(requestId, treasuryBetId, player, guess, result, won, payout)
                </span>
              </div>
              <div className="feature-row">
                <span className="feature-label">Raw randomness</span>
                <span className="feature-value">Read via VRFConsumer.getRandomWords(requestId)</span>
              </div>
            </div>

            <div className="proof-card" style={{ marginTop: '1rem' }}>
              <strong>Most recent request</strong>
              <div className="split-info">
                <div className="split-row">
                  <span className="split-label">Request ID</span>
                  <span className="split-value">
                    {dice.activeRecord ? formatAddress(dice.activeRecord.requestId, 8) : 'No request yet'}
                  </span>
                </div>
                <div className="split-row">
                  <span className="split-label">Tx hash</span>
                  <span className="split-value">
                    {dice.activeRecord ? formatAddress(dice.activeRecord.txHash, 8) : 'No request yet'}
                  </span>
                </div>
              </div>
            </div>
          </section>
        </div>
      </div>
    </>
  );
}
