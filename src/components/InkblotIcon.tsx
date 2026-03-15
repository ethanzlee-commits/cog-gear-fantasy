"use client";

import { motion } from "framer-motion";

const spring = { type: "spring" as const, stiffness: 400, damping: 25 };

export function InkblotIcon({ className = "w-6 h-6" }: { className?: string }) {
  return (
    <motion.svg
      viewBox="0 0 24 24"
      className={className}
      initial={{ scale: 0, opacity: 0 }}
      animate={{ scale: 1, opacity: 1 }}
      transition={spring}
      aria-hidden
    >
      <ellipse cx="12" cy="12" rx="8" ry="10" fill="currentColor" />
    </motion.svg>
  );
}
