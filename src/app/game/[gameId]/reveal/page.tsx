import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { RoleRevealClient } from "./RoleRevealClient";

interface PageProps {
  params: Promise<{ gameId: string }>;
}

export default async function GameRevealPage({ params }: PageProps) {
  const { gameId } = await params;
  const supabase = await createClient();

  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session?.user) {
    redirect(`/login?redirect=${encodeURIComponent(`/game/${gameId}/reveal`)}`);
  }

  const { data: game } = await supabase
    .from("games")
    .select("id")
    .eq("id", gameId)
    .single();

  if (!game) redirect("/");

  const { data: players } = await supabase
    .from("players")
    .select("id, role, user_id")
    .eq("game_id", gameId);

  const currentPlayer = players?.find((p) => p.user_id === session.user.id);
  if (!currentPlayer) {
    redirect(`/game/${gameId}`);
  }

  return (
    <RoleRevealClient
      role={currentPlayer.role}
      gameId={gameId}
    />
  );
}
