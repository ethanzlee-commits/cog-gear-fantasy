import Link from "next/link";
import { HomeClient } from "./HomeClient";
import { CharacterCard } from "@/components/CharacterCard";
import type { Role } from "@/lib/types";

const ROLES: Role[] = [
  "ace",
  "bot",
  "miner",
  "strongman",
  "undertaker",
  "ghost",
  "professor",
  "thief",
];

export default function HomePage() {
  return (
    <main
      className="min-h-screen flex flex-col items-center p-6 text-ink relative"
      style={{
        backgroundImage: "url(/studio-background.png)",
        backgroundSize: "cover",
        backgroundPosition: "center",
        backgroundAttachment: "fixed",
      }}
    >
      {/* Overlay so content stays readable */}
      <div
        className="absolute inset-0 bg-paper/75 pointer-events-none"
        aria-hidden
      />
      <div className="relative z-10 flex flex-col items-center w-full">
        <h1 className="font-title text-3xl font-bold text-ink mb-1 text-center uppercase tracking-wide mt-8">
          Project: Cog-Gear Fantasy
        </h1>
        <p className="text-ink-muted mb-8 text-center text-sm">Social deduction · Rubber hose</p>

        <HomeClient />

        <section className="w-full max-w-4xl mt-16">
          <h2 className="font-title text-xl font-bold uppercase tracking-wide text-ink mb-4 text-center border-b-2 border-ink pb-2">
            The cast
          </h2>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 justify-items-center">
            {ROLES.map((role) => (
              <CharacterCard key={role} role={role} />
            ))}
          </div>
        </section>

        <div className="mt-10 flex flex-col items-center gap-2">
          <Link
            href="/join"
            className="text-ink-muted hover:text-ink text-sm underline underline-offset-2"
          >
            Join a cast →
          </Link>
        <Link
          href="/reveal?role=ace"
          className="text-ink-muted hover:text-ink text-xs underline underline-offset-2"
        >
          Preview role reveal (Ace)
        </Link>
        <Link
          href="/dev"
          className="text-ink-muted hover:text-ink text-xs underline underline-offset-2"
        >
          Dev: preview night phase (no players needed)
        </Link>
        </div>
      </div>
    </main>
  );
}
