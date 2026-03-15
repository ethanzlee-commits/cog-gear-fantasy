"use client";

import { useEffect, useState } from "react";
import { motion } from "framer-motion";

const spring = { type: "spring" as const, stiffness: 300, damping: 25 };

type TransitionKind = "day_comes" | "night_falls";

interface PhaseTransitionOverlayProps {
  kind: TransitionKind;
  onComplete: () => void;
  durationMs?: number;
}

export function PhaseTransitionOverlay({
  kind,
  onComplete,
  durationMs = 3000,
}: PhaseTransitionOverlayProps) {
  const [mounted, setMounted] = useState(false);
  const title = kind === "day_comes" ? "Day Comes…" : "Night Falls…";
  const isNight = kind === "night_falls";

  useEffect(() => {
    const id = requestAnimationFrame(() => setMounted(true));
    return () => cancelAnimationFrame(id);
  }, []);

  return (
    <motion.div
      className="fixed inset-0 z-[100] flex items-center justify-center overflow-hidden"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.2 }}
    >
      {/* Curtain: two panels closing from sides — only animate after mount so it runs in browser */}
      <motion.div className="absolute inset-0 z-10 flex">
        <motion.div
          className="absolute left-0 top-0 h-full w-1/2 bg-ink"
          initial={{ x: mounted ? "-100%" : 0 }}
          animate={{ x: 0 }}
          transition={{ ...spring, delay: 0.05 }}
        />
        <motion.div
          className="absolute right-0 top-0 h-full w-1/2 bg-ink"
          initial={{ x: mounted ? "100%" : 0 }}
          animate={{ x: 0 }}
          transition={{ ...spring, delay: 0.05 }}
        />
      </motion.div>

      {/* Background: star pattern for night, warm for day */}
      <motion.div
        className={`absolute inset-0 z-0 ${isNight ? "bg-slate-950" : "bg-amber-950/95"}`}
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: 0.4 }}
      />
      {isNight && (
        <div
          className="absolute inset-0 z-0 opacity-40"
          style={{
            backgroundImage: `radial-gradient(circle at 20% 30%, white 1px, transparent 1px),
                             radial-gradient(circle at 60% 70%, white 1px, transparent 1px),
                             radial-gradient(circle at 80% 20%, white 1.5px, transparent 1.5px),
                             radial-gradient(circle at 40% 80%, white 1px, transparent 1px)`,
            backgroundSize: "60px 60px, 80px 80px, 100px 100px, 70px 70px",
          }}
        />
      )}

      {/* Title card — bouncy */}
      <motion.div
        className="relative z-20 text-center px-6"
        initial={{ scale: mounted ? 0.5 : 1, opacity: mounted ? 0 : 1 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ ...spring, delay: 0.35 }}
      >
        <motion.h1
          className="font-title text-4xl sm:text-5xl md:text-6xl font-bold text-paper uppercase tracking-wider"
          animate={{ scale: [1, 1.02, 1] }}
          transition={{ duration: 1.2, repeat: Infinity, repeatDelay: 0.3 }}
        >
          {title}
        </motion.h1>
      </motion.div>

      <AutoComplete ms={durationMs} onComplete={onComplete} />
    </motion.div>
  );
}

function AutoComplete({ ms, onComplete }: { ms: number; onComplete: () => void }) {
  useEffect(() => {
    const id = setTimeout(onComplete, ms);
    return () => clearTimeout(id);
  }, [ms, onComplete]);
  return null;
}
