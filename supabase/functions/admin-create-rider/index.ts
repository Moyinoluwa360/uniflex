// Supabase Edge Function: admin-create-rider
//
// Post-testing fixes, Section 7 — lets Admin invite a new Rider account
// from inside the app instead of seeding one by hand in the Supabase
// dashboard (Phase 1's original pattern). Still invite-only: this
// function is never reachable from anywhere a student could hit it, and
// there is still no public Rider signup screen.
//
// Creating an auth.users row requires the Supabase Admin API
// (`auth.admin.createUser`), which needs the service-role key — hence an
// Edge Function rather than a client-side RPC.
//
// Deploy:
//   supabase functions deploy admin-create-rider --no-verify-jwt
//
// No extra secrets needed beyond the ones Supabase injects automatically:
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200) {
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
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  // ── 1. Authenticate the caller and confirm they're an admin ──────────
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  const { data: isAdmin, error: isAdminError } = await userClient.rpc("is_admin");
  if (isAdminError || !isAdmin) {
    return jsonResponse({ error: "Only Admin can create Rider accounts" }, 403);
  }

  // ── 2. Parse and validate the request body ───────────────────────────
  let body: {
    email?: string;
    password?: string;
    full_name?: string;
    phone?: string;
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const { email, password, full_name, phone } = body;
  if (!email || !password || !full_name) {
    return jsonResponse(
      { error: "email, password, and full_name are required" },
      400,
    );
  }
  // A phone number is required: the student's tracking screen offers to call
  // their assigned rider, and a rider seeded without one leaves that with
  // nothing to dial.
  if (!phone || phone.trim().length < 7) {
    return jsonResponse({ error: "A valid phone number is required" }, 400);
  }
  if (password.length < 8) {
    return jsonResponse({ error: "Password must be at least 8 characters" }, 400);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  // ── 3. Create the Auth user ────────────────────────────────────────
  const { data: created, error: createError } = await adminClient.auth.admin
    .createUser({
      email,
      password,
      email_confirm: true,
    });

  if (createError || !created.user) {
    return jsonResponse(
      { error: createError?.message ?? "Could not create the account" },
      400,
    );
  }

  // ── 4. Write the profiles row (role='rider', already onboarded) ─────
  const { error: profileError } = await adminClient.from("profiles").insert({
    id: created.user.id,
    role: "rider",
    email,
    full_name,
    phone: phone.trim(),
    onboarding_complete: true,
    is_active: true,
  });

  if (profileError) {
    // Roll back the orphaned auth user so a failed invite doesn't leave a
    // dangling account with no profile.
    await adminClient.auth.admin.deleteUser(created.user.id);
    return jsonResponse({ error: profileError.message }, 500);
  }

  return jsonResponse({ success: true, rider_id: created.user.id });
});
