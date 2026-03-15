import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        paper: "#f4f1ea",
        ink: "#1a1a1a",
        "ink-muted": "#4a4a4a",
      },
      fontFamily: {
        /* Main titles — 1930s movie poster (Limelight) */
        title: ["'Limelight'", "cursive"],
        /* Buttons / action — loud, hand-drawn (Bangers) */
        action: ["'Bangers'", "cursive"],
        /* Dialogue / chat — round, friendly (Ranchers) */
        dialogue: ["'Ranchers'", "cursive"],
        /* Game UI / role names — period display (Bebas Neue; use Market Deco if you add the font file) */
        "game-ui": ["'Bebas Neue'", "sans-serif"],
        /* Flavor text — 1930s typewriter (Special Elite; use Bygonest if you add the font file) */
        flavor: ["'Special Elite'", "'Courier New'", "monospace"],
      },
    },
  },
  plugins: [],
};
export default config;
