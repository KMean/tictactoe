//file: frontend/lib/wagmi.ts
import { createConfig, http } from 'wagmi'
import { zkSyncEra, zkSyncSepolia, zkSyncLocal } from './chains'

export const config = createConfig({
  chains: [zkSyncEra, zkSyncSepolia, zkSyncLocal],
  transports: {
    [zkSyncEra.id]: http(),
    [zkSyncSepolia.id]: http(),
    [zkSyncLocal.id]: http(),
  },
  ssr: true,
})