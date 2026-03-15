"use client";

import { useRouter } from "next/navigation";
import { useCallback, useState } from "react";
import { NightPhaseClient } from "./NightPhaseClient";
import { DayPhaseVoting } from "@/components/DayPhaseVoting";
import { PhaseTransitionOverlay } from "@/components/PhaseTransitionOverlay";
import { InkedScene } from "@/components/InkedScene";
import { AdminGear } from "@/components/AdminGear";
import {
  completeTransitionToDay,
  completeTransitionToNight,
  startTransitionToNight,
} from "@/app/actions/game";
import type { Game, Player } from "@/lib/types";

const TRANSITION_DURATION_MS = 3000;

interface GameClientProps {
  gameId: string;
  game: Game;
  currentPlayer: Player;
  alivePlayers: Player[];
  allPlayers: Player[];
  voteCounts: Record<string, number>;
}

export function GameClient({
  gameId,
  game,
  currentPlayer,
  alivePlayers,
  allPlayers,
  voteCounts,
}: GameClientProps) {
  const router = useRouter();
  const [endingDay, setEndingDay] = useState(false);

  const refresh = useCallback(() => {
    router.refresh();
  }, [router]);

  const gameState = game.game_state ?? "night_phase";
  const transitionTo = game.transition_to ?? null;
  const votedOutPlayerId = game.voted_out_player_id ?? null;
  const votedOutPlayer = votedOutPlayerId
    ? allPlayers.find((p) => p.id === votedOutPlayerId)
    : null;

  // 1) Inked scene — voted out, show ink then advance
  if (gameState === "animation_lock" && votedOutPlayer) {
    return (
      <>
        <InkedScene
          gameId={gameId}
          votedOutPlayer={votedOutPlayer}
          onComplete={refresh}
        />
        <AdminGear gameId={gameId} game={game} players={allPlayers} />
      </>
    );
  }

  // 2) Day Comes overlay — after night ends
  if (gameState === "animation_lock" && transitionTo === "day") {
    return (
      <>
        <PhaseTransitionOverlay
          kind="day_comes"
          durationMs={TRANSITION_DURATION_MS}
          onComplete={async () => {
            await completeTransitionToDay(gameId);
            refresh();
          }}
        />
        <AdminGear gameId={gameId} game={game} players={allPlayers} />
      </>
    );
  }

  // 3) Night Falls overlay — after day ends
  if (gameState === "animation_lock" && transitionTo === "night") {
    return (
      <>
        <PhaseTransitionOverlay
          kind="night_falls"
          durationMs={TRANSITION_DURATION_MS}
          onComplete={async () => {
            await completeTransitionToNight(gameId);
            refresh();
          }}
        />
        <AdminGear gameId={gameId} game={game} players={allPlayers} />
      </>
    );
  }

  // 4) Day phase — voting board
  if (gameState === "day_phase") {
    return (
      <>
        <DayPhaseVoting
          gameId={gameId}
          game={game}
          currentPlayer={currentPlayer}
          alivePlayers={alivePlayers}
          voteCounts={voteCounts}
        />
        <div className="fixed bottom-6 left-1/2 -translate-x-1/2 z-20">
          <button
            type="button"
            disabled={endingDay}
            onClick={async () => {
              setEndingDay(true);
              try {
                await startTransitionToNight(gameId);
                refresh();
              } finally {
                setEndingDay(false);
              }
            }}
            className="font-action rounded-lg bg-amber-600 hover:bg-amber-500 text-amber-950 font-bold px-4 py-2 disabled:opacity-50"
          >
            {endingDay ? "Ending day…" : "End day"}
          </button>
        </div>
        <AdminGear gameId={gameId} game={game} players={allPlayers} />
      </>
    );
  }

  // 5) Night phase
  return (
    <>
      <NightPhaseClient
        gameId={gameId}
        game={game}
        currentPlayer={currentPlayer}
        alivePlayers={alivePlayers}
      />
      <AdminGear gameId={gameId} game={game} players={allPlayers} />
    </>
  );
}
