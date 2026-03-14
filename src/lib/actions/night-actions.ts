"use client";

import { createClient } from "@/lib/supabase/client";
import type { MinerResult } from "@/lib/types";

const supabase = createClient();

export async function submitAceTarget(gameId: string, playerId: string, targetPlayerId: string) {
  const { error } = await supabase.rpc("night_action_ace", {
    p_game_id: gameId,
    p_player_id: playerId,
    p_target_player_id: targetPlayerId,
  });
  if (error) throw error;
}

export async function submitBotSwap(
  gameId: string,
  playerId: string,
  targetPlayerId1: string,
  targetPlayerId2: string
) {
  const { error } = await supabase.rpc("night_action_bot", {
    p_game_id: gameId,
    p_player_id: playerId,
    p_target_1: targetPlayerId1,
    p_target_2: targetPlayerId2,
  });
  if (error) throw error;
}

export async function submitMinerTarget(
  gameId: string,
  playerId: string,
  targetPlayerId: string
): Promise<MinerResult> {
  const { data, error } = await supabase.rpc("night_action_miner", {
    p_game_id: gameId,
    p_player_id: playerId,
    p_target_player_id: targetPlayerId,
  });
  if (error) throw error;
  if (data?.error) throw new Error(data.error);
  if (data?.visited === true)
    return { visited: true, target_name: data.target_name ?? "Someone" };
  return { visited: false };
}

export async function submitStrongmanProtection(
  gameId: string,
  playerId: string,
  protectPlayerId: string | null
) {
  const { error } = await supabase.rpc("night_action_strongman", {
    p_game_id: gameId,
    p_player_id: playerId,
    p_protect_player_id: protectPlayerId,
  });
  if (error) throw error;
}

export async function submitUndertakerClean(gameId: string, playerId: string) {
  const { data, error } = await supabase.rpc("night_action_undertaker", {
    p_game_id: gameId,
    p_player_id: playerId,
  });
  if (error) throw error;
  return data as { success: boolean; message: string; gained_role?: string };
}

export async function submitThiefSwap(
  gameId: string,
  playerId: string,
  targetPlayerId: string
) {
  const { error } = await supabase.rpc("night_action_thief", {
    p_game_id: gameId,
    p_player_id: playerId,
    p_target_player_id: targetPlayerId,
  });
  if (error) throw error;
}
