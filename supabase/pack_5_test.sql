-- =====================================================================
-- Pack 5 — SQL test script
--
-- Paste into the Supabase SQL editor AFTER pack_5.sql. Everything runs in
-- ONE transaction that is ROLLED BACK at the end — no test data survives.
-- Read the result grid at the bottom: every line starts with PASS or FAIL.
--
-- What this proves (the security logic all lives in SQL; the Edge Function
-- only adds Termii + the admin "create auth user" call):
--   • signup is refused: no proof / expired / other phone's proof / reused
--   • taken email / phone / nickname / matric are refused (and nothing is
--     half-written)
--   • a valid signup writes profile + wallet + hashed PIN + proof-spent together
--   • send limits (60 s, 5/day/phone, per IP, per device), attempt limit
--   • anon / authenticated users cannot call any pack5_* function
-- NOT covered here (needs the deployed function + real SMS): Termii, the
-- auth admin API, HTTP status codes — see BEFORE_YOU_BUILD.md section 6.
-- =====================================================================
begin;

create schema uf_test;
grant usage on schema uf_test to public;

create function uf_test.ok(p_name text, p_cond boolean) returns void
language plpgsql as $$
begin
  perform set_config('uf.log',
    coalesce(current_setting('uf.log', true), '') ||
    case when coalesce(p_cond, false) then 'PASS  ' else 'FAIL  ' end ||
    p_name || E'\n', true);
  raise notice '% %', case when coalesce(p_cond, false) then 'PASS' else 'FAIL' end, p_name;
end $$;

create function uf_test.raises(p_sql text, p_expect text) returns boolean
language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return position(p_expect in sqlerrm) > 0;
end $$;

-- A verified phone with a live proof; returns the proof's plain text.
-- (The real flow stores only the hash; tests mimic that with a fake hash.)
create function uf_test.mk_proof(p_phone text, p_hash text,
                                 p_expires interval default interval '30 minutes',
                                 p_used boolean default false) returns void
language plpgsql as $$
begin
  insert into public.signup_phone_verifications
    (phone, pin_id, verified_at, proof_hash, proof_expires_at, proof_used_at)
  values (p_phone, 'pin-' || p_hash, now(), p_hash, now() + p_expires,
          case when p_used then now() end);
end $$;

create function uf_test.finish(p_uid uuid, p_hash text, p_email text, p_phone text,
                               p_nick text, p_matric text default null,
                               p_ref text default null, p_pin text default '1234')
returns uuid language sql as $$
  select public.pack5_finish_signup(
    p_uid, p_hash, p_email, p_phone, p_nick, 'Test Student', p_matric,
    'Redeemer''s University', (current_date - interval '20 years')::date, p_ref, p_pin);
$$;

-- ── Fixtures: one finished account (taken email/phone/nick/matric),
--    one stuck legacy account, one referrer code ───────────────────────
do $$
declare
  v_done  uuid := gen_random_uuid();
  v_stuck uuid := gen_random_uuid();
begin
  insert into auth.users (id, email) values (v_done, 'taken@example.com'), (v_stuck, 'stuck@example.com');
  insert into public.profiles (id, email, phone, phone_verified_at, nickname, full_name,
                               matric_number, onboarding_complete, role)
  values (v_done, 'taken@example.com', '+2348030000001', now(), 'TakenNick', 'Taken', 'RUN/1/1', true, 'student'),
         (v_stuck, 'stuck@example.com', '+2348030000002', null, null, null, null, false, 'student');
  insert into public.referral_codes (code, owner_id, owner_label, is_active)
  values ('P5CODE', v_done, 'test', true);
  perform set_config('uf.done', v_done::text, true);
end $$;

-- ═════════════ A. identity / availability checks ═════════════
select uf_test.ok('A1 free email+phone → OK',
  public.pack5_identity_status('new@example.com', '+2348031111111') = 'OK');
select uf_test.ok('A2 taken email → EMAIL_TAKEN (case-insensitive)',
  public.pack5_identity_status('TAKEN@Example.com', '+2348031111111') = 'EMAIL_TAKEN');
select uf_test.ok('A3 legacy stuck email → EMAIL_STUCK ("log in and continue")',
  public.pack5_identity_status('stuck@example.com', '+2348031111111') = 'EMAIL_STUCK');
select uf_test.ok('A4 verified phone of another account → PHONE_TAKEN',
  public.pack5_identity_status('new@example.com', '+2348030000001') = 'PHONE_TAKEN');
select uf_test.ok('A5 an UNVERIFIED stub phone does not block a new signup',
  public.pack5_identity_status('new@example.com', '+2348030000002') = 'OK');
select uf_test.ok('A6 precheck: nickname taken (case-insensitive)',
  public.pack5_precheck_signup('new@example.com', '+2348031111111', 'takennick', null) = 'NICKNAME_TAKEN');
select uf_test.ok('A7 precheck: matric taken',
  public.pack5_precheck_signup('new@example.com', '+2348031111111', 'FreshNick', 'run/1/1') = 'MATRIC_TAKEN');
select uf_test.ok('A8 precheck: empty matric is fine',
  public.pack5_precheck_signup('new@example.com', '+2348031111111', 'FreshNick', '  ') = 'OK');

-- ═════════════ B. signup refusals — and nothing half-written ═════════════
do $$
declare
  u uuid := gen_random_uuid();
  n_before int; n_after int;
begin
  insert into auth.users (id, email) values (u, 'b@example.com');
  perform uf_test.mk_proof('+2348032222222', 'h-good');
  perform uf_test.mk_proof('+2348032222223', 'h-expired', interval '-1 minute');
  perform uf_test.mk_proof('+2348032222224', 'h-used', interval '30 minutes', true);
  select count(*) into n_before from public.wallets;

  perform uf_test.ok('B1 no proof → refused',
    uf_test.raises(format($q$select uf_test.finish(%L,'', 'b@example.com','+2348032222222','BNick')$q$, u), 'PROOF_INVALID'));
  perform uf_test.ok('B2 unknown proof → refused',
    uf_test.raises(format($q$select uf_test.finish(%L,'nope','b@example.com','+2348032222222','BNick')$q$, u), 'PROOF_INVALID'));
  perform uf_test.ok('B3 expired proof → refused',
    uf_test.raises(format($q$select uf_test.finish(%L,'h-expired','b@example.com','+2348032222223','BNick')$q$, u), 'PROOF_EXPIRED'));
  perform uf_test.ok('B4 proof for a DIFFERENT phone → refused',
    uf_test.raises(format($q$select uf_test.finish(%L,'h-good','b@example.com','+2348039999999','BNick')$q$, u), 'PROOF_INVALID'));
  perform uf_test.ok('B5 already-used proof → refused',
    uf_test.raises(format($q$select uf_test.finish(%L,'h-used','b@example.com','+2348032222224','BNick')$q$, u), 'PROOF_USED'));
  perform uf_test.ok('B6 status helper agrees (OK/INVALID/EXPIRED/USED)',
    public.pack5_proof_status('+2348032222222','h-good') = 'OK'
    and public.pack5_proof_status('+2348039999999','h-good') = 'INVALID'
    and public.pack5_proof_status('+2348032222223','h-expired') = 'EXPIRED'
    and public.pack5_proof_status('+2348032222224','h-used') = 'USED');
  perform uf_test.ok('B7 taken nickname → refused',
    uf_test.raises(format($q$select uf_test.finish(%L,'h-good','b@example.com','+2348032222222','TAKENNICK')$q$, u), 'NICKNAME_TAKEN'));
  perform uf_test.ok('B8 taken matric → refused',
    uf_test.raises(format($q$select uf_test.finish(%L,'h-good','b@example.com','+2348032222222','BNick','run/1/1')$q$, u), 'MATRIC_TAKEN'));
  perform uf_test.ok('B9 bad referral code → refused',
    uf_test.raises(format($q$select uf_test.finish(%L,'h-good','b@example.com','+2348032222222','BNick',null,'NOPE')$q$, u), 'REFERRAL_INVALID'));
  perform uf_test.ok('B10 non-4-digit PIN → refused',
    uf_test.raises(format($q$select uf_test.finish(%L,'h-good','b@example.com','+2348032222222','BNick',null,null,'12a4')$q$, u), 'INVALID_INPUT'));
  perform uf_test.ok('B11 taken verified phone → refused (even with a valid proof for it)',
    (select uf_test.raises(format($q$select uf_test.finish(%L,'h-taken','b@example.com','+2348030000001','BNick')$q$, u), 'PHONE_TAKEN')
       from (select uf_test.mk_proof('+2348030000001','h-taken')) s));

  select count(*) into n_after from public.wallets;
  perform uf_test.ok('B12 after all refusals: no profile/wallet/PIN for the user, proof still unspent',
    not exists (select 1 from public.profiles where id = u)
    and n_after = n_before
    and not exists (select 1 from public.transaction_pins where user_id = u)
    and (select proof_used_at is null from public.signup_phone_verifications where proof_hash = 'h-good'));
end $$;

-- ═════════════ C. a valid signup writes everything together ═════════════
do $$
declare
  u uuid := gen_random_uuid();
  v_ref uuid := current_setting('uf.done')::uuid;
begin
  insert into auth.users (id, email) values (u, 'c@example.com');
  perform uf_test.mk_proof('+2348033333333', 'h-c');
  perform uf_test.finish(u, 'h-c', 'C@Example.com', '+2348033333333', 'CNick', 'run/9/9', 'p5code', '4321');

  perform uf_test.ok('C1 profile complete + verified + student + lower-cased email',
    exists (select 1 from public.profiles where id = u and onboarding_complete
            and role = 'student' and phone = '+2348033333333' and phone_verified_at is not null
            and nickname = 'CNick' and email = 'c@example.com' and matric_number = 'run/9/9'
            and referred_by_code = 'P5CODE'));
  perform uf_test.ok('C2 wallet created at 0 / Bronze',
    exists (select 1 from public.wallets where user_id = u and balance = 0 and tier = 'Bronze'));
  perform uf_test.ok('C3 PIN stored HASHED and verifies',
    (select pin_hash <> '4321' and pin_hash = extensions.crypt('4321', pin_hash)
       from public.transaction_pins where user_id = u));
  perform uf_test.ok('C4 referral relationship + code use recorded',
    exists (select 1 from public.referrals where referred_id = u and referrer_id = v_ref)
    and exists (select 1 from public.referral_code_uses where referred_id = u));
  perform uf_test.ok('C5 proof is now spent',
    public.pack5_proof_status('+2348033333333', 'h-c') = 'USED');
  perform uf_test.ok('C6 re-using the same proof for a second account is refused',
    uf_test.raises(format($q$select uf_test.finish(%L,'h-c','c2@example.com','+2348033333333','Other')$q$, gen_random_uuid()), 'PROOF_USED'));
  perform uf_test.ok('C7 the email is now reported taken',
    public.pack5_identity_status('c@example.com', '+2348034444444') = 'EMAIL_TAKEN'
    and public.pack5_identity_status('new@example.com', '+2348033333333') = 'PHONE_TAKEN');
end $$;

-- ═════════════ D. all-or-nothing: a LATE failure undoes the earlier writes ═════════════
-- A temporary trigger makes the very last step of pack5_finish_signup (marking
-- the proof spent) blow up AFTER the profile, wallet, referral and PIN were written.
create function uf_test.boom() returns trigger language plpgsql as $$
begin raise exception 'BOOM'; end $$;
create trigger t_boom before update on public.signup_phone_verifications
  for each row when (new.proof_used_at is not null and old.proof_used_at is null)
  execute function uf_test.boom();

do $$
declare u uuid := gen_random_uuid();
begin
  insert into auth.users (id, email) values (u, 'd@example.com');
  perform uf_test.mk_proof('+2348035555555', 'h-d');
  perform uf_test.ok('D1 late failure → the call raises',
    uf_test.raises(format($q$select uf_test.finish(%L,'h-d','d@example.com','+2348035555555','DNick',null,'P5CODE')$q$, u), 'BOOM'));
  perform uf_test.ok('D2 …and NOTHING was kept: no profile, wallet, PIN, referral; proof unspent',
    not exists (select 1 from public.profiles where id = u and onboarding_complete)
    and not exists (select 1 from public.wallets where user_id = u)
    and not exists (select 1 from public.transaction_pins where user_id = u)
    and not exists (select 1 from public.referrals where referred_id = u)
    and (select proof_used_at is null from public.signup_phone_verifications where proof_hash = 'h-d'));
end $$;
drop trigger t_boom on public.signup_phone_verifications;

-- ═════════════ E. send limits ═════════════
do $$
declare r jsonb; i int;
begin
  r := public.pack5_otp_reserve_send('+2348036000001', '1.1.1.1', 'dev-1');
  perform uf_test.ok('E1 first send allowed', (r->>'ok')::boolean);
  perform public.pack5_otp_finish_send((r->>'id')::uuid, 'pin-e1');

  r := public.pack5_otp_reserve_send('+2348036000001', '1.1.1.1', 'dev-1');
  perform uf_test.ok('E2 second send within 60 s → TOO_SOON with retry_after',
    r->>'reason' = 'TOO_SOON' and (r->>'retry_after')::int between 1 and 60);

  -- walk the clock back so only the daily cap is in play
  update public.signup_phone_verifications set created_at = now() - interval '2 minutes'
   where phone = '+2348036000001';
  for i in 2..5 loop
    r := public.pack5_otp_reserve_send('+2348036000001', '1.1.1.' || i, 'dev-e' || i);
    perform public.pack5_otp_finish_send((r->>'id')::uuid, 'pin-e' || i);
    update public.signup_phone_verifications set created_at = now() - interval '2 minutes'
     where phone = '+2348036000001' and created_at > now() - interval '1 minute';
  end loop;
  r := public.pack5_otp_reserve_send('+2348036000001', '9.9.9.9', 'dev-z');
  perform uf_test.ok('E3 6th send to one phone in 24 h → PHONE_LIMIT', r->>'reason' = 'PHONE_LIMIT');

  -- per IP: 20 distinct phones from one IP, the 21st is refused
  for i in 1..20 loop
    r := public.pack5_otp_reserve_send('+23480370' || lpad(i::text, 5, '0'), '7.7.7.7', 'dev-ip-' || i);
  end loop;
  r := public.pack5_otp_reserve_send('+2348037099999', '7.7.7.7', 'dev-ip-x');
  perform uf_test.ok('E4 21st send from one IP in an hour → IP_LIMIT', r->>'reason' = 'IP_LIMIT');

  -- per device: 10 phones, one device, the 11th is refused
  for i in 1..10 loop
    r := public.pack5_otp_reserve_send('+23480380' || lpad(i::text, 5, '0'), '8.8.8.' || i, 'dev-same');
  end loop;
  r := public.pack5_otp_reserve_send('+2348038099999', '8.8.8.99', 'dev-same');
  perform uf_test.ok('E5 11th send from one device in an hour → DEVICE_LIMIT', r->>'reason' = 'DEVICE_LIMIT');

  -- a cancelled (failed-at-Termii) send does not count
  r := public.pack5_otp_reserve_send('+2348039000001', '5.5.5.5', 'dev-c');
  perform public.pack5_otp_cancel_send((r->>'id')::uuid);
  perform uf_test.ok('E6 cancelled send leaves no row (no cooldown, no quota used)',
    not exists (select 1 from public.signup_phone_verifications where phone = '+2348039000001'));
end $$;

-- ═════════════ F. code attempts ═════════════
do $$
declare r jsonb; v_id uuid; i int;
begin
  insert into public.signup_phone_verifications (phone, pin_id) values ('+2348039100001', 'pin-f') returning id into v_id;
  for i in 1..5 loop
    r := public.pack5_otp_begin_verify('+2348039100001', '4.4.4.4');
  end loop;
  perform uf_test.ok('F1 five tries are allowed (attempts_left counts down to 0)',
    (r->>'ok')::boolean and (r->>'attempts_left')::int = 0);
  r := public.pack5_otp_begin_verify('+2348039100001', '4.4.4.4');
  perform uf_test.ok('F2 sixth try → TOO_MANY_ATTEMPTS', r->>'reason' = 'TOO_MANY_ATTEMPTS');

  r := public.pack5_otp_begin_verify('+2348039100002', '4.4.4.4');
  perform uf_test.ok('F3 no code sent for that phone → NO_ACTIVE_CODE', r->>'reason' = 'NO_ACTIVE_CODE');

  insert into public.signup_phone_verifications (phone, pin_id, expires_at)
  values ('+2348039100003', 'pin-old', now() - interval '1 second');
  r := public.pack5_otp_begin_verify('+2348039100003', '4.4.4.4');
  perform uf_test.ok('F4 expired code → NO_ACTIVE_CODE', r->>'reason' = 'NO_ACTIVE_CODE');

  -- a newer code supersedes the older one
  insert into public.signup_phone_verifications (phone, pin_id, created_at) values ('+2348039100004', 'pin-1', now() - interval '5 minutes');
  insert into public.signup_phone_verifications (phone, pin_id) values ('+2348039100004', 'pin-2');
  r := public.pack5_otp_begin_verify('+2348039100004', '4.4.4.4');
  perform uf_test.ok('F5 only the NEWEST code is checked', r->>'pin_id' = 'pin-2');

  -- verifying issues a proof and supersedes earlier unspent proofs
  perform uf_test.mk_proof('+2348039100005', 'h-old');
  insert into public.signup_phone_verifications (phone, pin_id) values ('+2348039100005', 'pin-new') returning id into v_id;
  perform public.pack5_otp_mark_verified(v_id, 'h-new');
  perform uf_test.ok('F6 new proof OK, older unspent proof for same phone is dead',
    public.pack5_proof_status('+2348039100005', 'h-new') = 'OK'
    and public.pack5_proof_status('+2348039100005', 'h-old') = 'USED');
end $$;

-- ═════════════ G. nothing is callable by app users ═════════════
select uf_test.ok('G1 anon cannot execute ANY pack5_* function',
  not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname like 'pack5\_%' and has_function_privilege('anon', p.oid, 'execute')));
select uf_test.ok('G2 authenticated cannot execute ANY pack5_* function',
  not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
              and p.proname like 'pack5\_%' and has_function_privilege('authenticated', p.oid, 'execute')));
select uf_test.ok('G3 service_role can execute them',
  (select bool_and(has_function_privilege('service_role', p.oid, 'execute')) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname like 'pack5\_%'));
select uf_test.ok('G4 anon/authenticated cannot read the two new tables',
  not has_table_privilege('anon', 'public.signup_phone_verifications', 'select')
  and not has_table_privilege('authenticated', 'public.signup_phone_verifications', 'select')
  and not has_table_privilege('anon', 'public.signup_events', 'select')
  and not has_table_privilege('authenticated', 'public.signup_events', 'select'));
select uf_test.ok('G5 identity answers are single short codes (no user data)',
  public.pack5_identity_status('taken@example.com', '+2348030000001') in ('EMAIL_TAKEN'));

-- ── Result grid ──────────────────────────────────────────────────────
select unnest(string_to_array(current_setting('uf.log', true), E'\n')) as result
 where true
 order by 1 asc;

rollback;
