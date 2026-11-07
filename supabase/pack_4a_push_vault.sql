-- =====================================================================
-- Pack 4A — push settings via Supabase Vault (patch)
--
-- Hosted Supabase refuses `alter database postgres set app.…`
-- ("permission denied to set parameter"). This patch makes the push
-- trigger read the project URL and secret key from Vault instead.
-- Safe to run more than once. Run AFTER pack_4a.sql.
--
-- STEP 1 — store the two values (replace the placeholders, run ONCE;
--          running it again for the same name errors: use step 1b):
--
--   select vault.create_secret('https://YOUR_PROJECT_REF.supabase.co', 'push_project_url');
--   select vault.create_secret('sb_secret_YOUR_KEY',                 'push_secret_key');
--
-- STEP 1b — to change a value later:
--
--   select vault.update_secret(
--            (select id from vault.secrets where name = 'push_secret_key'),
--            'sb_secret_NEW_KEY');
--
-- STEP 2 — run everything below.
-- =====================================================================

create or replace function public._trigger_push_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_key text;
begin
  -- Preferred: Supabase Vault.
  begin
    select decrypted_secret into v_url
      from vault.decrypted_secrets where name = 'push_project_url' limit 1;
    select decrypted_secret into v_key
      from vault.decrypted_secrets where name = 'push_secret_key' limit 1;
  exception when others then
    v_url := null;
    v_key := null;
  end;
  -- Fallback: the old database settings.
  if v_url is null or v_url = '' or v_key is null or v_key = '' then
    begin
      v_url := current_setting('app.supabase_project_url', true);
      v_key := current_setting('app.supabase_service_role_key', true);
    exception when others then
      return new;
    end;
  end if;
  if v_url is null or v_url = '' or v_key is null or v_key = '' then
    return new;
  end if;

  perform net.http_post(
    url     := v_url || '/functions/v1/push-notification',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_key),
    body    := jsonb_build_object(
      'notification_id', new.id,
      'user_id',         new.user_id,
      'title',           new.title,
      'body',            new.body,
      'type',            new.type,
      'order_id',        new.order_id,
      'group_id',        new.group_id,
      'conversation_id', new.conversation_id));
  return new;
exception when others then
  -- pg_net missing / any failure: never block the insert.
  return new;
end;
$$;

-- Check (shows names only, never the values):
select name, created_at from vault.secrets
 where name in ('push_project_url', 'push_secret_key') order by name;
