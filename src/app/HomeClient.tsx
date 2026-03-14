"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { getDeviceId } from "@/lib/deviceId";
import { createRoom } from "@/app/actions/room";

export function HomeClient() {
  const router = useRouter();
  const [hosting, setHosting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleStartProduction() {
    setError(null);
    setHosting(true);
    try {
      const deviceId = getDeviceId();
      if (!deviceId) {
        setError("Could not get device ID. Enable cookies or storage and try again.");
        return;
      }
      const result = await createRoom(deviceId);
      const code = result?.code;
      if (!code || typeof code !== "string") {
        setError("Room was created but no code returned. Try again.");
        return;
      }
      router.push(`/room/${code}`);
    } catch (e) {
      const message = e instanceof Error ? e.message : "Failed to create room.";
      setError(message);
    } finally {
      setHosting(false);
    }
  }

  return (
    <div className="flex flex-col items-center gap-4 w-full max-w-xs">
      <button
        onClick={handleStartProduction}
        disabled={hosting}
        className="w-full rounded-md border-2 border-ink bg-ink text-paper font-bold uppercase tracking-wide py-3 px-6 disabled:opacity-50 hover:bg-ink-muted hover:border-ink-muted"
      >
        {hosting ? "Starting…" : "Start a New Production"}
      </button>
      <a
        href="/join"
        className="w-full rounded-md border-2 border-ink bg-paper text-ink font-bold uppercase tracking-wide py-3 px-6 text-center hover:bg-ink hover:text-paper"
      >
        Join a Cast
      </a>
      {error && (
        <div className="rounded-md border-2 border-ink bg-paper px-3 py-2 w-full">
          <p className="text-ink text-sm font-medium text-center">{error}</p>
        </div>
      )}
    </div>
  );
}
