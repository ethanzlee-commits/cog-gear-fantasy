import { Suspense } from "react";
import { RoleRevealDemo } from "./RoleRevealDemo";

export default function RevealDemoPage() {
  return (
    <Suspense fallback={<div className="min-h-screen bg-paper flex items-center justify-center text-ink">Loading…</div>}>
      <RoleRevealDemo />
    </Suspense>
  );
}
