import type { Metadata } from 'next';
import { IBM_Plex_Mono, Space_Grotesk } from 'next/font/google';

import '@/app/globals.css';
import { Providers } from '@/app/providers';
import { SiteHeader } from '@/components/site-header';

const spaceGrotesk = Space_Grotesk({
  variable: '--font-display',
  subsets: ['latin'],
});

const plexMono = IBM_Plex_Mono({
  variable: '--font-mono',
  subsets: ['latin'],
  weight: ['400', '500', '600'],
});

export const metadata: Metadata = {
  title: 'Verifiable Random Game Platform',
  description:
    'Frontend control room for a provably fair gaming platform built on Chainlink VRF.',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={`${spaceGrotesk.variable} ${plexMono.variable}`}>
        <Providers>
          <div className="app-frame">
            <div className="background-orb background-orb-left" />
            <div className="background-orb background-orb-right" />
            <SiteHeader />
            <main className="page-shell">{children}</main>
          </div>
        </Providers>
      </body>
    </html>
  );
}
