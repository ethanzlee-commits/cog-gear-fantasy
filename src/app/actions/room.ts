"use server";

import { createClient } from "@/lib/supabase/server";
import { generateRoomCode } from "@/lib/roomCode";
import {
  memoryCreateRoom,
  memoryAddRoomPlayer,
  memoryGetRoomByCode,
  memoryGetRoomPlayer,
  memoryGetRoomPlayers,
  memoryCodeExists,
} from "@/lib/memoryStore";
import { isSupabaseConfigured } from "@/lib/supabase/configured";

export async function createRoom(hostDeviceId: string): Promise<{ code: string }> {
  if (!isSupabaseConfigured()) {
    let code = generateRoomCode();
    let attempts = 0;
    while (attempts < 10 && memoryCodeExists(code)) {
      code = generateRoomCode();
      attempts++;
    }
    const room = memoryCreateRoom(code, hostDeviceId);
    memoryAddRoomPlayer(room.id, hostDeviceId, "Host");
    return { code: room.code };
  }

  try {
    const supabase = await createClient();
    let code = generateRoomCode();
    let attempts = 0;
    const maxAttempts = 10;

    while (attempts < maxAttempts) {
      const { data: existing } = await supabase.from("rooms").select("id").eq("code", code).single();
      if (!existing) break;
      code = generateRoomCode();
      attempts++;
    }

    const { data: room, error: roomError } = await supabase
      .from("rooms")
      .insert({ code, host_device_id: hostDeviceId })
      .select("id, code")
      .single();

    if (roomError) {
      if (roomError.code === "42P01" || roomError.message?.includes("does not exist")) {
        throw new Error("Rooms table missing. Run migration 003_rooms_lobby.sql in Supabase SQL Editor.");
      }
      throw new Error(roomError.message);
    }
    if (!room) throw new Error("Failed to create room");

    const { error: playerError } = await supabase.from("room_players").insert({
      room_id: room.id,
      device_id: hostDeviceId,
      nickname: "Host",
    });

    if (playerError) {
      if (playerError.code === "42P01" || playerError.message?.includes("does not exist")) {
        throw new Error("room_players table missing. Run migration 003_rooms_lobby.sql in Supabase.");
      }
      throw new Error(playerError.message);
    }

    return { code: room.code };
  } catch (e) {
    if (e instanceof Error) throw e;
    const msg = String(e);
    if (msg.includes("fetch") || msg.includes("URL") || msg.includes("network")) {
      throw new Error("Can't reach Supabase. Check .env.local: NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY.");
    }
    throw new Error("Failed to create room. Check Supabase setup and migrations.");
  }
}

export async function joinRoom(
  code: string,
  deviceId: string,
  nickname: string
): Promise<{ code: string }> {
  const normalized = code.toUpperCase().replace(/[^A-Z]/g, "").slice(0, 4);
  if (normalized.length !== 4) throw new Error("Invalid room code");
  if (!deviceId || String(deviceId).trim() === "") {
    throw new Error("Could not identify your device. Enable cookies or local storage and try again.");
  }

  if (!isSupabaseConfigured()) {
    const room = memoryGetRoomByCode(normalized);
    if (!room) {
      throw new Error(
        "Room not found. Use the same link as the host (e.g. the person who started the room) and check the 4-letter code."
      );
    }
    memoryAddRoomPlayer(room.id, deviceId, nickname.trim() || "Player");
    return { code: room.code };
  }

  const supabase = await createClient();
  const { data: room, error: roomError } = await supabase
    .from("rooms")
    .select("id, code")
    .eq("code", normalized)
    .single();

  if (roomError || !room) {
    throw new Error(
      "Room not found. Check the 4-letter code. If the host is on a different link (e.g. their own tab), everyone must use the same app URL."
    );
  }

  const { error: playerError } = await supabase.from("room_players").insert({
    room_id: room.id,
    device_id: deviceId,
    nickname: nickname.trim() || "Player",
  });

  if (playerError) {
    if (playerError.code === "23505") throw new Error("You're already in this room.");
    throw new Error(playerError.message);
  }

  return { code: room.code };
}

export async function getRoomByCode(code: string) {
  const normalized = code.toUpperCase().replace(/[^A-Z]/g, "").slice(0, 4);
  if (!isSupabaseConfigured()) {
    const room = memoryGetRoomByCode(normalized);
    return room ? { id: room.id, code: room.code, host_device_id: room.host_device_id, created_at: room.created_at } : null;
  }
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("rooms")
    .select("id, code, host_device_id, created_at")
    .eq("code", normalized)
    .single();
  if (error || !data) return null;
  return data;
}

export async function getRoomPlayer(roomId: string, deviceId: string) {
  if (!isSupabaseConfigured()) {
    const p = memoryGetRoomPlayer(roomId, deviceId);
    return p ? { id: p.id, nickname: p.nickname } : null;
  }
  const supabase = await createClient();
  const { data } = await supabase
    .from("room_players")
    .select("id, nickname")
    .eq("room_id", roomId)
    .eq("device_id", deviceId)
    .single();
  return data;
}

/** List all players in a room (for lobby display; works with or without Supabase) */
export async function getRoomPlayersByCode(code: string): Promise<{ nickname: string; device_id: string }[]> {
  const normalized = code.toUpperCase().replace(/[^A-Z]/g, "").slice(0, 4);
  if (!isSupabaseConfigured()) {
    const room = memoryGetRoomByCode(normalized);
    if (!room) return [];
    return memoryGetRoomPlayers(room.id).map((p) => ({ nickname: p.nickname, device_id: p.device_id }));
  }
  const supabase = await createClient();
  const room = await getRoomByCode(normalized);
  if (!room) return [];
  const { data } = await supabase
    .from("room_players")
    .select("nickname, device_id")
    .eq("room_id", room.id);
  return (data ?? []).map((r: { nickname: string; device_id: string }) => ({ nickname: r.nickname, device_id: r.device_id }));
}

export async function getMyRoomPlayerByCode(code: string, deviceId: string) {
  const room = await getRoomByCode(code);
  if (!room) return null;
  return getRoomPlayer(room.id, deviceId);
}
