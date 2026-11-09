/**
 * push-notification — Supabase Edge Function  (Pack 4A)
 *
 * The ONE place a push is sent for an in-app notification. A database
 * trigger on `public.notifications` (AFTER INSERT) calls it with the row,
 * so every notification — order events, support messages, free-text
 * messages from Admin / a rider — is pushed from the same code path and
 * always has an inbox row to match.
 *
 * Auth: service-role key only (the database trigger sends it; clients can
 * never call this). Same pattern as support-notify.
 *
 * Body (either shape is accepted):
 *   { notification_id, user_id, title, body, type, order_id, group_id,
 *     conversation_id }                       ← pg_net trigger
 *   { type: 'INSERT', record: { …same fields… } }  ← Database Webhook
 *
 * The push carries data { type, notification_id, order_id, group_id,
 * conversation_id } (strings only — FCM requires that) so tapping it can
 * open the right screen, including from a cold start.
 *
 * Deploy:   supabase functions deploy push-notification --no-verify-jwt
 *           supabase functions deploy send-notification --no-verify-jwt
 *           supabase secrets set PUSH_TRIGGER_SECRET=<your sb_secret_ key>
 *           (a sb_secret_ key is not a JWT, so the gateway's JWT check must
 *           be off; the function checks the key itself.)
 * Secrets:  FIREBASE_SERVICE_ACCOUNT_JSON is used by send-notification
 *           (already set). SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are
 *           injected by the runtime.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

type Row = {
  notification_id?: string
  id?: string
  user_id?: string
  title?: string
  body?: string
  type?: string | null
  order_id?: string | null
  group_id?: string | null
  conversation_id?: string | null
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const presented = (req.headers.get('Authorization') ?? '')
    .replace(/^Bearer\s+/i, '')
    .trim()
  // New-style `sb_secret_…` keys are not JWTs: accept them via the
  // PUSH_TRIGGER_SECRET function secret (deploy with --no-verify-jwt).
  const triggerSecret = Deno.env.get('PUSH_TRIGGER_SECRET') ?? ''
  const authorised =
    presented !== '' &&
    ((serviceKey !== '' && presented === serviceKey) ||
      (triggerSecret !== '' && presented === triggerSecret))
  if (!authorised) {
    return json({ error: 'Unauthorized' }, 401)
  }
  // Key used for our own calls: prefer the secret key when one is configured.
  const callKey = triggerSecret || serviceKey

  let payload: Row & { record?: Row }
  try {
    payload = await req.json()
  } catch {
    return json({ error: 'Invalid JSON body' }, 400)
  }

  const row: Row = payload.record ?? payload
  const notificationId = row.notification_id ?? row.id ?? ''
  const userId = row.user_id ?? ''
  const title = row.title ?? ''
  const body = row.body ?? ''
  if (!userId || !title || !body) {
    return json({ error: 'user_id, title and body are required' }, 400)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const admin = createClient(supabaseUrl, callKey)

  // Every phone this person is signed in on (push_devices), plus the legacy
  // single token as a fallback for old builds / before the table exists.
  const tokens = new Set<string>()
  {
    const { data: devices } = await admin
      .from('push_devices')
      .select('token')
      .eq('user_id', userId)
    for (const d of devices ?? []) if (d.token) tokens.add(d.token as string)

    const { data: profile } = await admin
      .from('profiles')
      .select('fcm_token')
      .eq('id', userId)
      .maybeSingle()
    if (profile?.fcm_token) tokens.add(profile.fcm_token as string)
  }

  if (tokens.size === 0) {
    // The inbox row already exists; there is just no device to push to.
    return json({ delivered: 'inbox_only', reason: 'no device token' })
  }

  // FCM data values must be strings; omit anything empty.
  const data: Record<string, string> = {}
  if (row.type) data.type = String(row.type)
  if (notificationId) data.notification_id = String(notificationId)
  if (row.order_id) data.order_id = String(row.order_id)
  if (row.group_id) data.group_id = String(row.group_id)
  if (row.conversation_id) data.conversation_id = String(row.conversation_id)

  // A token is only dropped when FCM says the phone itself is gone. Any
  // other failure (our payload, Apple/Google outage, bad credentials) keeps
  // the token — wiping it would silence a perfectly good phone.
  const isDeadToken = (status: number, text: string): boolean => {
    let code = ''
    let message = ''
    try {
      const parsed = JSON.parse(text)
      code = parsed?.error?.details?.[0]?.errorCode ?? parsed?.error?.status ?? ''
      message = String(parsed?.error?.message ?? '')
    } catch { /* not JSON */ }
    if (code === 'UNREGISTERED' || code === 'NOT_FOUND') return true
    return code === 'INVALID_ARGUMENT' && /registration token/i.test(message)
  }

  let sent = 0
  let failed = 0
  await Promise.all(
    [...tokens].map(async (token) => {
      try {
        const res = await fetch(`${supabaseUrl}/functions/v1/send-notification`, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${callKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ token, title, body, data }),
        })
        if (res.ok) {
          sent++
          return
        }
        failed++
        const text = await res.text()
        console.warn(
          `Push failed for user ${userId} token ${token.slice(0, 10)}…: ${res.status} ${text}`,
        )
        if (isDeadToken(res.status, text)) {
          await admin.from('push_devices').delete().eq('token', token)
          await admin.from('profiles').update({ fcm_token: null }).eq('fcm_token', token)
        }
      } catch (err) {
        failed++
        console.warn(`Push request threw for user ${userId}:`, err)
      }
    }),
  )

  if (sent === 0) {
    return json({ delivered: 'inbox_only', reason: 'push failed', failed })
  }
  return json({ delivered: 'push', sent, failed })

})
