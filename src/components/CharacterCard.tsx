"use client";

import Image from "next/image";
import type { Role } from "@/lib/types";

const ROLE_DISPLAY: Record<Role, string> = {
  ace: "The Ace",
  bot: "The Bot",
  miner: "The Miner",
  strongman: "The Strongman",
  undertaker: "The Undertaker",
  ghost: "The Ghost",
  professor: "The Professor",
  thief: "The Thief",
};

/** Per-role character image (vintage rubber hose style) */
const ROLE_IMAGE: Record<Role, string> = {
  ace: "/characters/ace.png",
  bot: "/characters/bot.png",
  miner: "/characters/miner.png",
  strongman: "/characters/strongman.png",
  undertaker: "/characters/undertaker.png",
  ghost: "/characters/ghost.png",
  professor: "/characters/professor.png",
  thief: "/characters/thief.png",
};

interface CharacterCardProps {
  role: Role;
  /** Optional subtitle (e.g. alliance or ability name) */
  subtitle?: string;
  className?: string;
  /** Show full image (no crop); kept for API compatibility, ignored with single-image assets */
  fullSheet?: boolean;
}

export function CharacterCard({
  role,
  subtitle,
  className = "",
}: CharacterCardProps) {
  const src = ROLE_IMAGE[role];

  return (
    <article
      className={`
        relative overflow-hidden rounded-md border-2 border-ink
        w-full max-w-[200px]
        ${className}
      `}
      style={{
        boxShadow: "2px 2px 0 var(--border-vintage), 4px 4px 0 rgba(0,0,0,0.08)",
      }}
    >
      <div className="relative w-full bg-transparent overflow-hidden rounded-t-[calc(0.375rem-2px)]">
        <Image
          src={src}
          alt={ROLE_DISPLAY[role]}
          width={200}
          height={267}
          className="block w-full h-auto object-cover object-center"
          sizes="(max-width: 240px) 100vw, 200px"
        />
      </div>
      <div className="border-t-2 border-ink bg-paper px-3 py-1">
        <p className="font-bold uppercase tracking-wide text-ink text-sm">
          {ROLE_DISPLAY[role]}
        </p>
        {subtitle && (
          <p className="text-xs text-ink-muted mt-0.5">{subtitle}</p>
        )}
      </div>
    </article>
  );
}
