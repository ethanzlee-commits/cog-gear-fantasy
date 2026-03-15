-- Thief can use their copied role's night action. Store copied role on player for checks.
-- All night_action_* (ace, bot, miner, strongman, undertaker) accept Thief when copied_role matches.

ALTER TABLE players
  ADD COLUMN IF NOT EXISTS copied_role role_type;

-- Backfill: Thieves who already copied get copied_role from the referenced player
UPDATE players p
SET copied_role = src.role
FROM players src
WHERE p.copied_role_from_player_id = src.id AND p.copied_role IS NULL;

-- Thief: when copying, store the role so we can allow using it later
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

-- Ace: allow Thief with copied_role = 'ace' to submit kill. Target must be alive (eliminated players cannot be chosen again).
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

-- Bot: allow Thief with copied_role = 'bot'; use actor's bot_uses_remaining
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

-- Miner: allow Thief with copied_role = 'miner'; use actor's miner_uses_remaining
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

-- Strongman: allow Thief with copied_role = 'strongman'; use actor's strongman_uses_remaining
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

-- Undertaker: allow Thief with copied_role = 'undertaker'; use actor's undertaker_uses_remaining
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
