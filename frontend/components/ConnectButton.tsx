//file: frontend/components/ConnectButton.tsx
'use client'

import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { injected } from 'wagmi/connectors'

export default function ConnectButton() {
  const { address, isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const { disconnect } = useDisconnect()

  return (
    <div className="text-sm text-center">
      {isConnected ? (
        <div className="flex flex-col items-center gap-2">
          <span>Connected as <code>{address}</code></span>
          <button
            className="bg-red-500 hover:bg-red-600 text-white px-4 py-1 rounded"
            onClick={() => disconnect()}
          >
            Disconnect
          </button>
        </div>
      ) : (
        <button
          className="bg-green-500 hover:bg-green-600 text-white px-4 py-1 rounded"
          onClick={() => connect({ connector: connectors[0] })}
        >
          Connect Wallet
        </button>
      )}
    </div>
  )
}
