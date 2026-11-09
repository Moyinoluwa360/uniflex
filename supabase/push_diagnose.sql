-- Push health check — READ ONLY. Paste into the Supabase SQL editor.
-- 1. Who has a registered phone (after push_devices.sql is applied)?
select p.nickname, p.role, d.platform, left(d.token, 10) || '…' as token, d.updated_at
  from public.push_devices d join public.profiles p on p.id = d.user_id
 order by d.updated_at desc;

-- 2. Accounts with NO registered phone (these get the bell only, never a push)
select p.nickname, p.role from public.profiles p
 where not exists (select 1 from public.push_devices d where d.user_id = p.id)
   and p.fcm_token is null
 order by p.nickname limit 30;

-- 3. Is the database -> Edge Function link set up? (expect 2 rows: lengths > 0)
select name, length(decrypted_secret) as len from vault.decrypted_secrets
 where name in ('push_project_url', 'push_secret_key');

-- 4. Did the database call the push function for recent notifications?
--    status_code 200 = function ran. Anything else = read `content`.
select created, status_code, left(content, 200) as content
  from net._http_response order by created desc limit 15;
