"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";

export async function resolveNightToDay(gameId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("resolve_night_to_day", { p_game_id: gameId });
  if (error) throw new Error(error.message);
  revalidatePath(`/game/${gameId}`);
}
