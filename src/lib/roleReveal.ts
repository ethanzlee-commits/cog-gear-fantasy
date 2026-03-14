import type { Role } from "./types";

export const ROLE_DISPLAY: Record<Role, string> = {
  ace: "The Ace",
  bot: "The Bot",
  miner: "The Miner",
  strongman: "The Strongman",
  undertaker: "The Undertaker",
  ghost: "The Ghost",
  professor: "The Professor",
  thief: "The Thief",
};

/** Ability description for the Reveal screen (vintage typewriter copy) */
export const ROLE_ABILITY: Record<Role, string> = {
  ace: "The Hit — You must stay alive to win. Eliminate one player per round. Your choice is hidden until day.",
  bot: "The Switcheroo — Swap the roles of any two players (excluding yourself) at any time. Chaos is your craft.",
  miner: "The Tunnel — Track one player per night. Learn whether they visited someone or stayed home.",
  strongman: "Meatshield — Invincible for the first two rounds. Stand in front of a player to protect them; if attacked, you lose your invincibility.",
  undertaker: "Cleanup — You know exactly who has been eliminated. Clean up a body to gain that player's ability for one round.",
  ghost: "Vengeance — If voted out during a meeting, you immediately take one player of your choice with you.",
  professor: "The Reveal — After Round 3, you automatically discover and reveal the identity of the Ace.",
  thief: "Identity Theft — Choose to switch your own role with another player's. Change teams or powers in an instant.",
};

/** Per-role character image for the Reveal screen */
export const ROLE_IMAGE: Record<Role, string> = {
  ace: "/characters/ace.png",
  bot: "/characters/bot.png",
  miner: "/characters/miner.png",
  strongman: "/characters/strongman.png",
  undertaker: "/characters/undertaker.png",
  ghost: "/characters/ghost.png",
  professor: "/characters/professor.png",
  thief: "/characters/thief.png",
};
