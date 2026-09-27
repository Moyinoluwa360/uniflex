// Supabase Edge Function: paystack-webhook
//
// Credits a student's wallet when Paystack reports a successful charge
// that the app never saw — specifically, a bank transfer into the
// student's Dedicated Virtual Account (DVA).
//
// Why this exists (audit 2026-09-27, finding #15):
//
//   create-virtual-account can issue a real Paystack DVA and the wallet
//   screen shows that account number to the student as somewhere to send
//   money. But the ONLY credit path in the system was
//   verify-paystack-payment, which the client calls after an in-app
//   checkout. A bank transfer into the DVA produced no client callback at
//   all, so the money arrived at Paystack and never reached the wallet.
//   This closes that loop.
//
// Deploy (must be public — Paystack is not a Supabase user, so the
// gateway must not demand a Supabase JWT; authenticity is proven by the
// HMAC signature instead):
//   supabase functions deploy paystack-webhook --no-verify-jwt
//
// Then register the URL in the Paystack dashboard under
// Settings → API Keys & Webhooks → Webhook URL:
//   https://<project-ref>.supabase.co/functions/v1/paystack-webhook
//
// Required secrets (Dashboard → Edge Functions → Secrets):
//   PAYSTACK_SECRET_KEY=sk_...
// Auto-injected by the Supabase runtime:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/// Constant-time comparison, so a caller cannot narrow in on the expected
/// signature by timing our rejections.
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

async function hmacSha512Hex(key: string, message: string): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(key),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    cryptoKey,
    new TextEncoder().encode(message),
  );
  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const secret = Deno.env.get("PAYSTACK_SECRET_KEY") ?? "";
  if (!secret) {
    console.error("PAYSTACK_SECRET_KEY is not set in Edge Function secrets");
    return new Response("Misconfigured", { status: 500 });
  }

  // The signature covers the exact bytes Paystack sent, so the body must be
  // read as raw text and only parsed AFTER verification.
  const rawBody = await req.text();
  const presented = req.headers.get("x-paystack-signature") ?? "";
  const expected = await hmacSha512Hex(secret, rawBody);

  if (!presented || !timingSafeEqual(presented, expected)) {
    console.warn("Rejected webhook with an invalid signature");
    return new Response("Invalid signature", { status: 401 });
  }

  let event: {
    event?: string;
    data?: {
      status?: string;
      amount?: number;
      currency?: string;
      reference?: string;
      customer?: { email?: string };
      metadata?: { user_id?: string } | string | null;
      authorization?: { receiver_bank_account_number?: string };
    };
  };
  try {
    event = JSON.parse(rawBody);
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  // Acknowledge anything we don't act on — Paystack retries non-2xx, and
  // it sends many event types we have no interest in.
  if (event.event !== "charge.success" || event.data?.status !== "success") {
    return new Response(JSON.stringify({ ignored: true }), { status: 200 });
  }

  const data = event.data;
  if (data.currency !== "NGN") {
    return new Response(JSON.stringify({ ignored: "currency" }), { status: 200 });
  }

  const reference = data.reference;
  const amountNaira = (data.amount ?? 0) / 100;
  if (!reference || !Number.isFinite(amountNaira) || amountNaira <= 0) {
    return new Response(JSON.stringify({ ignored: "shape" }), { status: 200 });
  }

  const adminClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // ── Work out whose wallet this belongs to ───────────────────────────
  // Three strategies, most specific first.
  let userId: string | null = null;

  const metadata = typeof data.metadata === "object" && data.metadata !== null
    ? data.metadata
    : null;
  if (typeof metadata?.user_id === "string") {
    userId = metadata.user_id;
  }

  const receivingAccount = data.authorization?.receiver_bank_account_number;
  if (!userId && receivingAccount) {
    const { data: wallet } = await adminClient
      .from("wallets")
      .select("user_id")
      .eq("virtual_account_number", receivingAccount)
      .maybeSingle();
    userId = (wallet?.user_id as string | undefined) ?? null;
  }

  const payerEmail = data.customer?.email;
  if (!userId && payerEmail) {
    const { data: profile } = await adminClient
      .from("profiles")
      .select("id")
      .ilike("email", payerEmail)
      .maybeSingle();
    userId = (profile?.id as string | undefined) ?? null;
  }

  if (!userId) {
    // Still acknowledge, so Paystack stops retrying, but log loudly — this
    // is money that arrived and could not be attributed.
    console.error(
      `UNATTRIBUTED PAYMENT: reference=${reference} amount=${amountNaira} ` +
        `email=${payerEmail ?? "none"} account=${receivingAccount ?? "none"}`,
    );
    return new Response(JSON.stringify({ unattributed: true }), { status: 200 });
  }

  // credit_wallet raises DUPLICATE_REFERENCE if this reference was already
  // credited (by verify-paystack-payment, or by an earlier delivery of this
  // same webhook), which is what makes retries safe.
  const { error } = await adminClient.rpc("credit_wallet", {
    p_user_id: userId,
    p_amount: amountNaira,
    p_reference: reference,
  });

  if (error) {
    if (error.message.includes("DUPLICATE_REFERENCE")) {
      return new Response(JSON.stringify({ duplicate: true }), { status: 200 });
    }
    console.error("credit_wallet failed for webhook:", error);
    // Non-2xx so Paystack retries — the money is real and unlanded.
    return new Response("Could not credit wallet", { status: 500 });
  }

  return new Response(JSON.stringify({ credited: amountNaira }), {
    status: 200,
  });
});
