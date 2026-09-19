// Supabase Edge Function: verify-paystack-payment
//
// Receives a Paystack reference from the Flutter client after a checkout
// session, verifies the payment server-side using the secret key, and —
// if verified — atomically credits the student's wallet via the
// credit_wallet Postgres RPC.
//
// PAYSTACK_SECRET_KEY is read from Deno.env (set in the Supabase
// dashboard under Edge Functions → Secrets). It is NEVER bundled into
// the Flutter app or stored in .env on the client.
//
// Deploy:
//   supabase functions deploy verify-paystack-payment --no-verify-jwt
// (--no-verify-jwt lets the function handle auth itself via the JWT in
//  the Authorization header, which is the standard Supabase pattern)
//
// Required secrets (set in Supabase dashboard → Edge Functions → Secrets):
//   PAYSTACK_SECRET_KEY=sk_test_...
// The following are injected automatically by the Supabase runtime:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // ── 1. Authenticate the calling user via their Supabase JWT ─────────
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(
      JSON.stringify({ error: "Missing Authorization header" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  // Admin client (service-role) — used for DB writes that bypass RLS
  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  // User client — used only to resolve the JWT to a user ID
  const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // ── 2. Parse and validate the request body ───────────────────────────
  let body: { reference?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(
      JSON.stringify({ error: "Invalid JSON body" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const { reference } = body;
  if (!reference || typeof reference !== "string") {
    return new Response(
      JSON.stringify({ error: "Missing or invalid 'reference' field" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // ── 3. Verify the payment with Paystack ──────────────────────────────
  const paystackSecretKey = Deno.env.get("PAYSTACK_SECRET_KEY") ?? "";
  if (!paystackSecretKey) {
    console.error("PAYSTACK_SECRET_KEY is not set in Edge Function secrets");
    return new Response(
      JSON.stringify({ error: "Payment service misconfigured" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  let paystackData: {
    status: boolean;
    data?: {
      status: string;
      amount: number;   // in kobo
      currency: string;
      reference: string;
    };
  };

  try {
    const paystackRes = await fetch(
      `https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,
      {
        headers: {
          Authorization: `Bearer ${paystackSecretKey}`,
          "Content-Type": "application/json",
        },
      },
    );
    paystackData = await paystackRes.json();
  } catch (err) {
    console.error("Paystack API request failed:", err);
    return new Response(
      JSON.stringify({ error: "Could not reach Paystack API" }),
      { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  if (
    !paystackData.status ||
    !paystackData.data ||
    paystackData.data.status !== "success"
  ) {
    return new Response(
      JSON.stringify({ error: "payment_not_successful" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  if (paystackData.data.currency !== "NGN") {
    return new Response(
      JSON.stringify({ error: "Unexpected currency" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // Paystack stores amounts in kobo — convert to naira
  const amountNaira = paystackData.data.amount / 100;

  // ── 4. Credit the wallet via the SECURITY DEFINER RPC ───────────────
  const { data: rpcResult, error: rpcError } = await adminClient.rpc(
    "credit_wallet",
    {
      p_user_id: user.id,
      p_amount: amountNaira,
      p_reference: reference,
    },
  );

  if (rpcError) {
    if (rpcError.message.includes("DUPLICATE_REFERENCE")) {
      // Idempotent: this reference was already credited — return success
      // so the client doesn't retry indefinitely.
      return new Response(
        JSON.stringify({ duplicate: true, message: "Already processed" }),
        { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    console.error("credit_wallet RPC error:", rpcError);
    return new Response(
      JSON.stringify({ error: "Failed to credit wallet" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  return new Response(
    JSON.stringify({ success: true, balance: (rpcResult as { balance: number }).balance }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
