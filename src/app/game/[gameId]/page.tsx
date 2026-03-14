import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { NightPhaseClient } from "./NightPhaseClient";
import Link from "next/link";

interface PageProps {
  params: Promise<{ gameId: string }>;
}

export default async function GamePage({ params }: PageProps) {
  const { gameId } = await params;
  const supabase = await createClient();

  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session?.user) {
    redirect(`/login?redirect=${encodeURIComponent(`/game/${gameId}`)}`);
  }

  const { data: game, error: gameError } = await supabase
    .from("games")
    .select("*")
    .eq("id", gameId)
    .single();

  if (gameError || !game) {
    redirect("/");
  }

  const { data: players } = await supabase
    .from("players")
    .select("*")
    .eq("game_id", gameId)
    .order("display_name");

  if (!players?.length) {
    return (
      <main className="min-h-screen p-6 bg-paper text-ink">
        <p>No players in this game. Join from the lobby.</p>
        <Link href="/" className="text-ink-muted hover:text-ink mt-2 inline-block">Home</Link>
      </main>
    );
  }

  const currentPlayer = players.find((p) => p.user_id === session.user.id);
  if (!currentPlayer) {
    return (
      <main className="min-h-screen p-6 bg-paper text-ink">
        <p>You&apos;re not in this game.</p>
        <Link href="/" className="text-ink-muted hover:text-ink mt-2 inline-block">Home</Link>
      </main>
    );
  }

  const alivePlayers = players.filter((p) => p.is_alive);

  if (game.phase !== "night") {
    return (
      <main className="min-h-screen p-6 bg-paper text-ink">
        <p>Current phase: {game.phase}. Night phase only shows when phase is &quot;night&quot;.</p>
        <Link href="/" className="text-ink-muted hover:text-ink mt-2 inline-block">Home</Link>
      </main>
    );
  }

  return (
    <NightPhaseClient
      gameId={gameId}
      game={game}
      currentPlayer={currentPlayer}
      alivePlayers={alivePlayers}
    />
  );
}
