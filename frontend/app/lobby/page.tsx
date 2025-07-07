// =========================
// frontend/app/lobby/page.tsx – NEW glossy UI using modern wagmi hooks
// =========================
'use client'

import React, { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import toast from 'react-hot-toast'
import {
  useAccount,
  useChainId,
  useWriteContract,
  useWaitForTransactionReceipt,
  useReadContract,
  useReadContracts,
  useWatchContractEvent,
} from 'wagmi'
import { parseEther, formatEther } from 'viem'
import { TICTACTOE_ABI, TICTACTOE_ADDRESS } from '@/lib/contract'

/*─────────────────── Types mirroring contract ───────────────────*/
enum GameState { WaitingForPlayer, InProgress, Finished, Canceled }

interface GameMeta {
  id: number
  creator: `0x${string}`
  opponent: `0x${string}`
  creatorSymbol: number
  turn: number
  bet: bigint
  state: GameState
  winner: `0x${string}`
  lastMoveTime: bigint
}

/*────────────────────────── Component ───────────────────────────*/
export default function LobbyPage () {
  const chainId           = useChainId()
  const { address }       = useAccount()
  const [symbol, setSymbol] = useState(1)        // 1 = X, 2 = O
  const [bet, setBet]       = useState('0.01')

  /*── global counters ─*/
  const { data: gameCount } = useReadContract({
    address:      TICTACTOE_ADDRESS,
    abi:          TICTACTOE_ABI,
    functionName: 'gameCount',

  })

  /*── dynamic meta batch ─*/
  const gameIds   = useMemo(() => gameCount ? [...Array(Number(gameCount)).keys()] : [], [gameCount])
  const contracts = useMemo(() => gameIds.map(i => ({
    address:      TICTACTOE_ADDRESS,
    abi:          TICTACTOE_ABI,
    functionName: 'getGameMeta',
    args:         [BigInt(i)],
    chainId,
  })), [gameIds, chainId])

  const { data: metasRaw, refetch } = useReadContracts({
    contracts,
    allowFailure: true,
    watch: true,
  })

  /*── decode meta tuples into nicer objects ─*/
  const games: GameMeta[] = useMemo(() => metasRaw?.map((tuple, idx) => {
    if (!tuple?.result) return null
    const [creator, opponent, creatorSymbol, turn, bet, state, winner, last] = tuple.result as any
    if (creator === '0x0000000000000000000000000000000000000000') return null
    return { id: idx, creator, opponent, creatorSymbol: Number(creatorSymbol), turn: Number(turn), bet: BigInt(bet), state: state as GameState, winner, lastMoveTime: BigInt(last) }
  }).filter(Boolean) as GameMeta[] ?? [], [metasRaw])

  /*──────────────────── on-chain writes ────────────────────*/
  const { writeContract, data: txHash, isPending } = useWriteContract()
  const { isLoading: waitingTx } = useWaitForTransactionReceipt({ hash: txHash })

  const createGame = () => {
    toast.loading('Creating game…')
    writeContract({
      address:      TICTACTOE_ADDRESS,
      abi:          TICTACTOE_ABI,
      functionName: 'createGame',
      args:         [symbol],
      value:        parseEther(bet),
    }, {
      onSettled: () => toast.dismiss(),
      onSuccess: () => toast.success('Lobby created!'),
      onError:   (e) => toast.error(e.message),
    })
  }

  /*── watch on-chain events to refresh automatically ─*/
  const EVENTS = ['GameCreated','GameJoined','GameCanceled','GameEnded','WinByTimeout'] as const
  EVENTS.forEach(ev => useWatchContractEvent({
    address:      TICTACTOE_ADDRESS,
    abi:          TICTACTOE_ABI,
    eventName:    ev,
    chainId,
    onLogs: () => refetch(),
  }))

  /*────────────────────────── UI ──────────────────────────*/
  return (
    <div className="relative min-h-screen bg-gradient-to-br from-blue-100 to-purple-900 dark:from-gray-900 dark:to-gray-900 overflow-hidden">
      {/* glowing blobs */}
      <div className="absolute inset-0 overflow-hidden">
        <div className="absolute -top-40 left-1/2 w-[600px] h-[600px] bg-purple-300 dark:bg-purple-500 opacity-20 blur-[160px]" />
        <div className="absolute top-40 right-1/3 w-[400px] h-[400px] bg-blue-300 dark:bg-blue-500 opacity-20 blur-[140px]" />
      </div>

      {/* frosted glass card */}
      <div className="relative z-10 pt-40 w-full max-w-5xl mx-auto p-6 bg-white/10 dark:bg-gray-900/30 rounded-lg backdrop-blur-md space-y-16">
        {/* ── Create section ── */}
        <section className="flex flex-col items-center bg-purple-100/10 dark:bg-gray-900/20 p-4 rounded-lg gap-4">
          <div className="flex flex-wrap justify-center gap-4 max-w-2xl w-full">
            <select value={symbol} onChange={e => setSymbol(Number(e.target.value))}
              className="flex-1 px-4 py-3 rounded-lg bg-white dark:bg-gray-800 border focus:ring-purple-500">
              <option value={1}>Play as X</option>
              <option value={2}>Play as O</option>
            </select>
            <input type="number" min="0.01" max="1" step="0.01" value={bet} onChange={e => setBet(e.target.value)}
              className="flex-1 px-4 py-3 rounded-lg bg-white dark:bg-gray-800 border focus:ring-blue-500" placeholder="Bet in ETH" />
            <button onClick={createGame} disabled={isPending || waitingTx}
              className="w-full lg:w-auto flex items-center justify-center gap-2 px-6 py-3 rounded-lg bg-gradient-to-r from-blue-500 to-purple-500 text-white hover:from-blue-600 hover:to-purple-600 disabled:opacity-50">
              {isPending || waitingTx ? 'Creating…' : 'New Game'}
            </button>
          </div>
        </section>

        {/* ── Active games grid ── */}
        <section className="space-y-6">
          <h2 className="text-2xl font-bold text-white flex items-center gap-2">Active Games <span className="text-blue-300">{games.filter(g => g.state === GameState.WaitingForPlayer || g.state === GameState.InProgress).length}</span></h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
            {games.filter(g => g.state === GameState.WaitingForPlayer || g.state === GameState.InProgress).length === 0 && (
              <p className="col-span-full text-center text-gray-200">No open games.</p>
            )}
            {games.filter(g => g.state === GameState.WaitingForPlayer || g.state === GameState.InProgress).map(g => (
              <div key={g.id} className="p-4 bg-white/20 dark:bg-gray-800/40 rounded-lg shadow flex flex-col gap-2">
                <span className="text-white font-semibold">Game #{g.id}</span>
                <span className="text-sm text-gray-200">Bet {formatEther(g.bet)} ETH</span>
                <span className="text-sm text-gray-300">State: {GameState[g.state]}</span>
                <div className="mt-2 flex gap-3">
                  {g.state === GameState.WaitingForPlayer && (
                    g.creator === address ? (
                      <button onClick={() => writeContract({ address:TICTACTOE_ADDRESS, abi:TICTACTOE_ABI, functionName:'cancelGame', args:[BigInt(g.id)] })}
                        className="flex-1 text-red-500 hover:underline">Cancel</button>
                    ) : (
                      <button onClick={() => writeContract({ address:TICTACTOE_ADDRESS, abi:TICTACTOE_ABI, functionName:'joinGame', args:[BigInt(g.id)], value:g.bet })}
                        className="flex-1 text-green-400 hover:underline">Join</button>
                    )
                  )}
                  <Link href={`/game/${g.id}`} className="flex-1 text-blue-400 hover:underline text-center">View</Link>
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* ── Finished games (scroll) ── */}
        <section className="space-y-6">
          <h2 className="text-2xl font-bold text-white flex items-center gap-2">Finished Games <span className="text-blue-300">{games.filter(g => g.state === GameState.Finished || g.state === GameState.Canceled).length}</span></h2>
          <div className="max-h-96 overflow-y-auto grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4 no-scrollbar">
            {games.filter(g => g.state === GameState.Finished || g.state === GameState.Canceled).map(g => (
              <div key={g.id} className="p-4 bg-gray-700/40 rounded-lg shadow flex flex-col gap-1 text-sm text-gray-200">
                <span className="font-semibold text-white">Game #{g.id}</span>
                <span>Bet {formatEther(g.bet)} ETH</span>
                <span>{g.state === GameState.Finished ? `Winner: ${g.winner.slice(0,6)}…` : 'Canceled'}</span>
                <Link href={`/game/${g.id}`} className="text-blue-400 hover:underline mt-1">Details</Link>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  )
}

// =========================
// Note: game page remains identical to previous version in the canvas.
// =========================