"use client";

import { useRouter } from "next/navigation";
import { RoleReveal } from "@/components/RoleReveal";
import type { Role } from "@/lib/types";

interface RoleRevealClientProps {
  role: Role;
  gameId: string;
}

export function RoleRevealClient({ role, gameId }: RoleRevealClientProps) {
  const router = useRouter();

  function handleContinue() {
    router.push(`/game/${gameId}`);
  }

  return (
    <RoleReveal
      role={role}
      onContinue={handleContinue}
    />
  );
}
