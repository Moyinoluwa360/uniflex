// Supabase Edge Function: signup  (Pack 5)
//
// The ONLY backend path for creating a student account. Nothing exists in
// auth.users / profiles until `complete` succeeds at the very last step.
//
// Called by the app BEFORE the person is signed in (with the anon key), so
// every action is rate limited per IP / device / phone inside Postgres
// (see supabase/pack_5.sql) and every response is deliberately minimal.
//
// Actions (POST JSON {action: ...}):
//   send     {email, phone, device_id}
//              → checks email+phone are free, THEN sends the Termii SMS.
//              ← {sent:true, cooldown:60}  or  {error: CODE, retry_after?}
//   verify   {phone, code}
//              ← {verified:true, proof, expires_in:1800}
//                {verified:false, attempts_left}   or  {error: CODE}
//              The proof is a random token tied to that phone; only its
//              SHA-256 is stored. Valid 30 min, single use.
//   complete {proof, email, password, phone, nickname, full_name,
//             matric_number?, school, date_of_birth, referral_code?, pin}
//              → validates the proof, re-checks everything is free, creates
//                the auth user (email pre-confirmed) and then calls
//                pack5_finish_signup() (profile + wallet + referral + hashed
//                PIN, one transaction). If that fails the auth user is
//                deleted again — all or nothing.
//              ← {ok:true}  or  {error: CODE}
//
// Secrets (Dashboard → Edge Functions → Secrets):  TERMII_API_KEY
// Auto-injected: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Deploy:  supabase functions deploy signup        (JWT verification stays ON:
//          the app sends its anon key, which is public by design.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const TERMII_BASE = "https://api.ng.termii.com/api";
const COOLDOWN_SECONDS = 60;
const PROOF_TTL_SECONDS = 30 * 60;
const SCHOOLS = ["Redeemer's University"];

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function clientIp(req: Request): string {
  const cf = req.headers.get("cf-connecting-ip");
  if (cf) return cf.trim();
  const xff = req.headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0].trim();
  return "";
}

async function sha256Hex(text: string): Promise<string> {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function newProof(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

const E164 = /^\+[1-9]\d{7,14}$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const KNOWN_ERRORS = [
  "PROOF_INVALID", "PROOF_EXPIRED", "PROOF_USED", "PHONE_TAKEN",
  "NICKNAME_TAKEN", "MATRIC_TAKEN", "REFERRAL_INVALID", "CANNOT_REFER_SELF",
  "INVALID_INPUT",
];

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const termiiKey = Deno.env.get("TERMII_API_KEY") ?? "";
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("signup: Supabase env missing");
    return json({ error: "SERVER_ERROR" }, 500);
  }
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // deno-lint-ignore no-explicit-any
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: "INVALID_INPUT" }, 400);
  }
  const ip = clientIp(req);
  const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");

  // ── send ───────────────────────────────────────────────────────────────
  if (body.action === "send") {
    const email = str(body.email).toLowerCase();
    const phone = str(body.phone);
    const device = str(body.device_id).slice(0, 64);
    if (!EMAIL.test(email) || !E164.test(phone)) {
      return json({ error: "INVALID_INPUT" }, 400);
    }
    if (!termiiKey) {
      console.error("signup: TERMII_API_KEY not set");
      return json({ error: "SERVER_ERROR" }, 500);
    }

    // The availability answer is an enumeration oracle by nature — cap it.
    const { data: allowed } = await admin.rpc("pack5_rate_hit", {
      p_kind: "check_ip", p_key: ip, p_limit: 40, p_window_seconds: 600,
    });
    if (allowed === false) return json({ error: "RATE_LIMITED" }, 429);

    const { data: status, error: statusErr } = await admin.rpc(
      "pack5_identity_status", { p_email: email, p_phone: phone },
    );
    if (statusErr) {
      console.error("identity_status failed:", statusErr.message);
      return json({ error: "SERVER_ERROR" }, 500);
    }
    if (status !== "OK") return json({ error: status }, 409); // before ANY SMS

    const { data: reserve, error: reserveErr } = await admin.rpc(
      "pack5_otp_reserve_send", { p_phone: phone, p_ip: ip, p_device: device },
    );
    if (reserveErr || !reserve) {
      console.error("reserve_send failed:", reserveErr?.message);
      return json({ error: "SERVER_ERROR" }, 500);
    }
    if (!reserve.ok) {
      if (reserve.reason === "TOO_SOON") {
        return json({ error: "TOO_SOON", retry_after: reserve.retry_after }, 429);
      }
      if (reserve.reason === "PHONE_LIMIT") {
        return json({ error: "PHONE_LIMIT" }, 429);
      }
      return json({ error: "RATE_LIMITED" }, 429);
    }

    let pinId: string | null = null;
    try {
      const res = await fetch(`${TERMII_BASE}/sms/otp/send`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        signal: AbortSignal.timeout(20000),
        body: JSON.stringify({
          api_key: termiiKey,
          message_type: "NUMERIC",
          to: phone, // same E.164 form the existing phone-otp function sends
          from: "OE Alert",
          channel: "dnd",
          pin_attempts: 5,
          pin_time_to_live: 10,
          pin_length: 6,
          pin_placeholder: "< 1234 >",
          message_text:
            "Your Uniflex verification code is < 1234 >. This code expires in " +
            "10 minutes. Do not share with anyone.",
        }),
      });
      const t = await res.json();
      if (typeof t?.pinId === "string") pinId = t.pinId;
      else console.warn("Termii send rejected:", t?.message);
    } catch (err) {
      console.error("Termii send failed:", String(err));
    }

    if (!pinId) {
      // Failed sends never count against the person.
      await admin.rpc("pack5_otp_cancel_send", { p_id: reserve.id });
      return json({ error: "SEND_FAILED" }, 502);
    }
    await admin.rpc("pack5_otp_finish_send", {
      p_id: reserve.id, p_pin_id: pinId,
    });
    // Housekeeping on our own temp tables; never blocks the response.
    admin.rpc("pack5_purge_signup_artifacts").then(() => {}, () => {});
    return json({ sent: true, cooldown: COOLDOWN_SECONDS });
  }

  // ── verify ─────────────────────────────────────────────────────────────
  if (body.action === "verify") {
    const phone = str(body.phone);
    const code = str(body.code);
    if (!E164.test(phone) || !/^\d{6}$/.test(code)) {
      return json({ error: "INVALID_INPUT" }, 400);
    }
    if (!termiiKey) return json({ error: "SERVER_ERROR" }, 500);

    const { data: begin, error: beginErr } = await admin.rpc(
      "pack5_otp_begin_verify", { p_phone: phone, p_ip: ip },
    );
    if (beginErr || !begin) {
      console.error("begin_verify failed:", beginErr?.message);
      return json({ error: "SERVER_ERROR" }, 500);
    }
    if (!begin.ok) {
      if (begin.reason === "NO_ACTIVE_CODE") return json({ error: "CODE_EXPIRED" }, 410);
      if (begin.reason === "TOO_MANY_ATTEMPTS") return json({ error: "TOO_MANY_ATTEMPTS" }, 429);
      return json({ error: "RATE_LIMITED" }, 429);
    }

    let verified = false;
    try {
      const res = await fetch(`${TERMII_BASE}/sms/otp/verify`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        signal: AbortSignal.timeout(20000),
        body: JSON.stringify({ api_key: termiiKey, pin_id: begin.pin_id, pin: code }),
      });
      const t = await res.json();
      verified = t?.verified === true || t?.verified === "True" || t?.verified === "true";
    } catch (err) {
      console.error("Termii verify failed:", String(err));
      return json({ error: "SEND_FAILED" }, 502);
    }

    if (!verified) {
      return json({ verified: false, attempts_left: begin.attempts_left });
    }

    const proof = newProof();
    const { error: markErr } = await admin.rpc("pack5_otp_mark_verified", {
      p_id: begin.id, p_proof_hash: await sha256Hex(proof),
    });
    if (markErr) {
      console.error("mark_verified failed:", markErr.message);
      return json({ error: "SERVER_ERROR" }, 500);
    }
    return json({ verified: true, proof, expires_in: PROOF_TTL_SECONDS });
  }

  // ── complete ───────────────────────────────────────────────────────────
  if (body.action === "complete") {
    const proof = str(body.proof);
    const email = str(body.email).toLowerCase();
    const password = typeof body.password === "string" ? body.password : "";
    const phone = str(body.phone);
    const nickname = str(body.nickname);
    const fullName = str(body.full_name);
    const matric = str(body.matric_number);
    const school = str(body.school) || SCHOOLS[0];
    const dob = str(body.date_of_birth);
    const referral = str(body.referral_code);
    const pin = typeof body.pin === "string" ? body.pin : "";

    if (
      !proof || !EMAIL.test(email) || !E164.test(phone) ||
      password.length < 8 || password.length > 72 || !/\d/.test(password) ||
      !nickname || !fullName || !/^\d{4}-\d{2}-\d{2}$/.test(dob) ||
      !/^\d{4}$/.test(pin) || !SCHOOLS.includes(school)
    ) {
      return json({ error: "INVALID_INPUT" }, 400);
    }

    const { data: allowed } = await admin.rpc("pack5_rate_hit", {
      p_kind: "signup_ip", p_key: ip, p_limit: 15, p_window_seconds: 3600,
    });
    if (allowed === false) return json({ error: "RATE_LIMITED" }, 429);

    const proofHash = await sha256Hex(proof);
    const { data: proofStatus, error: proofErr } = await admin.rpc(
      "pack5_proof_status", { p_phone: phone, p_proof_hash: proofHash },
    );
    if (proofErr) return json({ error: "SERVER_ERROR" }, 500);
    if (proofStatus === "EXPIRED") return json({ error: "PROOF_EXPIRED" }, 410);
    if (proofStatus === "USED") return json({ error: "PROOF_USED" }, 409);
    if (proofStatus !== "OK") return json({ error: "PROOF_INVALID" }, 400);

    const { data: pre, error: preErr } = await admin.rpc(
      "pack5_precheck_signup",
      { p_email: email, p_phone: phone, p_nickname: nickname, p_matric: matric },
    );
    if (preErr) return json({ error: "SERVER_ERROR" }, 500);
    if (pre !== "OK") return json({ error: pre }, 409);

    const { data: created, error: createErr } = await admin.auth.admin
      .createUser({ email, password, email_confirm: true });
    if (createErr || !created?.user) {
      const msg = (createErr?.message ?? "").toLowerCase();
      if (msg.includes("already") || msg.includes("registered")) {
        return json({ error: "EMAIL_TAKEN" }, 409);
      }
      console.error("createUser failed:", createErr?.message);
      return json({ error: "SIGNUP_FAILED" }, 500);
    }
    const userId = created.user.id;

    const { error: finishErr } = await admin.rpc("pack5_finish_signup", {
      p_user_id: userId,
      p_proof_hash: proofHash,
      p_email: email,
      p_phone: phone,
      p_nickname: nickname,
      p_full_name: fullName,
      p_matric: matric || null,
      p_school: school,
      p_dob: dob,
      p_referral: referral || null,
      p_pin: pin,
    });

    if (finishErr) {
      // Undo: the database transaction already rolled back; remove the auth user.
      const { error: delErr } = await admin.auth.admin.deleteUser(userId);
      if (delErr) console.error("rollback deleteUser failed:", delErr.message);
      const known = KNOWN_ERRORS.find((c) => finishErr.message.includes(c));
      if (known) return json({ error: known }, 409);
      console.error("finish_signup failed:", finishErr.message);
      return json({ error: "SIGNUP_FAILED" }, 500);
    }

    return json({ ok: true });
  }

  return json({ error: "INVALID_INPUT" }, 400);
});
