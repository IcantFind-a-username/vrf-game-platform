'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  formatUnits,
  parseAbiItem,
  parseEventLogs,
  zeroAddress,
  zeroHash,
  type Address,
} from 'viem';
import { useAccount, usePublicClient, useWriteContract } from 'wagmi';

import { lotteryAbi } from '@/lib/abis/lottery';
import { referralAbi } from '@/lib/abis/referral';
import { contractAddresses } from '@/lib/addresses';
import { appConfig, appMode, demoTokens } from '@/lib/config';
import { formatCountdown } from '@/lib/utils/format';
import { liveIntegrationMessage, upsertLiveLotteryHistory } from '@/services/live';
import {
  enterLotteryRound,
  fastForwardLotteryRound,
  getLotteryState,
  syncLotteryRound,
} from '@/services/mock';
import type { FlowState, LotteryHistoryRecord, LotteryRoundState } from '@/types/game';

const drawCompletedEvent = parseAbiItem(
  'event DrawCompleted(uint256 indexed roundId, uint256 indexed requestId, uint256[] randomWords, address[] winners, uint256[] payouts)',
);

const drawRequestedEvent = parseAbiItem(
  'event DrawRequested(uint256 indexed roundId, uint256 indexed requestId)',
);

type OnchainRound = {
  id: bigint;
  token: Address;
  ticketPrice: bigint;
  maxTickets: bigint;
  startTime: bigint;
  endTime: bigint;
  totalTicketsSold: bigint;
  prizePool: bigint;
  requestId: bigint;
  numWinners: bigint | number;
  status: bigint | number;
  prizesClaimable: boolean;
};

function tokenMetaForAddress(tokenAddress: Address) {
  if (tokenAddress.toLowerCase() === zeroAddress.toLowerCase()) {
    return demoTokens.find((token) => token.address === zeroAddress) ?? demoTokens[0];
  }

  return (
    demoTokens.find((token) => token.address.toLowerCase() === tokenAddress.toLowerCase()) ?? {
      symbol: 'TOKEN',
      label: 'Unknown token',
      address: tokenAddress,
      decimals: 18,
      kind: 'erc20' as const,
      minBet: 0,
      maxBet: 0,
      accent: '#d3e9ff',
    }
  );
}

function formatTokenValue(value: bigint, tokenAddress: Address) {
  const token = tokenMetaForAddress(tokenAddress);
  return formatUnits(value, token.decimals);
}

function inferRoundStatusLabel(round: OnchainRound) {
  if (round.prizesClaimable) {
    return 'Prizes claimable';
  }

  if (round.requestId > 0n) {
    return 'Draw requested';
  }

  if (round.endTime * 1000n <= BigInt(Date.now())) {
    return 'Closed';
  }

  if (round.startTime * 1000n > BigInt(Date.now())) {
    return 'Scheduled';
  }

  return 'Open';
}

function toErrorMessage(error: unknown, fallback: string) {
  if (typeof error === 'object' && error && 'shortMessage' in error) {
    const shortMessage = (error as { shortMessage?: unknown }).shortMessage;

    if (typeof shortMessage === 'string' && shortMessage.trim()) {
      return shortMessage;
    }
  }

  if (error instanceof Error && error.message.trim()) {
    return error.message;
  }

  return fallback;
}

export function useLottery() {
  const { address, chainId, isConnected } = useAccount();
  const publicClient = usePublicClient({ chainId: appConfig.targetChainId });
  const { writeContractAsync } = useWriteContract();
  const [selectedTokenSymbol, setSelectedTokenSymbol] = useState('USDC');
  const [flow, setFlow] = useState<FlowState>({ stage: 'idle' });
  const [round, setRound] = useState<LotteryRoundState | null>(null);
  const [countdown, setCountdown] = useState('--:--');
  const phaseTimers = useRef<number[]>([]);
  const runId = useRef(0);

  const clearPhaseTimers = useCallback(() => {
    phaseTimers.current.forEach((timer) => window.clearTimeout(timer));
    phaseTimers.current = [];
  }, []);

  const buildLiveLotteryRecord = useCallback(
    async (currentRoundId: bigint) => {
      if (!publicClient || !contractAddresses.lottery) {
        return null;
      }

      const candidateRoundIds = [currentRoundId, currentRoundId - 1n, currentRoundId - 2n].filter(
        (roundId) => roundId > 0n,
      );

      for (const candidateRoundId of candidateRoundIds) {
        const drawCompletedLogs = await publicClient.getLogs({
          address: contractAddresses.lottery,
          event: drawCompletedEvent,
          args: { roundId: candidateRoundId },
          toBlock: 'latest',
        });

        const drawCompleted = drawCompletedLogs.at(-1);

        if (!drawCompleted) {
          continue;
        }

        const roundData = (await publicClient.readContract({
          address: contractAddresses.lottery,
          abi: lotteryAbi,
          functionName: 'getRound',
          args: [candidateRoundId],
        })) as unknown as OnchainRound;

        const drawRequestedLogs = await publicClient.getLogs({
          address: contractAddresses.lottery,
          event: drawRequestedEvent,
          args: {
            roundId: candidateRoundId,
            requestId: drawCompleted.args.requestId,
          },
          toBlock: 'latest',
        });

        const drawBlock = await publicClient.getBlock({
          blockHash: drawCompleted.blockHash,
        });
        const tokenMeta = tokenMetaForAddress(roundData.token);
        const winners = drawCompleted.args.winners ?? [];
        const randomWords = drawCompleted.args.randomWords ?? [];
        const record: LotteryHistoryRecord = {
          id: `lottery-live-${candidateRoundId.toString()}`,
          kind: 'lottery',
          roundId: candidateRoundId.toString(),
          tokenSymbol: tokenMeta.symbol,
          prizePool: formatTokenValue(roundData.prizePool, roundData.token),
          participantCount: Number(roundData.totalTicketsSold),
          winner: winners[0] ?? zeroAddress,
          requestId: drawCompleted.args.requestId?.toString() ?? roundData.requestId.toString(),
          txHash:
            drawRequestedLogs.at(-1)?.transactionHash ?? drawCompleted.transactionHash,
          settleTxHash: drawCompleted.transactionHash,
          randomWord: randomWords[0]?.toString() ?? 'Not available',
          stage: 'settled',
          createdAt: Number(roundData.endTime) * 1000,
          updatedAt: Number(drawBlock.timestamp) * 1000,
          userWon: Boolean(
            address &&
              winners.some((winner) => winner.toLowerCase() === address.toLowerCase()),
          ),
          winnerCount: winners.length,
          claimable: roundData.prizesClaimable,
        };

        upsertLiveLotteryHistory(record);
        return record;
      }

      return null;
    },
    [address, publicClient],
  );

  const refreshRound = useCallback(async () => {
    if (appMode !== 'live') {
      const nextRound = syncLotteryRound();
      setRound(nextRound);
      setCountdown(formatCountdown(nextRound.closesAt));
      return;
    }

    if (!publicClient || !contractAddresses.lottery) {
      return;
    }

    try {
      const currentRoundId = (await publicClient.readContract({
        address: contractAddresses.lottery,
        abi: lotteryAbi,
        functionName: 'currentRoundId',
      })) as bigint;

      if (currentRoundId === 0n) {
        setRound(null);
        setCountdown('--:--');
        return;
      }

      const roundData = (await publicClient.readContract({
        address: contractAddresses.lottery,
        abi: lotteryAbi,
        functionName: 'getRound',
        args: [currentRoundId],
      })) as unknown as OnchainRound;

      const tokenMeta = tokenMetaForAddress(roundData.token);
      const userEntries =
        address && contractAddresses.lottery
          ? ((await publicClient.readContract({
              address: contractAddresses.lottery,
              abi: lotteryAbi,
              functionName: 'getUserTicketCount',
              args: [currentRoundId, address],
            })) as bigint)
          : 0n;
      const canClaimPrize =
        address && contractAddresses.lottery
          ? ((await publicClient.readContract({
              address: contractAddresses.lottery,
              abi: lotteryAbi,
              functionName: 'canClaimPrize',
              args: [currentRoundId, address],
            })) as boolean)
          : false;
      const userIsWinner =
        address && contractAddresses.lottery
          ? ((await publicClient.readContract({
              address: contractAddresses.lottery,
              abi: lotteryAbi,
              functionName: 'isWinner',
              args: [currentRoundId, address],
            })) as boolean)
          : false;

      let referralCode: string | undefined;
      let pendingCommission: string | undefined;
      let commissionBps: number | undefined;

      if (address && contractAddresses.referral) {
        const [code, pending, bps] = await Promise.all([
          publicClient.readContract({
            address: contractAddresses.referral,
            abi: referralAbi,
            functionName: 'getReferralCode',
            args: [address],
          }) as Promise<`0x${string}`>,
          publicClient.readContract({
            address: contractAddresses.referral,
            abi: referralAbi,
            functionName: 'getPendingCommission',
            args: [address, roundData.token],
          }) as Promise<bigint>,
          publicClient.readContract({
            address: contractAddresses.referral,
            abi: referralAbi,
            functionName: 'commissionBps',
          }) as Promise<bigint>,
        ]);

        referralCode = code !== zeroHash ? code : undefined;
        pendingCommission = formatTokenValue(pending, roundData.token);
        commissionBps = Number(bps);
      }

      const lastDraw = await buildLiveLotteryRecord(currentRoundId);
      const nextRound: LotteryRoundState = {
        roundId: currentRoundId.toString(),
        tokenSymbol: tokenMeta.symbol,
        tokenAddress: roundData.token,
        ticketPrice: formatTokenValue(roundData.ticketPrice, roundData.token),
        ticketPriceRaw: roundData.ticketPrice.toString(),
        prizePool: formatTokenValue(roundData.prizePool, roundData.token),
        prizePoolRaw: roundData.prizePool.toString(),
        participantCount: Number(roundData.totalTicketsSold),
        closesAt: Number(roundData.endTime) * 1000,
        userEntries: Number(userEntries),
        requestId: roundData.requestId > 0n ? roundData.requestId.toString() : undefined,
        numWinners: Number(roundData.numWinners),
        prizesClaimable: roundData.prizesClaimable,
        statusCode:
          typeof roundData.status === 'bigint' ? Number(roundData.status) : roundData.status,
        statusLabel: inferRoundStatusLabel(roundData),
        canClaimPrize,
        userIsWinner,
        referralCode,
        pendingCommission,
        commissionBps,
        lastDraw,
      };

      setSelectedTokenSymbol(tokenMeta.symbol);
      setRound(nextRound);
      setCountdown(formatCountdown(nextRound.closesAt));
    } catch (error) {
      setFlow({
        stage: 'failed',
        error: toErrorMessage(error, 'Failed to load the live lottery round from Sepolia.'),
      });
    }
  }, [address, buildLiveLotteryRecord, publicClient]);

  useEffect(() => {
    if (appMode !== 'live') {
      const currentRound = getLotteryState();
      setRound(currentRound);
      setCountdown(formatCountdown(currentRound.closesAt));

      const timer = window.setInterval(() => {
        void refreshRound();
      }, 1000);

      return () => {
        window.clearInterval(timer);
        clearPhaseTimers();
      };
    }

    void refreshRound();
    const refreshTimer = window.setInterval(() => {
      void refreshRound();
    }, 7000);

    return () => {
      window.clearInterval(refreshTimer);
      clearPhaseTimers();
    };
  }, [clearPhaseTimers, refreshRound]);

  useEffect(() => clearPhaseTimers, [clearPhaseTimers]);

  useEffect(() => {
    if (!round?.closesAt) {
      setCountdown('--:--');
      return;
    }

    const timer = window.setInterval(() => {
      setCountdown(formatCountdown(round.closesAt));
    }, 1000);

    setCountdown(formatCountdown(round.closesAt));

    return () => window.clearInterval(timer);
  }, [round?.closesAt]);

  const enterRound = useCallback(async () => {
    if (appMode === 'live') {
      if (!isConnected || !address) {
        setFlow({
          stage: 'failed',
          error: 'Connect a wallet before buying a live lottery ticket.',
        });
        return;
      }

      if (chainId !== appConfig.targetChainId) {
        setFlow({
          stage: 'failed',
          error: `Switch the wallet to ${appConfig.targetChainName} before entering the lottery.`,
        });
        return;
      }

      if (!publicClient || !contractAddresses.lottery || !round) {
        setFlow({
          stage: 'failed',
          error: liveIntegrationMessage,
        });
        return;
      }

      if (!round.ticketPriceRaw) {
        setFlow({
          stage: 'failed',
          error: 'Lottery ticket price is unavailable, so the entry transaction cannot be built yet.',
        });
        return;
      }

      if (
        round.tokenAddress &&
        round.tokenAddress.toLowerCase() !== zeroAddress.toLowerCase()
      ) {
        setFlow({
          stage: 'failed',
          error: 'This frontend currently wires the native ETH ticket path only. An ERC-20 approve flow would need to be added for this round token.',
        });
        return;
      }

      setFlow({ stage: 'wallet_confirming' });

      try {
        const txHash = await writeContractAsync({
          address: contractAddresses.lottery,
          abi: lotteryAbi,
          functionName: 'buyTicket',
          args: [BigInt(round.roundId), 1n, zeroHash],
          value: BigInt(round.ticketPriceRaw),
          chainId: appConfig.targetChainId,
        });

        setFlow({ stage: 'tx_pending', txHash });

        const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
        const purchaseLogs = parseEventLogs({
          abi: lotteryAbi,
          logs: receipt.logs,
          eventName: 'TicketsPurchased',
          strict: false,
        });
        const hasOwnPurchase = purchaseLogs.some((log) => {
          const buyer = log.args.buyer;
          return typeof buyer === 'string' && buyer.toLowerCase() === address.toLowerCase();
        });

        if (!hasOwnPurchase) {
          setFlow({
            stage: 'failed',
            txHash,
            error: 'Transaction mined, but TicketsPurchased was not found for the connected wallet.',
          });
          return;
        }

        setFlow({
          stage: 'settled',
          txHash,
        });
        await refreshRound();
      } catch (error) {
        setFlow({
          stage: 'failed',
          error: toErrorMessage(error, 'Lottery ticket purchase failed on Sepolia.'),
        });
      }

      return;
    }

    clearPhaseTimers();
    runId.current += 1;
    setFlow({ stage: 'wallet_confirming' });
    const currentRun = runId.current;

    phaseTimers.current.push(
      window.setTimeout(() => {
        if (runId.current !== currentRun) {
          return;
        }

        setFlow({ stage: 'tx_pending' });
      }, 500),
    );

    phaseTimers.current.push(
      window.setTimeout(() => {
        if (runId.current !== currentRun) {
          return;
        }

        const { txHash, updatedRound } = enterLotteryRound(
          { tokenSymbol: selectedTokenSymbol },
          address,
        );

        setRound(updatedRound);
        setCountdown(formatCountdown(updatedRound.closesAt));
        setFlow({
          stage: 'settled',
          txHash,
        });
      }, 1350),
    );
  }, [
    address,
    chainId,
    clearPhaseTimers,
    isConnected,
    publicClient,
    refreshRound,
    round,
    selectedTokenSymbol,
    writeContractAsync,
  ]);

  const fastForwardDraw = useCallback(() => {
    if (appMode === 'live') {
      return;
    }

    clearPhaseTimers();
    runId.current += 1;
    const currentRun = runId.current;
    setFlow({ stage: 'tx_pending' });

    phaseTimers.current.push(
      window.setTimeout(() => {
        if (runId.current !== currentRun) {
          return;
        }

        const nextRound = fastForwardLotteryRound();
        setRound(nextRound);
        setCountdown(formatCountdown(nextRound.closesAt));
        setFlow({ stage: 'settled' });
      }, 650),
    );
  }, [clearPhaseTimers]);

  const tokens = useMemo(() => {
    if (appMode === 'live' && round?.tokenAddress) {
      const tokenMeta = tokenMetaForAddress(round.tokenAddress);
      return [tokenMeta];
    }

    return demoTokens.filter((token) => token.symbol !== 'ETH');
  }, [round?.tokenAddress]);

  return {
    flow,
    round,
    countdown,
    enterRound,
    fastForwardDraw,
    refreshRound,
    selectedTokenSymbol,
    setSelectedTokenSymbol,
    tokens,
    liveMode: appMode === 'live',
  };
}
