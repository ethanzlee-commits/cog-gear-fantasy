"use client";

import { useSearchParams, useRouter } from "next/navigation";
import Link from "next/link";
import { RoleReveal } from "@/components/RoleReveal";
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

export function RoleRevealDemo() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const roleParam = searchParams.get("role")?.toLowerCase();
  const role: Role =
    roleParam && ROLES.includes(roleParam as Role) ? (roleParam as Role) : "professor";

  return (
    <>
      <RoleReveal
        role={role}
        onContinue={() => router.push("/")}
      />
      <div className="fixed bottom-4 left-4 right-4 flex flex-wrap justify-center gap-2 z-10">
        <p className="w-full text-center text-ink-muted text-xs mb-1">Try a role:</p>
        {ROLES.map((r) => (
          <Link
            key={r}
            href={`/reveal?role=${r}`}
            className="rounded-md border border-ink px-2 py-1 text-xs uppercase hover:bg-ink hover:text-paper"
          >
            {r}
          </Link>
        ))}
      </div>
    </>
  );
}
