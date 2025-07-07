//file: frontend/app/page.tsx
import Image from "next/image";
import ConnectButton from "@/components/ConnectButton";

export default function Home() {
  return (
    <div className="grid grid-rows-[20px_1fr_20px] items-center justify-items-center min-h-screen p-8 pb-20 gap-16 sm:p-20 font-[family-name:var(--font-geist-sans)]">
      <main className="flex flex-col gap-[32px] row-start-2 items-center sm:items-start">
        <ConnectButton />

        {/* Your other content... */}
        <div className="min-h-screen flex flex-col items-center justify-center bg-gray-900 text-white">
          <h1 className="text-4xl font-bold mb-4 text-blue-400">Tailwind CSS Test</h1>
          <p className="mb-2 text-lg">If you can see styles like colors and spacing, Tailwind is working! ✅</p>
          <button className="mt-4 px-4 py-2 bg-green-500 hover:bg-green-600 rounded shadow">
            Test Button
          </button>
        </div>
      </main>

      {/* Footer stays the same */}
    </div>
  );
}
