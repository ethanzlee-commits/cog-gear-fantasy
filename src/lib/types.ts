/**
 * Project: Cog-Gear Fantasy — Types
 */

export type GamePhase = "lobby" | "night" | "day";

/** UI cycle: night_phase (night actions), day_phase (voting), animation_lock (transition or inked overlay) */
export type GameStateType = "night_phase" | "day_phase" | "animation_lock";

export type Role =
  | "ace"        // Bad Guy — The Hit: eliminate one per round
  | "bot"        // Chaos — The Switcheroo: swap two other players' roles
  | "miner"      // Good Guy — The Tunnel: track who one player visited
  | "strongman"  // Good Guy — Meatshield: invincible first 2 rounds; protect one (lose invincibility if attacked)
  | "undertaker" // Support — Cleanup: clean a body to gain that role for one round
  | "ghost"      // Good Guy — Vengeance: if voted out, take one player with you
  | "professor"  // Good Guy — The Reveal: after Round 3, automatically discover the Ace
  | "thief";     // Neutral/Chaos — Identity Theft: copy one player's role for rest of game (they keep theirs)

export interface Player {
  id: string;
  game_id: string;
  user_id: string;
  display_name: string;
  role: Role;
  is_alive: boolean;
  is_invincible: boolean; // Strongman protection; consumed when blocking Ace
  /** Deceased player id whose role Undertaker cleaned (temporary for next night) */
  cleaned_role_from_player_id: string | null;
  /** For Miner: did this player visit anyone last night (target player id or null) */
  last_night_visited_player_id: string | null;
  /** Bot: swaps left (2 total). Miner: uses left (2 total). Strongman: uses left (2 total). Undertaker: uses left (2 total). */
  bot_uses_remaining?: number | null;
  miner_uses_remaining?: number | null;
  strongman_uses_remaining?: number | null;
  undertaker_uses_remaining?: number | null;
  /** Thief: player id whose role was copied (permanent); target keeps their role */
  copied_role_from_player_id?: string | null;
  /** Thief: role they copied (set at copy time) so they can use that role's night action */
  copied_role?: Role | null;
  created_at: string;
  updated_at: string;
}

export interface Game {
  id: string;
  phase: GamePhase;
  round_number: number;
  /** NIGHT_PHASE | DAY_PHASE | ANIMATION_LOCK for day/night cycle and overlays */
  game_state?: GameStateType | null;
  /** Player id of the body on the ground (last elimination), if any */
  body_player_id: string | null;
  /** Set when a player is voted out (4 votes); used for Inked scene then cleared */
  voted_out_player_id?: string | null;
  /** When animation_lock: 'day' = Day Comes overlay, 'night' = Night Falls overlay */
  transition_to?: "day" | "night" | null;
  /** After Round 3, if Professor is alive: Ace's player id (revealed to Professor). Set by migration 004. */
  revealed_ace_player_id?: string | null;
  created_at: string;
  updated_at: string;
}

/** Night action payloads (stored in night_actions table until resolution) */
export interface NightActionAce {
  kind: "ace";
  target_player_id: string;
}

export interface NightActionBot {
  kind: "bot";
  target_player_id_1: string;
  target_player_id_2: string;
}

export interface NightActionMiner {
  kind: "miner";
  target_player_id: string;
}

export interface NightActionStrongman {
  kind: "strongman";
  protect_player_id: string | null; // null = not protecting
}

export interface NightActionUndertaker {
  kind: "undertaker";
  clean_body: boolean; // true = clean current body
}

export interface NightActionThief {
  kind: "thief";
  target_player_id: string; // copy this player's role for rest of game (one-time)
}

export type NightAction =
  | NightActionAce
  | NightActionBot
  | NightActionMiner
  | NightActionStrongman
  | NightActionUndertaker
  | NightActionThief;

export interface NightActionRow {
  id: string;
  game_id: string;
  round_number: number;
  player_id: string;
  action: NightAction;
  created_at: string;
}

/** Miner result for UI */
export type MinerResult =
  | { visited: true; target_name: string }
  | { visited: false };
