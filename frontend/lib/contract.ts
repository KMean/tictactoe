//file: frontend/lib/contract.ts
import { parseAbi } from 'viem'
import { zkSyncEra } from './chains'
import { ticTacToeAbi } from '@/config/tictactoe'
export const TICTACTOE_ADDRESS = '0x7626aa2Af631CB787796CbC99796103e2e0F3Ef3' as `0x${string}`

export const TICTACTOE_ABI = ticTacToeAbi