"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { motion } from "framer-motion";
import { InkblotIcon } from "./InkblotIcon";
import { castDayVote } from "@/app/actions/game";
import type { Game, Player } from "@/lib/types";
import Link from "next/link";

const spring = { type: "spring" as const, stiffness: 300, damping: 25 };

interface DayPhaseVotingProps {
  gameId: string;
  game: Game;
  currentPlayer: Player;
  alivePlayers: Player[];
  voteCounts: Record<string, number>;
}

export function DayPhaseVoting({
  gameId,
  game,
  currentPlayer,
  alivePlayers,
  voteCounts,
}: DayPhaseVotingProps) {
  const router = useRouter();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleVote(targetId: string) {
    if (targetId === currentPlayer.id) return;
    setError(null);
    setLoading(true);
    setSelectedId(targetId);
    try {
      await castDayVote(gameId, currentPlayer.id, targetId);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Vote failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-paper text-ink p-6 flex flex-col items-center">
      <h1 className="font-title text-2xl font-bold uppercase tracking-wide mb-1">
        The Meeting
      </h1>
      <p className="text-ink-muted text-sm mb-6">Round {game.round_number} — Vote to eliminate</p>

      {error && (
        <div className="rounded-lg bg-red-100 border border-red-300 text-red-800 px-4 py-2 mb-4 text-sm">
          {error}
        </div>
      )}

      <motion.div
        className="grid grid-cols-2 sm:grid-cols-3 gap-3 w-full max-w-lg"
        initial="hidden"
        animate="visible"
        variants={{
          visible: { transition: { staggerChildren: 0.05 } },
          hidden: {},
        }}
      >
        {alivePlayers.map((player) => {
          const votes = voteCounts[player.id] ?? 0;
          const isSelected = selectedId === player.id;
          const isSelf = player.id === currentPlayer.id;

          return (
            <motion.button
              key={player.id}
              type="button"
              disabled={loading || isSelf}
              variants={{
                visible: { opacity: 1, scale: 1 },
                hidden: { opacity: 0, scale: 0.8 },
              }}
              transition={spring}
              onClick={() => !isSelf && handleVote(player.id)}
              className={`
                font-dialogue flex items-center justify-between gap-2 rounded-lg border-2 px-4 py-3 text-left
                transition-colors
                ${isSelf ? "border-ink-muted bg-ink/5 cursor-not-allowed opacity-70" : "border-ink bg-paper hover:bg-ink hover:text-paper"}
                ${isSelected ? "ring-2 ring-amber-500" : ""}
              `}
            >
              <span className="font-game-ui font-semibold truncate">{player.display_name}</span>
              <span className="flex items-center gap-1 shrink-0">
                {Array.from({ length: votes }).map((_, i) => (
                  <InkblotIcon key={i} className="w-5 h-5 text-ink" />
                ))}
              </span>
            </motion.button>
          );
        })}
      </motion.div>

      <p className="text-ink-muted text-xs mt-6 text-center max-w-sm">
        Click a name to place your vote. First to 4 votes is eliminated.
      </p>

      <Link href="/" className="mt-8 text-ink-muted hover:text-ink text-sm">
        Back home
      </Link>
    </div>
  );
}
