-- =====================================================================
-- Pack 2 — SQL test for pack2_security_hardening.sql.
-- Run AFTER the migration (or, to dry-run, prepend the migration body in
-- the same transaction):
--   supabase db query --linked -f supabase/pack2_security_hardening_test.sql
-- One transaction; the last block RAISES the PASS/FAIL log, which rolls
-- everything back (no test user, order, wallet or PIN survives).
-- Users are simulated as PostgREST does (JWT claims + role authenticated),
-- so Row Level Security really applies.
-- =====================================================================
begin;

create schema uf_p2;
grant usage on schema uf_p2 to public;

create function uf_p2.ok(p_name text, p_cond boolean) returns void
language plpgsql as $$
begin
  perform set_config('uf.log',
    coalesce(current_setting('uf.log', true), '') ||
    case when coalesce(p_cond, false) then 'PASS  ' else 'FAIL  ' end ||
    p_name || E'\n', true);
end $$;
grant execute on function uf_p2.ok(text, boolean) to public;

create function uf_p2.raises(p_sql text, p_expect text) returns boolean
language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return position(p_expect in sqlerrm) > 0;
end $$;
grant execute on function uf_p2.raises(text, text) to public;

create function uf_p2.as_user(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
end $$;
grant execute on function uf_p2.as_user(uuid) to public;

do $$
declare
  s   uuid := gen_random_uuid();   -- student
  o   uuid := gen_random_uuid();   -- another student
  a   uuid := gen_random_uuid();   -- admin
  v   uuid;
  p   uuid;
  pd  uuid;
  g   uuid;
  e   uuid;
  r   jsonb;
  n   int;
begin
  insert into auth.users (id, email) values
    (s, 'p2s@example.invalid'), (o, 'p2o@example.invalid'), (a, 'p2a@example.invalid');
  insert into public.profiles (id, role, email, nickname, full_name, phone, onboarding_complete) values
    (s, 'student', 'p2s@example.invalid', 'p2s', 'P2 Student', '+2348091000001', true),
    (o, 'student', 'p2o@example.invalid', 'p2o', 'P2 Other',   '+2348091000002', true);
  insert into public.profiles (id, role, email, nickname, full_name, onboarding_complete, admin_tier)
  values (a, 'admin', 'p2a@example.invalid', 'p2a', 'P2 Admin', true, 'super_admin');
  insert into public.wallets (user_id, balance, virtual_account_number) values
    (s, 50000, 'UFX-P2-S-' || left(s::text, 6)), (o, 0, 'UFX-P2-O-' || left(o::text, 6));
  insert into public.transaction_pins (user_id, pin_hash)
  values (s, extensions.crypt('1234', extensions.gen_salt('bf')));

  insert into public.vendors (name) values ('P2 Test Kitchen') returning id into v;
  insert into public.products (vendor_id, name, category, base_price, section, food_subsection)
  values (v, 'P2 Rice', 'Rice', 1000, 'food', 'meal') returning id into p;
  insert into public.products (vendor_id, name, category, base_price, section, food_subsection, deleted_at)
  values (v, 'P2 Ghost Rice', 'Rice', 1000, 'food', 'meal', now()) returning id into pd;

  insert into public.referral_codes (code, owner_id, owner_label) values ('P2CODE', s, 'P2');

  -- A delivery checkout waiting for the final payment (as the rider leaves it).
  insert into public.delivery_groups (student_id, delivery_type, status, final_amount, rider_id)
  values (s, 'delivery', 'awaiting_final_payment', 3000, null) returning id into g;
  -- An errand waiting for the final payment.
  insert into public.orders (student_id, type, status, final_amount, commitment_fee_amount, total_amount)
  values (s, 'errand', 'awaiting_final_payment', 2000, 500, 500) returning id into e;

  -- ── S-01 / S-07: no direct writes by app users ──────────────────────
  perform uf_p2.as_user(s);
  set local role authenticated;
  perform uf_p2.ok('S01a a student cannot insert a (default "paid") order row directly',
    uf_p2.raises(format($q$insert into public.orders (student_id, type, delivery_type, total_amount) values (%L, 'food', 'pickup', 99999)$q$, s), 'row-level security'));
  perform uf_p2.ok('S01b … nor order_items into their own order',
    uf_p2.raises(format($q$insert into public.order_items (order_id, product_id, product_name, quantity, unit_price) values (%L, %L, 'x', 1, 0)$q$, e, p), 'row-level security'));
  perform uf_p2.ok('S01c … nor an errand_requests row',
    uf_p2.raises(format($q$insert into public.errand_requests (order_id, category, pickup_location, item_description) values (%L, 'x', 'x', 'x')$q$, e), 'row-level security'));
  reset role;
  perform uf_p2.ok('S01d lifetime spending / tier did not move',
    (select lifetime_spending from public.profiles where id = s) = 0
    and (select membership_tier from public.profiles where id = s) = 'Bronze');

  perform uf_p2.ok('S07 the "insert own profile" policy is gone',
    not exists (select 1 from pg_policies where schemaname = 'public'
                 and tablename = 'profiles' and cmd = 'INSERT'));

  -- ── S-02 / S-03 / S-06: functions app users must not call ────────────
  perform uf_p2.ok('S02a the old no-PIN checkout_group_order overload is dropped',
    to_regprocedure('public.checkout_group_order(uuid,jsonb,numeric,text,text)') is null);
  perform uf_p2.ok('S02b group-order RPCs are not callable by app users',
    not has_function_privilege('authenticated', 'public.checkout_group_order(uuid,jsonb,numeric,text,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.create_group_order(uuid,numeric)', 'execute')
    and not has_function_privilege('anon', 'public.join_group_order(uuid)', 'execute'));
  perform uf_p2.ok('S03 _insert_order_items / _line_items_subtotal / _delivery_fee / _check_transaction_pin are internal',
    not has_function_privilege('authenticated', 'public._insert_order_items(uuid,jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public._line_items_subtotal(uuid,jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public._delivery_fee(uuid,text)', 'execute')
    and not has_function_privilege('authenticated', 'public._check_transaction_pin(text)', 'execute')
    and not has_function_privilege('anon', 'public._insert_order_items(uuid,jsonb)', 'execute'));
  perform uf_p2.as_user(s);
  set local role authenticated;
  perform uf_p2.ok('S03b a student calling _insert_order_items is refused',
    uf_p2.raises(format($q$select public._insert_order_items(%L, '[{"product_id":"%s","quantity":5}]')$q$, e, p), 'permission denied'));
  reset role;
  perform uf_p2.ok('S06 birthday rewards / can_notify_order: service role only',
    not has_function_privilege('authenticated', 'public.process_birthday_rewards()', 'execute')
    and not has_function_privilege('anon', 'public.process_birthday_rewards()', 'execute')
    and has_function_privilege('service_role', 'public.process_birthday_rewards()', 'execute')
    and not has_function_privilege('authenticated', 'public.can_notify_order(uuid,uuid)', 'execute')
    and has_function_privilege('service_role', 'public.can_notify_order(uuid,uuid)', 'execute'));
  perform uf_p2.ok('S09 every SECURITY DEFINER function in public has a fixed search_path',
    not exists (select 1 from pg_proc pr join pg_namespace ns on ns.oid = pr.pronamespace
                 where ns.nspname = 'public' and pr.prosecdef
                   and not exists (select 1 from unnest(coalesce(pr.proconfig, '{}')) c
                                    where c like 'search_path=%')));

  -- ── S-04: PIN guessing is counted everywhere ─────────────────────────
  perform uf_p2.ok('S04a verify_transaction_pin (no lockout) is no longer callable',
    not has_function_privilege('authenticated', 'public.verify_transaction_pin(text)', 'execute'));

  perform uf_p2.as_user(s);
  set local role authenticated;
  r := public.pay_group_final_amount(g, '0000');
  reset role;
  perform uf_p2.ok('S04b wrong PIN on the delivery final payment → INVALID_PIN returned',
    r ->> 'error' = 'INVALID_PIN');
  perform uf_p2.ok('S04c … and the failed attempt is kept (counter = 1)',
    (select failed_attempts from public.transaction_pins where user_id = s) = 1);
  perform uf_p2.ok('S04d … and nothing was paid',
    (select status from public.delivery_groups where id = g) = 'awaiting_final_payment'
    and (select balance from public.wallets where user_id = s) = 50000);

  perform uf_p2.as_user(s);
  set local role authenticated;
  r := public.pay_final_amount(e, '9999');
  reset role;
  perform uf_p2.ok('S04e wrong PIN on the errand final payment → INVALID_PIN, counted (2)',
    r ->> 'error' = 'INVALID_PIN'
    and (select failed_attempts from public.transaction_pins where user_id = s) = 2);

  perform uf_p2.as_user(s);
  set local role authenticated;
  r := public.set_transaction_pin('5555', '1111');
  reset role;
  perform uf_p2.ok('S04f wrong current PIN on change-PIN → INVALID_CURRENT_PIN, counted (3), PIN unchanged',
    r ->> 'error' = 'INVALID_CURRENT_PIN'
    and (select failed_attempts from public.transaction_pins where user_id = s) = 3
    and (select pin_hash = extensions.crypt('1234', pin_hash) from public.transaction_pins where user_id = s));

  perform uf_p2.as_user(s);
  set local role authenticated;
  r := public.pay_group_final_amount(g, '1111');
  r := public.pay_group_final_amount(g, '2222');
  r := public.pay_group_final_amount(g, '1234');   -- right PIN, but locked now
  reset role;
  perform uf_p2.ok('S04g after 5 wrong PINs even the right PIN answers PIN_LOCKED',
    r ->> 'error' = 'PIN_LOCKED'
    and (select locked_until from public.transaction_pins where user_id = s) > now());
  perform uf_p2.as_user(s);
  set local role authenticated;
  r := public.set_transaction_pin('5555', '1234');
  reset role;
  perform uf_p2.ok('S04h change-PIN is locked too (no way around the lockout)',
    r ->> 'error' = 'PIN_LOCKED');

  update public.transaction_pins set failed_attempts = 0, locked_until = null where user_id = s;
  perform uf_p2.as_user(s);
  set local role authenticated;
  r := public.pay_group_final_amount(g, '1234');
  reset role;
  perform uf_p2.ok('S04i right PIN pays the delivery final amount once (₦3,000)',
    r ->> 'error' is null and (r ->> 'total_paid')::numeric = 3000
    and (select status from public.delivery_groups where id = g) = 'out_for_delivery'
    and (select balance from public.wallets where user_id = s) = 47000);
  perform uf_p2.as_user(s);
  set local role authenticated;
  perform uf_p2.ok('S04j paying the same checkout again is refused',
    uf_p2.raises(format($q$select public.pay_group_final_amount(%L, '1234')$q$, g), 'not awaiting final payment'));
  r := public.pay_final_amount(e, '1234');
  reset role;
  perform uf_p2.ok('S04k right PIN pays the errand final amount (₦2,000), ledger row written',
    r ->> 'error' is null
    and (select status from public.orders where id = e) = 'out_for_delivery'
    and (select balance from public.wallets where user_id = s) = 45000
    and exists (select 1 from public.wallet_transactions where user_id = s and order_id = e and amount = 2000));

  perform uf_p2.as_user(s);
  set local role authenticated;
  r := public.set_transaction_pin('5555', '1234');
  reset role;
  perform uf_p2.ok('S04l change-PIN with the right current PIN works',
    r ->> 'ok' = 'true'
    and (select pin_hash = extensions.crypt('5555', pin_hash) from public.transaction_pins where user_id = s));

  perform uf_p2.as_user(o);
  set local role authenticated;
  r := public.set_transaction_pin('4321', null);
  perform uf_p2.ok('S04m another student cannot pay this student''s checkout',
    uf_p2.raises(format($q$select public.pay_group_final_amount(%L, '4321')$q$, g), 'Unauthorized'));
  reset role;
  perform uf_p2.ok('S04n a first PIN can be set without a current PIN',
    r ->> 'ok' = 'true' and exists (select 1 from public.transaction_pins where user_id = o));
  perform uf_p2.ok('S04o anon cannot call the PIN / payment functions',
    not has_function_privilege('anon', 'public.set_transaction_pin(text,text)', 'execute')
    and not has_function_privilege('anon', 'public.pay_group_final_amount(uuid,text)', 'execute'));

  -- ── S-05: referral codes / amounts invisible to students ─────────────
  perform uf_p2.as_user(s);
  set local role authenticated;
  select count(*) into n from public.referral_codes;
  perform uf_p2.ok('S05a the code owner cannot read their own referral code', n = 0);
  perform uf_p2.ok('S05b my_referral_code() is refused',
    uf_p2.raises('select public.my_referral_code()', 'permission denied'));
  perform uf_p2.ok('S05c get_referral_leaderboard() is refused',
    uf_p2.raises('select public.get_referral_leaderboard()', 'permission denied'));
  reset role;
  perform uf_p2.as_user(a);
  set local role authenticated;
  select count(*) into n from public.referral_codes where code = 'P2CODE';
  reset role;
  perform uf_p2.ok('S05d an admin still reads referral codes', n = 1);

  -- ── B-01: search ──────────────────────────────────────────────────────
  perform uf_p2.as_user(s);
  set local role authenticated;
  r := public.search_products('P2 ');
  reset role;
  perform uf_p2.ok('B01a search finds the live product',
    exists (select 1 from jsonb_array_elements(r) x where x ->> 'product_id' = p::text));
  perform uf_p2.ok('B01b search hides the deleted product',
    not exists (select 1 from jsonb_array_elements(r) x where x ->> 'product_id' = pd::text));
  perform uf_p2.as_user(s);
  set local role authenticated;
  r := public.search_products('%');
  reset role;
  perform uf_p2.ok('B01c "%" is a literal, not "everything"', jsonb_array_length(r) = 0);
end $$;

do $$
begin
  raise exception 'PACK2 SECURITY TEST RESULTS (rolled back):%', E'\n' || current_setting('uf.log', true);
end $$;
