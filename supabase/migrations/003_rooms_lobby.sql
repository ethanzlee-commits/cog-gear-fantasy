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

-- Enable realtime for presence (use channel room:{code}); table subscription optional
-- ALTER PUBLICATION supabase_realtime ADD TABLE room_players;
