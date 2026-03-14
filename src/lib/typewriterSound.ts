let ctx: AudioContext | null = null;

function getContext(): AudioContext | null {
  if (typeof window === "undefined") return null;
  if (!ctx) ctx = new (window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)();
  return ctx;
}

export function playTypewriterKey(): void {
  const context = getContext();
  if (!context) return;

  const now = context.currentTime;
  const osc = context.createOscillator();
  const gain = context.createGain();

  osc.connect(gain);
  gain.connect(context.destination);

  osc.type = "sine";
  osc.frequency.setValueAtTime(880, now);
  osc.frequency.exponentialRampToValueAtTime(660, now + 0.03);
  osc.start(now);
  osc.stop(now + 0.04);

  gain.gain.setValueAtTime(0.12, now);
  gain.gain.exponentialRampToValueAtTime(0.001, now + 0.04);

  setTimeout(() => {
    osc.disconnect();
    gain.disconnect();
  }, 50);
}
