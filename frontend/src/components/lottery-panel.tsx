'use client';

import { StatusPill } from '@/components/status-pill';
import { uiCopy } from '@/lib/config';
import { formatAddress, formatAmount, formatDateTime } from '@/lib/utils/format';
import type { ReturnTypeOfUseLottery } from '@/types/internal';

export function LotteryPanel({
  lottery,
}: {
  lottery: ReturnTypeOfUseLottery;
}) {
  return (
    <section className="panel section-card">
      <div className="section-header">
        <div>
          <div className="eyebrow">Lottery</div>
          <h2 className="section-title">Round-based pool and draw</h2>
          <p className="section-subtitle">
            The UI keeps the round status visible and refreshes countdown state so users can see when
            the draw is due. In the real contract this maps to `buyTicket`, `triggerDraw`,
            `retryDraw`, `claimPrize`, and `claimRefund`.
          </p>
        </div>
        <StatusPill stage={lottery.flow.stage} />
      </div>

      <div className="field-grid">
        <div>
          <label className="field-label">
            <span>Entry token</span>
            <span className="muted">ERC-20 path</span>
          </label>
          <select
            className="select-control"
            onChange={(event) => lottery.setSelectedTokenSymbol(event.target.value)}
            value={lottery.selectedTokenSymbol}
          >
            {lottery.tokens.map((token) => (
              <option key={token.symbol} value={token.symbol}>
                {token.symbol} · {token.label}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div className="feature-list">
        <div className="feature-row">
          <span className="feature-label">Current round</span>
          <span className="feature-value">{lottery.round?.roundId ?? 'Loading'}</span>
        </div>
        <div className="feature-row">
          <span className="feature-label">Countdown</span>
          <span className="feature-value mono">{lottery.countdown}</span>
        </div>
        <div className="feature-row">
          <span className="feature-label">Prize pool</span>
          <span className="feature-value">
            {lottery.round
              ? formatAmount(lottery.round.prizePool, lottery.round.tokenSymbol)
              : 'Loading'}
          </span>
        </div>
        <div className="feature-row">
          <span className="feature-label">Participants</span>
          <span className="feature-value">{lottery.round?.participantCount ?? 'Loading'}</span>
        </div>
        <div className="feature-row">
          <span className="feature-label">Ticket price</span>
          <span className="feature-value">
            {lottery.round
              ? formatAmount(lottery.round.ticketPrice, lottery.round.tokenSymbol)
              : 'Loading'}
          </span>
        </div>
      </div>

      <div className="cta-row">
        <button className="button" onClick={lottery.enterRound} type="button">
          Buy Ticket
        </button>
        <button className="button-ghost" onClick={lottery.refreshRound} type="button">
          Refresh round
        </button>
      </div>

      {lottery.flow.error ? <div className="alert">{lottery.flow.error}</div> : null}

      <div className="proof-card" style={{ marginTop: '1rem' }}>
        <div className="row-between">
          <strong>Draw handling</strong>
          <span className="helper-text">{uiCopy.lotteryHint}</span>
        </div>

        {lottery.round?.lastDraw ? (
          <div className="split-info">
            <div className="split-row">
              <span className="split-label">Last drawn round</span>
              <span className="split-value">{lottery.round.lastDraw.roundId}</span>
            </div>
            <div className="split-row">
              <span className="split-label">Winner</span>
              <span className="split-value">{formatAddress(lottery.round.lastDraw.winner, 6)}</span>
            </div>
            <div className="split-row">
              <span className="split-label">Random request</span>
              <span className="split-value">
                {formatAddress(lottery.round.lastDraw.requestId, 8)}
              </span>
            </div>
            <div className="split-row">
              <span className="split-label">Draw time</span>
              <span className="split-value">
                {formatDateTime(lottery.round.lastDraw.updatedAt)}
              </span>
            </div>
          </div>
        ) : (
          <div className="empty-state" style={{ marginTop: '1rem' }}>
            <strong>No draw settled yet</strong>
            <div className="helper-text">
              Let the countdown expire in mock mode to generate a lottery draw history item.
            </div>
          </div>
        )}
      </div>
    </section>
  );
}
