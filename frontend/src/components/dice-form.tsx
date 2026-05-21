'use client';

import { StatusPill } from '@/components/status-pill';
import { VrfProgress } from '@/components/vrf-progress';
import { uiCopy } from '@/lib/config';
import {
  formatAmount,
  formatCompactValue,
  formatDateTime,
  formatProbability,
} from '@/lib/utils/format';
import type { ReturnTypeOfUseDiceBet } from '@/types/internal';

export function DiceForm({
  dice,
}: {
  dice: ReturnTypeOfUseDiceBet;
}) {
  const activeRecord = dice.activeRecord ?? dice.recentRecord;
  const displayMode = activeRecord?.mode ?? dice.mode;

  return (
    <section className="panel section-card">
      <div className="section-header">
        <div>
          <div className="eyebrow">Dice</div>
          <h2 className="section-title">Bet, wait, reveal, settle</h2>
          <p className="section-subtitle">
            {dice.liveMode
              ? 'In live mode, we use the standard rollDice path for the formal demo. Commit-reveal stays in mock mode as the advanced anti-cheating flow.'
              : 'We keep both the standard path and the commit-reveal path here so we can test the UX tradeoff clearly before switching to the live demo flow.'}
          </p>
        </div>
        <StatusPill stage={dice.flow.stage} />
      </div>

      <div className="field-grid">
        <div>
          <label className="field-label">
            <span>Play mode</span>
            <span className="muted">Aligned to DiceGame.sol</span>
          </label>
          <div className="cta-row">
            <button
              className={dice.mode === 'standard' ? 'button-secondary' : 'button-ghost'}
              onClick={() => dice.setMode('standard')}
              type="button"
            >
              Standard roll
            </button>
            <button
              className={dice.mode === 'commit_reveal' ? 'button-secondary' : 'button-ghost'}
              disabled={dice.liveMode}
              onClick={() => dice.setMode('commit_reveal')}
              type="button"
            >
              Commit-reveal
            </button>
          </div>
        </div>

        <div>
          <label className="field-label">
            <span>Bet token</span>
            <span className="muted">Current Dice contract uses native ETH</span>
          </label>
          <select
            className="select-control"
            disabled
            onChange={(event) => dice.setSelectedTokenSymbol(event.target.value)}
            value={dice.selectedTokenSymbol}
          >
            {dice.tokens.map((token) => (
              <option key={token.symbol} value={token.symbol}>
                {token.symbol} · {token.label}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="field-label">
            <span>Amount</span>
            <span className="muted">House edge 2.5%</span>
          </label>
          <input
            className="field-control"
            inputMode="decimal"
            onChange={(event) => dice.setAmount(event.target.value)}
            placeholder={`e.g. ${dice.selectedToken?.minBet ?? '0.01'}`}
            value={dice.amount}
          />
        </div>

        <div>
          <label className="field-label">
            <span>{dice.mode === 'commit_reveal' ? 'Hidden guess' : 'Prediction'}</span>
            <span className="muted">{formatProbability(dice.prediction)}</span>
          </label>
          <input
            className="slider-input"
            max={6}
            min={1}
            onChange={(event) => dice.setPrediction(Number(event.target.value))}
            type="range"
            value={dice.prediction}
          />
          <div className="row-between">
            <span className="tag mono">Selected face: {dice.prediction}</span>
            <span className="helper-text">{uiCopy.dicePayoutHint}</span>
          </div>
        </div>
      </div>

      <div className="feature-list">
        <div className="feature-row">
          <span className="feature-label">Potential payout</span>
          <span className="feature-value">
            {formatAmount(dice.payoutPreview, dice.selectedToken?.symbol)}
          </span>
        </div>
        <div className="feature-row">
          <span className="feature-label">Current contract path</span>
          <span className="feature-value">
            {dice.mode === 'commit_reveal'
              ? 'commitRoll(commitment) -> DiceRandomnessReady -> revealRoll'
              : 'rollDice(guess)'}
          </span>
        </div>
        {dice.liveMode ? (
          <div className="feature-row">
            <span className="feature-label">Live demo recommendation</span>
            <span className="feature-value">Use standard rollDice with native ETH value</span>
          </div>
        ) : null}
      </div>

      <div className="cta-row">
        <button className="button" onClick={dice.submitBet} type="button">
          {dice.mode === 'commit_reveal' ? 'Commit Dice Bet' : 'Roll Dice'}
        </button>
        <button className="button-ghost" onClick={dice.resetFlow} type="button">
          Reset local flow
        </button>
      </div>

      {dice.flow.error ? <div className="alert">{dice.flow.error}</div> : null}

      <VrfProgress mode={displayMode} stage={dice.flow.stage} />

      {activeRecord ? (
        <div className="proof-card" style={{ marginTop: '1rem' }}>
          <div className="row-between">
            <strong>Latest Dice record</strong>
            <StatusPill stage={activeRecord.stage} />
          </div>
          <div className="split-info">
            <div className="split-row">
              <span className="split-label">Mode</span>
              <span className="split-value">
                {activeRecord.mode === 'commit_reveal' ? 'Commit-reveal' : 'Standard'}
              </span>
            </div>
            <div className="split-row">
              <span className="split-label">Request ID</span>
              <span className="split-value">{formatCompactValue(activeRecord.requestId, 8)}</span>
            </div>
            <div className="split-row">
              <span className="split-label">Treasury bet ID</span>
              <span className="split-value">{formatCompactValue(activeRecord.treasuryBetId, 8)}</span>
            </div>
            <div className="split-row">
              <span className="split-label">Prediction → outcome</span>
              <span className="split-value">
                {activeRecord.prediction} →{' '}
                {activeRecord.stage !== 'settled'
                  ? 'Pending'
                  : activeRecord.outcome === 0
                    ? 'Forfeited'
                    : activeRecord.outcome}
              </span>
            </div>
            <div className="split-row">
              <span className="split-label">Potential / actual payout</span>
              <span className="split-value">
                {formatAmount(activeRecord.payout, activeRecord.tokenSymbol)}
              </span>
            </div>
            {activeRecord.mode === 'commit_reveal' ? (
              <div className="split-row">
                <span className="split-label">Reveal status</span>
                <span className="split-value">
                  {activeRecord.stage === 'reveal_pending'
                    ? dice.isRevealExpired
                      ? 'Reveal window expired'
                      : `Waiting for reveal · ${dice.revealCountdown ?? '--:--'} left`
                    : activeRecord.wasForfeited
                      ? 'Forfeited'
                      : 'Reveal completed'}
                </span>
              </div>
            ) : null}
            <div className="split-row">
              <span className="split-label">Updated</span>
              <span className="split-value">{formatDateTime(activeRecord.updatedAt)}</span>
            </div>
          </div>

          {activeRecord.stage === 'reveal_pending' ? (
            <div className="cta-row" style={{ marginTop: '1rem' }}>
              <button
                className="button-secondary"
                disabled={dice.isRevealSubmitting || dice.isRevealExpired}
                onClick={dice.revealBet}
                type="button"
              >
                {dice.isRevealSubmitting ? 'Submitting reveal...' : 'Reveal and settle'}
              </button>
              <button
                className="button-ghost"
                disabled={dice.isForfeitSubmitting || !dice.isRevealExpired}
                onClick={dice.forfeitBet}
                type="button"
              >
                {dice.isForfeitSubmitting ? 'Submitting forfeit...' : 'Forfeit expired bet'}
              </button>
            </div>
          ) : null}

          {activeRecord.achievementMinted ? (
            <div className="alert">
              First-win milestone hit. The settlement flow observed an `AchievementMinted` signal.
            </div>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}
