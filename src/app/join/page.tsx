import Link from "next/link";
import { Suspense } from "react";
import { JoinForm } from "./JoinForm";

export default function JoinPage() {
  return (
    <main className="min-h-screen flex flex-col items-center justify-center p-6 bg-paper text-ink">
      <h1 className="text-2xl font-bold text-ink uppercase tracking-wide mb-2">Join a Cast</h1>
      <p className="text-ink-muted mb-6 text-center text-sm">Enter the 4-letter room code</p>
      <Suspense fallback={<div className="text-ink-muted">Loading…</div>}>
        <JoinForm />
      </Suspense>
      <Link href="/" className="mt-6 text-ink-muted hover:text-ink text-sm">
        ← Back
      </Link>
    </main>
  );
}
