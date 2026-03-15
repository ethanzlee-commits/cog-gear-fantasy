"use client";

interface ClapboardProps {
  code: string;
}

export function Clapboard({ code }: ClapboardProps) {
  return (
    <div
      className="relative flex items-center justify-center p-8 rounded-lg"
      role="img"
      aria-label={`Room code: ${code}`}
    >
      {/* Vintage clapboard: wooden board with top clip */}
      <div className="relative bg-ink-muted shadow-xl rounded-sm border-4 border-ink">
        <div className="absolute inset-0 rounded-sm overflow-hidden opacity-20">
          <div className="absolute inset-0 bg-[linear-gradient(90deg,transparent_0%,rgba(0,0,0,0.2)_50%,transparent_100%)] bg-[length:12px_100%] repeat-x" />
        </div>
        <div className="absolute -top-3 left-1/2 -translate-x-1/2 w-[110%] h-4 bg-ink rounded-b border-2 border-ink shadow-inner" />
        <div className="relative bg-[#3d3d3d] border-4 border-ink rounded-sm px-10 py-6 mt-2 mx-2 mb-2 shadow-inner">
          <div className="flex justify-center gap-2 sm:gap-3">
            {Array.from({ length: 4 }).map((_, i) => (
              <span
                key={i}
                className="font-game-ui inline-flex items-center justify-center w-12 h-14 sm:w-14 sm:h-16 text-3xl sm:text-4xl font-bold text-paper tracking-tight border-b-2 border-ink-muted"
                style={{ textShadow: "1px 1px 0 rgba(0,0,0,0.5)" }}
              >
                {code[i] ?? "—"}
              </span>
            ))}
          </div>
          <p className="font-flavor text-center text-ink-muted text-xs mt-2 uppercase tracking-widest font-medium">
            Room code
          </p>
        </div>
      </div>
    </div>
  );
}
