"use client";

import { useState, useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { getDeviceId } from "@/lib/deviceId";
import { joinRoom } from "@/app/actions/room";
import { playTypewriterKey } from "@/lib/typewriterSound";

export function JoinForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [code, setCode] = useState("");
  const [nickname, setNickname] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const q = searchParams.get("code");
    if (q) setCode(q.toUpperCase().replace(/[^A-Z]/g, "").slice(0, 4));
  }, [searchParams]);

  function handleCodeChange(e: React.ChangeEvent<HTMLInputElement>) {
    const raw = e.target.value.toUpperCase().replace(/[^A-Z]/g, "").slice(0, 4);
    setCode(raw);
  }

  function handleCodeKeyDown() {
    playTypewriterKey();
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (code.length !== 4) {
      setError("Enter a 4-letter code.");
      return;
    }
    setError(null);
    setLoading(true);
    try {
      const deviceId = getDeviceId();
      const { code: finalCode } = await joinRoom(code, deviceId, nickname.trim() || "Player");
      router.push(`/room/${finalCode}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to join.");
      setLoading(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="w-full max-w-sm space-y-4">
      <div>
        <label htmlFor="code" className="block text-ink-muted text-sm mb-2 text-center">
          Room code
        </label>
        <input
          id="code"
          type="text"
          inputMode="text"
          maxLength={4}
          value={code}
          onChange={handleCodeChange}
          onKeyDown={handleCodeKeyDown}
          placeholder="····"
          className="w-full text-center text-3xl tracking-[0.6em] font-mono uppercase rounded-md bg-paper border-2 border-ink text-ink px-4 py-3 focus:ring-2 focus:ring-ink focus:border-ink outline-none"
          autoComplete="off"
          autoFocus
        />
      </div>
      <div>
        <label htmlFor="nickname" className="block text-ink-muted text-sm mb-1">
          Your nickname
        </label>
        <input
          id="nickname"
          type="text"
          value={nickname}
          onChange={(e) => setNickname(e.target.value)}
          placeholder="Player"
          maxLength={24}
          className="w-full rounded-md bg-paper border-2 border-ink text-ink px-3 py-2 focus:border-ink outline-none"
        />
      </div>
      {error && (
        <p className="text-ink text-sm text-center px-3 py-2 rounded-md border-2 border-ink bg-paper" role="alert">
          {error}
        </p>
      )}
      <button
        type="submit"
        disabled={loading || code.length !== 4}
        className="w-full rounded-md border-2 border-ink bg-ink text-paper font-bold uppercase tracking-wide py-2 disabled:opacity-50 hover:bg-ink-muted"
      >
        {loading ? "Joining…" : "Join"}
      </button>
    </form>
  );
}
