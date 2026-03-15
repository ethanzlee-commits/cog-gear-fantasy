import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!url || !key) {
  throw new Error(
    "Missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY in .env.local"
  );
}

/**
 * Simple Supabase client: createClient(url, anonKey).
 * Use in server-side code (API routes, server actions, scripts).
 * For Client Components use createClient() from @/lib/supabase/client instead.
 */
export const supabase = createClient(url, key);
