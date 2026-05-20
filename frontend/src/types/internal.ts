import type { useBetHistory } from '@/hooks/useBetHistory';
import type { useDiceBet } from '@/hooks/useDiceBet';
import type { useLottery } from '@/hooks/useLottery';

export type ReturnTypeOfUseDiceBet = ReturnType<typeof useDiceBet>;
export type ReturnTypeOfUseLottery = ReturnType<typeof useLottery>;
export type ReturnTypeOfUseBetHistory = ReturnType<typeof useBetHistory>;
