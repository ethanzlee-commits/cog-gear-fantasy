import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { GameClient } from "./GameClient";
import { getDayVoteCounts } from "@/app/actions/game";
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

  if (game.phase === "lobby") {
    return (
      <main className="min-h-screen p-6 bg-paper text-ink flex flex-col items-center justify-center">
        <p className="text-ink-muted">Game has not started yet. Stay in the lobby until the host starts.</p>
        <Link href="/" className="text-ink-muted hover:text-ink mt-4">Home</Link>
      </main>
    );
  }

  let voteCounts: Record<string, number> = {};
  if (game.phase === "day" || game.game_state === "day_phase") {
    try {
      voteCounts = await getDayVoteCounts(gameId);
    } catch {
      voteCounts = {};
    }
  }

  return (
    <GameClient
      gameId={gameId}
      game={game}
      currentPlayer={currentPlayer}
      alivePlayers={alivePlayers}
      allPlayers={players}
      voteCounts={voteCounts}
    />
  );
}
