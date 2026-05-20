import { appMode } from '@/lib/config';
import { isLiveConfigured } from '@/lib/addresses';

export function ModeBadge() {
  return (
    <span className="mode-badge">
      {appMode === 'mock' ? 'Mock mode' : isLiveConfigured ? 'Live ready' : 'Live wiring pending'}
    </span>
  );
}
