import { addressExplorerUrl, txExplorerUrl } from '@/lib/utils/explorer';
import { formatAddress, formatAmount, formatDateTime } from '@/lib/utils/format';
import type { HistoryRecord } from '@/types/game';

export function ProofPanel({ record }: { record: HistoryRecord | null }) {
  if (!record) {
    return (
      <div className="empty-state">
        <strong>Select a record</strong>
        <div className="helper-text">
          The proof panel is where you explain fairness during the demo: request ID, tx trace, raw
          random word, and result derivation.
        </div>
      </div>
    );
  }

  return (
    <div className="detail-stack">
      <div className="proof-card">
        <div className="row-between">
          <strong>{record.kind === 'dice' ? 'Dice proof' : 'Lottery proof'}</strong>
          <span className="mode-badge">{record.kind}</span>
        </div>

        <div className="split-info">
          <div className="split-row">
            <span className="split-label">Request ID</span>
            <span className="split-value">{record.requestId}</span>
          </div>
          <div className="split-row">
            <span className="split-label">Request tx</span>
            <a
              className="split-value"
              href={txExplorerUrl(record.txHash)}
              rel="noreferrer"
              target="_blank"
            >
              {formatAddress(record.txHash, 8)}
            </a>
          </div>
          <div className="split-row">
            <span className="split-label">Settlement tx</span>
            <a
              className="split-value"
              href={txExplorerUrl(record.kind === 'dice' ? record.settleTxHash ?? record.txHash : record.settleTxHash)}
              rel="noreferrer"
              target="_blank"
            >
              {formatAddress(
                record.kind === 'dice' ? record.settleTxHash ?? record.txHash : record.settleTxHash,
                8,
              )}
            </a>
          </div>
          <div className="split-row">
            <span className="split-label">Raw random word</span>
            <span className="split-value">{record.randomWord}</span>
          </div>
          <div className="split-row">
            <span className="split-label">Updated</span>
            <span className="split-value">{formatDateTime(record.updatedAt)}</span>
          </div>
        </div>
      </div>

      {record.kind === 'dice' ? (
        <div className="proof-card">
          <strong>Dice derivation</strong>
          <div className="split-info">
            <div className="split-row">
              <span className="split-label">Mode</span>
              <span className="split-value">
                {record.mode === 'commit_reveal' ? 'Commit-reveal' : 'Standard'}
              </span>
            </div>
            <div className="split-row">
              <span className="split-label">Treasury bet ID</span>
              <span className="split-value">{record.treasuryBetId}</span>
            </div>
            {record.mode === 'commit_reveal' ? (
              <>
                <div className="split-row">
                  <span className="split-label">Commitment</span>
                  <span className="split-value">{record.commitment}</span>
                </div>
                <div className="split-row">
                  <span className="split-label">Reveal window</span>
                  <span className="split-value">
                    {record.revealDeadline
                      ? `${formatDateTime(record.revealDeadline)}`
                      : 'No reveal window'}
                  </span>
                </div>
              </>
            ) : null}
            <div className="split-row">
              <span className="split-label">Result formula</span>
              <span className="split-value">randomWord % 6 + 1</span>
            </div>
            <div className="split-row">
              <span className="split-label">Prediction → outcome</span>
              <span className="split-value">
                {record.prediction} → {record.outcome === 0 ? 'Forfeited' : record.outcome}
              </span>
            </div>
            <div className="split-row">
              <span className="split-label">Payout</span>
              <span className="split-value">
                {formatAmount(record.payout, record.tokenSymbol)}
              </span>
            </div>
            <div className="split-row">
              <span className="split-label">Settlement note</span>
              <span className="split-value">
                {record.wasForfeited
                  ? 'Player missed the reveal window and the bet was forfeited.'
                  : record.achievementMinted
                    ? 'First-win achievement would be minted in live mode.'
                    : record.note ?? 'Standard payout flow.'}
              </span>
            </div>
          </div>
        </div>
      ) : (
        <div className="proof-card">
          <strong>Lottery derivation</strong>
          <div className="split-info">
            <div className="split-row">
              <span className="split-label">Winner</span>
              <a
                className="split-value"
                href={addressExplorerUrl(record.winner)}
                rel="noreferrer"
                target="_blank"
              >
                {record.winner}
              </a>
            </div>
            <div className="split-row">
              <span className="split-label">Round</span>
              <span className="split-value">{record.roundId}</span>
            </div>
            <div className="split-row">
              <span className="split-label">Prize pool</span>
              <span className="split-value">
                {formatAmount(record.prizePool, record.tokenSymbol)}
              </span>
            </div>
            <div className="split-row">
              <span className="split-label">Participants</span>
              <span className="split-value">{record.participantCount}</span>
            </div>
            <div className="split-row">
              <span className="split-label">Winner count</span>
              <span className="split-value">{record.winnerCount ?? 1}</span>
            </div>
            <div className="split-row">
              <span className="split-label">Claim status</span>
              <span className="split-value">
                {record.claimable ? 'Prizes claimable' : 'Claim state not open yet'}
              </span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
