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
            {lottery.liveMode
              ? 'The live Sepolia view now reads the deployed round directly from the Lottery contract, including prize pool, ticket count, request status, and referral snapshot.'
              : 'The UI keeps the round status visible and refreshes countdown state so users can see when the draw is due. In the real contract this maps to `buyTicket`, `triggerDraw`, `retryDraw`, `claimPrize`, and `claimRefund`.'}
          </p>
        </div>
        <StatusPill stage={lottery.flow.stage} />
      </div>

      <div className="field-grid">
        <div>
          <label className="field-label">
            <span>Entry token</span>
            <span className="muted">
              {lottery.liveMode ? 'Current deployed round token' : 'Mock token path'}
            </span>
          </label>
          <select
            className="select-control"
            disabled={lottery.liveMode}
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
          <span className="feature-label">Round status</span>
          <span className="feature-value">
            {lottery.round?.statusLabel ?? 'Waiting for on-chain round'}
          </span>
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
        <div className="feature-row">
          <span className="feature-label">Your tickets</span>
          <span className="feature-value">{lottery.round?.userEntries ?? '0'}</span>
        </div>
        <div className="feature-row">
          <span className="feature-label">Request ID</span>
          <span className="feature-value mono">
            {lottery.round?.requestId ? formatAddress(lottery.round.requestId, 8) : 'Not requested yet'}
          </span>
        </div>
        <div className="feature-row">
          <span className="feature-label">Claimability</span>
          <span className="feature-value">
            {lottery.round?.canClaimPrize
              ? 'You can claim a prize'
              : lottery.round?.prizesClaimable
              ? 'Prizes claimable'
                : 'Waiting for draw'}
          </span>
        </div>
        <div className="feature-row">
          <span className="feature-label">Winner flag</span>
          <span className="feature-value">
            {lottery.round?.userIsWinner ? 'Current wallet is a winner' : 'No win flagged'}
          </span>
        </div>
      </div>

      {lottery.liveMode && lottery.round ? (
        <div className="proof-card" style={{ marginBottom: '1rem' }}>
          <div className="row-between">
            <strong>Referral snapshot</strong>
            <span className="helper-text">
              {lottery.round.commissionBps !== undefined
                ? `${(lottery.round.commissionBps / 100).toFixed(2)}% commission`
                : 'Bonus flow'}
            </span>
          </div>
          <div className="split-info">
            <div className="split-row">
              <span className="split-label">Your code</span>
              <span className="split-value mono">
                {lottery.round.referralCode
                  ? formatAddress(lottery.round.referralCode, 8)
                  : 'Not registered'}
              </span>
            </div>
            <div className="split-row">
              <span className="split-label">Pending commission</span>
              <span className="split-value">
                {lottery.round.pendingCommission
                  ? formatAmount(lottery.round.pendingCommission, lottery.round.tokenSymbol)
                  : `0 ${lottery.round.tokenSymbol}`}
              </span>
            </div>
          </div>
        </div>
      ) : null}

      <div className="cta-row">
        <button
          className="button"
          disabled={lottery.liveMode && !lottery.round}
          onClick={lottery.enterRound}
          type="button"
        >
          {lottery.liveMode ? 'Buy 1 live ticket' : 'Buy Ticket'}
        </button>
        <button className="button-ghost" onClick={lottery.refreshRound} type="button">
          Refresh round
        </button>
      </div>

      {lottery.flow.error ? <div className="alert">{lottery.flow.error}</div> : null}

      <div className="proof-card" style={{ marginTop: '1rem' }}>
        <div className="row-between">
          <strong>Draw handling</strong>
          <span className="helper-text">
            {lottery.liveMode
              ? 'Live view surfaces the latest DrawCompleted trace once the round settles.'
              : uiCopy.lotteryHint}
          </span>
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
              <span className="split-label">Winner count</span>
              <span className="split-value">
                {lottery.round.lastDraw.winnerCount ?? 1}
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
              {lottery.liveMode
                ? 'The contract has not emitted a DrawCompleted event that this page can surface yet.'
                : 'Let the countdown expire in mock mode to generate a lottery draw history item.'}
            </div>
            {!lottery.liveMode ? (
              <button className="button-secondary" onClick={lottery.fastForwardDraw} type="button">
                Fast-forward mock draw
              </button>
            ) : null}
          </div>
        )}
      </div>
    </section>
  );
}
