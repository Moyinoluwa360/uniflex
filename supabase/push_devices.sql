-- =====================================================================
-- Push devices — one row per phone (fixes flaky / missing push)
--
-- Before: ONE token per profile (profiles.fcm_token). Signing in on a second
-- phone overwrote the first; a sign-out never cleared anything; a phone that
-- changed account kept pushing to the old account.
--
-- Now: public.push_devices holds one row per (phone token). A token belongs
-- to exactly ONE user at a time — registering it moves it to whoever is
-- signed in on that phone. A user can have several phones.
--
-- Additive and safe to run more than once. Nothing is deleted.
-- profiles.fcm_token is kept (old app builds still write it; the push
-- function reads both).
-- =====================================================================

create table if not exists public.push_devices (
  token      text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  platform   text,
  updated_at timestamptz not null default now()
);

create index if not exists push_devices_user_idx on public.push_devices(user_id);

-- Nobody reads or writes this table directly: only the RPCs below (and the
-- service role used by the push Edge Function) touch it.
alter table public.push_devices enable row level security;
revoke all on public.push_devices from anon, authenticated;

-- ── register_push_token ──────────────────────────────────────────────
create or replace function public.register_push_token(
  p_token text,
  p_platform text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  if p_token is null or length(trim(p_token)) < 20 then
    raise exception 'Invalid device token';
  end if;

  -- The token moves to the current user (a phone can only be one person).
  insert into public.push_devices (token, user_id, platform, updated_at)
  values (p_token, auth.uid(), nullif(trim(coalesce(p_platform, '')), ''), now())
  on conflict (token) do update
    set user_id    = excluded.user_id,
        platform   = coalesce(excluded.platform, public.push_devices.platform),
        updated_at = now();

  -- Keep the legacy single-token column in step (old builds + fallback), and
  -- make sure nobody else still lists this phone there.
  update public.profiles set fcm_token = null
   where fcm_token = p_token and id <> auth.uid();
  update public.profiles set fcm_token = p_token where id = auth.uid();
end $$;

revoke all on function public.register_push_token(text, text) from public, anon;
grant execute on function public.register_push_token(text, text) to authenticated;

-- ── unregister_push_token (called on sign-out, while still signed in) ──
create or replace function public.unregister_push_token(p_token text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or p_token is null then
    return;
  end if;
  delete from public.push_devices
   where token = p_token and user_id = auth.uid();
  update public.profiles set fcm_token = null
   where id = auth.uid() and fcm_token = p_token;
end $$;

revoke all on function public.unregister_push_token(text) from public, anon;
grant execute on function public.unregister_push_token(text) to authenticated;

-- ── store_fcm_token (old builds) now also feeds push_devices ─────────
-- A null token (old sign-out call) only clears the legacy column: it must
-- not wipe the person's other phones.
create or replace function public.store_fcm_token(p_token text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return;
  end if;
  if p_token is null then
    update public.profiles set fcm_token = null where id = auth.uid();
    return;
  end if;
  perform public.register_push_token(p_token, null);
end $$;

grant execute on function public.store_fcm_token(text) to authenticated;

-- ── Backfill: carry over every token already stored ──────────────────
insert into public.push_devices (token, user_id)
select p.fcm_token, p.id
  from public.profiles p
 where p.fcm_token is not null
   and length(p.fcm_token) >= 20
on conflict (token) do nothing;

-- ── Health check (read-only) ─────────────────────────────────────────
-- select p.nickname, p.role, d.platform, left(d.token, 10) as tok, d.updated_at
--   from public.push_devices d join public.profiles p on p.id = d.user_id
--  order by d.updated_at desc;
