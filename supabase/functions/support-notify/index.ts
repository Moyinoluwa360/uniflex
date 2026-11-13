/**
 * support-notify — Supabase Edge Function
 *
 * Sends a push notification after a new support message is created.
 * Called by the pg_net database trigger OR a Supabase Database Webhook
 * on INSERT into support_messages.
 *
 * Routing:
 *   sender_role = 'student' → push to ALL admin users with an FCM token
 *   sender_role = 'admin'   → push to the student who owns the conversation
 *
 * Notification payload:
 *   title: sender's name ("Uniflex Support" for admin messages)
 *   body:  message preview (first 100 chars)
 *   data:  { type: 'support', conversation_id: '...' }
 *
 * Deploy:
 *   supabase functions deploy support-notify
 *
 * Required secrets (auto-injected by Supabase runtime):
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 *
 * Invalid / expired FCM tokens are cleared from profiles.fcm_token so
 * stale devices do not accumulate.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { serviceKey, allServiceKeys } from "../_shared/keys.ts";

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

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  // This function is only called by the database trigger or webhook,
  // both of which supply the service-role key.
  const svcKey = serviceKey() ?? ''
  const presented = (req.headers.get('Authorization') ?? '')
    .replace(/^Bearer\s+/i, '')
    .trim()
  if (!allServiceKeys().includes(presented)) {
    return json({ error: 'Unauthorized' }, 401)
  }

  let body: {
    message_id?: string
    conversation_id?: string
    sender_id?: string
    sender_role?: string
    sender_name?: string
    body?: string
  }
  try {
    body = await req.json()
  } catch {
    return json({ error: 'Invalid JSON body' }, 400)
  }

  const {
    conversation_id: conversationId,
    sender_role: senderRole,
    sender_name: senderName,
    body: messageBody,
  } = body

  if (!conversationId || !senderRole || !senderName || !messageBody) {
    return json({ error: 'Missing required fields' }, 400)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const admin = createClient(supabaseUrl, svcKey)

  // Resolve notification content.
  const title = senderRole === 'admin'
    ? `Uniflex Support (${senderName.split(' ')[0]})`
    : senderName
  const preview = messageBody.length > 100
    ? messageBody.slice(0, 97) + '…'
    : messageBody
  const data = { type: 'support', conversation_id: conversationId }

  // Collect recipient FCM tokens.
  const tokens: Array<{ userId: string; token: string }> = []

  if (senderRole === 'student') {
    // Push to all admins with a device token.
    const { data: admins } = await admin
      .from('profiles')
      .select('id, fcm_token')
      .eq('role', 'admin')
      .not('fcm_token', 'is', null)

    for (const a of admins ?? []) {
      if (a.fcm_token) tokens.push({ userId: a.id, token: a.fcm_token })
    }
  } else {
    // Push to the student who owns this conversation.
    const { data: conv } = await admin
      .from('support_conversations')
      .select('student_id, profiles!inner(id, fcm_token)')
      .eq('id', conversationId)
      .maybeSingle()

    // Supabase join returns profiles as a single object when the FK is unique.
    const profile = conv?.profiles as
      | { id: string; fcm_token: string | null }
      | undefined

    if (profile?.fcm_token) {
      tokens.push({ userId: profile.id, token: profile.fcm_token })
    }
  }

  if (tokens.length === 0) {
    return json({ delivered: 'no_tokens' })
  }

  // Send push to each recipient, clearing stale tokens.
  let pushed = 0
  for (const { userId, token } of tokens) {
    try {
      const res = await fetch(`${supabaseUrl}/functions/v1/send-notification`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${svcKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ token, title, body: preview, data }),
      })

      if (!res.ok) {
        const text = await res.text()
        console.warn(`Push failed for user ${userId}: ${res.status} ${text}`)

        // Clear invalid / unregistered tokens.
        if (res.status === 400 || res.status === 404) {
          const payload = JSON.parse(text)
          const errCode = payload?.error?.details?.[0]?.errorCode as
            | string
            | undefined
          if (
            errCode === 'UNREGISTERED' ||
            errCode === 'INVALID_ARGUMENT' ||
            res.status === 404
          ) {
            await admin
              .from('profiles')
              .update({ fcm_token: null })
              .eq('id', userId)
          }
        }
      } else {
        pushed++
      }
    } catch (err) {
      console.warn(`Push request threw for user ${userId}:`, err)
    }
  }

  return json({ delivered: pushed, attempted: tokens.length })
})
