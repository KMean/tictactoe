//file: frontend/lib/chains.ts
import { defineChain } from 'viem'

export const zkSyncEra = defineChain({
  id: 324,
  name: 'zkSync Era',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://mainnet.era.zksync.io'] },
  },
  blockExplorers: {
    default: { name: 'zkSync Explorer', url: 'https://explorer.zksync.io' },
  },
  network: 'zksync-era',
})

export const zkSyncSepolia = defineChain({
  id: 300,
  name: 'zkSync Sepolia',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://sepolia.era.zksync.dev'] },
  },
  blockExplorers: {
    default: { name: 'zkSync Sepolia Explorer', url: 'https://sepolia.explorer.zksync.dev' },
  },
  network: 'zksync-sepolia',
})

export const zkSyncLocal = defineChain({
  id: 260,
  name: 'ZKsync Local Devnet',
  nativeCurrency: {
    name: 'Ether',
    symbol: 'ETH',
    decimals: 18,
  },
  rpcUrls: {
    default: {
      http: ['http://localhost:8011'], // or 127.0.0.1
    },
  },
  blockExplorers: {
    default: {
      name: 'ZK Local',
      url: '',
    },
  },
  network: 'zksync-local',
})
