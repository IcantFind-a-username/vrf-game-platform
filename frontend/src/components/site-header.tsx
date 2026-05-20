'use client';

import { ConnectButton } from '@rainbow-me/rainbowkit';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

import { ModeBadge } from '@/components/mode-badge';

const LINKS = [
  { href: '/', label: 'Overview' },
  { href: '/dice', label: 'Dice' },
  { href: '/lottery', label: 'Lottery' },
  { href: '/history', label: 'History' },
] as const;

export function SiteHeader() {
  const pathname = usePathname();

  return (
    <header className="site-header">
      <div className="site-header-inner">
        <Link className="brand" href="/">
          <div className="brand-mark mono">VRF</div>
          <div>
            <div className="brand-title">Fair Play Console</div>
            <div className="brand-name">Verifiable Random Games</div>
          </div>
        </Link>

        <nav className="site-nav">
          {LINKS.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="nav-link"
              style={
                pathname === link.href
                  ? {
                      color: 'var(--text-primary)',
                      background: 'rgba(255, 255, 255, 0.06)',
                    }
                  : undefined
              }
            >
              {link.label}
            </Link>
          ))}
        </nav>

        <div className="inline-actions">
          <ModeBadge />
          <ConnectButton chainStatus="icon" showBalance={false} />
        </div>
      </div>
    </header>
  );
}
