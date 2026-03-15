"use client";

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  setGameState,
  resetDayVotes,
  killPlayerForDev,
} from "@/app/actions/game";
import type { Game, Player } from "@/lib/types";

const spring = { type: "spring" as const, stiffness: 300, damping: 25 };

interface AdminGearProps {
  gameId: string;
  game: Game;
  players: Player[];
}

export function AdminGear({ gameId, game, players }: AdminGearProps) {
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);

  if (process.env.NODE_ENV !== "development") return null;

  async function forceDay() {
    setLoading(true);
    try {
      await setGameState(gameId, "day_phase");
      window.location.reload();
    } finally {
      setLoading(false);
    }
  }

  async function forceNight() {
    setLoading(true);
    try {
      await setGameState(gameId, "night_phase");
      window.location.reload();
    } finally {
      setLoading(false);
    }
  }

  async function resetVotes() {
    setLoading(true);
    try {
      await resetDayVotes(gameId);
      window.location.reload();
    } finally {
      setLoading(false);
    }
  }

  async function killFirst() {
    const first = players[0];
    if (!first) return;
    setLoading(true);
    try {
      await killPlayerForDev(gameId, first.id);
      window.location.reload();
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="fixed bottom-4 right-4 z-50">
      <motion.button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="flex items-center justify-center w-12 h-12 rounded-full bg-amber-600 text-amber-950 font-action text-lg shadow-lg"
        whileHover={{ scale: 1.05 }}
        whileTap={{ scale: 0.95 }}
        transition={spring}
        aria-label="Admin menu"
      >
        ⚙
      </motion.button>

      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, y: 8, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 8, scale: 0.95 }}
            transition={spring}
            className="absolute bottom-14 right-0 flex flex-col gap-2 p-2 rounded-lg bg-slate-900 border border-amber-500/50 shadow-xl min-w-[140px]"
          >
            <span className="text-amber-400 text-xs font-semibold px-2">Admin</span>
            <button
              type="button"
              disabled={loading}
              onClick={forceDay}
              className="font-action text-left text-sm text-slate-200 hover:text-amber-400 px-2 py-1 rounded disabled:opacity-50"
            >
              Force Day
            </button>
            <button
              type="button"
              disabled={loading}
              onClick={forceNight}
              className="font-action text-left text-sm text-slate-200 hover:text-amber-400 px-2 py-1 rounded disabled:opacity-50"
            >
              Force Night
            </button>
            <button
              type="button"
              disabled={loading}
              onClick={resetVotes}
              className="font-action text-left text-sm text-slate-200 hover:text-amber-400 px-2 py-1 rounded disabled:opacity-50"
            >
              Reset Votes
            </button>
            <button
              type="button"
              disabled={loading || !players.length}
              onClick={killFirst}
              className="font-action text-left text-sm text-red-300 hover:text-red-400 px-2 py-1 rounded disabled:opacity-50"
            >
              Kill Player 1
            </button>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
