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
        typewriter: ["'Special Elite'", "'Courier New'", "monospace"],
      },
    },
  },
  plugins: [],
};
export default config;
