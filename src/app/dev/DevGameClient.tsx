"use client";

import { useState, useCallback } from "react";
import Link from "next/link";
import { NightPhase, type DevActionPayload } from "@/components/NightPhase";
import { PhaseTransitionOverlay } from "@/components/PhaseTransitionOverlay";
import { InkedScene } from "@/components/InkedScene";
import { DayPhaseVoting } from "@/components/DayPhaseVoting";
import { DEV_GAME, DEV_PLAYERS, ROLES_ORDER } from "./devData";
import type { Role } from "@/lib/types";
import type { Player } from "@/lib/types";

const ROLE_LABELS: Record<Role, string> = {
  ace: "The Ace",
  bot: "The Bot",
  miner: "The Miner",
  strongman: "The Strongman",
  undertaker: "The Undertaker",
  ghost: "The Ghost",
  professor: "The Professor",
  thief: "The Thief",
};

function clonePlayers(players: Player[]): Player[] {
  return players.map((p) => ({ ...p }));
}

type PreviewAnimation = null | "day_comes" | "night_falls" | "inked";

export function DevGameClient() {
  const [players, setPlayers] = useState<Player[]>(() => clonePlayers(DEV_PLAYERS));
  const [role, setRole] = useState<Role>("ace");
  const [roundKey, setRoundKey] = useState(0);
  const [preview, setPreview] = useState<PreviewAnimation>(null);
  const [showVotingPreview, setShowVotingPreview] = useState(false);

  const alivePlayers = players.filter((p) => p.is_alive);
  const currentPlayer = players.find((p) => p.role === role && p.is_alive) ?? alivePlayers[0]!;
  const inkedPlayer = alivePlayers[0] ?? currentPlayer;

  const applyDevAction = useCallback((payload: DevActionPayload | undefined) => {
    if (!payload) return;
    setPlayers((prev) => {
      const cur = prev.find((p) => p.role === role && p.is_alive);
      if (!cur) return prev;
      return prev.map((p) => {
        if (p.id !== cur.id) return p;
        const next = { ...p };
        switch (payload.action) {
          case "bot":
            next.bot_uses_remaining = Math.max(0, (next.bot_uses_remaining ?? 2) - 1);
            break;
          case "miner":
            next.miner_uses_remaining = Math.max(0, (next.miner_uses_remaining ?? 2) - 1);
            break;
          case "strongman":
            if (payload.protectPlayerId != null)
              next.strongman_uses_remaining = Math.max(0, (next.strongman_uses_remaining ?? 2) - 1);
            break;
          case "undertaker":
            next.undertaker_uses_remaining = Math.max(0, (next.undertaker_uses_remaining ?? 2) - 1);
            break;
          case "thief": {
            const target = prev.find((x) => x.id === payload.targetPlayerId);
            if (target) {
              next.copied_role_from_player_id = target.id;
              next.copied_role = target.role;
            }
            break;
          }
          case "ace": {
            if ("targetPlayerId" in payload && payload.targetPlayerId) {
              setPlayers((prev) =>
                prev.map((p) =>
                  p.id === payload.targetPlayerId ? { ...p, is_alive: false } : p
                )
              );
            }
            break;
          }
        }
        return next;
      });
    });
  }, [role]);

  const devGameWithRound = { ...DEV_GAME, round_number: (DEV_GAME.round_number + roundKey) % 5 || 1 };

  return (
    <div className="game-background night-lights-out relative min-h-screen">
      <div className="night-overlay" aria-hidden />
      <div className="relative z-10 container mx-auto px-4 py-6 max-w-2xl">
        <div className="flex flex-wrap items-center gap-3 mb-4 p-3 rounded-lg bg-slate-900/80 border border-amber-500/50">
          <span className="text-amber-400 font-semibold text-sm">Dev build — preview</span>
          <label className="text-slate-400 text-sm flex items-center gap-2">
            View as:
            <select
              value={role}
              onChange={(e) => setRole(e.target.value as Role)}
              className="rounded bg-slate-800 text-slate-200 border border-slate-600 px-2 py-1 text-sm"
            >
              {ROLES_ORDER.map((r) => (
                <option key={r} value={r}>
                  {ROLE_LABELS[r]}
                </option>
              ))}
            </select>
          </label>
          <button
            type="button"
            onClick={() => setRoundKey((k) => k + 1)}
            className="rounded-lg bg-amber-600 hover:bg-amber-500 text-slate-900 font-semibold px-3 py-1.5 text-sm"
          >
            Next day →
          </button>
          <span className="text-slate-500 text-xs">Animations:</span>
          <button
            type="button"
            onClick={() => setPreview("day_comes")}
            className="rounded bg-amber-950 text-amber-200 px-2 py-1 text-xs hover:bg-amber-900"
          >
            Day Comes
          </button>
          <button
            type="button"
            onClick={() => setPreview("night_falls")}
            className="rounded bg-slate-800 text-slate-200 px-2 py-1 text-xs hover:bg-slate-700"
          >
            Night Falls
          </button>
          <button
            type="button"
            onClick={() => setPreview("inked")}
            className="rounded bg-ink text-paper px-2 py-1 text-xs hover:bg-ink-muted"
          >
            Inked
          </button>
          <Link
            href="/"
            className="text-slate-400 hover:text-slate-300 text-sm"
          >
            ← Home
          </Link>
        </div>
        {preview === "day_comes" && (
          <PhaseTransitionOverlay
            kind="day_comes"
            onComplete={() => {
              setPreview(null);
              setShowVotingPreview(true);
            }}
          />
        )}
        {preview === "night_falls" && (
          <PhaseTransitionOverlay kind="night_falls" onComplete={() => setPreview(null)} />
        )}
        {preview === "inked" && (
          <InkedScene
            gameId="dev-game-id"
            votedOutPlayer={inkedPlayer}
            onComplete={() => setPreview(null)}
            devPreview
          />
        )}
        {showVotingPreview && (
          <div className="mb-6 rounded-lg border border-amber-500/50 bg-paper/95 p-4">
            <div className="mb-3 flex items-center justify-between">
              <span className="text-amber-600 text-sm font-medium">Voting (preview after Day Comes)</span>
              <button
                type="button"
                onClick={() => setShowVotingPreview(false)}
                className="rounded bg-slate-200 px-2 py-1 text-xs text-slate-700 hover:bg-slate-300"
              >
                Close
              </button>
            </div>
            <DayPhaseVoting
              gameId={DEV_GAME.id}
              game={{ ...devGameWithRound, game_state: "day_phase" }}
              currentPlayer={currentPlayer}
              alivePlayers={alivePlayers}
              voteCounts={{}}
            />
          </div>
        )}
        <NightPhase
          key={roundKey}
          game={devGameWithRound}
          currentPlayer={currentPlayer}
          alivePlayers={alivePlayers}
          onActionComplete={applyDevAction}
          devMode
        />
        <div className="mt-6 flex gap-3">
          <Link
            href="/reveal?role=ace"
            className="text-slate-400 hover:text-slate-300 text-sm"
          >
            Preview role reveal →
          </Link>
        </div>
      </div>
    </div>
  );
}
