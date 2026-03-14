/**
 * Project: Cog-Gear Fantasy — Types
 */

export type GamePhase = "lobby" | "night" | "day";

export type Role =
  | "ace"        // Bad Guy — The Hit: eliminate one per round
  | "bot"        // Chaos — The Switcheroo: swap two other players' roles
  | "miner"      // Good Guy — The Tunnel: track who one player visited
  | "strongman"  // Good Guy — Meatshield: invincible first 2 rounds; protect one (lose invincibility if attacked)
  | "undertaker" // Support — Cleanup: clean a body to gain that role for one round
  | "ghost"      // Good Guy — Vengeance: if voted out, take one player with you
  | "professor"  // Good Guy — The Reveal: after Round 3, automatically discover the Ace
  | "thief";     // Neutral/Chaos — Identity Theft: swap your role with another player's

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
  created_at: string;
  updated_at: string;
}

export interface Game {
  id: string;
  phase: GamePhase;
  round_number: number;
  /** Player id of the body on the ground (last elimination), if any */
  body_player_id: string | null;
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
  target_player_id: string; // swap own role with this player's
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
