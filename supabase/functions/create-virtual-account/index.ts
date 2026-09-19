// Supabase Edge Function: create-virtual-account
//
// Attempts to issue a real Paystack Dedicated Virtual Account (NUBAN)
// for the calling student. Dedicated Virtual Accounts typically require
// Paystack business verification, which may not be complete for this
// project yet. If Paystack returns any error (plan not enabled, test-mode
// limitation, etc.) this function falls back gracefully: it returns the
// student's existing placeholder VAN and sets is_real_account: false in
// the response so the UI can show an appropriate "pending" message.
//
// TODO: revisit once business verification with Paystack is complete.
// At that point, the DVA API should succeed in both test and live modes.
//
// Deploy:
//   supabase functions deploy create-virtual-account --no-verify-jwt
//
// Required secrets (set in Supabase dashboard → Edge Functions → Secrets):
//   PAYSTACK_SECRET_KEY=sk_test_...
// The following are injected automatically by the Supabase runtime:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // ── Authenticate ─────────────────────────────────────────────────────
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(
      JSON.stringify({ error: "Missing Authorization header" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const paystackSecretKey = Deno.env.get("PAYSTACK_SECRET_KEY") ?? "";

  const adminClient = createClient(supabaseUrl, serviceRoleKey);
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

  // ── Fetch existing wallet for fallback VAN ───────────────────────────
  const { data: wallet, error: walletError } = await adminClient
    .from("wallets")
    .select("virtual_account_number")
    .eq("user_id", user.id)
    .maybeSingle();

  if (walletError || !wallet) {
    return new Response(
      JSON.stringify({ error: "Wallet not found" }),
      { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const placeholderVan: string = wallet.virtual_account_number as string;

  // If already a real account (not the UFX- placeholder), return it
  if (!placeholderVan.startsWith("UFX-")) {
    return new Response(
      JSON.stringify({
        account_number: placeholderVan,
        bank_name: "Wema Bank",
        is_real_account: true,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  if (!paystackSecretKey) {
    console.warn("PAYSTACK_SECRET_KEY not set — falling back to placeholder VAN");
    return _fallbackResponse(placeholderVan, corsHeaders);
  }

  // ── Fetch profile for customer creation ──────────────────────────────
  const { data: profile } = await adminClient
    .from("profiles")
    .select("email, full_name, phone")
    .eq("id", user.id)
    .maybeSingle();

  const email: string = (profile?.email as string | undefined) ?? user.email ?? "";
  const fullName: string = (profile?.full_name as string | undefined) ?? "Uniflex Student";

  try {
    // ── Step 1: Create or retrieve a Paystack customer ────────────────
    const customerRes = await fetch("https://api.paystack.co/customer", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${paystackSecretKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email,
        first_name: fullName.split(" ")[0] ?? fullName,
        last_name: fullName.split(" ").slice(1).join(" ") || "—",
        phone: profile?.phone ?? undefined,
      }),
    });

    const customerData = await customerRes.json();
    if (!customerData.status) {
      console.warn("Paystack customer creation failed:", customerData.message);
      return _fallbackResponse(placeholderVan, corsHeaders);
    }

    const customerCode: string = customerData.data.customer_code;

    // ── Step 2: Request a Dedicated Virtual Account (NUBAN) ───────────
    // NOTE: This API call typically requires business verification with
    // Paystack. In test mode without verification it will return an error.
    // The fallback path handles this gracefully.
    const dvaRes = await fetch("https://api.paystack.co/dedicated_account", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${paystackSecretKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        customer: customerCode,
        preferred_bank: "test-bank", // sandbox bank for Paystack test mode
      }),
    });

    const dvaData = await dvaRes.json();

    if (!dvaData.status || !dvaData.data?.account_number) {
      console.warn(
        "Paystack DVA creation failed (likely needs business verification):",
        dvaData.message,
      );
      // TODO: revisit after Paystack business verification is complete.
      return _fallbackResponse(placeholderVan, corsHeaders);
    }

    const accountNumber: string = dvaData.data.account_number;
    const bankName: string = dvaData.data.bank?.name ?? "Wema Bank";

    // ── Step 3: Persist the real VAN in the wallets table ────────────
    await adminClient
      .from("wallets")
      .update({ virtual_account_number: accountNumber })
      .eq("user_id", user.id);

    return new Response(
      JSON.stringify({
        account_number: accountNumber,
        bank_name: bankName,
        is_real_account: true,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("create-virtual-account unexpected error:", err);
    return _fallbackResponse(placeholderVan, corsHeaders);
  }
});

function _fallbackResponse(
  placeholderVan: string,
  headers: Record<string, string>,
): Response {
  return new Response(
    JSON.stringify({
      account_number: placeholderVan,
      bank_name: "Uniflex (Pending Activation)",
      is_real_account: false,
    }),
    { status: 200, headers: { ...headers, "Content-Type": "application/json" } },
  );
}
