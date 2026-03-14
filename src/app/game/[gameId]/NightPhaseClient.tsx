"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { NightPhase } from "@/components/NightPhase";
import { resolveNightToDay } from "@/app/actions/game";
import type { Game, Player } from "@/lib/types";
import Link from "next/link";

interface NightPhaseClientProps {
  gameId: string;
  game: Game;
  currentPlayer: Player;
  alivePlayers: Player[];
}

export function NightPhaseClient({
  gameId,
  game,
  currentPlayer,
  alivePlayers,
}: NightPhaseClientProps) {
  const router = useRouter();
  const [endingNight, setEndingNight] = useState(false);
  const [endError, setEndError] = useState<string | null>(null);

  async function handleEndNight() {
    setEndError(null);
    setEndingNight(true);
    try {
      await resolveNightToDay(gameId);
      router.refresh();
    } catch (e) {
      setEndError(e instanceof Error ? e.message : "Failed to end night.");
    } finally {
      setEndingNight(false);
    }
  }

  return (
    <>
      <NightPhase
        game={game}
        currentPlayer={currentPlayer}
        alivePlayers={alivePlayers}
        onActionComplete={() => router.refresh()}
      />
      <div className="fixed bottom-6 left-1/2 -translate-x-1/2 z-20 flex flex-col items-center gap-2">
        {endError && (
          <p className="text-red-400 text-sm bg-slate-900/90 px-3 py-1 rounded">{endError}</p>
        )}
        <button
          onClick={handleEndNight}
          disabled={endingNight}
          className="rounded-lg bg-slate-600 hover:bg-slate-500 disabled:opacity-50 text-white font-medium px-4 py-2"
        >
          {endingNight ? "Ending night…" : "End night"}
        </button>
        <Link
          href="/"
          className="text-slate-400 hover:text-slate-300 text-sm"
        >
          Back home
        </Link>
      </div>
    </>
  );
}
