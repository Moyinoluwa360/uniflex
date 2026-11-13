// Pack 2 / S-11 — API keys for Edge Functions, new style first.
//
// Supabase injects the new keys as JSON dictionaries keyed by name:
//   SUPABASE_SECRET_KEYS       e.g. {"default":"sb_secret_…"}
//   SUPABASE_PUBLISHABLE_KEYS  e.g. {"default":"sb_publishable_…"}
// and the legacy JWT keys as SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY.
//
// These helpers return the new key ("default", else the first one) and fall
// back to the legacy key, so the functions work both BEFORE and AFTER the
// legacy keys are disabled in Dashboard → Settings → API Keys.

function fromDictionary(name: string): string {
  try {
    const raw = Deno.env.get(name);
    if (!raw) return "";
    const dict = JSON.parse(raw) as Record<string, string>;
    return dict["default"] ?? Object.values(dict)[0] ?? "";
  } catch {
    return "";
  }
}

/** Server key that bypasses RLS — never return it or log it. */
export function serviceKey(): string {
  return fromDictionary("SUPABASE_SECRET_KEYS") ||
    (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
}

/** Public key, used with the caller's own JWT so RLS applies. */
export function publishableKey(): string {
  return fromDictionary("SUPABASE_PUBLISHABLE_KEYS") ||
    (Deno.env.get("SUPABASE_ANON_KEY") ?? "");
}

/** Every server key currently valid (new ones + legacy), for comparing a
 *  key presented by a trusted caller such as the database trigger. */
export function allServiceKeys(): string[] {
  const keys: string[] = [];
  try {
    const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
    if (raw) keys.push(...Object.values(JSON.parse(raw) as Record<string, string>));
  } catch { /* ignore */ }
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) keys.push(legacy);
  return keys.filter((k) => k !== "");
}
