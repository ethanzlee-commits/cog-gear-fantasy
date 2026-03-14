"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";

export function LoginForm() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{ type: "error" | "success"; text: string } | null>(null);
  const router = useRouter();
  const searchParams = useSearchParams();
  const redirectTo = searchParams.get("redirect") ?? "/";

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setMessage(null);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setLoading(false);
    if (error) {
      setMessage({ type: "error", text: error.message });
      return;
    }
    router.push(redirectTo);
    router.refresh();
  }

  async function handleSignUp(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setMessage(null);
    const supabase = createClient();
    const { error } = await supabase.auth.signUp({ email, password, options: { emailRedirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent(redirectTo)}` } });
    setLoading(false);
    if (error) {
      setMessage({ type: "error", text: error.message });
      return;
    }
    setMessage({ type: "success", text: "Check your email for the confirmation link." });
  }

  return (
    <main className="min-h-screen flex flex-col items-center justify-center p-6 bg-paper text-ink">
      <h1 className="text-2xl font-bold text-ink uppercase tracking-wide mb-6">Project: Cog-Gear Fantasy</h1>
      <form onSubmit={handleSubmit} className="w-full max-w-sm space-y-4">
        <div>
          <label htmlFor="email" className="block text-ink-muted text-sm mb-1">Email</label>
          <input
            id="email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            className="w-full rounded-md bg-paper border-2 border-ink text-ink px-3 py-2 outline-none focus:ring-2 focus:ring-ink"
          />
        </div>
        <div>
          <label htmlFor="password" className="block text-ink-muted text-sm mb-1">Password</label>
          <input
            id="password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            className="w-full rounded-md bg-paper border-2 border-ink text-ink px-3 py-2 outline-none focus:ring-2 focus:ring-ink"
          />
        </div>
        {message && (
          <p className={message.type === "error" ? "text-ink-muted text-sm" : "text-ink text-sm"}>
            {message.text}
          </p>
        )}
        <div className="flex gap-2">
          <button
            type="submit"
            disabled={loading}
            className="flex-1 rounded-md border-2 border-ink bg-ink text-paper font-bold uppercase tracking-wide py-2 disabled:opacity-50 hover:bg-ink-muted"
          >
            Sign in
          </button>
          <button
            type="button"
            onClick={handleSignUp}
            disabled={loading}
            className="flex-1 rounded-md border-2 border-ink bg-paper text-ink font-bold uppercase py-2 disabled:opacity-50 hover:bg-ink hover:text-paper"
          >
            Sign up
          </button>
        </div>
      </form>
      <Link href="/" className="mt-4 text-ink-muted hover:text-ink text-sm">Back home</Link>
    </main>
  );
}
