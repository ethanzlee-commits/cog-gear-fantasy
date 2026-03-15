import type { Game, Player } from "@/lib/types";

const NOW = new Date().toISOString();

export const DEV_GAME: Game = {
  id: "dev-game-id",
  phase: "night",
  round_number: 2,
  body_player_id: "dev-player-6", // dead player = body for Undertaker
  created_at: NOW,
  updated_at: NOW,
};

const base = (id: string, name: string, role: Player["role"], isAlive = true): Player => ({
  id,
  game_id: DEV_GAME.id,
  user_id: `user-${id}`,
  display_name: name,
  role,
  is_alive: isAlive,
  is_invincible: role === "strongman",
  cleaned_role_from_player_id: null,
  last_night_visited_player_id: null,
  bot_uses_remaining: 2,
  miner_uses_remaining: 2,
  strongman_uses_remaining: 2,
  undertaker_uses_remaining: 2,
  copied_role_from_player_id: null,
  copied_role: null,
  created_at: NOW,
  updated_at: NOW,
});

/** 8 alive (one per role) + 1 dead (body) so Undertaker can "clean" */
export const DEV_PLAYERS: Player[] = [
  base("dev-player-1", "Alex", "ace"),
  base("dev-player-2", "Sam", "miner"),
  base("dev-player-3", "Jordan", "strongman"),
  base("dev-player-4", "Riley", "ghost"),
  base("dev-player-5", "Casey", "professor"),
  base("dev-player-6", "Violet", "undertaker", false), // dead = body on ground
  base("dev-player-7", "Morgan", "bot"),
  base("dev-player-8", "Quinn", "thief"),
  base("dev-player-9", "Drew", "undertaker"), // alive Undertaker to preview role
];

export const ROLES_ORDER: Player["role"][] = [
  "ace", "bot", "miner", "strongman", "undertaker", "ghost", "professor", "thief",
];
