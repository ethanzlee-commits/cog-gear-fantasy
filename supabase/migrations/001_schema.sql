-- Project: Cog-Gear Fantasy — Schema
-- Run this in Supabase SQL Editor or via supabase db push

-- Game phase: 'lobby' | 'night' | 'day'
CREATE TYPE game_phase AS ENUM ('lobby', 'night', 'day');

CREATE TYPE role_type AS ENUM ('ace', 'bot', 'miner', 'strongman', 'undertaker');

-- Games (body_player_id added after players exist)
CREATE TABLE games (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phase game_phase NOT NULL DEFAULT 'lobby',
  round_number INT NOT NULL DEFAULT 0,
  body_player_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Players
CREATE TABLE players (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  display_name TEXT NOT NULL,
  role role_type NOT NULL,
  is_alive BOOLEAN NOT NULL DEFAULT true,
  is_invincible BOOLEAN NOT NULL DEFAULT false,
  cleaned_role_from_player_id UUID,
  last_night_visited_player_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE games
  ADD CONSTRAINT fk_body_player
  FOREIGN KEY (body_player_id) REFERENCES players(id);
ALTER TABLE players
  ADD CONSTRAINT fk_cleaned_role_from
  FOREIGN KEY (cleaned_role_from_player_id) REFERENCES players(id);
ALTER TABLE players
  ADD CONSTRAINT fk_last_night_visited
  FOREIGN KEY (last_night_visited_player_id) REFERENCES players(id);

-- Night actions (stored per round, resolved when moving to day)
CREATE TABLE night_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  round_number INT NOT NULL,
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  action JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (game_id, round_number, player_id)
);

-- Indexes
CREATE INDEX idx_players_game_id ON players(game_id);
CREATE INDEX idx_players_user_id ON players(user_id);
CREATE INDEX idx_night_actions_game_round ON night_actions(game_id, round_number);

-- RLS (simplified: allow anon for dev; tighten with auth in production)
ALTER TABLE games ENABLE ROW LEVEL SECURITY;
ALTER TABLE players ENABLE ROW LEVEL SECURITY;
ALTER TABLE night_actions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow read games" ON games FOR SELECT USING (true);
CREATE POLICY "Allow read players" ON players FOR SELECT USING (true);
CREATE POLICY "Allow read night_actions" ON night_actions FOR SELECT USING (true);
CREATE POLICY "Allow insert/update games" ON games FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow insert/update players" ON players FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow insert/update night_actions" ON night_actions FOR ALL USING (true) WITH CHECK (true);
