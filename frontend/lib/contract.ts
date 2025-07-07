//file: frontend/lib/contract.ts
import { parseAbi } from 'viem'
import { zkSyncEra } from './chains'
import { ticTacToeAbi } from '@/config/tictactoe'
export const TICTACTOE_ADDRESS = '0x6ddbE5cAE2863A0D75f8e33f9CDB0D33aff0B363' as `0x${string}`

export const TICTACTOE_ABI = ticTacToeAbi