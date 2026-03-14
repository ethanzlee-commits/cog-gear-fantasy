"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { getDeviceId } from "@/lib/deviceId";
import { getMyRoomPlayerByCode, getRoomPlayersByCode } from "@/app/actions/room";
import { Clapboard } from "@/components/Clapboard";
import Link from "next/link";

const PRESENCE_CHANNEL_PREFIX = "room:";
const OFFLINE_POLL_MS = 3000;

interface PresencePlayer {
  device_id: string;
  nickname: string;
}

interface LobbyClientProps {
  roomCode: string;
  useSupabase: boolean;
  initialPlayers: { nickname: string; device_id: string }[];
}

function isPublicUrl(): boolean {
  if (typeof window === "undefined") return false;
  const h = window.location.hostname;
  return h !== "localhost" && h !== "127.0.0.1" && !h.startsWith("192.168.") && !h.startsWith("10.");
}

export function LobbyClient({ roomCode, useSupabase, initialPlayers }: LobbyClientProps) {
  const router = useRouter();
  const [nickname, setNickname] = useState<string | null>(null);
  const [players, setPlayers] = useState<PresencePlayer[]>(initialPlayers);
  const [shareUrl, setShareUrl] = useState("");
  useEffect(() => {
    setShareUrl(typeof window !== "undefined" ? window.location.origin : "");
  }, []);

  useEffect(() => {
    let channel: ReturnType<ReturnType<typeof createClient>["channel"]> | null = null;
    let pollInterval: ReturnType<typeof setInterval> | null = null;

    async function setup() {
      const deviceId = getDeviceId();
      const me = await getMyRoomPlayerByCode(roomCode, deviceId);
      if (!me) {
        router.push(`/join?code=${encodeURIComponent(roomCode)}`);
        return;
      }
      setNickname(me.nickname);

      if (useSupabase) {
        const supabase = createClient();
        const channelName = `${PRESENCE_CHANNEL_PREFIX}${roomCode}`;
        channel = supabase.channel(channelName, {
          config: { presence: { key: deviceId } },
        });
        channel
          .on("presence", { event: "sync" }, () => {
            const state = channel?.presenceState() ?? {};
            const list: PresencePlayer[] = [];
            Object.values(state).forEach((presences) => {
              (Array.isArray(presences) ? presences : []).forEach((p: unknown) => {
                const q = p as { nickname?: string; device_id?: string };
                if (q?.nickname != null && q?.device_id != null) {
                  list.push({ nickname: q.nickname, device_id: q.device_id });
                }
              });
            });
            setPlayers(list);
          })
          .subscribe(async (status) => {
            if (status === "SUBSCRIBED" && channel) {
              await channel.track({
                device_id: deviceId,
                nickname: me.nickname,
              });
            }
          });
      } else {
        pollInterval = setInterval(async () => {
          const list = await getRoomPlayersByCode(roomCode);
          setPlayers(list);
        }, OFFLINE_POLL_MS);
      }
    }

    setup();

    return () => {
      if (channel) {
        channel.untrack();
        createClient().removeChannel(channel);
      }
      if (pollInterval) clearInterval(pollInterval);
    };
  }, [roomCode, router, useSupabase]);

  const mainBg = {
    backgroundImage: "url(/studio-background.png)",
    backgroundSize: "cover",
    backgroundPosition: "center",
    backgroundAttachment: "fixed",
  };

  if (nickname === null && players.length === 0) {
    return (
      <main
        className="min-h-screen flex flex-col items-center justify-center p-6 text-ink relative"
        style={mainBg}
      >
        <div className="absolute inset-0 bg-paper/75 pointer-events-none" aria-hidden />
        <p className="relative z-10 text-ink-muted">Loading lobby…</p>
      </main>
    );
  }

  return (
    <main
      className="min-h-screen flex flex-col items-center p-6 text-ink relative"
      style={mainBg}
    >
      <div className="absolute inset-0 bg-paper/75 pointer-events-none" aria-hidden />
      <div className="relative z-10 flex flex-col items-center w-full">
      <h1 className="text-xl font-bold text-ink uppercase tracking-wide mb-6">Lobby</h1>

      <Clapboard code={roomCode} />

      <p className="text-ink-muted text-sm mt-6 mb-2">Share the code so others can join.</p>
      {isPublicUrl() && useSupabase ? (
        <p className="text-ink-muted text-xs max-w-sm mb-2">
          <strong>Anyone can join from anywhere.</strong> Share this link and the code: <span className="font-mono text-[0.65rem] break-all">{shareUrl}</span> — friends open it, click Join a Cast, and enter the 4-letter code.
        </p>
      ) : useSupabase ? (
        <p className="text-ink-muted text-xs max-w-sm mb-2">
          Right now only people who can open this URL can join. <strong>To let anyone in the world join:</strong> deploy this app (e.g. Vercel), add your Supabase env there, and share the deployed link + code. See README.
        </p>
      ) : (
        <p className="text-ink-muted text-xs max-w-sm mb-2">
          Others must open <strong>this same link</strong>. On the same Wi‑Fi use <span className="font-mono text-[0.65rem] break-all">http://YOUR_IP:3000</span> (not localhost). Find your IP: Mac <span className="font-mono">ipconfig getifaddr en0</span> or System Settings → Network. <strong>To let anyone join from anywhere:</strong> use Supabase + deploy the app (see README).
        </p>
      )}

      <section className="w-full max-w-sm mt-4">
        <h2 className="text-ink-muted text-sm font-medium mb-2">In the cast</h2>
        <ul className="rounded-md bg-paper border-2 border-ink p-3 space-y-1">
          {players.length === 0 ? (
            <li className="text-ink-muted text-sm">Waiting for players…</li>
          ) : (
            players.map((p) => (
              <li key={p.device_id} className="text-ink flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-ink" aria-hidden />
                {p.nickname}
              </li>
            ))
          )}
        </ul>
      </section>

      <Link
        href="/"
        className="mt-8 text-ink-muted hover:text-ink text-sm"
      >
        ← Leave lobby
      </Link>
      </div>
    </main>
  );
}
