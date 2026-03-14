# Project: Cog-Gear Fantasy

Social deduction game built with **Next.js** and **Supabase**. This repo includes the **Night Phase** flow: role-specific actions and Supabase-backed resolution.

## Setup

1. **Install dependencies**
   ```bash
   cd cog-gear-fantasy && npm install
   ```

2. **Supabase**
   - Create a project at [supabase.com](https://supabase.com).
   - **Run migrations** (pick one):
     - **Option A — SQL Editor:** In the Supabase Dashboard → SQL Editor, run in order:
       - `supabase/migrations/001_schema.sql`
       - `supabase/migrations/002_night_phase_functions.sql`
       - `supabase/migrations/003_rooms_lobby.sql`
       - `supabase/migrations/004_ghost_professor_thief.sql`
     - **Option B — CLI:** `npx supabase link` (then add project ref), then `npm run db:migrate`.
   - **Env:** `.env.local` is present with placeholders. Replace with your project values (Dashboard → Settings → API):
     - `NEXT_PUBLIC_SUPABASE_URL`
     - `NEXT_PUBLIC_SUPABASE_ANON_KEY`

3. **Run the app**
   ```bash
   npm run dev
   ```
   Open [http://localhost:3000](http://localhost:3000).

   **Run without Supabase:** If you don't set `NEXT_PUBLIC_SUPABASE_URL` (or leave `.env.local` missing), the app uses an **in-memory backend** for the lobby. You can "Start a New Production" and "Join a Cast" (e.g. in another tab with the same code); the player list in the lobby updates every few seconds. Data is lost when the dev server restarts. Game phase (night/day) and auth still require Supabase.

4. **Let anyone join from anywhere (different Wi‑Fi / different cities)**
   - Use **Supabase** (steps above) so rooms are stored in the cloud.
   - **Deploy the app** so there’s one public URL everyone can open:
     - **Vercel (recommended):** Push this repo to GitHub, then [vercel.com](https://vercel.com) → Import project → add env vars `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` → Deploy. Share the deployed URL (e.g. `https://your-app.vercel.app`) and the 4-letter room code; anyone can open that link, click Join a Cast, and join.
     - **Other hosts:** Build with `npm run build`, run `npm start` (or use the host’s Node server), and set the same env vars. Put the app behind HTTPS so it’s reachable from anywhere.
   - With Supabase + a public URL, the host and players can be on different networks and still join the same lobby.

5. **Room Code lobby (no accounts)**
   - **Home:** “Start a New Production” creates a room with a random 4-letter code and adds you as host. “Join a Cast” opens a form to enter the code and nickname.
   - **Identity:** A unique `deviceId` is stored in `localStorage`; no sign-up required for the lobby.
   - **Real-time:** Supabase presence on channel `room:{code}` shows who is in the lobby as they join.
   - **Visual:** Room code is shown on a vintage movie-clapboard style card. Typing the code on the Join form plays a typewriter-style sound.

6. **Auth** (for game phase)
   - In Supabase Dashboard → Authentication → URL Configuration, add to Redirect URLs: `http://localhost:3000/auth/callback` (and your production URL when you deploy). Enable Email provider if you use email/password.
   - Sign up or sign in at [/login](/login). Unauthenticated users visiting a game are redirected to login, then back to the game.
   - The **current player** is the one whose `user_id` matches the signed-in user.

7. **Night phase**
   - Use `/game/[gameId]` with a real `gameId` and ensure the game has `phase = 'night'` to see the Night Phase UI.
   - Use the **End night** button (fixed at bottom) to call `resolve_night_to_day` and switch to Day.

## Night Phase Overview

When the game phase is **Night**, the **NightPhase** component is shown:

- **Lights Out** film-grain overlay and dark layout.
- **Role-specific menus:**
  - **Ace** — Choose one player to eliminate (hidden until Day).
  - **Bot** — Choose two other players; their roles are swapped in the DB immediately. Cannot select self.
  - **Miner** — Choose one player; result is *"This player visited [Name]"* or *"This player stayed home."*
  - **Strongman** — Toggle “Protect a player” and choose a target. If the Ace targets that player, the kill fails and the Strongman’s `is_invincible` is set to `false`.
  - **Undertaker** — If there is a body from a previous round, “Clean” it to temporarily gain that player’s role for the next Night.

  - **Ghost** (Good Guy) — Vengeance: if voted out during a meeting, choose one player to take with you.
  - **Professor** (Good Guy) — The Reveal: after Round 3 the Ace's identity is revealed to you.
  - **Thief** (Neutral/Chaos) — Identity Theft: swap your role with another player's.

## Supabase

- **Tables:** `games`, `players`, `night_actions`; `rooms`, `room_players` (lobby); `day_actions` (Ghost vengeance).
- **RPCs:** `night_action_ace`, `night_action_bot`, `night_action_miner`, `night_action_strongman`, `night_action_undertaker`, `night_action_thief`, and `resolve_night_to_day(game_id)` to apply night results and switch to Day. **Day:** `day_actions` table stores Ghost vengeance (when voted out).

To run a full night cycle, call `resolve_night_to_day` (e.g. from a “End night” button or a backend cron) after all night actions are in.
