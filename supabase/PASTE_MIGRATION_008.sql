-- =============================================================================
-- MIGRATION 008 — Game state (day/night cycle) + voting
-- Paste this into Supabase SQL Editor and run (after 001–007 are applied).
-- =============================================================================

-- game_state: NIGHT_PHASE | DAY_PHASE | ANIMATION_LOCK for day/night cycle and transition overlays
-- day_votes: one row per vote (voter -> target) per round; when any player reaches 4 votes, set game_state to ANIMATION_LOCK

CREATE TYPE game_state_type AS ENUM ('night_phase', 'day_phase', 'animation_lock');

ALTER TABLE games
  ADD COLUMN IF NOT EXISTS game_state game_state_type NOT NULL DEFAULT 'night_phase';

-- Backfill: games already in day phase get day_phase state
UPDATE games SET game_state = 'day_phase'::game_state_type WHERE phase = 'day';

CREATE TABLE IF NOT EXISTS day_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  round_number INT NOT NULL,
  voter_player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  target_player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (game_id, round_number, voter_player_id)
);

CREATE INDEX IF NOT EXISTS idx_day_votes_game_round ON day_votes(game_id, round_number);

ALTER TABLE day_votes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all day_votes" ON day_votes FOR ALL USING (true) WITH CHECK (true);

-- When a player is voted out (inked), we store who was eliminated this round for the Inked scene
ALTER TABLE games
  ADD COLUMN IF NOT EXISTS voted_out_player_id UUID REFERENCES players(id),
  ADD COLUMN IF NOT EXISTS transition_to TEXT CHECK (transition_to IN ('day', 'night'));

COMMENT ON COLUMN games.game_state IS 'night_phase | day_phase | animation_lock; lock used during transition or inked scene';
COMMENT ON COLUMN games.transition_to IS 'When animation_lock: day = show Day Comes, night = show Night Falls; null = show Inked if voted_out set';
COMMENT ON COLUMN games.voted_out_player_id IS 'Set when someone is voted out (reaches 4 votes); used for Inked animation then cleared';

-- Cast a day vote; if target reaches 4 votes, set game_state to animation_lock and voted_out_player_id
CREATE OR REPLACE FUNCTION cast_day_vote(
  p_game_id UUID,
  p_voter_player_id UUID,
  p_target_player_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_round INT;
  v_count INT;
BEGIN
  SELECT round_number INTO v_round FROM games WHERE id = p_game_id;
  IF v_round IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Game not found');
  END IF;

  IF p_voter_player_id = p_target_player_id THEN
    RETURN jsonb_build_object('ok', false, 'error', 'You cannot vote for yourself');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM players WHERE id = p_voter_player_id AND game_id = p_game_id AND is_alive) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Invalid voter');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM players WHERE id = p_target_player_id AND game_id = p_game_id AND is_alive) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Cannot vote for eliminated player');
  END IF;

  INSERT INTO day_votes (game_id, round_number, voter_player_id, target_player_id)
  VALUES (p_game_id, v_round, p_voter_player_id, p_target_player_id)
  ON CONFLICT (game_id, round_number, voter_player_id)
  DO UPDATE SET target_player_id = p_target_player_id, created_at = now();

  SELECT COUNT(*)::INT INTO v_count
  FROM day_votes
  WHERE game_id = p_game_id AND round_number = v_round AND target_player_id = p_target_player_id;

  IF v_count >= 4 THEN
    UPDATE games
    SET game_state = 'animation_lock',
        voted_out_player_id = p_target_player_id,
        updated_at = now()
    WHERE id = p_game_id;
    RETURN jsonb_build_object('ok', true, 'voted_out', true, 'target_player_id', p_target_player_id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'voted_out', false);
END;
$$;

-- After night resolve: set game_state to animation_lock + transition_to 'day' (Day Comes overlay)
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

  UPDATE games SET phase = 'day', game_state = 'animation_lock', transition_to = 'day', updated_at = now() WHERE id = p_game_id;
END;
$$;

-- After Day Comes overlay (3s): show day phase
CREATE OR REPLACE FUNCTION complete_transition_to_day(p_game_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE games SET game_state = 'day_phase', transition_to = NULL, updated_at = now() WHERE id = p_game_id;
END;
$$;

-- Start Night Falls transition (call when "End day" is clicked)
CREATE OR REPLACE FUNCTION start_transition_to_night(p_game_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE games SET game_state = 'animation_lock', transition_to = 'night', updated_at = now() WHERE id = p_game_id;
END;
$$;

-- After Night Falls overlay (3s): advance to next night
CREATE OR REPLACE FUNCTION complete_transition_to_night(p_game_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE games SET game_state = 'night_phase', phase = 'night', transition_to = NULL, round_number = round_number + 1, updated_at = now() WHERE id = p_game_id;
END;
$$;

-- Call after Inked animation completes: eliminate player, clear voted_out, go to night
CREATE OR REPLACE FUNCTION finish_inked_and_advance(p_game_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_voted_out UUID;
BEGIN
  SELECT voted_out_player_id INTO v_voted_out FROM games WHERE id = p_game_id;
  IF v_voted_out IS NOT NULL THEN
    UPDATE players SET is_alive = false, updated_at = now() WHERE id = v_voted_out AND game_id = p_game_id;
  END IF;
  UPDATE games
  SET voted_out_player_id = NULL, game_state = 'night_phase', phase = 'night',
      round_number = round_number + 1, body_player_id = NULL, updated_at = now()
  WHERE id = p_game_id;
END;
$$;

-- Get vote counts per player for current round (for UI)
CREATE OR REPLACE FUNCTION get_day_vote_counts(p_game_id UUID)
RETURNS TABLE(target_player_id UUID, vote_count BIGINT)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT dv.target_player_id, COUNT(*)::BIGINT
  FROM day_votes dv
  JOIN games g ON g.id = dv.game_id AND dv.round_number = g.round_number
  WHERE dv.game_id = p_game_id
  GROUP BY dv.target_player_id;
$$;
