-- Project: Cog-Gear Fantasy — Night Phase RPCs
-- Resolve order: Bot (swap) → Strongman (set protection) → Ace (kill, check Strongman) → Miner (set visit) → Undertaker (clean body)

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
  -- Store in night_actions; resolution will set a "protected_by" or we use action to apply protection
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

-- Resolve night → day: apply Ace kill (respect Strongman), set Miner visit data for next round, consume Strongman
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

  -- Get Ace target
  SELECT (action->>'target_player_id')::UUID, na.player_id INTO ace_target, killer_id
  FROM night_actions na
  WHERE na.game_id = p_game_id AND na.round_number = v_round
    AND (na.action->>'kind') = 'ace'
  LIMIT 1;

  -- Get Strongman protection for this round
  SELECT (na.action->>'protect_player_id')::UUID, na.player_id
  INTO strongman_protect, strongman_player_id
  FROM night_actions na
  WHERE na.game_id = p_game_id AND na.round_number = v_round
    AND (na.action->>'kind') = 'strongman'
    AND (na.action->>'protect_player_id') IS NOT NULL
  LIMIT 1;

  -- Apply kill only if Ace has a target and target is not protected
  IF ace_target IS NOT NULL AND (strongman_protect IS NULL OR strongman_protect != ace_target) THEN
    UPDATE players SET is_alive = false, updated_at = now() WHERE id = ace_target;
    UPDATE games SET body_player_id = ace_target, updated_at = now() WHERE id = p_game_id;
  ELSIF ace_target IS NOT NULL AND strongman_protect = ace_target THEN
    -- Kill failed; consume Strongman's invincibility
    UPDATE players SET is_invincible = false, updated_at = now() WHERE id = strongman_player_id;
  END IF;

  -- Set last_night_visited_player_id for each player who had a target this night (for Miner next round)
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

  -- Advance to day
  UPDATE games SET phase = 'day', updated_at = now() WHERE id = p_game_id;
END;
$$;
