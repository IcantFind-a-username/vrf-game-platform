import { appMode } from '@/lib/config';
import { diceLiveReady, isLiveConfigured } from '@/lib/addresses';

export function ModeBadge() {
  return (
    <span className="mode-badge">
      {appMode === 'mock'
        ? 'Mock mode'
        : isLiveConfigured
          ? 'Live ready'
          : diceLiveReady
            ? 'Dice live ready'
            : 'Live wiring pending'}
    </span>
  );
}
