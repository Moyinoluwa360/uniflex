// Supabase Edge Function: notify-user
//
// The one authorized way to notify a customer about their order. Called by
// the Admin app (kitchen queue) and the Rider app.
//
// Two modes:
//   kind: 'order_status' — the copy is derived here from the order's
//                          current status, so the wording lives in one
//                          place instead of being retyped per caller.
//   kind: 'message'      — free text typed by Admin or the assigned Rider.
//
// Authorization is delegated to can_notify_order(), which allows an active
// admin, or the rider currently assigned to that order. A student can
// never notify anyone.
//
// Why this exists rather than calling send-notification directly:
// send-notification takes a raw FCM device token, so exposing it to the
// client would mean handing out other people's push tokens. This function
// resolves the token server-side and never returns it.
//
// Deploy:
//   supabase functions deploy notify-user
//
// Auto-injected by the Supabase runtime:
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/// Customer-facing copy for each order status. Returning null means "this
/// status is not worth a push" — the client fires on every change and we
/// filter here rather than making every caller know the rules.
function copyForStatus(
  status: string,
  isDelivery: boolean,
  riderName: string | null,
): { title: string; body: string } | null {
  switch (status) {
    case "placed":
      return {
        title: "Order received",
        body: "We have your order — it is queued for the kitchen.",
      };
    case "preparing":
      return {
        title: "Your order is being prepared",
        body: "The kitchen has started on it.",
      };
    case "ready":
      return isDelivery
        ? {
          title: "Your order is ready",
          body: "It is packed and waiting for a rider.",
        }
        : {
          title: "Your order is ready",
          body: "Come and collect it whenever you are ready.",
        };
    case "ready_for_pickup":
      return {
        title: "Ready for pickup",
        body: "Your order is at the counter waiting for you.",
      };
    case "out_for_delivery":
      return {
        title: "On the way",
        body: riderName
          ? `${riderName} is on the way with your order.`
          : "Your rider is on the way with your order.",
      };
    case "completed":
      return isDelivery
        ? { title: "Delivered", body: "Enjoy your meal." }
        : { title: "Order complete", body: "Enjoy your meal." };
    case "cancelled":
      return {
        title: "Order cancelled",
        body: "Your order was cancelled and the amount refunded to your wallet.",
      };
    default:
      return null;
  }
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

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: { order_id?: string; kind?: string; message?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const orderId = (body.order_id ?? "").trim();
  const kind = body.kind === "order_status" ? "order_status" : "message";
  if (!orderId) {
    return json({ error: "order_id is required" }, 400);
  }

  // ── Is this caller allowed to notify about this order? ──────────────
  const { data: allowed, error: allowedError } = await adminClient.rpc(
    "can_notify_order",
    { p_order_id: orderId, p_actor: user.id },
  );
  if (allowedError) {
    console.error("can_notify_order failed:", allowedError);
    return json({ error: "Could not send notification." }, 500);
  }
  if (allowed !== true) {
    return json({ error: "You cannot notify the customer on this order." }, 403);
  }

  const { data: order, error: orderError } = await adminClient
    .from("orders")
    .select("id, student_id, status, delivery_type, rider_id")
    .eq("id", orderId)
    .maybeSingle();

  if (orderError || !order) {
    return json({ error: "Order not found" }, 404);
  }

  // ── Work out what to say ────────────────────────────────────────────
  let title: string;
  let messageBody: string;

  if (kind === "order_status") {
    const isDelivery = ["delivery", "campus_delivery", "hostel_delivery"]
      .includes(order.delivery_type as string);

    let riderName: string | null = null;
    if (order.rider_id) {
      const { data: rider } = await adminClient
        .from("profiles")
        .select("full_name, nickname")
        .eq("id", order.rider_id)
        .maybeSingle();
      riderName = (rider?.nickname as string | null) ??
        (rider?.full_name as string | null) ?? null;
      // First name only — the student does not need the rider's full name
      // in a push notification.
      if (riderName) riderName = riderName.split(" ")[0];
    }

    const copy = copyForStatus(
      order.status as string,
      isDelivery,
      riderName,
    );
    if (copy === null) {
      return json({ skipped: true, reason: "status not notifiable" });
    }
    title = copy.title;
    messageBody = copy.body;
  } else {
    const text = (body.message ?? "").trim();
    if (text === "") {
      return json({ error: "message is required" }, 400);
    }
    if (text.length > 300) {
      return json({ error: "Message is too long (300 characters max)." }, 400);
    }
    title = "Message about your order";
    messageBody = text;
  }

  // ── Record it in the in-app inbox ───────────────────────────────────
  // This is the durable half: it works even with no FCM token, and the
  // student sees it next time they open the app.
  const { error: insertError } = await adminClient
    .from("notifications")
    .insert({
      user_id: order.student_id,
      title,
      body: messageBody,
      kind,
      order_id: order.id,
      sent_by: user.id,
    });

  if (insertError) {
    console.error("Could not record notification:", insertError);
    return json({ error: "Could not send notification." }, 500);
  }

  // ── Best-effort push ────────────────────────────────────────────────
  const { data: recipient } = await adminClient
    .from("profiles")
    .select("fcm_token")
    .eq("id", order.student_id)
    .maybeSingle();

  const token = recipient?.fcm_token as string | null | undefined;
  if (!token) {
    return json({ delivered: "inbox_only", reason: "no device token" });
  }

  try {
    const pushRes = await fetch(
      `${supabaseUrl}/functions/v1/send-notification`,
      {
        method: "POST",
        headers: {
          // send-notification only accepts the service role, so that a
          // client cannot push to an arbitrary device token.
          Authorization: `Bearer ${serviceRoleKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          token,
          title,
          body: messageBody,
          data: { order_id: order.id, kind },
        }),
      },
    );

    if (!pushRes.ok) {
      console.warn(
        `Push failed for order ${order.id}: ${pushRes.status} ${await pushRes.text()}`,
      );
      return json({ delivered: "inbox_only", reason: "push failed" });
    }
  } catch (err) {
    console.warn("Push request threw:", err);
    return json({ delivered: "inbox_only", reason: "push error" });
  }

  return json({ delivered: "push" });
});
