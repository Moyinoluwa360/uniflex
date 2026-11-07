-- =====================================================================
-- Uniflex — Pack 5: account created only at the very last step
-- (additive, safe to run once; re-running is harmless)
--
-- Run order:  1) this file   2) deploy the `signup` Edge Function
--             (3) optional: pack_5_test.sql, pack_5_legacy_accounts.sql)
--
-- What this adds (nothing existing is changed or deleted):
--   • signup_events               — tiny rate-limit ledger (per IP / device / phone)
--   • signup_phone_verifications  — one row per SMS sent before an account
--                                   exists; later holds the hash of the
--                                   short-lived "phone verified" proof
--   • pack5_* functions           — ALL callable by service_role ONLY (the
--                                   `signup` Edge Function). anon/authenticated
--                                   cannot execute them.
--   • pack5_finish_signup()       — the one atomic write: profile + wallet +
--                                   referral + hashed PIN + proof consumed.
--   • a partial UNIQUE index so one verified phone can belong to one account
--     (skipped with a NOTICE if live data already has duplicates).
--
-- Legacy half-made accounts (auth user + stub profile, onboarding not
-- finished) are NOT touched. The app still resumes them via ResumeOtpScreen /
-- CompleteProfileScreen, and the old `phone-otp` function keeps working.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tables (service-role only: RLS on, no policies, no client grants)
-- ---------------------------------------------------------------------
create table if not exists public.signup_events (
  id         bigint generated always as identity primary key,
  kind       text        not null,
  key        text        not null,
  created_at timestamptz not null default now()
);
create index if not exists signup_events_lookup_idx
  on public.signup_events (kind, key, created_at desc);

create table if not exists public.signup_phone_verifications (
  id               uuid primary key default gen_random_uuid(),
  phone            text        not null,            -- E.164
  pin_id           text,                            -- Termii reference (null while reserved)
  ip               text,
  device_id        text,
  created_at       timestamptz not null default now(),
  expires_at       timestamptz not null default now() + interval '10 minutes',
  attempts         int         not null default 0,  -- wrong/any code tries
  verified_at      timestamptz,
  proof_hash       text,                            -- sha256(proof) — the proof itself is never stored
  proof_expires_at timestamptz,
  proof_used_at    timestamptz
);
create index if not exists signup_pv_phone_idx
  on public.signup_phone_verifications (phone, created_at desc);
create unique index if not exists signup_pv_proof_hash_uq
  on public.signup_phone_verifications (proof_hash) where proof_hash is not null;

alter table public.signup_events              enable row level security;
alter table public.signup_phone_verifications enable row level security;
revoke all on table public.signup_events              from public, anon, authenticated;
revoke all on table public.signup_phone_verifications from public, anon, authenticated;

-- One verified phone ↔ one account. Guarded so a pre-existing duplicate on
-- live data can never make this script fail (the prechecks still apply).
do $$
begin
  if exists (
    select 1 from public.profiles
     where phone is not null and phone_verified_at is not null
     group by phone having count(*) > 1
  ) then
    raise notice 'pack_5: duplicate verified phones exist — unique index SKIPPED (prechecks still enforce it)';
  else
    create unique index if not exists profiles_phone_verified_uq
      on public.profiles (phone) where phone_verified_at is not null;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Rate-limit helper: true = allowed (and the hit is recorded)
-- ---------------------------------------------------------------------
create or replace function public.pack5_rate_hit(
  p_kind text, p_key text, p_limit int, p_window_seconds int
) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  if p_key is null or p_key = '' then
    return true;   -- nothing to key on (e.g. no device id) — other limits still apply
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_kind || ':' || p_key, 0));
  select count(*) into v_count from public.signup_events
   where kind = p_kind and key = p_key
     and created_at > now() - make_interval(secs => p_window_seconds);
  if v_count >= p_limit then
    return false;
  end if;
  insert into public.signup_events (kind, key) values (p_kind, p_key);
  return true;
end $$;

-- ---------------------------------------------------------------------
-- 3. Is this email / phone usable? One short code, no data about anyone.
--    OK | EMAIL_TAKEN | EMAIL_STUCK | PHONE_TAKEN
--    EMAIL_STUCK = a legacy half-made account owns the email → "log in".
-- ---------------------------------------------------------------------
create or replace function public.pack5_identity_status(p_email text, p_phone text)
returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_uid   uuid;
  v_done  boolean;
begin
  if v_email <> '' then
    select u.id into v_uid from auth.users u where lower(u.email) = v_email limit 1;
    if v_uid is not null then
      select p.onboarding_complete into v_done from public.profiles p where p.id = v_uid;
      if found and v_done is false then
        return 'EMAIL_STUCK';
      end if;
      return 'EMAIL_TAKEN';
    end if;
    if exists (select 1 from public.profiles p where lower(p.email) = v_email) then
      return 'EMAIL_TAKEN';
    end if;
  end if;

  if coalesce(p_phone, '') <> '' and exists (
    select 1 from public.profiles p
     where p.phone = p_phone and p.phone_verified_at is not null
  ) then
    return 'PHONE_TAKEN';
  end if;

  return 'OK';
end $$;

-- identity + nickname + matric, used right before the auth user is created
create or replace function public.pack5_precheck_signup(
  p_email text, p_phone text, p_nickname text, p_matric text
) returns text
language plpgsql stable security definer set search_path = public as $$
declare v_status text;
begin
  v_status := public.pack5_identity_status(p_email, p_phone);
  if v_status <> 'OK' then return v_status; end if;
  if exists (select 1 from public.profiles
              where lower(nickname) = lower(trim(p_nickname))) then
    return 'NICKNAME_TAKEN';
  end if;
  if nullif(trim(coalesce(p_matric, '')), '') is not null and exists (
       select 1 from public.profiles
        where lower(matric_number) = lower(trim(p_matric))) then
    return 'MATRIC_TAKEN';
  end if;
  return 'OK';
end $$;

-- ---------------------------------------------------------------------
-- 4. Sending a code (before any account exists)
--    Reserve → (Edge Function calls Termii) → finish, or cancel on failure.
--    Limits: 60 s between sends to one phone, 5 / 24 h per phone,
--            20 / h per IP, 10 / h per device. A failed Termii call is
--            cancelled so it never counts.
-- ---------------------------------------------------------------------
create or replace function public.pack5_otp_reserve_send(
  p_phone text, p_ip text, p_device text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_last  timestamptz;
  v_count int;
  v_id    uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('send_phone:' || p_phone, 0));

  select max(created_at) into v_last
    from public.signup_phone_verifications where phone = p_phone;
  if v_last is not null and v_last > now() - interval '60 seconds' then
    return jsonb_build_object(
      'ok', false, 'reason', 'TOO_SOON',
      'retry_after', greatest(1, ceil(extract(epoch from (v_last + interval '60 seconds' - now())))::int));
  end if;

  select count(*) into v_count from public.signup_phone_verifications
   where phone = p_phone and created_at > now() - interval '24 hours';
  if v_count >= 5 then
    return jsonb_build_object('ok', false, 'reason', 'PHONE_LIMIT');
  end if;

  if not public.pack5_rate_hit('send_ip', p_ip, 20, 3600) then
    return jsonb_build_object('ok', false, 'reason', 'IP_LIMIT');
  end if;
  if not public.pack5_rate_hit('send_device', p_device, 10, 3600) then
    return jsonb_build_object('ok', false, 'reason', 'DEVICE_LIMIT');
  end if;

  insert into public.signup_phone_verifications (phone, ip, device_id)
  values (p_phone, nullif(p_ip, ''), nullif(p_device, ''))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.pack5_otp_finish_send(p_id uuid, p_pin_id text)
returns void language sql security definer set search_path = public as $$
  update public.signup_phone_verifications
     set pin_id = p_pin_id, created_at = now(), expires_at = now() + interval '10 minutes'
   where id = p_id and pin_id is null;
$$;

create or replace function public.pack5_otp_cancel_send(p_id uuid)
returns void language sql security definer set search_path = public as $$
  delete from public.signup_phone_verifications where id = p_id and pin_id is null;
$$;

-- ---------------------------------------------------------------------
-- 5. Checking a code. Counts the try BEFORE Termii is asked (so parallel
--    guesses cannot exceed the limit). Only the newest code for a phone
--    is ever valid — a resend discards the older one.
-- ---------------------------------------------------------------------
create or replace function public.pack5_otp_begin_verify(p_phone text, p_ip text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r public.signup_phone_verifications;
begin
  if not public.pack5_rate_hit('verify_ip', p_ip, 40, 3600) then
    return jsonb_build_object('ok', false, 'reason', 'IP_LIMIT');
  end if;

  select * into r from public.signup_phone_verifications
   where phone = p_phone and pin_id is not null and verified_at is null
   order by created_at desc limit 1
   for update;

  if not found or r.expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'NO_ACTIVE_CODE');
  end if;
  if r.attempts >= 5 then
    return jsonb_build_object('ok', false, 'reason', 'TOO_MANY_ATTEMPTS');
  end if;

  update public.signup_phone_verifications set attempts = attempts + 1 where id = r.id;
  return jsonb_build_object('ok', true, 'id', r.id, 'pin_id', r.pin_id,
                            'attempts_left', 5 - (r.attempts + 1));
end $$;

-- Termii said the code is right: store the proof's hash (valid 30 min).
create or replace function public.pack5_otp_mark_verified(p_id uuid, p_proof_hash text)
returns void
language plpgsql security definer set search_path = public as $$
declare v_phone text;
begin
  update public.signup_phone_verifications
     set verified_at = now(), proof_hash = p_proof_hash,
         proof_expires_at = now() + interval '30 minutes'
   where id = p_id and verified_at is null
   returning phone into v_phone;
  if v_phone is null then return; end if;
  -- older, unspent proofs for the same phone are superseded
  update public.signup_phone_verifications
     set proof_used_at = now()
   where phone = v_phone and id <> p_id
     and proof_hash is not null and proof_used_at is null;
end $$;

-- OK | INVALID | EXPIRED | USED   (a proof for another phone is just INVALID)
create or replace function public.pack5_proof_status(p_phone text, p_proof_hash text)
returns text
language plpgsql stable security definer set search_path = public as $$
declare r public.signup_phone_verifications;
begin
  if coalesce(p_proof_hash, '') = '' then return 'INVALID'; end if;
  select * into r from public.signup_phone_verifications where proof_hash = p_proof_hash;
  if not found or r.phone <> p_phone then return 'INVALID'; end if;
  if r.proof_used_at is not null then return 'USED'; end if;
  if r.proof_expires_at is null or r.proof_expires_at <= now() then return 'EXPIRED'; end if;
  return 'OK';
end $$;

-- ---------------------------------------------------------------------
-- 6. THE atomic signup write. The Edge Function creates the auth user
--    (admin API, email pre-confirmed) and then calls this; if this raises,
--    EVERYTHING below is rolled back and the function deletes the auth user.
--    Raises one of: PROOF_INVALID PROOF_EXPIRED PROOF_USED PHONE_TAKEN
--    NICKNAME_TAKEN MATRIC_TAKEN REFERRAL_INVALID CANNOT_REFER_SELF INVALID_INPUT
-- ---------------------------------------------------------------------
create or replace function public.pack5_finish_signup(
  p_user_id     uuid,
  p_proof_hash  text,
  p_email       text,
  p_phone       text,
  p_nickname    text,
  p_full_name   text,
  p_matric      text,
  p_school      text,
  p_dob         date,
  p_referral    text,
  p_pin         text
) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  r             public.signup_phone_verifications;
  v_nick        text := trim(coalesce(p_nickname, ''));
  v_name        text := trim(coalesce(p_full_name, ''));
  v_matric      text := nullif(trim(coalesce(p_matric, '')), '');
  v_code        text := upper(trim(coalesce(p_referral, '')));
  v_code_id     uuid;
  v_referrer_id uuid;
begin
  if p_user_id is null or v_nick = '' or v_name = '' or p_dob is null
     or coalesce(p_pin, '') !~ '^[0-9]{4}$'
     or p_dob > (current_date - interval '14 years')
     or p_dob < (current_date - interval '100 years')
     or length(v_nick) > 40 or length(v_name) > 120 then
    raise exception 'INVALID_INPUT';
  end if;

  -- 1) the proof: exists, same phone, not spent, not expired — and lock it
  select * into r from public.signup_phone_verifications
   where proof_hash = p_proof_hash for update;
  if not found or r.phone <> p_phone then raise exception 'PROOF_INVALID'; end if;
  if r.proof_used_at is not null then raise exception 'PROOF_USED'; end if;
  if r.proof_expires_at is null or r.proof_expires_at <= now() then
    raise exception 'PROOF_EXPIRED';
  end if;

  -- 2) uniqueness (the unique constraints below are the final word)
  if exists (select 1 from public.profiles
              where phone = p_phone and phone_verified_at is not null and id <> p_user_id) then
    raise exception 'PHONE_TAKEN';
  end if;
  if exists (select 1 from public.profiles
              where lower(nickname) = lower(v_nick) and id <> p_user_id) then
    raise exception 'NICKNAME_TAKEN';
  end if;
  if v_matric is not null and exists (select 1 from public.profiles
              where lower(matric_number) = lower(v_matric) and id <> p_user_id) then
    raise exception 'MATRIC_TAKEN';
  end if;

  -- 3) referral code: admin-minted first, then legacy per-student
  if v_code <> '' then
    select id, owner_id into v_code_id, v_referrer_id
      from public.referral_codes where code = v_code and is_active;
    if v_code_id is null then
      select id into v_referrer_id from public.profiles where referral_code = v_code;
      if v_referrer_id is null then raise exception 'REFERRAL_INVALID'; end if;
    end if;
    if v_referrer_id = p_user_id then raise exception 'CANNOT_REFER_SELF'; end if;
  end if;

  -- 4) the writes (one transaction; any failure undoes all of it)
  perform set_config('uniflex.trusted_write', 'on', true);

  insert into public.profiles (
    id, role, email, phone, phone_verified_at, nickname, full_name,
    matric_number, school, date_of_birth, referred_by_code, onboarding_complete
  ) values (
    p_user_id, 'student', lower(trim(p_email)), p_phone, r.verified_at, v_nick, v_name,
    v_matric, coalesce(nullif(trim(p_school), ''), 'Redeemer''s University'),
    p_dob, nullif(v_code, ''), true
  )
  on conflict (id) do update set
    role = 'student', email = excluded.email, phone = excluded.phone,
    phone_verified_at = excluded.phone_verified_at, nickname = excluded.nickname,
    full_name = excluded.full_name, matric_number = excluded.matric_number,
    school = excluded.school, date_of_birth = excluded.date_of_birth,
    referred_by_code = excluded.referred_by_code, onboarding_complete = true;

  insert into public.wallets (user_id, balance, virtual_account_number, tier)
  values (p_user_id, 0,
          'UFX-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
          'Bronze')
  on conflict (user_id) do nothing;

  if v_code_id is not null then
    insert into public.referral_code_uses (code_id, referred_id)
    values (v_code_id, p_user_id) on conflict (referred_id) do nothing;
  end if;
  if v_referrer_id is not null then
    insert into public.referrals (referrer_id, referred_id, referral_code_used)
    values (v_referrer_id, p_user_id, v_code) on conflict (referred_id) do nothing;
  end if;

  insert into public.transaction_pins (user_id, pin_hash, failed_attempts, locked_until, updated_at)
  values (p_user_id, crypt(p_pin, gen_salt('bf')), 0, null, now())
  on conflict (user_id) do update
    set pin_hash = excluded.pin_hash, failed_attempts = 0, locked_until = null, updated_at = now();

  update public.signup_phone_verifications set proof_used_at = now() where id = r.id;

  perform set_config('uniflex.trusted_write', 'off', true);
  return p_user_id;
exception
  when unique_violation then
    perform set_config('uniflex.trusted_write', 'off', true);
    if sqlerrm like '%nickname%' then raise exception 'NICKNAME_TAKEN'; end if;
    if sqlerrm like '%matric%'   then raise exception 'MATRIC_TAKEN';   end if;
    if sqlerrm like '%phone%'    then raise exception 'PHONE_TAKEN';    end if;
    raise exception 'INVALID_INPUT';
end $$;

-- ---------------------------------------------------------------------
-- 7. Housekeeping for the two new tables only (never touches real data)
-- ---------------------------------------------------------------------
create or replace function public.pack5_purge_signup_artifacts()
returns void language sql security definer set search_path = public as $$
  delete from public.signup_events where created_at < now() - interval '2 days';
  delete from public.signup_phone_verifications where created_at < now() - interval '2 days';
$$;

-- ---------------------------------------------------------------------
-- 8. Lock every pack5_* function to the service role (the Edge Function)
-- ---------------------------------------------------------------------
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname like 'pack5\_%'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;
