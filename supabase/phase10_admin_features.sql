-- =====================================================================
-- PHASE 10 — Admin-controlled referral codes, notifications,
--            and home-page advertisements
-- =====================================================================
-- Run this ONCE in the Supabase SQL editor, AFTER phase9_security_hardening.sql.
-- Every block is idempotent, so re-running is safe.
--
-- Four features:
--   1. Referral codes are now minted by Admin and allocated to a person,
--      instead of every student auto-generating one at signup. Usage is
--      tracked per code.
--   2. An in-app notifications inbox, written by the `notify-user` Edge
--      Function — automatically on every order status change, and manually
--      when Admin or the assigned Rider messages a customer.
--   3. (No schema needed — rider/customer contact already flows through
--      get_customer_info() and get_rider_info().)
--   4. Home-page advertisements, managed by Admin.
-- =====================================================================


-- =====================================================================
-- 1. Admin-minted referral codes
-- =====================================================================

create table if not exists public.referral_codes (
  id          uuid primary key default gen_random_uuid(),
  code        text unique not null,
  -- The student who earns the ₦500 when a code holder's referral completes
  -- a first order. NULL for a code handed to someone who is not an app
  -- user (a promoter, a poster, an orientation stand) — those still track
  -- signups, they just have nobody to pay.
  owner_id    uuid references public.profiles (id) on delete set null,
  -- Free-text label for an owner who has no profile row, e.g.
  -- 'Bola — Instagram'. Shown in the admin list when owner_id is null.
  owner_label text,
  note        text,
  is_active   boolean not null default true,
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now()
);

comment on table public.referral_codes is
  'Referral codes minted by Admin and allocated to a person. Replaces the '
  'per-student auto-generated profiles.referral_code, which is kept only so '
  'codes already shared before this change keep resolving.';

-- One row per signup that used a code. Separate from `referrals` because a
-- code can have no owner, while referrals.referrer_id is NOT NULL.
create table if not exists public.referral_code_uses (
  id          uuid primary key default gen_random_uuid(),
  code_id     uuid not null references public.referral_codes (id) on delete cascade,
  referred_id uuid not null unique references public.profiles (id) on delete cascade,
  used_at     timestamptz not null default now()
);

create index if not exists referral_code_uses_code_idx
  on public.referral_code_uses (code_id);

alter table public.referral_codes    enable row level security;
alter table public.referral_code_uses enable row level security;

-- A student may read a code allocated to them (so the Referral screen can
-- show it). Everything else goes through the admin RPCs below.
drop policy if exists "referral_codes: owner reads own" on public.referral_codes;
create policy "referral_codes: owner reads own"
  on public.referral_codes for select to authenticated
  using (owner_id = auth.uid() or public.is_admin());

drop policy if exists "referral_code_uses: admin read" on public.referral_code_uses;
create policy "referral_code_uses: admin read"
  on public.referral_code_uses for select to authenticated
  using (public.is_admin());

-- ── Validity check, used live as the student types at signup ──────────
-- Accepts an admin-minted active code OR a legacy per-student code.
create or replace function public.is_referral_code_valid(p_code text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.referral_codes
     where code = upper(trim(p_code)) and is_active
  ) or exists (
    select 1 from public.profiles
     where referral_code = upper(trim(p_code))
  );
$$;

grant execute on function public.is_referral_code_valid(text) to authenticated;

-- ── Admin: mint a code ────────────────────────────────────────────────
create or replace function public.admin_create_referral_code(
  p_code        text,
  p_owner_id    uuid default null,
  p_owner_label text default null,
  p_note        text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_id   uuid;
begin
  if not public.is_admin() then
    raise exception 'Unauthorized';
  end if;

  if v_code !~ '^[A-Z0-9]{4,16}$' then
    raise exception 'CODE_FORMAT';
  end if;

  -- Must not collide with a legacy per-student code either, or a signup
  -- could not tell which one was meant.
  if exists (select 1 from public.referral_codes where code = v_code)
     or exists (select 1 from public.profiles where referral_code = v_code) then
    raise exception 'CODE_TAKEN';
  end if;

  if p_owner_id is not null
     and not exists (select 1 from public.profiles where id = p_owner_id) then
    raise exception 'OWNER_NOT_FOUND';
  end if;

  insert into public.referral_codes
    (code, owner_id, owner_label, note, created_by)
  values
    (v_code, p_owner_id, nullif(trim(coalesce(p_owner_label, '')), ''),
     nullif(trim(coalesce(p_note, '')), ''), auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.admin_create_referral_code(text, uuid, text, text)
  to authenticated;

-- ── Admin: re-allocate / pause / annotate a code ──────────────────────
create or replace function public.admin_update_referral_code(
  p_code_id     uuid,
  p_owner_id    uuid    default null,
  p_owner_label text    default null,
  p_note        text    default null,
  p_is_active   boolean default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Unauthorized';
  end if;

  if p_owner_id is not null
     and not exists (select 1 from public.profiles where id = p_owner_id) then
    raise exception 'OWNER_NOT_FOUND';
  end if;

  update public.referral_codes
     set owner_id    = p_owner_id,
         owner_label = nullif(trim(coalesce(p_owner_label, '')), ''),
         note        = nullif(trim(coalesce(p_note, '')), ''),
         is_active   = coalesce(p_is_active, is_active)
   where id = p_code_id;

  if not found then
    raise exception 'CODE_NOT_FOUND';
  end if;
end;
$$;

grant execute on function public.admin_update_referral_code(uuid, uuid, text, text, boolean)
  to authenticated;

-- ── Admin: delete an unused code ──────────────────────────────────────
-- A code that people have already signed up with is never deleted, so the
-- attribution trail survives — deactivate it instead.
create or replace function public.admin_delete_referral_code(p_code_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uses int;
begin
  if not public.is_admin() then
    raise exception 'Unauthorized';
  end if;

  select count(*) into v_uses
    from public.referral_code_uses where code_id = p_code_id;

  if v_uses > 0 then
    raise exception 'CODE_IN_USE';
  end if;

  delete from public.referral_codes where id = p_code_id;
  if not found then
    raise exception 'CODE_NOT_FOUND';
  end if;
end;
$$;

grant execute on function public.admin_delete_referral_code(uuid) to authenticated;

-- ── Admin: list codes with their usage counts ─────────────────────────
create or replace function public.admin_list_referral_codes()
returns table (
  id            uuid,
  code          text,
  owner_id      uuid,
  owner_name    text,
  owner_label   text,
  note          text,
  is_active     boolean,
  use_count     bigint,
  created_at    timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    rc.id,
    rc.code,
    rc.owner_id,
    coalesce(p.nickname, p.full_name)                    as owner_name,
    rc.owner_label,
    rc.note,
    rc.is_active,
    (select count(*) from public.referral_code_uses u
      where u.code_id = rc.id)                           as use_count,
    rc.created_at
  from public.referral_codes rc
  left join public.profiles p on p.id = rc.owner_id
  where public.is_admin()
  order by rc.created_at desc;
$$;

grant execute on function public.admin_list_referral_codes() to authenticated;

-- ── Admin: who used a given code ──────────────────────────────────────
create or replace function public.admin_referral_code_uses(p_code_id uuid)
returns table (
  referred_id   uuid,
  referred_name text,
  matric_number text,
  used_at       timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    u.referred_id,
    coalesce(p.nickname, p.full_name) as referred_name,
    p.matric_number,
    u.used_at
  from public.referral_code_uses u
  join public.profiles p on p.id = u.referred_id
  where u.code_id = p_code_id and public.is_admin()
  order by u.used_at desc;
$$;

grant execute on function public.admin_referral_code_uses(uuid) to authenticated;

-- ── Admin: find a student to allocate a code to ───────────────────────
create or replace function public.admin_search_students(p_query text)
returns table (
  id            uuid,
  display_name  text,
  matric_number text,
  email         text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    p.id,
    coalesce(p.nickname, p.full_name, p.email) as display_name,
    p.matric_number,
    p.email
  from public.profiles p
  where public.is_admin()
    and p.role = 'student'
    and (
      p_query is null or trim(p_query) = ''
      or p.full_name     ilike '%' || trim(p_query) || '%'
      or p.nickname      ilike '%' || trim(p_query) || '%'
      or p.matric_number ilike '%' || trim(p_query) || '%'
      or p.email         ilike '%' || trim(p_query) || '%'
    )
  order by coalesce(p.nickname, p.full_name, p.email)
  limit 25;
$$;

grant execute on function public.admin_search_students(text) to authenticated;

-- ── Student: the code allocated to me, and how it is doing ────────────
create or replace function public.my_referral_code()
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select case
    when rc.id is null then null
    else jsonb_build_object(
      'code',      rc.code,
      'is_active', rc.is_active,
      'use_count', (select count(*) from public.referral_code_uses u
                     where u.code_id = rc.id)
    )
  end
  from (
    select * from public.referral_codes
     where owner_id = auth.uid()
     order by is_active desc, created_at desc
     limit 1
  ) rc;
$$;

grant execute on function public.my_referral_code() to authenticated;

-- ── Onboarding: no longer mints a personal code ───────────────────────
-- Resolves the entered code against admin-minted codes first, then falls
-- back to a legacy per-student code so anything already shared keeps
-- working. Records the use either way; only creates a `referrals` row (the
-- thing the ₦500 payout trigger watches) when the code actually has an
-- owner to pay.
create or replace function public.complete_student_onboarding(
  p_nickname           text,
  p_full_name          text,
  p_matric_number      text,
  p_school             text,
  p_date_of_birth      date,
  p_referral_code_used text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id     uuid := auth.uid();
  v_referrer_id uuid;
  v_code_id     uuid;
  v_code        text := upper(trim(coalesce(p_referral_code_used, '')));
  v_profile     public.profiles;
  v_done        boolean;
begin
  if v_user_id is null then
    raise exception 'Not signed in';
  end if;

  select onboarding_complete into v_done
    from public.profiles where id = v_user_id;
  if not found then
    raise exception 'No profile row for %; Step One (create account) must run first', v_user_id;
  end if;
  if v_done then
    raise exception 'ALREADY_ONBOARDED';
  end if;

  if v_code <> '' then
    select id, owner_id into v_code_id, v_referrer_id
      from public.referral_codes
     where code = v_code and is_active;

    if v_code_id is null then
      -- Legacy per-student code, from before codes became admin-minted.
      select id into v_referrer_id
        from public.profiles where referral_code = v_code;
      if v_referrer_id is null then
        raise exception 'Referral code % not found', p_referral_code_used;
      end if;
    end if;

    if v_referrer_id = v_user_id then
      raise exception 'CANNOT_REFER_SELF';
    end if;
  end if;

  perform set_config('uniflex.trusted_write', 'on', true);

  update public.profiles set
    role                = 'student',
    nickname            = p_nickname,
    full_name           = p_full_name,
    matric_number       = p_matric_number,
    school              = p_school,
    date_of_birth       = p_date_of_birth,
    referred_by_code    = nullif(v_code, ''),
    onboarding_complete = true
  where id = v_user_id
  returning * into v_profile;

  insert into public.wallets (user_id, balance, virtual_account_number, tier)
  values (
    v_user_id, 0,
    'UFX-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
    'Bronze'
  )
  on conflict (user_id) do nothing;

  if v_code_id is not null then
    insert into public.referral_code_uses (code_id, referred_id)
    values (v_code_id, v_user_id)
    on conflict (referred_id) do nothing;
  end if;

  if v_referrer_id is not null then
    insert into public.referrals (referrer_id, referred_id, referral_code_used)
    values (v_referrer_id, v_user_id, v_code)
    on conflict (referred_id) do nothing;
  end if;

  perform set_config('uniflex.trusted_write', 'off', true);
  return v_profile;
end;
$$;

grant execute on function public.complete_student_onboarding(
  text, text, text, text, date, text
) to authenticated;


-- =====================================================================
-- 2. Notifications
-- =====================================================================

create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  title      text not null,
  body       text not null,
  -- 'order_status' = generated from a status change
  -- 'message'      = free text typed by Admin or the assigned Rider
  kind       text not null default 'message'
               check (kind in ('order_status', 'message')),
  order_id   uuid references public.orders (id) on delete set null,
  sent_by    uuid references public.profiles (id) on delete set null,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

-- Rows are written only by the notify-user Edge Function (service role);
-- recipients read and mark their own as read.
drop policy if exists "notifications: read own" on public.notifications;
create policy "notifications: read own"
  on public.notifications for select to authenticated
  using (user_id = auth.uid());

create or replace function public.mark_notification_read(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.notifications
     set read_at = coalesce(read_at, now())
   where id = p_id and user_id = auth.uid();
end;
$$;

grant execute on function public.mark_notification_read(uuid) to authenticated;

create or replace function public.mark_all_notifications_read()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.notifications
     set read_at = now()
   where user_id = auth.uid() and read_at is null;
end;
$$;

grant execute on function public.mark_all_notifications_read() to authenticated;

create or replace function public.unread_notification_count()
returns int
language sql
security definer
set search_path = public
stable
as $$
  select count(*)::int from public.notifications
   where user_id = auth.uid() and read_at is null;
$$;

grant execute on function public.unread_notification_count() to authenticated;

-- Who is allowed to notify the customer on a given order: Admin, or the
-- rider currently assigned to it. Called by the notify-user Edge Function
-- so the rule lives in one place.
create or replace function public.can_notify_order(p_order_id uuid, p_actor uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.orders o
    join public.profiles p on p.id = p_actor
    where o.id = p_order_id
      and p.is_active
      and (
        (p.role = 'admin')
        or (p.role = 'rider' and o.rider_id = p_actor)
      )
  );
$$;

grant execute on function public.can_notify_order(uuid, uuid) to service_role;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    execute 'alter publication supabase_realtime add table public.notifications';
  end if;
end;
$$;


-- =====================================================================
-- 3. Rider contact details
-- =====================================================================
-- get_customer_info() and get_rider_info() already carry name + phone in
-- both directions. The only gap was riders seeded without a phone, which
-- left the student with nothing to call. Nothing to change in SQL — the
-- admin "Add Rider" form now requires a phone (see admin-create-rider).


-- =====================================================================
-- 4. Home-page advertisements
-- =====================================================================

create table if not exists public.advertisements (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  subtitle   text not null default '',
  image_url  text,
  -- Matches the existing promo card's light/dark treatment.
  is_dark    boolean not null default false,
  -- What tapping the card does.
  link_type  text not null default 'none'
               check (link_type in ('none', 'vendor', 'wallet', 'url')),
  -- vendor id for 'vendor', an https URL for 'url', otherwise null.
  link_value text,
  is_active  boolean not null default true,
  sort_order int not null default 0,
  starts_at  timestamptz,
  ends_at    timestamptz,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

comment on table public.advertisements is
  'Banners in the student home carousel. Replaces the hardcoded list that '
  'used to live in student_home_screen.dart.';

alter table public.advertisements enable row level security;

-- Students see only live ads; admin sees everything so it can manage
-- scheduled and paused ones.
drop policy if exists "advertisements: read live" on public.advertisements;
create policy "advertisements: read live"
  on public.advertisements for select to authenticated
  using (
    public.is_admin()
    or (
      is_active
      and (starts_at is null or starts_at <= now())
      and (ends_at   is null or ends_at   >  now())
    )
  );

drop policy if exists "advertisements: admin insert" on public.advertisements;
create policy "advertisements: admin insert"
  on public.advertisements for insert to authenticated
  with check (public.is_admin());

drop policy if exists "advertisements: admin update" on public.advertisements;
create policy "advertisements: admin update"
  on public.advertisements for update to authenticated
  using (public.is_admin());

drop policy if exists "advertisements: admin delete" on public.advertisements;
create policy "advertisements: admin delete"
  on public.advertisements for delete to authenticated
  using (public.is_admin());

-- Seed the three banners that were hardcoded in the Flutter app, so the
-- carousel does not go blank the moment it starts reading from here.
insert into public.advertisements (title, subtitle, is_dark, sort_order)
select * from (values
  ('Free delivery over ₦5,000',
   'All Uniflex Kitchen orders · ends Sunday', false, 0),
  ('Flex Fridays',
   '15% back to your wallet every Friday',     true,  1),
  ('Refer a friend, earn ₦500',
   'Share your code — you both get wallet credit', false, 2)
) as v(title, subtitle, is_dark, sort_order)
where not exists (select 1 from public.advertisements);
