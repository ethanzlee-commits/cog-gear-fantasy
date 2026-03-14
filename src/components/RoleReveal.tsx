"use client";

import { useEffect } from "react";
import Image from "next/image";
import type { Role } from "@/lib/types";
import { ROLE_DISPLAY, ROLE_ABILITY, ROLE_IMAGE } from "@/lib/roleReveal";

interface RoleRevealProps {
  role: Role;
  onContinue?: () => void;
  /** Optional; call onContinue after this many ms */
  autoContinueAfterMs?: number;
}

export function RoleReveal({
  role,
  onContinue,
  autoContinueAfterMs,
}: RoleRevealProps) {
  const imageSrc = ROLE_IMAGE[role];
  const isAce = role === "ace";

  useEffect(() => {
    if (autoContinueAfterMs == null || !onContinue) return;
    const t = setTimeout(onContinue, autoContinueAfterMs);
    return () => clearTimeout(t);
  }, [autoContinueAfterMs, onContinue]);

  return (
    <div
      className={`min-h-screen flex flex-col items-center justify-center p-6 bg-paper text-ink overflow-hidden ${isAce ? "reveal-flicker" : ""}`}
    >
      {/* Character image — slides in from the right with bouncy easing */}
      <div className="reveal-slide-in relative w-full max-w-md mx-auto">
        <div className="relative w-full aspect-[3/4] max-h-[45vh] bg-paper rounded-md border-2 border-ink overflow-hidden flex items-center justify-center">
          <Image
            src={imageSrc}
            alt={ROLE_DISPLAY[role]}
            fill
            className="object-contain object-center"
            sizes="(max-width: 448px) 100vw, 448px"
            priority
          />
        </div>

        {/* Name + ability in vintage typewriter font */}
        <div className="mt-6 text-center">
          <h1 className="text-2xl sm:text-3xl font-bold uppercase tracking-wider text-ink">
            {ROLE_DISPLAY[role]}
          </h1>
          <p
            className="mt-3 text-sm sm:text-base text-ink-muted max-w-md mx-auto leading-relaxed font-typewriter"
            style={{ fontFamily: "'Special Elite', 'Courier New', monospace" }}
          >
            {ROLE_ABILITY[role]}
          </p>
        </div>

        {onContinue && (
          <div className="mt-8 flex justify-center">
            <button
              type="button"
              onClick={onContinue}
              className="rounded-md border-2 border-ink bg-ink text-paper font-bold uppercase tracking-wide py-3 px-8 hover:bg-ink-muted"
            >
              Continue
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
