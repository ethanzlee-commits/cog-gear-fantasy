const PLACEHOLDER_KEY_PATTERNS = /^(your-anon-key|your_supabase_anon_key|xxx|)$/i;

/**
 * Whether Supabase is configured with a real project (not placeholder).
 * When false, the app uses in-memory store for the lobby.
 */
export function isSupabaseConfigured(): boolean {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (typeof url !== "string" || url.length === 0) return false;
  if (url.includes("your-project") || url.includes("xxx.supabase.co")) return false;
  if (typeof key !== "string" || key.length === 0) return false;
  if (PLACEHOLDER_KEY_PATTERNS.test(key.trim())) return false;
  return true;
}
