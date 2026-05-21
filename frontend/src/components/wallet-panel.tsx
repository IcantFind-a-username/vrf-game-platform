'use client';

import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount, useBalance, useEnsName } from 'wagmi';
import { mainnet } from 'wagmi/chains';

import { formatAddress } from '@/lib/utils/format';

export function WalletPanel() {
  const { address, isConnected } = useAccount();
  const { data: nativeBalance } = useBalance({
    address,
    query: { enabled: Boolean(address) },
  });
  const { data: ensName } = useEnsName({
    address,
    chainId: mainnet.id,
    query: { enabled: Boolean(address) },
  });

  return (
    <section className="panel section-card">
      <div className="section-header">
        <div className="section-copy">
          <div className="eyebrow">Wallet</div>
          <h2 className="section-title">Connection and identity</h2>
          <p className="section-subtitle">
            RainbowKit handles wallet onboarding. ENS lookup is included as an optional presentation
            bonus.
          </p>
        </div>
        <div className="wallet-connect-slot">
          {isConnected ? (
            <span className="mode-badge">Managed in header</span>
          ) : (
            <ConnectButton />
          )}
        </div>
      </div>

      <div className="feature-list">
        <div className="feature-row">
          <span className="feature-label">Status</span>
          <span className="feature-value">{isConnected ? 'Connected' : 'Disconnected'}</span>
        </div>
        <div className="feature-row">
          <span className="feature-label">Address</span>
          <span className="feature-value mono">
            {address ? formatAddress(address, 6) : 'Connect wallet'}
          </span>
        </div>
        <div className="feature-row">
          <span className="feature-label">ENS</span>
          <span className="feature-value">{ensName ?? 'No ENS found'}</span>
        </div>
        <div className="feature-row">
          <span className="feature-label">Native balance</span>
          <span className="feature-value">
            {nativeBalance
              ? `${Number(nativeBalance.formatted).toFixed(4)} ${nativeBalance.symbol}`
              : 'Not available'}
          </span>
        </div>
      </div>
    </section>
  );
}
