'use client';

import { HistoryTable } from '@/components/history-table';
import { ProofPanel } from '@/components/proof-panel';
import { useBetHistory } from '@/hooks/useBetHistory';

export default function HistoryPage() {
  const history = useBetHistory();

  return (
    <>
      <section className="panel hero-card" style={{ marginTop: '1rem' }}>
        <div className="eyebrow">Verification surface</div>
        <h1 className="page-title">History and proof trace for every randomness-driven outcome.</h1>
        <p className="page-subtitle">
          This is the page you should open when the marker asks, “How do users know the result was
          fair?” It connects request IDs, tx hashes, raw random output, and final outcome.
        </p>
      </section>

      {history.liveMode ? <div className="alert">{history.liveMessage}</div> : null}

      <section className="panel section-card" style={{ marginTop: '1rem' }}>
        <div className="section-header">
          <div>
            <div className="eyebrow">Filters</div>
            <h2 className="section-title">Search stored records</h2>
            <p className="section-subtitle">
              Filter by request ID, tx hash, round ID, or game type. Mock mode stores data locally so
              the page remains useful even before Solidity integration is done.
            </p>
          </div>
          <button className="button-ghost" onClick={history.resetHistory} type="button">
            Reset mock data
          </button>
        </div>

        <div className="search-row">
          <input
            className="search-input"
            onChange={(event) => history.setQuery(event.target.value)}
            placeholder="Search requestId, txHash, roundId..."
            value={history.query}
          />

          <select
            className="select-control"
            onChange={(event) =>
              history.setKindFilter(event.target.value as 'all' | 'dice' | 'lottery')
            }
            value={history.kindFilter}
          >
            <option value="all">All games</option>
            <option value="dice">Dice only</option>
            <option value="lottery">Lottery only</option>
          </select>
        </div>
      </section>

      <div className="history-grid" style={{ marginTop: '1rem' }}>
        <section className="panel section-card">
          <div className="row-between">
            <div>
              <div className="eyebrow">Records</div>
              <h2 className="section-title">Stored outcomes</h2>
            </div>
            <span className="mode-badge">{history.rawHistoryCount} total</span>
          </div>

          <HistoryTable
            history={history.history}
            onSelect={history.setSelectedId}
            selectedId={history.selectedId}
          />
        </section>

        <section className="panel section-card">
          <div className="eyebrow">Proof panel</div>
          <h2 className="section-title">Selected record</h2>
          <p className="section-subtitle">
            Show this panel during the presentation when explaining how the front end exposes
            randomness evidence to users.
          </p>
          <div style={{ marginTop: '1rem' }}>
            <ProofPanel record={history.selectedRecord} />
          </div>
        </section>
      </div>
    </>
  );
}
