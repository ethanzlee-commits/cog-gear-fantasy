"use client";

import { useState } from "react";
import type { Game, Player, Role } from "@/lib/types";
import {
  submitAceTarget,
  submitBotSwap,
  submitMinerTarget,
  submitStrongmanProtection,
  submitUndertakerClean,
  submitThiefSwap,
} from "@/lib/actions/night-actions";

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

/** Payload for dev mode so the host can update use counts / Thief copy state */
export type DevActionPayload =
  | { action: "ace"; targetPlayerId: string }
  | { action: "bot" }
  | { action: "miner" }
  | { action: "strongman"; protectPlayerId: string | null }
  | { action: "undertaker" }
  | { action: "thief"; targetPlayerId: string };

interface NightPhaseProps {
  game: Game;
  currentPlayer: Player;
  /** All alive players in the game (for targeting). Exclude self where required. */
  alivePlayers: Player[];
  /** Called after an action is submitted. In dev mode, optional payload describes the action for updating use counts. */
  onActionComplete?: (devPayload?: DevActionPayload) => void;
  /** When true, actions are no-op (for dev/demo preview without Supabase). */
  devMode?: boolean;
}

export function NightPhase({
  game,
  currentPlayer,
  alivePlayers,
  onActionComplete,
  devMode = false,
}: NightPhaseProps) {
  const [error, setError] = useState<string | null>(null);
  const [minerResult, setMinerResult] = useState<string | null>(null);
  const [undertakerResult, setUndertakerResult] = useState<string | null>(null);
  const [submitted, setSubmitted] = useState(false);

  const otherAlive = alivePlayers.filter((p) => p.id !== currentPlayer.id);
  const hasBody = game.body_player_id != null;

  const handleAce = async (targetId: string) => {
    setError(null);
    if (devMode) {
      setSubmitted(true);
      onActionComplete?.({ action: "ace", targetPlayerId: targetId });
      return;
    }
    try {
      await submitAceTarget(game.id, currentPlayer.id, targetId);
      setSubmitted(true);
      onActionComplete?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to submit.");
    }
  };

  const handleBot = async (target1Id: string, target2Id: string) => {
    if (target1Id === target2Id) {
      setError("Select two different players.");
      return;
    }
    setError(null);
    if (devMode) {
      setSubmitted(true);
      onActionComplete?.({ action: "bot" });
      return;
    }
    try {
      await submitBotSwap(game.id, currentPlayer.id, target1Id, target2Id);
      setSubmitted(true);
      onActionComplete?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to swap.");
    }
  };

  const handleMiner = async (targetId: string) => {
    setError(null);
    setMinerResult(null);
    if (devMode) {
      const name = alivePlayers.find((p) => p.id === targetId)?.display_name ?? "Someone";
      setMinerResult(`[Dev] This player visited ${name}.`);
      setSubmitted(true);
      onActionComplete?.({ action: "miner" });
      return;
    }
    try {
      const result = await submitMinerTarget(game.id, currentPlayer.id, targetId);
      setMinerResult(
        result.visited
          ? `This player visited ${result.target_name}.`
          : "This player stayed home."
      );
      setSubmitted(true);
      onActionComplete?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to investigate.");
    }
  };

  const handleStrongman = async (protectPlayerId: string | null) => {
    setError(null);
    if (devMode) {
      setSubmitted(true);
      onActionComplete?.({ action: "strongman", protectPlayerId });
      return;
    }
    try {
      await submitStrongmanProtection(game.id, currentPlayer.id, protectPlayerId);
      setSubmitted(true);
      onActionComplete?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to set protection.");
    }
  };

  const handleUndertaker = async () => {
    setError(null);
    setUndertakerResult(null);
    if (devMode) {
      setUndertakerResult("[Dev] Body cleaned.");
      setSubmitted(true);
      onActionComplete?.({ action: "undertaker" });
      return;
    }
    try {
      const data = await submitUndertakerClean(game.id, currentPlayer.id);
      setUndertakerResult(data?.message ?? (data?.success ? "Body cleaned." : "No body to clean."));
      setSubmitted(true);
      onActionComplete?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to clean.");
    }
  };

  const handleThiefSwap = async (targetId: string) => {
    setError(null);
    if (devMode) {
      setSubmitted(true);
      onActionComplete?.({ action: "thief", targetPlayerId: targetId });
      return;
    }
    try {
      await submitThiefSwap(game.id, currentPlayer.id, targetId);
      setSubmitted(true);
      onActionComplete?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to swap.");
    }
  };

  return (
    <div className="night-lights-out relative">
      {/* Lights Out film-grain overlay */}
      <div className="night-overlay" aria-hidden />

      <div className="relative z-10 container mx-auto px-4 py-8 max-w-2xl">
        <h1 className="font-title text-2xl font-bold text-amber-400/90 tracking-wide mb-1">
          Lights Out
        </h1>
        <p className="text-slate-400 text-sm mb-6">Night Phase — Round {game.round_number}</p>

        <div className="rounded-lg border border-slate-700/80 bg-slate-900/80 p-4 mb-4">
          <p className="text-slate-300 text-sm">
            You are <span className="font-game-ui font-semibold text-amber-400 tracking-wide">{ROLE_LABELS[currentPlayer.role]}</span>
          </p>
        </div>

        {error && (
          <div className="rounded-lg bg-red-950/60 border border-red-800 text-red-200 px-4 py-2 mb-4 text-sm">
            {error}
          </div>
        )}

        {minerResult && (
          <div className="rounded-lg bg-emerald-950/50 border border-emerald-800 text-emerald-200 px-4 py-3 mb-4">
            {minerResult}
          </div>
        )}

        {undertakerResult && (
          <div className="rounded-lg bg-emerald-950/50 border border-emerald-800 text-emerald-200 px-4 py-3 mb-4">
            {undertakerResult}
          </div>
        )}

        {!submitted && (
          <RoleMenu
            role={currentPlayer.role}
            copiedRole={currentPlayer.role === "thief" ? currentPlayer.copied_role ?? null : null}
            currentPlayerId={currentPlayer.id}
            otherAlive={otherAlive}
            hasBody={hasBody}
            isInvincible={currentPlayer.is_invincible}
            roundNumber={game.round_number}
            botUsesLeft={currentPlayer.bot_uses_remaining ?? 2}
            minerUsesLeft={currentPlayer.miner_uses_remaining ?? 2}
            strongmanUsesLeft={currentPlayer.strongman_uses_remaining ?? 2}
            undertakerUsesLeft={currentPlayer.undertaker_uses_remaining ?? 2}
            thiefAlreadyCopied={!!currentPlayer.copied_role_from_player_id}
            onAceTarget={handleAce}
            onBotSwap={handleBot}
            onMinerTarget={handleMiner}
            onStrongmanProtect={handleStrongman}
            onUndertakerClean={handleUndertaker}
            onThiefSwap={handleThiefSwap}
          />
        )}

        {submitted && (
          <p className="text-slate-500 text-sm">Action submitted. Waiting for night to end...</p>
        )}
      </div>
    </div>
  );
}

const ACTION_ROLES: Role[] = ["ace", "bot", "miner", "strongman", "undertaker"];

interface RoleMenuProps {
  role: Role;
  /** When Thief has copied, the role they copied (so we show that role's action UI). */
  copiedRole: Role | null;
  currentPlayerId: string;
  otherAlive: Player[];
  hasBody: boolean;
  isInvincible: boolean;
  roundNumber: number;
  botUsesLeft: number;
  minerUsesLeft: number;
  strongmanUsesLeft: number;
  undertakerUsesLeft: number;
  thiefAlreadyCopied: boolean;
  onAceTarget: (targetId: string) => void;
  onBotSwap: (id1: string, id2: string) => void;
  onMinerTarget: (targetId: string) => void;
  onStrongmanProtect: (playerId: string | null) => void;
  onUndertakerClean: () => void;
  onThiefSwap: (targetId: string) => void;
}

function RoleMenu({
  role,
  copiedRole,
  currentPlayerId,
  otherAlive,
  hasBody,
  isInvincible,
  roundNumber,
  botUsesLeft,
  minerUsesLeft,
  strongmanUsesLeft,
  undertakerUsesLeft,
  thiefAlreadyCopied,
  onAceTarget,
  onBotSwap,
  onMinerTarget,
  onStrongmanProtect,
  onUndertakerClean,
  onThiefSwap,
}: RoleMenuProps) {
  const [aceTarget, setAceTarget] = useState<string>("");
  const [botTarget1, setBotTarget1] = useState<string>("");
  const [botTarget2, setBotTarget2] = useState<string>("");
  const [minerTarget, setMinerTarget] = useState<string>("");
  const [strongmanProtect, setStrongmanProtect] = useState<boolean>(false);
  const [strongmanTarget, setStrongmanTarget] = useState<string>("");
  const [thiefTarget, setThiefTarget] = useState<string>("");

  const effectiveRole: Role =
    role === "thief" && thiefAlreadyCopied && copiedRole && ACTION_ROLES.includes(copiedRole)
      ? copiedRole
      : role;
  const usingCopiedRole = role === "thief" && effectiveRole !== "thief";

  switch (effectiveRole) {
    case "ace":
      return (
        <section className="space-y-3">
          {usingCopiedRole && copiedRole && (
            <p className="text-amber-400 text-sm">Using your copied role: <span className="font-game-ui">{ROLE_LABELS[copiedRole]}</span>.</p>
          )}
          <h2 className="font-title text-lg font-semibold text-slate-200">Eliminate a player</h2>
          <p className="text-slate-400 text-sm">Your choice is hidden until the Day phase.</p>
          <select
            value={aceTarget}
            onChange={(e) => setAceTarget(e.target.value)}
            className="w-full rounded-lg bg-slate-800 border border-slate-600 text-slate-100 px-3 py-2"
          >
            <option value="">Select a player…</option>
            {otherAlive.map((p) => (
              <option key={p.id} value={p.id}>
                {p.display_name}
              </option>
            ))}
          </select>
          <button
            onClick={() => aceTarget && onAceTarget(aceTarget)}
            disabled={!aceTarget}
            className="w-full rounded-lg bg-rose-700 hover:bg-rose-600 disabled:opacity-50 text-white font-medium py-2"
          >
            Confirm elimination
          </button>
        </section>
      );

    case "bot":
      return (
        <section className="space-y-3">
          {usingCopiedRole && copiedRole && (
            <p className="text-amber-400 text-sm">Using your copied role: <span className="font-game-ui">{ROLE_LABELS[copiedRole]}</span>.</p>
          )}
          <h2 className="font-title text-lg font-semibold text-slate-200">The Switcheroo</h2>
          <p className="text-slate-400 text-sm">Pick two players to swap their roles (excluding yourself). Uses left: {botUsesLeft}/2.</p>
          {botUsesLeft < 1 && <p className="text-amber-400 text-sm">You have used both swaps this game.</p>}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-slate-400 text-xs mb-1">First player</label>
              <select
                value={botTarget1}
                onChange={(e) => setBotTarget1(e.target.value)}
                className="w-full rounded-lg bg-slate-800 border border-slate-600 text-slate-100 px-3 py-2"
              >
                <option value="">Select…</option>
                {otherAlive.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.display_name}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-slate-400 text-xs mb-1">Second player</label>
              <select
                value={botTarget2}
                onChange={(e) => setBotTarget2(e.target.value)}
                className="w-full rounded-lg bg-slate-800 border border-slate-600 text-slate-100 px-3 py-2"
              >
                <option value="">Select…</option>
                {otherAlive.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.display_name}
                  </option>
                ))}
              </select>
            </div>
          </div>
          <button
            onClick={() => botTarget1 && botTarget2 && onBotSwap(botTarget1, botTarget2)}
            disabled={!botTarget1 || !botTarget2 || botUsesLeft < 1}
            className="w-full rounded-lg bg-violet-700 hover:bg-violet-600 disabled:opacity-50 text-white font-medium py-2"
          >
            Swap roles
          </button>
        </section>
      );

    case "miner":
      return (
        <section className="space-y-3">
          {usingCopiedRole && copiedRole && (
            <p className="text-amber-400 text-sm">Using your copied role: <span className="font-game-ui">{ROLE_LABELS[copiedRole]}</span>.</p>
          )}
          <h2 className="font-title text-lg font-semibold text-slate-200">The Tunnel</h2>
          <p className="text-slate-400 text-sm">Choose a player to learn if they visited someone or stayed home. Uses left: {minerUsesLeft}/2. (If you track the Bot, only one name is revealed.)</p>
          {minerUsesLeft < 1 && <p className="text-amber-400 text-sm">You have used both investigations this game.</p>}
          <select
            value={minerTarget}
            onChange={(e) => setMinerTarget(e.target.value)}
            className="w-full rounded-lg bg-slate-800 border border-slate-600 text-slate-100 px-3 py-2"
          >
            <option value="">Select a player…</option>
            {otherAlive.map((p) => (
              <option key={p.id} value={p.id}>
                {p.display_name}
              </option>
            ))}
          </select>
          <button
            onClick={() => minerTarget && onMinerTarget(minerTarget)}
            disabled={!minerTarget || minerUsesLeft < 1}
            className="w-full rounded-lg bg-amber-700 hover:bg-amber-600 disabled:opacity-50 text-white font-medium py-2"
          >
            Investigate
          </button>
        </section>
      );

    case "strongman":
      return (
        <section className="space-y-3">
          {usingCopiedRole && copiedRole && (
            <p className="text-amber-400 text-sm">Using your copied role: <span className="font-game-ui">{ROLE_LABELS[copiedRole]}</span>.</p>
          )}
          <h2 className="font-title text-lg font-semibold text-slate-200">Meatshield</h2>
          <p className="text-slate-400 text-sm">
            Protect yourself or one other player (2 uses per game). If the Ace targets them, the kill fails.
          </p>
          <p className="text-slate-500 text-xs">Uses left: {strongmanUsesLeft}/2.</p>
          {strongmanUsesLeft < 1 ? (
            <p className="text-amber-400 text-sm">You have used both protections this game.</p>
          ) : (
            <>
              <label className="flex items-center gap-2 text-slate-300">
                <input
                  type="checkbox"
                  checked={strongmanProtect}
                  onChange={(e) => setStrongmanProtect(e.target.checked)}
                  className="rounded border-slate-500"
                />
                Protect someone
              </label>
              {strongmanProtect && (
                <>
                  <select
                    value={strongmanTarget}
                    onChange={(e) => setStrongmanTarget(e.target.value)}
                    className="w-full rounded-lg bg-slate-800 border border-slate-600 text-slate-100 px-3 py-2"
                  >
                    <option value="">Select who to protect…</option>
                    <option value={currentPlayerId}>Yourself</option>
                    {otherAlive.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.display_name}
                      </option>
                    ))}
                  </select>
                  <button
                    onClick={() =>
                      strongmanTarget
                        ? onStrongmanProtect(strongmanTarget)
                        : onStrongmanProtect(null)
                    }
                    disabled={!strongmanTarget}
                    className="w-full rounded-lg bg-sky-700 hover:bg-sky-600 disabled:opacity-50 text-white font-medium py-2"
                  >
                    Confirm protection
                  </button>
                </>
              )}
              {!strongmanProtect && (
                <button
                  onClick={() => onStrongmanProtect(null)}
                  className="w-full rounded-lg bg-slate-600 hover:bg-slate-500 text-white font-medium py-2"
                >
                  Skip protection
                </button>
              )}
            </>
          )}
        </section>
      );

    case "undertaker":
      return (
        <section className="space-y-3">
          {usingCopiedRole && copiedRole && (
            <p className="text-amber-400 text-sm">Using your copied role: <span className="font-game-ui">{ROLE_LABELS[copiedRole]}</span>.</p>
          )}
          <h2 className="font-title text-lg font-semibold text-slate-200">Cleanup</h2>
          <p className="text-slate-400 text-sm">
            {hasBody
              ? "Clean a body to use that player's role for the next night. Uses left: " + undertakerUsesLeft + "/2."
              : "No body to clean this round."}
          </p>
          {undertakerUsesLeft < 1 && <p className="text-amber-400 text-sm">You have used both cleans this game.</p>}
          {hasBody && undertakerUsesLeft > 0 && (
            <button
              onClick={onUndertakerClean}
              className="w-full rounded-lg bg-slate-600 hover:bg-slate-500 text-white font-medium py-2"
            >
              Clean body
            </button>
          )}
        </section>
      );

    case "ghost":
      return (
        <section className="space-y-3">
          <h2 className="font-title text-lg font-semibold text-slate-200">Vengeance</h2>
          <p className="text-slate-400 text-sm">
            You have no night action. If you are voted out during a meeting, you immediately choose one player to take with you—both are eliminated.
          </p>
          <p className="text-slate-500 text-xs">Wait for the day phase.</p>
        </section>
      );

    case "professor":
      return (
        <section className="space-y-3">
          <h2 className="font-title text-lg font-semibold text-slate-200">The Reveal</h2>
          <p className="text-slate-400 text-sm">
            After Round 3, you automatically discover and reveal the identity of the Ace. No action needed tonight.
          </p>
          <p className="text-slate-500 text-xs">No night action.</p>
        </section>
      );

    case "thief":
      return (
        <section className="space-y-3">
          <h2 className="font-title text-lg font-semibold text-slate-200">Identity Theft</h2>
          {thiefAlreadyCopied ? (
            <>
              <p className="text-slate-400 text-sm">You have already copied a role for the rest of the game. You and the original player both have that role.</p>
              {copiedRole && (copiedRole === "ghost" || copiedRole === "professor") && (
                <p className="text-slate-500 text-sm">You are also <span className="font-game-ui">{ROLE_LABELS[copiedRole]}</span>. That role has no night action.</p>
              )}
            </>
          ) : (
            <>
              <p className="text-slate-400 text-sm">
                Choose one player to copy their role. You gain that role for the rest of the game; they keep their role too (you both have it).
              </p>
              <select
                value={thiefTarget}
                onChange={(e) => setThiefTarget(e.target.value)}
                className="w-full rounded-lg bg-slate-800 border border-slate-600 text-slate-100 px-3 py-2"
              >
                <option value="">Select a player…</option>
                {otherAlive.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.display_name}
                  </option>
                ))}
              </select>
              <button
                onClick={() => thiefTarget && onThiefSwap(thiefTarget)}
                disabled={!thiefTarget}
                className="w-full rounded-lg bg-amber-700 hover:bg-amber-600 disabled:opacity-50 text-white font-medium py-2"
              >
                Copy role
              </button>
            </>
          )}
        </section>
      );

    default:
      return (
        <p className="text-slate-500">No action available for your role.</p>
      );
  }
}
