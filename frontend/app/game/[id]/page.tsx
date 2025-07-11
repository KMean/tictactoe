'use client';

import React, { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useChainId,
} from 'wagmi';
import { toast } from 'react-hot-toast';
import { getPublicClient } from 'wagmi/actions';
import { config } from '@/lib/wagmi';
import { TICTACTOE_ABI, TICTACTOE_ADDRESS } from '@/lib/contract';
import clsx from 'clsx';
import { parseGwei } from 'viem';

////////////////////////////////////////////////////////////////////////////////
// ✏️  Types & helpers
////////////////////////////////////////////////////////////////////////////////

type Cell = 0 | 1 | 2;
const label = (c: Cell) => (c === 1 ? 'X' : c === 2 ? 'O' : '');

enum GameState {
  WaitingForPlayer,
  InProgress,
  Finished,
  Canceled,
}

const same = (a?: string, b?: string) =>
  (a ?? '').toLowerCase() === (b ?? '').toLowerCase();

function getPlayerSymbol(
  creatorSymbol: number,
  creator: string,
  opponent: string,
  player?: string
): number {
  if (!player) return 0;
  if (same(player, creator)) return creatorSymbol;
  if (same(player, opponent)) return creatorSymbol === 1 ? 2 : 1;
  return 0;
}

////////////////////////////////////////////////////////////////////////////////
// 🚀  Component
////////////////////////////////////////////////////////////////////////////////

export default function GamePage() {
  const { id } = useParams<{ id: string }>();
  const [gameId, setGameId] = useState<bigint | null>(null);

  const [board, setBoard] = useState<Cell[][]>([
    [0, 0, 0],
    [0, 0, 0],
    [0, 0, 0],
  ]);

  const [meta, setMeta] = useState<{
    creator: string;
    opponent: string;
    creatorSymbol: number;
    turn: number;
    state: GameState;
    bet: bigint;
  } | null>(null);

  const [error, setError] = useState<string | null>(null);

  // wagmi hooks
  const { address } = useAccount();
  const { writeContract, data: txHash, isPending } = useWriteContract();
  useWaitForTransactionReceipt({ hash: txHash });
  const chainId = useChainId();

  ////////////////////////////////////////////////////////////////////////////
  // Parse the route param
  ////////////////////////////////////////////////////////////////////////////
  useEffect(() => {
    if (id === undefined) return;
    try {
      setGameId(BigInt(id));
    } catch {
      setGameId(null);
    }
  }, [id]);

  ////////////////////////////////////////////////////////////////////////////
  // Load board + metadata from chain
  ////////////////////////////////////////////////////////////////////////////
  useEffect(() => {
    if (gameId === null || !chainId) return;

    const pc = getPublicClient(config, { chainId: chainId as 300 | 324 | 260 });

    const load = async () => {
      const toastId = toast.loading('Loading game data…');
      try {
        /* ------------------------------------------------------------------ */
        /* Board: getBoardState returns Player[9] (flat array of uint8)       */
        /* ------------------------------------------------------------------ */
        const flat = (await pc.readContract({
          address: TICTACTOE_ADDRESS,
          abi: TICTACTOE_ABI,
          functionName: 'getBoardState',
          args: [gameId],
        })) as readonly number[];

        setBoard([
          flat.slice(0, 3) as Cell[],
          flat.slice(3, 6) as Cell[],
          flat.slice(6, 9) as Cell[],
        ]);

        /* ------------------------------------------------------------------ */
        /* Game struct: 10-item tuple (see contract)                          */
        /* ------------------------------------------------------------------ */
        const tuple = (await pc.readContract({
          address: TICTACTOE_ADDRESS,
          abi: TICTACTOE_ABI,
          functionName: 'games',
          args: [gameId],
        })) as readonly [
          `0x${string}`, // creator
          `0x${string}`, // opponent
          number,        // creatorSymbol
          number,        // turn
          bigint,        // bet
          number,        // state
          bigint,        // boardX
          bigint,        // boardO
          `0x${string}`, // winner
          bigint         // lastMoveTime
        ];

        const [
          creator,
          opponent,
          creatorSymbol,
          turn,
          bet,
          state,
          /* boardX */,
          /* boardO */,
        ] = tuple;

        setMeta({
          creator,
          opponent,
          creatorSymbol,
          turn,
          bet,
          state: state as GameState,
        });

        setError(null);
        toast.dismiss(toastId);
      } catch (e) {
        console.error('❌ Error loading board:', e);
        setError('Game not found on chain');
        toast.dismiss(toastId);
        toast.error('Failed to load game');
      }
    };

    load();
  }, [gameId, txHash, chainId]);

  ////////////////////////////////////////////////////////////////////////////
  // Derived state
  ////////////////////////////////////////////////////////////////////////////
  const yourSymbol = meta
    ? getPlayerSymbol(
        meta.creatorSymbol,
        meta.creator,
        meta.opponent,
        address
      )
    : 0;

  const yourTurn =
    meta?.state === GameState.InProgress && yourSymbol === meta?.turn;

  ////////////////////////////////////////////////////////////////////////////
  // Send a move
  ////////////////////////////////////////////////////////////////////////////
  const move = (x: number, y: number) => {
    if (gameId === null) return;
    const toastId = toast.loading('Sending move…');

    writeContract(
      {
        address: TICTACTOE_ADDRESS,
        abi: TICTACTOE_ABI,
        functionName: 'makeMove',
        args: [gameId, x, y],
        gas: BigInt(300_000),
        maxFeePerGas: parseGwei('0.25'),
        maxPriorityFeePerGas: parseGwei('0.25'),
      },
      {
        onError: (e) => {
          toast.dismiss(toastId);
          toast.error(`Move failed: ${e.message}`);
        },
        onSettled: () => {
          toast.dismiss(toastId);
          toast.success('Move sent!');
        },
      }
    );
  };

  ////////////////////////////////////////////////////////////////////////////
  // Render
  ////////////////////////////////////////////////////////////////////////////
  if (id === undefined) return <p className="p-6">Loading…</p>;
  if (gameId === null)
    return <p className="p-6 text-red-600">Invalid game ID</p>;
  if (error) return <p className="p-6 text-red-600">{error}</p>;
  if (!meta) return <p className="p-6">Loading…</p>;

  return (
    <div className="relative min-h-screen bg-gradient-to-br from-blue-100 to-purple-900 dark:from-gray-900 dark:to-gray-900 overflow-hidden">
      {/* blurs */}
      <div className="absolute inset-0 overflow-hidden">
        <div className="absolute -top-40 left-1/2 w-[600px] h-[600px] bg-purple-300 dark:bg-purple-500 opacity-20 blur-[160px]" />
        <div className="absolute top-40 right-1/3 w-[400px] h-[400px] bg-blue-300 dark:bg-blue-500 opacity-20 blur-[140px]" />
      </div>

      <div className="relative z-10 max-w-md mx-auto p-6 mt-40 bg-white/10 dark:bg-gray-900/30 rounded-lg shadow-md backdrop-blur-md space-y-6">
        <h1 className="text-2xl font-bold text-white">Game #{id}</h1>
        <p className="text-white">Bet: {Number(meta.bet) / 1e18} ETH</p>
        <p className="text-white">
          You are playing as{' '}
          {yourSymbol === 1 ? 'X' : yourSymbol === 2 ? 'O' : 'Unknown'}
        </p>

        <p className="italic text-white">
          {meta.state === GameState.WaitingForPlayer && 'Waiting for opponent…'}
          {meta.state === GameState.InProgress &&
            (yourTurn ? '✅ Your turn!' : '⏳ Opponent’s turn…')}
          {meta.state === GameState.Finished && '🎉 Game finished'}
          {meta.state === GameState.Canceled && '❌ Game canceled'}
        </p>

        <div className="grid grid-cols-3 w-[192px] aspect-square mx-auto border border-gray-400">
          {board.flatMap((row, y) =>
            row.map((cell, x) => {
              const disabled = cell !== 0 || !yourTurn || isPending;
              return (
                <button
                  key={`${x}-${y}`}
                  disabled={disabled}
                  onClick={() => move(x, y)}
                  className={clsx(
                    'aspect-square w-full text-3xl flex items-center justify-center select-none',
                    'border border-gray-400 text-white',
                    !disabled && 'hover:bg-blue-100/20 cursor-pointer',
                    disabled && 'cursor-not-allowed opacity-70'
                  )}
                >
                  {label(cell)}
                </button>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
}
