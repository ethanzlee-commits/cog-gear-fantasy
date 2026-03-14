import { getRoomByCode, getRoomPlayersByCode } from "@/app/actions/room";
import { isSupabaseConfigured } from "@/lib/supabase/configured";
import { notFound } from "next/navigation";
import { LobbyClient } from "./LobbyClient";

interface PageProps {
  params: Promise<{ code: string }>;
}

export default async function RoomPage({ params }: PageProps) {
  const { code } = await params;
  const normalized = code.toUpperCase().replace(/[^A-Z]/g, "").slice(0, 4);
  const room = await getRoomByCode(normalized);
  if (!room) notFound();

  const initialPlayers = await getRoomPlayersByCode(normalized);
  const useSupabase = isSupabaseConfigured();

  return (
    <LobbyClient
      roomCode={room.code}
      useSupabase={useSupabase}
      initialPlayers={initialPlayers}
    />
  );
}
