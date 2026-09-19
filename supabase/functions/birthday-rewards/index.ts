/**
 * birthday-rewards — Supabase Edge Function
 *
 * Triggers the `process_birthday_rewards()` Postgres function which credits
 * wallet bonuses to Silver/Gold/Platinum students whose birthday is today.
 *
 * Designed to be invoked daily by pg_cron or the Supabase CRON scheduler:
 *
 *   -- In your Supabase SQL editor (requires pg_cron extension):
 *   select cron.schedule(
 *     'birthday-rewards-daily',
 *     '0 0 * * *',
 *     $$select public.process_birthday_rewards()$$
 *   );
 *
 * Alternatively, this Edge Function can be hit by an external cron job
 * (e.g. GitHub Actions at 00:00 UTC) using the service role key:
 *
 *   POST https://<project>.supabase.co/functions/v1/birthday-rewards
 *   Authorization: Bearer <service_role_key>
 *
 * Required secrets:
 *   SUPABASE_URL          — auto-injected by Supabase
 *   SUPABASE_SERVICE_ROLE_KEY — auto-injected by Supabase
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: { 'Access-Control-Allow-Origin': '*' },
    })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const supabase = createClient(supabaseUrl, serviceKey)

    const { error } = await supabase.rpc('process_birthday_rewards')

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    return new Response(
      JSON.stringify({ success: true, ran_at: new Date().toISOString() }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    )
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
