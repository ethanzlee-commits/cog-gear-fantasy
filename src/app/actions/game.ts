"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import type { GameStateType } from "@/lib/types";

export async function resolveNightToDay(gameId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("resolve_night_to_day", { p_game_id: gameId });
  if (error) throw new Error(error.message);
  revalidatePath(`/game/${gameId}`);
}

export async function setGameState(gameId: string, state: GameStateType) {
  const supabase = await createClient();
  const phase = state === "day_phase" ? "day" : "night";
  const { error } = await supabase
    .from("games")
    .update({ game_state: state, phase, updated_at: new Date().toISOString() })
    .eq("id", gameId);
  if (error) throw new Error(error.message);
  revalidatePath(`/game/${gameId}`);
}

export async function castDayVote(gameId: string, voterPlayerId: string, targetPlayerId: string) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("cast_day_vote", {
    p_game_id: gameId,
    p_voter_player_id: voterPlayerId,
    p_target_player_id: targetPlayerId,
  });
  if (error) throw new Error(error.message);
  const result = data as { ok: boolean; error?: string; voted_out?: boolean };
  if (!result.ok && result.error) throw new Error(result.error);
  revalidatePath(`/game/${gameId}`);
  return result;
}

export async function getDayVoteCounts(gameId: string): Promise<Record<string, number>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_day_vote_counts", { p_game_id: gameId });
  if (error) throw new Error(error.message);
  const rows = (data ?? []) as { target_player_id: string; vote_count: number }[];
  const out: Record<string, number> = {};
  for (const r of rows) out[r.target_player_id] = Number(r.vote_count);
  return out;
}

export async function resetDayVotes(gameId: string) {
  const supabase = await createClient();
  const { data: game } = await supabase.from("games").select("round_number").eq("id", gameId).single();
  if (!game) throw new Error("Game not found");
  const { error } = await supabase
    .from("day_votes")
    .delete()
    .eq("game_id", gameId)
    .eq("round_number", game.round_number);
  if (error) throw new Error(error.message);
  revalidatePath(`/game/${gameId}`);
}

export async function completeTransitionToDay(gameId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("complete_transition_to_day", { p_game_id: gameId });
  if (error) throw new Error(error.message);
  revalidatePath(`/game/${gameId}`);
}

export async function startTransitionToNight(gameId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("start_transition_to_night", { p_game_id: gameId });
  if (error) throw new Error(error.message);
  revalidatePath(`/game/${gameId}`);
}

export async function completeTransitionToNight(gameId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("complete_transition_to_night", { p_game_id: gameId });
  if (error) throw new Error(error.message);
  revalidatePath(`/game/${gameId}`);
}

export async function finishInkedAndAdvance(gameId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("finish_inked_and_advance", { p_game_id: gameId });
  if (error) throw new Error(error.message);
  revalidatePath(`/game/${gameId}`);
}

export async function killPlayerForDev(gameId: string, playerId: string) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("players")
    .update({ is_alive: false, updated_at: new Date().toISOString() })
    .eq("id", playerId)
    .eq("game_id", gameId);
  if (error) throw new Error(error.message);
  revalidatePath(`/game/${gameId}`);
}
