-- =============================================================================
-- PASTE THIS ENTIRE FILE INTO SUPABASE SQL EDITOR AND RUN (after 001-003 are applied)
-- Migrations 004 + 005 + 006 + 007: Ghost/Professor/Thief, character limits, Thief copy/use, Bot order
-- =============================================================================

-- ==================== MIGRATION 004 ====================
-- Add Ghost, Professor, Thief + Professor reveal + Ghost vengeance + Strongman first-2-rounds

ALTER TYPE role_type ADD VALUE IF NOT EXISTS 'ghost';
ALTER TYPE role_type ADD VALUE IF NOT EXISTS 'professor';
ALTER TYPE role_type ADD VALUE IF NOT EXISTS 'thief';

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
DROP POLICY IF EXISTS "Allow all day_actions" ON day_actions;
CREATE POLICY "Allow all day_actions" ON day_actions FOR ALL USING (true) WITH CHECK (true);

-- Thief (004 version; 005/006 replace with copy logic)
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

-- ==================== MIGRATION 005 ====================
-- Character logic: use limits (Bot 2, Miner 2, Strongman 2, Undertaker 2), Thief copies role (no swap), Strongman can protect self

ALTER TABLE players
  ADD COLUMN IF NOT EXISTS bot_uses_remaining INT DEFAULT 2,
  ADD COLUMN IF NOT EXISTS miner_uses_remaining INT DEFAULT 2,
  ADD COLUMN IF NOT EXISTS strongman_uses_remaining INT DEFAULT 2,
  ADD COLUMN IF NOT EXISTS undertaker_uses_remaining INT DEFAULT 2,
  ADD COLUMN IF NOT EXISTS copied_role_from_player_id UUID REFERENCES players(id);

UPDATE players SET bot_uses_remaining = 2 WHERE bot_uses_remaining IS NULL;
UPDATE players SET miner_uses_remaining = 2 WHERE miner_uses_remaining IS NULL;
UPDATE players SET strongman_uses_remaining = 2 WHERE strongman_uses_remaining IS NULL;
UPDATE players SET undertaker_uses_remaining = 2 WHERE undertaker_uses_remaining IS NULL;

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
  bot_uses INT;
BEGIN
  IF p_target_1 = p_player_id OR p_target_2 = p_player_id THEN
    RAISE EXCEPTION 'Bot cannot select themselves';
  END IF;

  SELECT bot_uses_remaining INTO bot_uses FROM players WHERE id = p_player_id AND game_id = p_game_id;
  IF bot_uses IS NULL OR bot_uses < 1 THEN
    RAISE EXCEPTION 'Bot can only swap roles twice per game.';
  END IF;

  SELECT role INTO r1 FROM players WHERE id = p_target_1 AND game_id = p_game_id AND is_alive;
  SELECT role INTO r2 FROM players WHERE id = p_target_2 AND game_id = p_game_id AND is_alive;
  IF r1 IS NULL OR r2 IS NULL THEN
    RAISE EXCEPTION 'Invalid targets';
  END IF;

  UPDATE players SET role = r2, updated_at = now() WHERE id = p_target_1 AND game_id = p_game_id;
  UPDATE players SET role = r1, updated_at = now() WHERE id = p_target_2 AND game_id = p_game_id;
  UPDATE players SET bot_uses_remaining = bot_uses_remaining - 1, updated_at = now() WHERE id = p_player_id AND game_id = p_game_id;

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
  uses_left INT;
BEGIN
  SELECT miner_uses_remaining INTO uses_left FROM players WHERE id = p_player_id AND game_id = p_game_id;
  IF uses_left IS NULL OR uses_left < 1 THEN
    RETURN jsonb_build_object('error', 'You can only use the Tunnel twice per game.');
  END IF;

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

  UPDATE players SET miner_uses_remaining = miner_uses_remaining - 1, updated_at = now()
  WHERE id = p_player_id AND game_id = p_game_id;

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

CREATE OR REPLACE FUNCTION night_action_strongman(
  p_game_id UUID,
  p_player_id UUID,
  p_protect_player_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  uses_left INT;
BEGIN
  IF p_protect_player_id IS NOT NULL THEN
    SELECT strongman_uses_remaining INTO uses_left FROM players WHERE id = p_player_id AND game_id = p_game_id;
    IF uses_left IS NULL OR uses_left < 1 THEN
      RAISE EXCEPTION 'You can only protect someone twice per game.';
    END IF;
    IF p_protect_player_id != p_player_id AND NOT EXISTS (
      SELECT 1 FROM players WHERE id = p_protect_player_id AND game_id = p_game_id AND is_alive
    ) THEN
      RAISE EXCEPTION 'Invalid protection target';
    END IF;
    UPDATE players SET strongman_uses_remaining = strongman_uses_remaining - 1, updated_at = now()
    WHERE id = p_player_id AND game_id = p_game_id;
  END IF;

  INSERT INTO night_actions (game_id, round_number, player_id, action)
  SELECT g.id, g.round_number, p_player_id, jsonb_build_object(
    'kind', 'strongman',
    'protect_player_id', p_protect_player_id
  )
  FROM games g
  JOIN players p ON p.id = p_player_id AND p.game_id = g.id
  WHERE g.id = p_game_id AND g.phase = 'night' AND p.is_alive AND p.role = 'strongman'
  ON CONFLICT (game_id, round_number, player_id)
  DO UPDATE SET action = EXCLUDED.action, created_at = now();
END;
$$;

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
  uses_left INT;
BEGIN
  SELECT undertaker_uses_remaining INTO uses_left FROM players WHERE id = p_player_id AND game_id = p_game_id;
  IF uses_left IS NULL OR uses_left < 1 THEN
    RETURN jsonb_build_object('success', false, 'message', 'You can only clean a body twice per game.');
  END IF;

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
  SET cleaned_role_from_player_id = v_body_id, undertaker_uses_remaining = undertaker_uses_remaining - 1, updated_at = now()
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
  r_target role_type;
BEGIN
  IF p_target_player_id = p_player_id THEN
    RAISE EXCEPTION 'Thief cannot select themselves';
  END IF;

  IF EXISTS (SELECT 1 FROM players WHERE id = p_player_id AND game_id = p_game_id AND copied_role_from_player_id IS NOT NULL) THEN
    RAISE EXCEPTION 'You have already copied a role for the rest of the game.';
  END IF;

  SELECT role INTO r_target FROM players WHERE id = p_target_player_id AND game_id = p_game_id AND is_alive;
  IF r_target IS NULL THEN
    RAISE EXCEPTION 'Invalid target';
  END IF;

  UPDATE players SET copied_role_from_player_id = p_target_player_id, updated_at = now()
  WHERE id = p_player_id AND game_id = p_game_id;

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

-- ==================== MIGRATION 006 ====================
-- Thief can use copied role's night action; store copied_role on player

ALTER TABLE players
  ADD COLUMN IF NOT EXISTS copied_role role_type;

UPDATE players p
SET copied_role = src.role
FROM players src
WHERE p.copied_role_from_player_id = src.id AND p.copied_role IS NULL;

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
  r_target role_type;
BEGIN
  IF p_target_player_id = p_player_id THEN
    RAISE EXCEPTION 'Thief cannot select themselves';
  END IF;

  IF EXISTS (SELECT 1 FROM players WHERE id = p_player_id AND game_id = p_game_id AND copied_role_from_player_id IS NOT NULL) THEN
    RAISE EXCEPTION 'You have already copied a role for the rest of the game.';
  END IF;

  SELECT role INTO r_target FROM players WHERE id = p_target_player_id AND game_id = p_game_id AND is_alive;
  IF r_target IS NULL THEN
    RAISE EXCEPTION 'Invalid target';
  END IF;

  UPDATE players
  SET copied_role_from_player_id = p_target_player_id, copied_role = r_target, updated_at = now()
  WHERE id = p_player_id AND game_id = p_game_id;

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
  IF p_target_player_id = p_player_id THEN
    RAISE EXCEPTION 'You cannot eliminate yourself.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM players
    WHERE id = p_target_player_id AND game_id = p_game_id AND is_alive
  ) THEN
    RAISE EXCEPTION 'That player is already eliminated or invalid. You can only target alive players.';
  END IF;

  INSERT INTO night_actions (game_id, round_number, player_id, action)
  SELECT g.id, g.round_number, p_player_id, jsonb_build_object(
    'kind', 'ace',
    'target_player_id', p_target_player_id
  )
  FROM games g
  JOIN players p ON p.id = p_player_id AND p.game_id = g.id
  WHERE g.id = p_game_id AND g.phase = 'night'
    AND p.is_alive
    AND (p.role = 'ace' OR (p.role = 'thief' AND p.copied_role = 'ace'))
    AND p_target_player_id IN (SELECT id FROM players WHERE game_id = g.id AND is_alive AND id != p_player_id)
  ON CONFLICT (game_id, round_number, player_id)
  DO UPDATE SET action = EXCLUDED.action, created_at = now();
END;
$$;

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
  bot_uses INT;
BEGIN
  IF p_target_1 = p_player_id OR p_target_2 = p_player_id THEN
    RAISE EXCEPTION 'Bot cannot select themselves';
  END IF;

  SELECT bot_uses_remaining INTO bot_uses FROM players WHERE id = p_player_id AND game_id = p_game_id;
  IF bot_uses IS NULL OR bot_uses < 1 THEN
    RAISE EXCEPTION 'Bot can only swap roles twice per game.';
  END IF;

  SELECT role INTO r1 FROM players WHERE id = p_target_1 AND game_id = p_game_id AND is_alive;
  SELECT role INTO r2 FROM players WHERE id = p_target_2 AND game_id = p_game_id AND is_alive;
  IF r1 IS NULL OR r2 IS NULL THEN
    RAISE EXCEPTION 'Invalid targets';
  END IF;

  UPDATE players SET role = r2, updated_at = now() WHERE id = p_target_1 AND game_id = p_game_id;
  UPDATE players SET role = r1, updated_at = now() WHERE id = p_target_2 AND game_id = p_game_id;
  UPDATE players SET bot_uses_remaining = bot_uses_remaining - 1, updated_at = now() WHERE id = p_player_id AND game_id = p_game_id;

  INSERT INTO night_actions (game_id, round_number, player_id, action)
  SELECT g.id, g.round_number, p_player_id, jsonb_build_object(
    'kind', 'bot',
    'target_player_id_1', p_target_1,
    'target_player_id_2', p_target_2
  )
  FROM games g
  JOIN players p ON p.id = p_player_id AND p.game_id = g.id
  WHERE g.id = p_game_id AND g.phase = 'night' AND p.is_alive
    AND (p.role = 'bot' OR (p.role = 'thief' AND p.copied_role = 'bot'))
  ON CONFLICT (game_id, round_number, player_id)
  DO UPDATE SET action = EXCLUDED.action, created_at = now();
END;
$$;

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
  uses_left INT;
BEGIN
  SELECT miner_uses_remaining INTO uses_left FROM players WHERE id = p_player_id AND game_id = p_game_id;
  IF uses_left IS NULL OR uses_left < 1 THEN
    RETURN jsonb_build_object('error', 'You can only use the Tunnel twice per game.');
  END IF;

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

  UPDATE players SET miner_uses_remaining = miner_uses_remaining - 1, updated_at = now()
  WHERE id = p_player_id AND game_id = p_game_id;

  INSERT INTO night_actions (game_id, round_number, player_id, action)
  SELECT g.id, g.round_number, p_player_id, jsonb_build_object(
    'kind', 'miner',
    'target_player_id', p_target_player_id
  )
  FROM games g
  JOIN players p ON p.id = p_player_id AND p.game_id = g.id
  WHERE g.id = p_game_id AND g.phase = 'night' AND p.is_alive
    AND (p.role = 'miner' OR (p.role = 'thief' AND p.copied_role = 'miner'))
  ON CONFLICT (game_id, round_number, player_id)
  DO UPDATE SET action = EXCLUDED.action, created_at = now();

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION night_action_strongman(
  p_game_id UUID,
  p_player_id UUID,
  p_protect_player_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  uses_left INT;
BEGIN
  IF p_protect_player_id IS NOT NULL THEN
    SELECT strongman_uses_remaining INTO uses_left FROM players WHERE id = p_player_id AND game_id = p_game_id;
    IF uses_left IS NULL OR uses_left < 1 THEN
      RAISE EXCEPTION 'You can only protect someone twice per game.';
    END IF;
    IF p_protect_player_id != p_player_id AND NOT EXISTS (
      SELECT 1 FROM players WHERE id = p_protect_player_id AND game_id = p_game_id AND is_alive
    ) THEN
      RAISE EXCEPTION 'Invalid protection target';
    END IF;
    UPDATE players SET strongman_uses_remaining = strongman_uses_remaining - 1, updated_at = now()
    WHERE id = p_player_id AND game_id = p_game_id;
  END IF;

  INSERT INTO night_actions (game_id, round_number, player_id, action)
  SELECT g.id, g.round_number, p_player_id, jsonb_build_object(
    'kind', 'strongman',
    'protect_player_id', p_protect_player_id
  )
  FROM games g
  JOIN players p ON p.id = p_player_id AND p.game_id = g.id
  WHERE g.id = p_game_id AND g.phase = 'night' AND p.is_alive
    AND (p.role = 'strongman' OR (p.role = 'thief' AND p.copied_role = 'strongman'))
  ON CONFLICT (game_id, round_number, player_id)
  DO UPDATE SET action = EXCLUDED.action, created_at = now();
END;
$$;

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
  uses_left INT;
BEGIN
  SELECT undertaker_uses_remaining INTO uses_left FROM players WHERE id = p_player_id AND game_id = p_game_id;
  IF uses_left IS NULL OR uses_left < 1 THEN
    RETURN jsonb_build_object('success', false, 'message', 'You can only clean a body twice per game.');
  END IF;

  SELECT g.body_player_id INTO v_body_id
  FROM games g
  JOIN players p ON p.id = p_player_id AND p.game_id = g.id
  WHERE g.id = p_game_id AND g.phase = 'night' AND p.is_alive
    AND (p.role = 'undertaker' OR (p.role = 'thief' AND p.copied_role = 'undertaker'));

  IF v_body_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'No body to clean.');
  END IF;

  SELECT role, display_name INTO v_body_role, v_body_name
  FROM players WHERE id = v_body_id;

  UPDATE players
  SET cleaned_role_from_player_id = v_body_id, undertaker_uses_remaining = undertaker_uses_remaining - 1, updated_at = now()
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

-- ==================== MIGRATION 007 ====================
-- Bot swap order: Bot first, then Thief-as-Bot (defer swaps to resolve)

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
  bot_uses INT;
BEGIN
  IF p_target_1 = p_player_id OR p_target_2 = p_player_id THEN
    RAISE EXCEPTION 'Bot cannot select themselves';
  END IF;

  SELECT bot_uses_remaining INTO bot_uses FROM players WHERE id = p_player_id AND game_id = p_game_id;
  IF bot_uses IS NULL OR bot_uses < 1 THEN
    RAISE EXCEPTION 'Bot can only swap roles twice per game.';
  END IF;

  SELECT role INTO r1 FROM players WHERE id = p_target_1 AND game_id = p_game_id AND is_alive;
  SELECT role INTO r2 FROM players WHERE id = p_target_2 AND game_id = p_game_id AND is_alive;
  IF r1 IS NULL OR r2 IS NULL THEN
    RAISE EXCEPTION 'Invalid targets';
  END IF;

  UPDATE players SET bot_uses_remaining = bot_uses_remaining - 1, updated_at = now() WHERE id = p_player_id AND game_id = p_game_id;

  INSERT INTO night_actions (game_id, round_number, player_id, action)
  SELECT g.id, g.round_number, p_player_id, jsonb_build_object(
    'kind', 'bot',
    'target_player_id_1', p_target_1,
    'target_player_id_2', p_target_2
  )
  FROM games g
  JOIN players p ON p.id = p_player_id AND p.game_id = g.id
  WHERE g.id = p_game_id AND g.phase = 'night' AND p.is_alive
    AND (p.role = 'bot' OR (p.role = 'thief' AND p.copied_role = 'bot'))
  ON CONFLICT (game_id, round_number, player_id)
  DO UPDATE SET action = EXCLUDED.action, created_at = now();
END;
$$;

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
  prof_alive BOOLEAN;
  r RECORD;
  t1 UUID;
  t2 UUID;
  r1 role_type;
  r2 role_type;
BEGIN
  SELECT round_number INTO v_round FROM games WHERE id = p_game_id;
  IF NOT FOUND THEN RETURN; END IF;

  FOR r IN
    SELECT na.player_id, na.action, p.role AS actor_role
    FROM night_actions na
    JOIN players p ON p.id = na.player_id AND p.game_id = p_game_id
    WHERE na.game_id = p_game_id AND na.round_number = v_round
      AND na.action->>'kind' = 'bot'
    ORDER BY (p.role = 'bot') DESC
  LOOP
    t1 := (r.action->>'target_player_id_1')::UUID;
    t2 := (r.action->>'target_player_id_2')::UUID;
    IF t1 IS NOT NULL AND t2 IS NOT NULL THEN
      SELECT role INTO r1 FROM players WHERE id = t1 AND game_id = p_game_id;
      SELECT role INTO r2 FROM players WHERE id = t2 AND game_id = p_game_id;
      UPDATE players SET role = r2, updated_at = now() WHERE id = t1 AND game_id = p_game_id;
      UPDATE players SET role = r1, updated_at = now() WHERE id = t2 AND game_id = p_game_id;
    END IF;
  END LOOP;

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
