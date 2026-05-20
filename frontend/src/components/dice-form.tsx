'use client';

import { StatusPill } from '@/components/status-pill';
import { VrfProgress } from '@/components/vrf-progress';
import { uiCopy } from '@/lib/config';
import { formatAddress, formatAmount, formatDateTime, formatProbability } from '@/lib/utils/format';
import type { ReturnTypeOfUseDiceBet } from '@/types/internal';

export function DiceForm({
  dice,
}: {
  dice: ReturnTypeOfUseDiceBet;
}) {
  const activeRecord = dice.activeRecord ?? dice.recentRecord;

  return (
    <section className="panel section-card">
      <div className="section-header">
        <div>
          <div className="eyebrow">Dice</div>
          <h2 className="section-title">Bet, wait, settle</h2>
          <p className="section-subtitle">
            This flow is built around the exact UX your demo needs: place a bet, enter a visible VRF
            waiting state, then surface the provable result. The latest 2号 handoff uses
            `rollDice(uint8 guess)` and native ETH staking.
          </p>
        </div>
        <StatusPill stage={dice.flow.stage} />
      </div>

      <div className="field-grid">
        <div>
          <label className="field-label">
            <span>Bet token</span>
            <span className="muted">
              Range {dice.selectedToken.minBet} - {dice.selectedToken.maxBet} {dice.selectedToken.symbol}
            </span>
          </label>
          <select
            className="select-control"
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
            placeholder={`e.g. ${dice.selectedToken.minBet}`}
            value={dice.amount}
          />
        </div>

        <div>
          <label className="field-label">
            <span>Prediction</span>
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
            {formatAmount(dice.payoutPreview, dice.selectedToken.symbol)}
          </span>
        </div>
        <div className="feature-row">
          <span className="feature-label">Current handoff note</span>
          <span className="feature-value">No commit-reveal interface exposed in the 2号 document</span>
        </div>
      </div>

      <div className="cta-row">
        <button className="button" onClick={dice.submitBet} type="button">
          {dice.flow.stage === 'idle' ? 'Place Dice Bet' : 'Run Dice Flow'}
        </button>
        <button className="button-ghost" onClick={dice.resetFlow} type="button">
          Reset local flow
        </button>
      </div>

      {dice.flow.error ? <div className="alert">{dice.flow.error}</div> : null}

      <VrfProgress stage={dice.flow.stage} />

      {activeRecord ? (
        <div className="proof-card" style={{ marginTop: '1rem' }}>
          <div className="row-between">
            <strong>Latest Dice record</strong>
            <StatusPill stage={activeRecord.stage} />
          </div>
          <div className="split-info">
            <div className="split-row">
              <span className="split-label">Request ID</span>
              <span className="split-value">{formatAddress(activeRecord.requestId, 8)}</span>
            </div>
            <div className="split-row">
              <span className="split-label">Prediction → outcome</span>
              <span className="split-value">
                {activeRecord.prediction} → {activeRecord.outcome}
              </span>
            </div>
            <div className="split-row">
              <span className="split-label">Potential / actual payout</span>
              <span className="split-value">
                {formatAmount(activeRecord.payout, activeRecord.tokenSymbol)}
              </span>
            </div>
            <div className="split-row">
              <span className="split-label">Updated</span>
              <span className="split-value">{formatDateTime(activeRecord.updatedAt)}</span>
            </div>
          </div>
        </div>
      ) : null}
    </section>
  );
}
