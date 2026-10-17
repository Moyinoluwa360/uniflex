// Supabase Edge Function: phone-otp
//
// Sends and verifies Termii phone OTPs on the server side.
//
// Why this exists (audit 2026-09-27, findings #2 and #6):
//
//   1. TERMII_API_KEY used to be read by the Flutter client from the
//      bundled .env, which ships inside the APK. Anyone could extract it
//      and send SMS on this project's account indefinitely. The key now
//      lives only in this function's secrets.
//
//   2. Verification used to be decided by the client: it asked Termii,
//      got a boolean, and then wrote profiles.phone_verified_at itself.
//      Nothing tied "Termii approved" to "the column got set", so the
//      whole gate could be skipped. Now only this function — holding the
//      service role — writes that column, and only after Termii confirms.
//
// Deploy:
//   supabase functions deploy phone-otp
//
// Required secrets (Dashboard → Edge Functions → Secrets):
//   TERMII_API_KEY=...
// Auto-injected by the Supabase runtime:
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const TERMII_BASE = "https://api.ng.termii.com/api";

/// Max OTP sends per user per rolling hour. Termii bills per message, so
/// an uncapped endpoint is a direct cost-of-service problem even with
/// auth required.
const SEND_LIMIT_PER_HOUR = 5;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing Authorization header" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const apiKey = Deno.env.get("TERMII_API_KEY") ?? "";

  if (!apiKey) {
    console.error("TERMII_API_KEY is not set in Edge Function secrets");
    return json({ error: "Verification service misconfigured" }, 500);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: {
    action?: string;
    phone?: string;
    pin_id?: string;
    pin?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  // ── send ─────────────────────────────────────────────────────────────
  if (body.action === "send") {
    const phone = (body.phone ?? "").trim();
    if (!/^\+[1-9]\d{7,14}$/.test(phone)) {
      return json({ error: "Phone number must be in E.164 form" }, 400);
    }

    // Rolling-hour rate limit, counted server-side per user.
    const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count, error: countError } = await adminClient
      .from("otp_send_log")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("sent_at", since);

    if (countError) {
      console.error("otp_send_log count failed:", countError);
      return json({ error: "Could not send verification code." }, 500);
    }
    if ((count ?? 0) >= SEND_LIMIT_PER_HOUR) {
      return json(
        {
          error:
            "Too many codes requested. Please wait a while before trying again.",
        },
        429,
      );
    }

    let termii: Record<string, unknown>;
    try {
      const res = await fetch(`${TERMII_BASE}/sms/otp/send`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          api_key: apiKey,
          message_type: "NUMERIC",
          to: phone,
          from: "OE Alert",
          channel: "generic",
          pin_attempts: 3,
          pin_time_to_live: 10,
          pin_length: 6,
          pin_placeholder: "< 1234 >",
          message_text:
            "Your Uniflex verification code is < 1234 >. This code expires in " +
            "10 minutes. Do not share with anyone.",
        }),
      });
      termii = await res.json();
    } catch (err) {
      console.error("Termii send failed:", err);
      return json({ error: "Could not reach the SMS provider." }, 502);
    }

    const pinId = termii["pinId"];
    if (typeof pinId !== "string") {
      console.warn("Termii send rejected:", termii["message"]);
      return json(
        { error: (termii["message"] as string) ?? "Could not send verification code." },
        400,
      );
    }

    await adminClient.from("otp_send_log").insert({ user_id: user.id });

    return json({ pin_id: pinId });
  }

  // ── verify ───────────────────────────────────────────────────────────
  if (body.action === "verify") {
    const pinId = (body.pin_id ?? "").trim();
    const pin = (body.pin ?? "").trim();
    const phone = (body.phone ?? "").trim();

    if (!pinId || !pin) {
      return json({ error: "pin_id and pin are required" }, 400);
    }
    if (!/^\+[1-9]\d{7,14}$/.test(phone)) {
      return json({ error: "Phone number must be in E.164 form" }, 400);
    }

    let termii: Record<string, unknown>;
    try {
      const res = await fetch(`${TERMII_BASE}/sms/otp/verify`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ api_key: apiKey, pin_id: pinId, pin }),
      });
      termii = await res.json();
    } catch (err) {
      console.error("Termii verify failed:", err);
      return json({ error: "Could not reach the SMS provider." }, 502);
    }

    const raw = termii["verified"];
    const verified = raw === true || raw === "True" || raw === "true";

    if (!verified) {
      return json({ verified: false });
    }

    // Only this function writes phone_verified_at, and only here — after
    // Termii has confirmed the code for this specific pin_id.
    const { error: updateError } = await adminClient
      .from("profiles")
      .update({
        phone: phone,
        phone_verified_at: new Date().toISOString(),
      })
      .eq("id", user.id);

    if (updateError) {
      console.error("Could not record phone verification:", updateError);
      return json({ error: "Could not record verification." }, 500);
    }

    return json({ verified: true });
  }

  return json({ error: "Unknown action" }, 400);
});
