'use client';

import { formatAmount, formatCompactValue, formatDateTime } from '@/lib/utils/format';
import type { HistoryRecord } from '@/types/game';

export function HistoryTable({
  history,
  selectedId,
  onSelect,
}: {
  history: HistoryRecord[];
  selectedId: string | null;
  onSelect: (id: string) => void;
}) {
  if (!history.length) {
    return (
      <div className="empty-state">
        <strong>No records yet</strong>
        <div className="helper-text">
          Run a Dice or Lottery flow first. This table reads from local mock storage or the live
          Dice cache captured by this browser session.
        </div>
      </div>
    );
  }

  return (
    <table className="table">
      <thead>
        <tr>
          <th>Game</th>
          <th>Request</th>
          <th>Result</th>
          <th>When</th>
        </tr>
      </thead>
      <tbody>
        {history.map((record) => (
          <tr
            key={record.id}
            className="table-row"
            data-active={record.id === selectedId}
            onClick={() => onSelect(record.id)}
          >
            <td>
              {record.kind === 'dice'
                ? record.mode === 'commit_reveal'
                  ? 'Dice (CR)'
                  : 'Dice'
                : `Lottery ${record.roundId}`}
            </td>
            <td className="mono">{formatCompactValue(record.requestId, 6)}</td>
            <td>
              {record.kind === 'dice'
                ? `${record.prediction} → ${record.outcome === 0 ? 'forfeit' : record.outcome} · ${formatAmount(record.payout, record.tokenSymbol)}`
                : `${record.participantCount} players · ${formatAmount(record.prizePool, record.tokenSymbol)}`}
            </td>
            <td>{formatDateTime(record.updatedAt)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
