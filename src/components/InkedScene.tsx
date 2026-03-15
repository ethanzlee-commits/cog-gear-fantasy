"use client";

import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { finishInkedAndAdvance } from "@/app/actions/game";
import { ROLE_IMAGE } from "@/lib/roleReveal";
import type { Player } from "@/lib/types";

const INK_SPLATTER_DURATION = 4.5;

/** Irregular ink splatter: overlapping circles scaled from center to read as one blob. */
function InkSplatter({
  mounted,
  onAnimationComplete,
}: {
  mounted: boolean;
  onAnimationComplete: () => void;
}) {
  return (
    <motion.div
      className="absolute inset-0 flex items-center justify-center pointer-events-none"
      style={{ originX: "50%", originY: "50%" }}
    >
      <motion.div
        className="absolute flex items-center justify-center"
        style={{
          width: "min(200vmax, 200vh)",
          height: "min(200vmax, 200vh)",
          originX: "0.5",
          originY: "0.5",
        }}
        initial={{ scale: 0 }}
        animate={mounted ? { scale: 2.2 } : { scale: 0 }}
        transition={{
          duration: INK_SPLATTER_DURATION,
          ease: [0.22, 0.61, 0.36, 1],
        }}
        onAnimationComplete={onAnimationComplete}
      >
        <svg
          viewBox="0 0 100 100"
          className="w-full h-full text-ink"
          preserveAspectRatio="xMidYMid slice"
        >
          {/* Main blob */}
          <circle cx="50" cy="50" r="46" fill="currentColor" />
          {/* Off-center lobes for splatter effect */}
          <circle cx="62" cy="36" r="28" fill="currentColor" />
          <circle cx="36" cy="64" r="32" fill="currentColor" />
          <circle cx="58" cy="58" r="22" fill="currentColor" />
          <circle cx="38" cy="38" r="18" fill="currentColor" />
          <circle cx="70" cy="52" r="20" fill="currentColor" />
        </svg>
      </motion.div>
    </motion.div>
  );
}

interface InkedSceneProps {
  gameId: string;
  votedOutPlayer: Player;
  onComplete: () => void;
  /** When true, skip server action and router refresh (e.g. dev animation preview). */
  devPreview?: boolean;
}

export function InkedScene({ gameId, votedOutPlayer, onComplete, devPreview }: InkedSceneProps) {
  const router = useRouter();
  const [phase, setPhase] = useState<"ink" | "black">("ink");
  const [mounted, setMounted] = useState(false);
  const characterSrc = ROLE_IMAGE[votedOutPlayer.role];

  useEffect(() => {
    const id = requestAnimationFrame(() => setMounted(true));
    return () => cancelAnimationFrame(id);
  }, []);

  useEffect(() => {
    if (phase !== "black") return;
    const t = setTimeout(async () => {
      if (!devPreview) {
        await finishInkedAndAdvance(gameId);
        router.refresh();
      }
      onComplete();
    }, 1600);
    return () => clearTimeout(t);
  }, [phase, gameId, onComplete, router, devPreview]);

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center overflow-hidden bg-ink">
      {/* Character art — centered, then covered by ink */}
      <motion.div
        className="absolute inset-0 flex items-center justify-center"
        initial={{ scale: 1 }}
        animate={{ scale: phase === "ink" ? 1 : 0.95 }}
        transition={{ duration: 3 }}
      >
        <div className="relative w-full max-w-md aspect-[3/4] max-h-[85vh]">
          <Image
            src={characterSrc}
            alt={votedOutPlayer.display_name}
            fill
            className="object-contain"
            sizes="(max-width: 448px) 100vw, 448px"
            priority
          />
        </div>
      </motion.div>

      {/* Expanding black ink splatter — irregular blob, scales from center until full screen */}
      <InkSplatter
        mounted={mounted}
        onAnimationComplete={() => setPhase("black")}
      />

      {/* Optional: name label */}
      <motion.p
        className="font-flavor absolute bottom-8 left-0 right-0 text-center text-paper/80 text-sm z-10"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.5 }}
      >
        {votedOutPlayer.display_name}
      </motion.p>
    </div>
  );
}
