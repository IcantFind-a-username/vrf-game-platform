'use client';

import { useAccount, useSwitchChain } from 'wagmi';
import { sepolia } from 'wagmi/chains';

export function NetworkGuard() {
  const { isConnected, chainId } = useAccount();
  const { switchChain, isPending } = useSwitchChain();

  if (!isConnected) {
    return (
      <div className="network-guard">
        <div>
          <strong>Wallet not connected</strong>
          <div className="helper-text">
            Connect a wallet to test transaction states and switch into the real Sepolia flow later.
          </div>
        </div>
      </div>
    );
  }

  if (chainId === sepolia.id) {
    return (
      <div className="network-guard">
        <div>
          <strong>Sepolia ready</strong>
          <div className="helper-text">
            Wallet is on the target chain for Dice and Lottery interactions.
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="network-guard">
      <div>
        <strong>Wrong network</strong>
        <div className="helper-text">
          Your wallet is connected, but gameplay should run on Sepolia for the final demo.
        </div>
      </div>

      <button
        className="button-secondary"
        disabled={isPending}
        onClick={() => switchChain({ chainId: sepolia.id })}
        type="button"
      >
        {isPending ? 'Switching...' : 'Switch to Sepolia'}
      </button>
    </div>
  );
}
