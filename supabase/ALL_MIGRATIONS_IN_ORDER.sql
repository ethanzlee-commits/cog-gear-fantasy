-- =============================================================================
-- COG-GEAR FANTASY — RUN IN SUPABASE SQL EDITOR
-- Run each section separately (one at a time) in this order: 001, 002, 003, 004.
-- =============================================================================


-- ==================== MIGRATION 001_schema.sql ====================
-- Project: Cog-Gear Fantasy — Schema
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


-- ==================== MIGRATION 002_night_phase_functions.sql ====================
-- Night Phase RPCs: Ace, Bot, Miner, Strongman, Undertaker + resolve_night_to_day

-- 1) Ace: submit kill target (stored; resolved when phase goes to day)
CREATE OR REPLACE FUNCTION night_action_ace(
  p_game_id UUID,
  p_player_id UUID,
  p_target_player_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO night_actions (game_id, round_number, player_id, action)
  SELECT g.id, g.round_number, p_player_id, jsonb_build_object(
    'kind', 'ace',
    'target_player_id', p_target_player_id
  )
  FROM games g
  JOIN players p ON p.id = p_player_id AND p.game_id = g.id
  WHERE g.id = p_game_id AND g.phase = 'night'
    AND p.is_alive
    AND p.role = 'ace'
    AND p_target_player_id IN (SELECT id FROM players WHERE game_id = g.id AND is_alive AND id != p_player_id)
  ON CONFLICT (game_id, round_number, player_id)
  DO UPDATE SET action = EXCLUDED.action, created_at = now();
END;
$$;

-- 2) Bot: swap two players' roles (instant)
CREATE OR REPLACE FUNCTION night_action_bot(
  p_game_id UUID,
  p_player_id UUID,
  p_target_1 UUID,
  p_target_2 UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r1 role_type;
  r2 role_type;
BEGIN
  IF p_target_1 = p_player_id OR p_target_2 = p_player_id THEN
    RAISE EXCEPTION 'Bot cannot select themselves';
  END IF;

  SELECT role INTO r1 FROM players WHERE id = p_target_1 AND game_id = p_game_id AND is_alive;
  SELECT role INTO r2 FROM players WHERE id = p_target_2 AND game_id = p_game_id AND is_alive;
  IF r1 IS NULL OR r2 IS NULL THEN
    RAISE EXCEPTION 'Invalid targets';
  END IF;

  UPDATE players SET role = r2, updated_at = now() WHERE id = p_target_1 AND game_id = p_game_id;
  UPDATE players SET role = r1, updated_at = now() WHERE id = p_target_2 AND game_id = p_game_id;

  INSERT INTO night_actions (game_id, round_number, player_id, action)
  SELECT g.id, g.round_number, p_player_id, jsonb_build_object(
    'kind', 'bot',
    'target_player_id_1', p_target_1,
    'target_player_id_2', p_target_2
  )
  FROM games g
  JOIN players p ON p.id = p_player_id AND p.game_id = g.id
  WHERE g.id = p_game_id AND g.phase = 'night' AND p.is_alive AND p.role = 'bot'
  ON CONFLICT (game_id, round_number, player_id)
  DO UPDATE SET action = EXCLUDED.action, created_at = now();
END;
$$;

-- 3) Miner: get result "visited [name]" or "stayed home"
CREATE OR REPLACE FUNCTION night_action_miner(
  p_game_id UUID,
  p_player_id UUID,
  p_target_player_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  visited_id UUID;
  target_display_name TEXT;
  result JSONB;
BEGIN
  SELECT last_night_visited_player_id, display_name
  INTO visited_id, target_display_name
  FROM players
  WHERE id = p_target_player_id AND game_id = p_game_id AND is_alive;

  IF target_display_name IS NULL THEN
    RETURN jsonb_build_object('error', 'Invalid target');
  END IF;

  IF visited_id IS NOT NULL THEN
    result := jsonb_build_object('visited', true, 'target_name', (
      SELECT display_name FROM players WHERE id = visited_id
    ));
  ELSE
    result := jsonb_build_object('visited', false);
  END IF;

  INSERT INTO night_actions (game_id, round_number, player_id, action)
  SELECT g.id, g.round_number, p_player_id, jsonb_build_object(
    'kind', 'miner',
    'target_player_id', p_target_player_id
  )
  FROM games g
  JOIN players p ON p.id = p_player_id AND p.game_id = g.id
  WHERE g.id = p_game_id AND g.phase = 'night' AND p.is_alive AND p.role = 'miner'
  ON CONFLICT (game_id, round_number, player_id)
  DO UPDATE SET action = EXCLUDED.action, created_at = now();

  RETURN result;
END;
$$;

-- 4) Strongman: set protection target (null = not protecting)
CREATE OR REPLACE FUNCTION night_action_strongman(
  p_game_id UUID,
  p_player_id UUID,
  p_protect_player_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO night_actions (game_id, round_number, player_id, action)
  SELECT g.id, g.round_number, p_player_id, jsonb_build_object(
    'kind', 'strongman',
    'protect_player_id', p_protect_player_id
  )
  FROM games g
  JOIN players p ON p.id = p_player_id AND p.game_id = g.id
  WHERE g.id = p_game_id AND g.phase = 'night' AND p.is_alive AND p.role = 'strongman'
    AND (p_protect_player_id IS NULL OR p_protect_player_id IN (
      SELECT id FROM players WHERE game_id = g.id AND is_alive AND id != p_player_id
    ))
  ON CONFLICT (game_id, round_number, player_id)
  DO UPDATE SET action = EXCLUDED.action, created_at = now();
END;
$$;

-- 5) Undertaker: clean body → gain that role for next night
CREATE OR REPLACE FUNCTION night_action_undertaker(
  p_game_id UUID,
  p_player_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_body_id UUID;
  v_body_role role_type;
  v_body_name TEXT;
BEGIN
  SELECT g.body_player_id INTO v_body_id
  FROM games g
  JOIN players p ON p.id = p_player_id AND p.game_id = g.id
  WHERE g.id = p_game_id AND g.phase = 'night' AND p.is_alive AND p.role = 'undertaker';

  IF v_body_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'No body to clean.');
  END IF;

  SELECT role, display_name INTO v_body_role, v_body_name
  FROM players WHERE id = v_body_id;

  UPDATE players
  SET cleaned_role_from_player_id = v_body_id, updated_at = now()
  WHERE id = p_player_id AND game_id = p_game_id;

  UPDATE games SET body_player_id = NULL, updated_at = now() WHERE id = p_game_id;

  INSERT INTO night_actions (game_id, round_number, player_id, action)
  SELECT g.id, g.round_number, p_player_id, jsonb_build_object(
    'kind', 'undertaker',
    'clean_body', true
  )
  FROM games g
  WHERE g.id = p_game_id AND g.phase = 'night'
  ON CONFLICT (game_id, round_number, player_id)
  DO UPDATE SET action = EXCLUDED.action, created_at = now();

  RETURN jsonb_build_object(
    'success', true,
    'message', 'You cleaned the body. You gain ' || v_body_name || '''s role for the next night.',
    'gained_role', v_body_role
  );
END;
$$;

-- Resolve night → day: apply Ace kill (respect Strongman), set Miner visit data, consume Strongman
CREATE OR REPLACE FUNCTION resolve_night_to_day(p_game_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_round INT;
  ace_target UUID;
  strongman_protect UUID;
  strongman_player_id UUID;
  killer_id UUID;
BEGIN
  SELECT round_number INTO v_round FROM games WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT (action->>'target_player_id')::UUID, na.player_id INTO ace_target, killer_id
  FROM night_actions na
  WHERE na.game_id = p_game_id AND na.round_number = v_round
    AND (na.action->>'kind') = 'ace'
  LIMIT 1;

  SELECT (na.action->>'protect_player_id')::UUID, na.player_id
  INTO strongman_protect, strongman_player_id
  FROM night_actions na
  WHERE na.game_id = p_game_id AND na.round_number = v_round
    AND (na.action->>'kind') = 'strongman'
    AND (na.action->>'protect_player_id') IS NOT NULL
  LIMIT 1;

  IF ace_target IS NOT NULL AND (strongman_protect IS NULL OR strongman_protect != ace_target) THEN
    UPDATE players SET is_alive = false, updated_at = now() WHERE id = ace_target;
    UPDATE games SET body_player_id = ace_target, updated_at = now() WHERE id = p_game_id;
  ELSIF ace_target IS NOT NULL AND strongman_protect = ace_target THEN
    UPDATE players SET is_invincible = false, updated_at = now() WHERE id = strongman_player_id;
  END IF;

  UPDATE players p
  SET last_night_visited_player_id = CASE (na.action->>'kind')
    WHEN 'ace' THEN (na.action->>'target_player_id')::UUID
    WHEN 'miner' THEN (na.action->>'target_player_id')::UUID
    WHEN 'strongman' THEN (na.action->>'protect_player_id')::UUID
    WHEN 'bot' THEN (na.action->>'target_player_id_1')::UUID
    ELSE NULL
  END,
  updated_at = now()
  FROM night_actions na
  WHERE na.game_id = p_game_id AND na.round_number = v_round
    AND p.id = na.player_id
    AND (na.action->>'kind') IN ('ace', 'miner', 'strongman', 'bot');

  UPDATE games SET phase = 'day', updated_at = now() WHERE id = p_game_id;
END;
$$;


-- ==================== MIGRATION 003_rooms_lobby.sql ====================
-- Room Code lobby: rooms + room_players (no auth; device_id + nickname)

CREATE TABLE rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  host_device_id TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE room_players (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  nickname TEXT NOT NULL,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (room_id, device_id)
);

CREATE INDEX idx_rooms_code ON rooms(code);
CREATE INDEX idx_room_players_room_id ON room_players(room_id);

ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE room_players ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow all rooms" ON rooms FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all room_players" ON room_players FOR ALL USING (true) WITH CHECK (true);


-- ==================== MIGRATION 004_ghost_professor_thief.sql ====================
-- Add Ghost, Professor, Thief + Professor reveal + Ghost vengeance + Strongman first-2-rounds

ALTER TYPE role_type ADD VALUE 'ghost';
ALTER TYPE role_type ADD VALUE 'professor';
ALTER TYPE role_type ADD VALUE 'thief';

ALTER TABLE games ADD COLUMN IF NOT EXISTS revealed_ace_player_id UUID REFERENCES players(id);

CREATE TABLE IF NOT EXISTS day_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  round_number INT NOT NULL,
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  action JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (game_id, round_number, player_id)
);

CREATE INDEX IF NOT EXISTS idx_day_actions_game_round ON day_actions(game_id, round_number);

ALTER TABLE day_actions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all day_actions" ON day_actions FOR ALL USING (true) WITH CHECK (true);

-- Thief: swap own role with target's role (instant)
CREATE OR REPLACE FUNCTION night_action_thief(
  p_game_id UUID,
  p_player_id UUID,
  p_target_player_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r_thief role_type;
  r_target role_type;
BEGIN
  IF p_target_player_id = p_player_id THEN
    RAISE EXCEPTION 'Thief cannot select themselves';
  END IF;

  SELECT role INTO r_thief FROM players WHERE id = p_player_id AND game_id = p_game_id AND is_alive;
  SELECT role INTO r_target FROM players WHERE id = p_target_player_id AND game_id = p_game_id AND is_alive;

  IF r_thief IS NULL OR r_thief != 'thief' OR r_target IS NULL THEN
    RAISE EXCEPTION 'Invalid thief action';
  END IF;

  UPDATE players SET role = r_target, updated_at = now() WHERE id = p_player_id AND game_id = p_game_id;
  UPDATE players SET role = r_thief, updated_at = now() WHERE id = p_target_player_id AND game_id = p_game_id;

  INSERT INTO night_actions (game_id, round_number, player_id, action)
  SELECT g.id, g.round_number, p_player_id, jsonb_build_object(
    'kind', 'thief',
    'target_player_id', p_target_player_id
  )
  FROM games g
  WHERE g.id = p_game_id AND g.phase = 'night'
  ON CONFLICT (game_id, round_number, player_id)
  DO UPDATE SET action = EXCLUDED.action, created_at = now();
END;
$$;

-- Update resolve_night_to_day: Professor reveal, Strongman invincibility, thief in last_night_visited
CREATE OR REPLACE FUNCTION resolve_night_to_day(p_game_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_round INT;
  ace_target UUID;
  ace_player_id UUID;
  strongman_protect UUID;
  strongman_player_id UUID;
  killer_id UUID;
  prof_alive BOOLEAN;
BEGIN
  SELECT round_number INTO v_round FROM games WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT (na.action->>'target_player_id')::UUID, na.player_id INTO ace_target, ace_player_id
  FROM night_actions na
  WHERE na.game_id = p_game_id AND na.round_number = v_round
    AND (na.action->>'kind') = 'ace'
  LIMIT 1;

  SELECT (na.action->>'protect_player_id')::UUID, na.player_id
  INTO strongman_protect, strongman_player_id
  FROM night_actions na
  WHERE na.game_id = p_game_id AND na.round_number = v_round
    AND (na.action->>'kind') = 'strongman'
    AND (na.action->>'protect_player_id') IS NOT NULL
  LIMIT 1;

  IF ace_target IS NOT NULL AND (strongman_protect IS NULL OR strongman_protect != ace_target) THEN
    UPDATE players SET is_alive = false, updated_at = now() WHERE id = ace_target;
    UPDATE games SET body_player_id = ace_target, updated_at = now() WHERE id = p_game_id;
  ELSIF ace_target IS NOT NULL AND strongman_protect = ace_target THEN
    UPDATE players SET is_invincible = false, updated_at = now() WHERE id = strongman_player_id;
  END IF;

  IF v_round >= 2 THEN
    UPDATE players SET is_invincible = false, updated_at = now()
    WHERE game_id = p_game_id AND role = 'strongman' AND is_invincible;
  END IF;

  IF v_round >= 3 AND ace_player_id IS NOT NULL THEN
    SELECT EXISTS (SELECT 1 FROM players WHERE game_id = p_game_id AND role = 'professor' AND is_alive) INTO prof_alive;
    IF prof_alive THEN
      UPDATE games SET revealed_ace_player_id = ace_player_id, updated_at = now() WHERE id = p_game_id;
    END IF;
  END IF;

  UPDATE players p
  SET last_night_visited_player_id = CASE (na.action->>'kind')
    WHEN 'ace' THEN (na.action->>'target_player_id')::UUID
    WHEN 'miner' THEN (na.action->>'target_player_id')::UUID
    WHEN 'strongman' THEN (na.action->>'protect_player_id')::UUID
    WHEN 'bot' THEN (na.action->>'target_player_id_1')::UUID
    WHEN 'thief' THEN (na.action->>'target_player_id')::UUID
    ELSE NULL
  END,
  updated_at = now()
  FROM night_actions na
  WHERE na.game_id = p_game_id AND na.round_number = v_round
    AND p.id = na.player_id
    AND (na.action->>'kind') IN ('ace', 'miner', 'strongman', 'bot', 'thief');

  UPDATE games SET phase = 'day', updated_at = now() WHERE id = p_game_id;
END;
$$;
