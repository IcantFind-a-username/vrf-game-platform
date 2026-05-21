'use client';

import Link from 'next/link';

import { DiceForm } from '@/components/dice-form';
import { NetworkGuard } from '@/components/network-guard';
import { WalletPanel } from '@/components/wallet-panel';
import { useDiceBet } from '@/hooks/useDiceBet';
import { contractAddresses, diceLiveReady } from '@/lib/addresses';
import { uiCopy } from '@/lib/config';
import { formatAddress } from '@/lib/utils/format';

export default function DicePage() {
  const dice = useDiceBet();

  return (
    <>
      <section className="panel hero-card" style={{ marginTop: '1rem' }}>
        <div className="eyebrow">Dice gameplay</div>
        <h1 className="page-title">VRF-backed Dice with standard and commit-reveal flows.</h1>
        <p className="page-subtitle">
          We use this page to demo the most important UX path in the project: place a bet, wait for
          asynchronous randomness fulfillment, and keep every state understandable. For the formal
          Sepolia demo, we use the standard `rollDice(uint8 guess)` flow.
        </p>
        <div className="alert">{uiCopy.infraHint}</div>
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
                <span className="feature-label">Standard path</span>
                <span className="feature-value">rollDice(guess) with native ETH value on Sepolia</span>
              </div>
              <div className="feature-row">
                <span className="feature-label">Commit-reveal path</span>
                <span className="feature-value">
                  Optional advanced flow: commitRoll(commitment) {'->'} revealRoll(requestId, guess, salt)
                </span>
              </div>
              <div className="feature-row">
                <span className="feature-label">Core events</span>
                <span className="feature-value">
                  DiceRollRequested / DiceRollCommitted / DiceRandomnessReady / DiceRollSettled
                </span>
              </div>
              <div className="feature-row">
                <span className="feature-label">Raw randomness</span>
                <span className="feature-value">Read via VRFConsumer.getRandomWords(requestId)</span>
              </div>
              <div className="feature-row">
                <span className="feature-label">Commit helper</span>
                <span className="feature-value">getCommitmentHash(player, guess, salt)</span>
              </div>
              <div className="feature-row">
                <span className="feature-label">Achievement signal</span>
                <span className="feature-value">AchievementMinted(player, tokenId, "FIRST_WIN")</span>
              </div>
              <div className="feature-row">
                <span className="feature-label">Dice live status</span>
                <span className="feature-value">
                  {diceLiveReady
                    ? `Configured at ${formatAddress(contractAddresses.diceGame ?? '0x', 6)}`
                    : 'Waiting for DiceGame + Achievement addresses'}
                </span>
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
