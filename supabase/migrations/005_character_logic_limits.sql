-- Character logic: use limits (Bot 2, Miner 2, Strongman 2, Undertaker 2), Thief copies role (no swap), Strongman can protect self
-- Ace: one kill per round, dead = spectator (already enforced by targeting alive only)

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

-- Bot: swap two players' roles (excluding self), max 2 times total
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

-- Miner: check who interacted with who, max 2 times total. (If target is Bot, only one name revealed — already set in resolve via last_night_visited.)
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

-- Strongman: protect self or one other, max 2 times total (each time he submits protection counts as one use)
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

-- Undertaker: use a dead person's role, max 2 times total
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

-- Thief: copy target's role for the rest of the game; target keeps their role (Thief also has that role). One-time only.
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

-- resolve_night_to_day: remove "Strongman loses invincibility after round 2" — we now use strongman_uses_remaining
-- (Strongman loses invincibility when his protection blocks a kill; uses are consumed when he submits protection)
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
