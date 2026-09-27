/**
 * send-notification — Supabase Edge Function
 *
 * Sends a Firebase Cloud Messaging push notification (FCM HTTP v1 API)
 * to a single device identified by its FCM token.
 *
 * The legacy FCM server key API was shut down June 2024. This function
 * uses the v1 API with a Google service account for auth.
 *
 * Deployment:
 *   supabase functions deploy send-notification
 *
 * Required secret (set in Supabase dashboard → Edge Functions → Secrets):
 *   FIREBASE_SERVICE_ACCOUNT_JSON — full contents of the service account
 *     JSON file downloaded from Firebase Console → Project Settings →
 *     Service Accounts → Generate new private key.
 *
 * Request body (JSON):
 *   {
 *     "token":   "<fcm_device_token>",
 *     "title":   "Notification title",
 *     "body":    "Notification body",
 *     "data":    { ...optional key-value pairs }
 *   }
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

// ── JWT helpers for service-account auth ─────────────────────────────────────

function b64url(data: Uint8Array): string {
  let str = ''
  for (const byte of data) str += String.fromCharCode(byte)
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

function jsonB64url(obj: object): string {
  return b64url(new TextEncoder().encode(JSON.stringify(obj)))
}

async function getAccessToken(sa: {
  client_email: string
  private_key: string
  token_uri: string
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = jsonB64url({ alg: 'RS256', typ: 'JWT' })
  const payload = jsonB64url({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: sa.token_uri,
    iat: now,
    exp: now + 3600,
  })

  const signingInput = `${header}.${payload}`

  // Strip PEM wrapper and decode
  const pemStripped = sa.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  const keyBytes = Uint8Array.from(atob(pemStripped), (c) => c.charCodeAt(0))

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    keyBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const sigBytes = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signingInput),
  )

  const jwt = `${signingInput}.${b64url(new Uint8Array(sigBytes))}`

  const res = await fetch(sa.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })

  const json = await res.json()
  if (!json.access_token) {
    throw new Error(`Token exchange failed: ${JSON.stringify(json)}`)
  }
  return json.access_token as string
}

// ── Main handler ──────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // This endpoint pushes to an arbitrary FCM device token, so it is a
    // service-role-only primitive: callers go through `notify-user`, which
    // checks that the caller may contact that customer and resolves the
    // token itself. Previously there was NO auth check here at all, so
    // anyone holding a device token could push to it.
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const presented = (req.headers.get('Authorization') ?? '')
      .replace(/^Bearer\s+/i, '')
      .trim()
    if (!serviceKey || presented !== serviceKey) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { token, title, body, data } = await req.json()

    if (!token || !title || !body) {
      return new Response(
        JSON.stringify({ error: 'token, title, and body are required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } },
      )
    }

    const saJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON')
    if (!saJson) {
      return new Response(
        JSON.stringify({ error: 'FIREBASE_SERVICE_ACCOUNT_JSON secret not set' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } },
      )
    }

    const sa = JSON.parse(saJson)
    const accessToken = await getAccessToken(sa)

    const fcmUrl =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`

    const fcmRes = await fetch(fcmUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: data ?? {},
        },
      }),
    })

    const result = await fcmRes.json()
    return new Response(JSON.stringify(result), {
      status: fcmRes.status,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
