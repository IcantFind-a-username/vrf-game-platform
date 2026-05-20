'use client';

import { useDeferredValue, useEffect, useMemo, useState } from 'react';

import { appMode } from '@/lib/config';
import { getCombinedHistory, resetMockData } from '@/services/mock';
import { liveIntegrationMessage } from '@/services/live';
import type { HistoryRecord } from '@/types/game';

export function useBetHistory() {
  const [history, setHistory] = useState<HistoryRecord[]>([]);
  const [query, setQuery] = useState('');
  const [kindFilter, setKindFilter] = useState<'all' | 'dice' | 'lottery'>('all');
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const deferredQuery = useDeferredValue(query);

  useEffect(() => {
    if (appMode === 'live') {
      return;
    }

    const refresh = () => {
      const nextHistory = getCombinedHistory();
      setHistory(nextHistory);
      setSelectedId((currentSelectedId) => currentSelectedId ?? nextHistory[0]?.id ?? null);
    };

    refresh();
    const interval = window.setInterval(refresh, 1500);
    window.addEventListener('focus', refresh);

    return () => {
      window.clearInterval(interval);
      window.removeEventListener('focus', refresh);
    };
  }, []);

  const filteredHistory = useMemo(() => {
    const search = deferredQuery.trim().toLowerCase();

    return history.filter((record) => {
      const kindMatches = kindFilter === 'all' || record.kind === kindFilter;

      if (!kindMatches) {
        return false;
      }

      if (!search) {
        return true;
      }

      const haystack =
        record.kind === 'dice'
          ? `${record.requestId} ${record.txHash} ${record.tokenSymbol}`
          : `${record.requestId} ${record.txHash} ${record.roundId} ${record.winner}`;

      return haystack.toLowerCase().includes(search);
    });
  }, [deferredQuery, history, kindFilter]);

  const selectedRecord =
    filteredHistory.find((record) => record.id === selectedId) ?? filteredHistory[0] ?? null;

  return {
    history: filteredHistory,
    rawHistoryCount: history.length,
    selectedRecord,
    selectedId,
    setSelectedId,
    query,
    setQuery,
    kindFilter,
    setKindFilter,
    resetHistory: () => {
      resetMockData();
      setHistory([]);
      setSelectedId(null);
    },
    liveMode: appMode === 'live',
    liveMessage: liveIntegrationMessage,
  };
}
