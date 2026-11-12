-- =====================================================================
-- Pack 2 — SQL test for pack2_account_deletion.sql (one transaction; the
-- last block RAISES the PASS/FAIL log so everything rolls back).
--   supabase db query --linked -f supabase/pack2_account_deletion_test.sql
-- =====================================================================
begin;

create schema uf_d2;
grant usage on schema uf_d2 to public;

create function uf_d2.ok(p_name text, p_cond boolean) returns void
language plpgsql as $$
begin
  perform set_config('uf.log',
    coalesce(current_setting('uf.log', true), '') ||
    case when coalesce(p_cond, false) then 'PASS  ' else 'FAIL  ' end ||
    p_name || E'\n', true);
end $$;
grant execute on function uf_d2.ok(text, boolean) to public;

create function uf_d2.as_user(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
end $$;
grant execute on function uf_d2.as_user(uuid) to public;

do $$
declare
  s   uuid := gen_random_uuid();   -- student who deletes
  b   uuid := gen_random_uuid();   -- bystander student
  rd  uuid := gen_random_uuid();   -- rider
  done_order uuid;
  act_order  uuid;
  conv uuid;
  r   jsonb;
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (s,  'p2del@example.invalid',  '{"full_name":"Del Me"}'),
    (b,  'p2keep@example.invalid', '{}'),
    (rd, 'p2rider@example.invalid','{}');
  insert into auth.identities (provider_id, user_id, identity_data, provider)
  values (s::text, s, jsonb_build_object('sub', s, 'email', 'p2del@example.invalid'), 'email');
  insert into public.profiles (id, role, email, nickname, full_name, phone, matric_number, school, date_of_birth, onboarding_complete) values
    (s, 'student', 'p2del@example.invalid',  'p2del',  'Del Me',  '+2348092000001', 'MAT/P2DEL',  'RUN', '2004-01-01', true),
    (b, 'student', 'p2keep@example.invalid', 'p2keep', 'Keep Me', '+2348092000002', 'MAT/P2KEEP', 'RUN', '2004-01-02', true);
  insert into public.profiles (id, role, email, full_name, phone, onboarding_complete)
  values (rd, 'rider', 'p2rider@example.invalid', 'P2 Rider', '+2348092000003', true);
  insert into public.wallets (user_id, balance, virtual_account_number) values
    (s, 1500, 'UFX-P2D-' || left(s::text, 6)), (b, 700, 'UFX-P2K-' || left(b::text, 6));
  insert into public.wallet_transactions (user_id, type, amount, source, balance_after, reference)
  values (s, 'credit', 1500, 'topup', 1500, 'P2DEL-' || s), (b, 'credit', 700, 'topup', 700, 'P2KEEP-' || b);
  insert into public.transaction_pins (user_id, pin_hash) values
    (s, extensions.crypt('1234', extensions.gen_salt('bf'))),
    (b, extensions.crypt('1234', extensions.gen_salt('bf'))),
    (rd, extensions.crypt('1234', extensions.gen_salt('bf')));

  insert into public.orders (student_id, type, status, total_amount, notes, location_details)
  values (s, 'food', 'completed', 2500, 'no pepper', 'Room 12') returning id into done_order;
  insert into public.orders (student_id, type, status, total_amount)
  values (s, 'food', 'preparing', 900) returning id into act_order;
  insert into public.support_conversations (student_id) values (s) returning id into conv;
  insert into public.support_messages (conversation_id, sender_id, sender_role, sender_name, body)
  values (conv, s, 'student', 'Del Me', 'my phone is …');

  -- D1 staff cannot delete themselves in the app
  perform uf_d2.as_user(rd);
  set local role authenticated;
  r := public.delete_my_account('1234');
  reset role;
  perform uf_d2.ok('D1 a rider gets STAFF_ACCOUNT (admins remove staff)', r ->> 'error' = 'STAFF_ACCOUNT');

  -- D2 wrong PIN refused and counted
  perform uf_d2.as_user(s);
  set local role authenticated;
  r := public.delete_my_account('9999');
  reset role;
  perform uf_d2.ok('D2 wrong PIN → INVALID_PIN, counted, nothing deleted',
    r ->> 'error' = 'INVALID_PIN'
    and (select failed_attempts from public.transaction_pins where user_id = s) = 1
    and (select email from public.profiles where id = s) is not null);

  -- D3 refused while an order is in progress
  perform uf_d2.as_user(s);
  set local role authenticated;
  r := public.delete_my_account('1234');
  reset role;
  perform uf_d2.ok('D3 an order in progress → ACTIVE_ORDERS, nothing deleted',
    r ->> 'error' = 'ACTIVE_ORDERS'
    and (select phone from public.profiles where id = s) is not null
    and (select balance from public.wallets where user_id = s) = 1500);

  update public.orders set status = 'completed' where id = act_order;

  -- D4 the deletion itself
  perform uf_d2.as_user(s);
  set local role authenticated;
  r := public.delete_my_account('1234');
  reset role;
  perform uf_d2.ok('D4 deletion succeeds and reports the forfeited ₦1,500',
    r ->> 'ok' = 'true' and (r ->> 'forfeited')::numeric = 1500);
  perform uf_d2.ok('D5 no personal field is left on the profile; inactive',
    (select email is null and phone is null and nickname is null
        and matric_number is null and school is null and date_of_birth is null
        and full_name = 'Deleted user' and not is_active
       from public.profiles where id = s));
  perform uf_d2.ok('D6 the login is anonymous, banned and has no identities / sessions',
    (select email like 'deleted-%@deleted.uniflex.invalid' and phone is null
        and raw_user_meta_data = '{}'::jsonb and banned_until > now() + interval '50 years'
       from auth.users where id = s)
    and not exists (select 1 from auth.identities where user_id = s)
    and not exists (select 1 from auth.sessions where user_id = s));
  perform uf_d2.ok('D7 balance forfeited through the ledger (balance 0 = sum of ledger)',
    (select balance from public.wallets where user_id = s) = 0
    and exists (select 1 from public.wallet_transactions
                 where user_id = s and source = 'account_deleted' and amount = 1500)
    and (select sum(case when type = 'credit' then amount else -amount end)
           from public.wallet_transactions where user_id = s) = 0);
  perform uf_d2.ok('D8 order records are kept, without the note / address',
    exists (select 1 from public.orders where id = done_order and total_amount = 2500
              and notes is null and location_details is null));
  perform uf_d2.ok('D9 support chat, PIN and the old account number are gone',
    not exists (select 1 from public.support_conversations where student_id = s)
    and not exists (select 1 from public.support_messages where sender_id = s)
    and not exists (select 1 from public.transaction_pins where user_id = s)
    and (select virtual_account_number from public.wallets where user_id = s) like 'DELETED-%');
  perform uf_d2.ok('D10 the email / phone / nickname / matric can be used again',
    not exists (select 1 from auth.users where email = 'p2del@example.invalid')
    and not exists (select 1 from public.profiles
                     where phone = '+2348092000001' or nickname = 'p2del'
                        or matric_number = 'MAT/P2DEL'));
  perform uf_d2.ok('D11 the other student is untouched',
    (select email from public.profiles where id = b) = 'p2keep@example.invalid'
    and (select balance from public.wallets where user_id = b) = 700
    and exists (select 1 from public.transaction_pins where user_id = b));

  -- D12 a deleted account cannot call it again (no PIN any more)
  perform uf_d2.as_user(s);
  set local role authenticated;
  r := public.delete_my_account('1234');
  reset role;
  perform uf_d2.ok('D12 calling it again just answers PIN_NOT_SET (nothing breaks)',
    r ->> 'error' = 'PIN_NOT_SET');
  perform uf_d2.ok('D13 anon cannot call delete_my_account',
    not has_function_privilege('anon', 'public.delete_my_account(text)', 'execute'));
end $$;

do $$
begin
  raise exception 'PACK2 ACCOUNT DELETION TEST RESULTS (rolled back):%', E'\n' || current_setting('uf.log', true);
end $$;
