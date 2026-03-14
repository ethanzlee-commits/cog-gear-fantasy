-- Add Ghost, Professor, Thief + Professor reveal + Ghost vengeance + Strongman first-2-rounds

-- Add new role types (run once; omit if already applied)
ALTER TYPE role_type ADD VALUE 'ghost';
ALTER TYPE role_type ADD VALUE 'professor';
ALTER TYPE role_type ADD VALUE 'thief';

-- Professor: after Round 3, Ace identity is revealed (store who the Ace is for UI)
ALTER TABLE games ADD COLUMN IF NOT EXISTS revealed_ace_player_id UUID REFERENCES players(id);

-- Day actions (e.g. Ghost vengeance when voted out)
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

-- Update resolve_night_to_day: Professor reveal after round 3, Strongman lose invincibility after round 2, thief in last_night_visited
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

  -- Get Ace target and Ace's player id (for Professor reveal)
  SELECT (na.action->>'target_player_id')::UUID, na.player_id INTO ace_target, ace_player_id
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
    UPDATE players SET is_invincible = false, updated_at = now() WHERE id = strongman_player_id;
  END IF;

  -- Strongman: lose invincibility after round 2 (first two rounds only)
  IF v_round >= 2 THEN
    UPDATE players SET is_invincible = false, updated_at = now()
    WHERE game_id = p_game_id AND role = 'strongman' AND is_invincible;
  END IF;

  -- Professor: after Round 3, reveal Ace to game (Professor sees this in Day UI)
  IF v_round >= 3 AND ace_player_id IS NOT NULL THEN
    SELECT EXISTS (SELECT 1 FROM players WHERE game_id = p_game_id AND role = 'professor' AND is_alive) INTO prof_alive;
    IF prof_alive THEN
      UPDATE games SET revealed_ace_player_id = ace_player_id, updated_at = now() WHERE id = p_game_id;
    END IF;
  END IF;

  -- Set last_night_visited_player_id for Miner next round (include thief)
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

  -- Advance to day
  UPDATE games SET phase = 'day', updated_at = now() WHERE id = p_game_id;
END;
$$;
