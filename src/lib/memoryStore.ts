/**
 * In-memory store for rooms and room_players when running without Supabase.
 * Used when NEXT_PUBLIC_SUPABASE_URL is not set.
 */

export interface MemoryRoom {
  id: string;
  code: string;
  host_device_id: string;
  created_at: string;
}

export interface MemoryRoomPlayer {
  id: string;
  room_id: string;
  device_id: string;
  nickname: string;
  joined_at: string;
}

const rooms = new Map<string, MemoryRoom>();
const roomsByCode = new Map<string, MemoryRoom>();
const roomPlayers = new Map<string, MemoryRoomPlayer[]>();

function id() {
  return crypto.randomUUID?.() ?? "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 3) | 8;
    return v.toString(16);
  });
}

export function memoryCreateRoom(code: string, hostDeviceId: string): MemoryRoom {
  const room: MemoryRoom = {
    id: id(),
    code,
    host_device_id: hostDeviceId,
    created_at: new Date().toISOString(),
  };
  rooms.set(room.id, room);
  roomsByCode.set(code, room);
  roomPlayers.set(room.id, []);
  return room;
}

export function memoryAddRoomPlayer(roomId: string, deviceId: string, nickname: string): void {
  const list = roomPlayers.get(roomId) ?? [];
  if (list.some((p) => p.device_id === deviceId)) return;
  list.push({
    id: id(),
    room_id: roomId,
    device_id: deviceId,
    nickname: nickname.trim() || "Player",
    joined_at: new Date().toISOString(),
  });
  roomPlayers.set(roomId, list);
}

export function memoryGetRoomByCode(code: string): MemoryRoom | null {
  return roomsByCode.get(code) ?? null;
}

export function memoryGetRoomPlayer(roomId: string, deviceId: string): MemoryRoomPlayer | null {
  const list = roomPlayers.get(roomId) ?? [];
  return list.find((p) => p.device_id === deviceId) ?? null;
}

export function memoryGetRoomPlayers(roomId: string): MemoryRoomPlayer[] {
  return roomPlayers.get(roomId) ?? [];
}

export function memoryCodeExists(code: string): boolean {
  return roomsByCode.has(code);
}
