-- 1) Bot swap order: real Bot's swap is applied before Thief-as-Bot's swap.
--    Defer role swaps to resolve; in resolve, process 'bot' actions with Bot first, then Thief.
-- 2) Ace eliminated + Thief copied Ace: Thief is the only one who can submit the ace kill (no code
--    change; resolve uses the single 'ace' action from night_actions, so Thief becomes the only Ace).

-- Bot (and Thief-as-Bot): only record the action and decrement uses; do NOT swap roles here.
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

  -- Defer swap to resolve_night_to_day so Bot always runs before Thief-as-Bot
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

-- resolve_night_to_day: apply Bot swaps first (Bot then Thief-as-Bot), then Ace kill, etc.
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

  -- Apply Bot and Thief-as-Bot swaps in order: Bot first, then Thief (so Thief's switch comes after Bot's)
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

  -- Ace kill: single 'ace' action (from Ace or Thief-as-Ace; if Ace is eliminated, Thief is the only Ace)
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
