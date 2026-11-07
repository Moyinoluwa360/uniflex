-- =====================================================================
-- Pack 4A — SQL test script
--
-- Paste into the Supabase SQL editor AFTER running pack_4a.sql.
-- Everything runs inside ONE transaction that is ROLLED BACK at the end,
-- so no test data survives. It creates its own throw-away student,
-- admin and rider, and simulates each of them by setting the JWT claim
-- and `set local role authenticated`, exactly as PostgREST does.
--
-- Read the result table at the bottom: every line starts with PASS or
-- FAIL. If your SQL editor does not show the final result grid, open the
-- "Messages"/notices panel instead (each check also RAISEs a NOTICE).
--
-- If `set local role authenticated` is refused in your editor, run the
-- script from the Supabase CLI / psql as the `postgres` user instead —
-- that is the closest safe alternative; nothing else changes.
-- =====================================================================

begin;

create schema uf_test;
grant usage on schema uf_test to public;

-- Result log kept in a transaction-local setting so it works under any role.
create function uf_test.ok(p_name text, p_cond boolean) returns void
language plpgsql as $$
begin
  perform set_config('uf.log',
    coalesce(current_setting('uf.log', true), '') ||
    case when coalesce(p_cond, false) then 'PASS  ' else 'FAIL  ' end ||
    p_name || E'\n', true);
  raise notice '% %', case when coalesce(p_cond, false) then 'PASS' else 'FAIL' end, p_name;
end $$;
grant execute on function uf_test.ok(text, boolean) to public;

-- Runs a statement that is EXPECTED to raise; true if its message contains p_expect.
create function uf_test.raises(p_sql text, p_expect text) returns boolean
language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return position(p_expect in sqlerrm) > 0;
end $$;
grant execute on function uf_test.raises(text, text) to public;

-- ── Fixtures (as the SQL-editor superuser) ───────────────────────────
do $$
declare
  v_student uuid := gen_random_uuid();
  v_admin   uuid := gen_random_uuid();
  v_rider   uuid := gen_random_uuid();
begin
  perform set_config('uf.student', v_student::text, true);
  perform set_config('uf.admin',   v_admin::text,   true);
  perform set_config('uf.rider',   v_rider::text,   true);

  insert into auth.users (id, email) values
    (v_student, 'uf-test-student@example.invalid'),
    (v_admin,   'uf-test-admin@example.invalid'),
    (v_rider,   'uf-test-rider@example.invalid');

  insert into public.profiles (id, role, email, nickname, full_name, onboarding_complete)
  values
    (v_student, 'student', 'uf-test-student@example.invalid', 'tstudent', 'Test Student', true),
    (v_admin,   'admin',   'uf-test-admin@example.invalid',   'tadmin',   'Test Admin',   true),
    (v_rider,   'rider',   'uf-test-rider@example.invalid',   'trider',   'Test Rider',   true);

  insert into public.wallets (user_id, balance, virtual_account_number)
  values (v_student, 20000, 'TEST-' || left(v_student::text, 8));

  -- PIN 1234, set the way the app sets it (as the student).
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_student, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.set_transaction_pin('1234');
  reset role;
end $$;

-- ── 1. PIN + balance failures leave NOTHING behind ───────────────────
do $$
declare
  v_student uuid := current_setting('uf.student')::uuid;
  v_uni  uuid := '00000000-0000-0000-0000-000000000001';
  v_loc  uuid;
  v_prod uuid;
  v_legs jsonb;
  v_key  uuid := gen_random_uuid();
  v_res  jsonb;
  v_before numeric;
  v_after  numeric;
  v_groups int;
  v_orders int;
begin
  select id into v_loc  from public.delivery_locations where is_active limit 1;
  select id into v_prod from public.products
   where vendor_id = v_uni and is_available and deleted_at is null limit 1;
  v_legs := jsonb_build_array(jsonb_build_object(
    'vendor_id', v_uni,
    'items', jsonb_build_array(jsonb_build_object('product_id', v_prod, 'quantity', 2))));

  select balance into v_before from public.wallets where user_id = v_student;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_student, 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- wrong PIN
  v_res := public.create_paid_delivery_order(v_key, '0000', v_legs, v_loc, 'Room 1', null);
  perform uf_test.ok('wrong PIN returns INVALID_PIN', v_res ->> 'error' = 'INVALID_PIN');

  -- missing PIN
  v_res := public.create_paid_delivery_order(gen_random_uuid(), null, v_legs, v_loc, 'Room 1', null);
  perform uf_test.ok('missing PIN returns INVALID_PIN', v_res ->> 'error' = 'INVALID_PIN');

  reset role;
  select count(*) into v_groups from public.delivery_groups where student_id = v_student;
  select count(*) into v_orders from public.orders          where student_id = v_student;
  select balance into v_after from public.wallets where user_id = v_student;
  perform uf_test.ok('wrong/missing PIN created no group', v_groups = 0);
  perform uf_test.ok('wrong/missing PIN created no order', v_orders = 0);
  perform uf_test.ok('wrong/missing PIN did not touch wallet', v_after = v_before);
  perform uf_test.ok('failed PIN attempts are COUNTED (lockout counter committed)',
    (select failed_attempts from public.transaction_pins where user_id = v_student) = 2);

  -- insufficient balance
  update public.wallets set balance = 10 where user_id = v_student;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_student, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform uf_test.ok('insufficient balance raises INSUFFICIENT_BALANCE',
    uf_test.raises(format($f$select public.create_paid_delivery_order(%L, '1234', %L::jsonb, %L, 'Room 1', null)$f$,
      gen_random_uuid(), v_legs::text, v_loc), 'INSUFFICIENT_BALANCE'));
  reset role;
  select count(*) into v_groups from public.delivery_groups where student_id = v_student;
  select count(*) into v_orders from public.orders          where student_id = v_student;
  select balance into v_after from public.wallets where user_id = v_student;
  perform uf_test.ok('insufficient balance created no group/order', v_groups = 0 and v_orders = 0);
  perform uf_test.ok('insufficient balance left wallet untouched', v_after = 10);

  update public.wallets set balance = 20000 where user_id = v_student;
  update public.transaction_pins set failed_attempts = 0 where user_id = v_student;
end $$;

-- ── 2. Success, service charge once, idempotency ─────────────────────
do $$
declare
  v_student uuid := current_setting('uf.student')::uuid;
  v_uni     uuid := '00000000-0000-0000-0000-000000000001';
  v_partner uuid := '00000000-0000-0000-0000-000000000002';
  v_loc     uuid;
  v_price   numeric;
  v_p1      uuid;
  v_p2      uuid;
  v_legs    jsonb;
  v_key     uuid := gen_random_uuid();
  v_res     jsonb;
  v_res2    jsonb;
  v_before  numeric;
  v_after   numeric;
  v_gid     uuid;
  v_groups  int;
  v_expect  numeric;
begin
  select id, price into v_loc, v_price from public.delivery_locations where is_active limit 1;
  select id into v_p1 from public.products
   where vendor_id = v_uni     and is_available and deleted_at is null limit 1;
  select id into v_p2 from public.products
   where vendor_id = v_partner and is_available and deleted_at is null limit 1;

  v_legs := jsonb_build_array(
    jsonb_build_object('vendor_id', v_uni,
      'items', jsonb_build_array(jsonb_build_object('product_id', v_p1, 'quantity', 1))),
    jsonb_build_object('vendor_id', v_partner,
      'items', jsonb_build_array(jsonb_build_object('product_id', v_p2, 'quantity', 3))));

  select balance into v_before from public.wallets where user_id = v_student;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_student, 'role', 'authenticated')::text, true);
  set local role authenticated;

  v_res  := public.create_paid_delivery_order(v_key, '1234', v_legs, v_loc, 'Room 204', 'extra napkins');
  v_res2 := public.create_paid_delivery_order(v_key, '1234', v_legs, v_loc, 'Room 204', 'extra napkins');
  reset role;

  v_gid := (v_res ->> 'group_id')::uuid;
  v_expect := v_price * 2 + 30;             -- two vendors, 0 packs each (1× bracket) + ONE service charge

  perform uf_test.ok('delivery order succeeded', v_res ->> 'error' is null and v_gid is not null);
  perform uf_test.ok('total = per-vendor delivery fees + service charge once',
    (v_res ->> 'total_charged')::numeric = v_expect);
  perform uf_test.ok('service charge on the response is 30', (v_res ->> 'service_charge')::numeric = 30);
  perform uf_test.ok('group stores the service charge actually charged',
    (select service_charge from public.delivery_groups where id = v_gid) = 30);
  perform uf_test.ok('group is paid and in the rider pool state (commitment_paid)',
    (select status = 'commitment_paid' and is_paid from public.delivery_groups where id = v_gid));
  perform uf_test.ok('one leg per vendor',
    (select count(*) from public.orders where delivery_group_id = v_gid) = 2);
  perform uf_test.ok('legs are marked commitment_fee_paid',
    (select bool_and(commitment_fee_paid) from public.orders where delivery_group_id = v_gid));
  perform uf_test.ok('line-item price came from the products table',
    (select oi.unit_price = p.base_price
       from public.order_items oi join public.products p on p.id = oi.product_id
       join public.orders o on o.id = oi.order_id
      where o.delivery_group_id = v_gid and p.id = v_p1));

  select balance into v_after from public.wallets where user_id = v_student;
  perform uf_test.ok('wallet debited exactly once', v_before - v_after = v_expect);
  perform uf_test.ok('same key replayed → flagged replayed', (v_res2 ->> 'replayed')::boolean is true);
  perform uf_test.ok('same key returns the SAME group', (v_res2 ->> 'group_id')::uuid = v_gid);
  select count(*) into v_groups from public.delivery_groups where student_id = v_student;
  perform uf_test.ok('same key twice → exactly one group', v_groups = 1);
  perform uf_test.ok('same key twice → exactly one debit',
    (select count(*) from public.wallet_transactions where user_id = v_student and type = 'debit') = 1);
  perform set_config('uf.group1', v_gid::text, true);
  perform set_config('uf.key1', v_key::text, true);
  perform set_config('uf.legs1', v_legs::text, true);
  perform set_config('uf.loc1', v_loc::text, true);
end $$;

-- Another signed-in user presenting the SAME key must not receive (or
-- be able to probe) somebody else's order.
do $$
declare
  v_other uuid := gen_random_uuid();
begin
  insert into auth.users (id, email) values (v_other, 'uf-test-other@example.invalid');
  insert into public.profiles (id, role, email, nickname, full_name, onboarding_complete)
  values (v_other, 'student', 'uf-test-other@example.invalid', 'tother', 'Other Student', true);
  insert into public.wallets (user_id, balance, virtual_account_number)
  values (v_other, 5000, 'TEST-' || left(v_other::text, 8));
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.set_transaction_pin('4321');
  perform uf_test.ok('another student cannot reuse someone else''s idempotency key',
    uf_test.raises(format($f$select public.create_paid_delivery_order(%L, '4321', %L::jsonb, %L, 'x', null)$f$,
      current_setting('uf.key1'), current_setting('uf.legs1'), current_setting('uf.loc1')),
      'IDEMPOTENCY_KEY_IN_USE'));
  reset role;
end $$;

-- ── 3. Admin changes the service charge; past orders do not change ───
do $$
declare
  v_admin   uuid := current_setting('uf.admin')::uuid;
  v_student uuid := current_setting('uf.student')::uuid;
  v_uni     uuid := '00000000-0000-0000-0000-000000000001';
  v_loc     uuid;
  v_p1      uuid;
  v_res     jsonb;
begin
  select id into v_loc from public.delivery_locations where is_active limit 1;
  select id into v_p1 from public.products
   where vendor_id = v_uni and is_available and deleted_at is null limit 1;

  -- a student cannot change it
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_student, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform uf_test.ok('student cannot set the service charge',
    uf_test.raises('select public.admin_set_service_charge(1)', 'Unauthorized'));
  perform uf_test.ok('student can read the service charge',
    public.get_service_charge() = 30);
  reset role;

  -- admin with tier NULL counts as super admin in is_super_admin()
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform uf_test.ok('negative service charge rejected',
    uf_test.raises('select public.admin_set_service_charge(-5)', 'INVALID_AMOUNT'));
  perform public.admin_set_service_charge(50);
  reset role;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_student, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_res := public.create_paid_delivery_order(gen_random_uuid(), '1234',
    jsonb_build_array(jsonb_build_object('vendor_id', v_uni,
      'items', jsonb_build_array(jsonb_build_object('product_id', v_p1, 'quantity', 1)))),
    v_loc, 'Room 9', null);
  reset role;

  perform uf_test.ok('new order uses the new charge (50)',
    (select service_charge from public.delivery_groups where id = (v_res ->> 'group_id')::uuid) = 50);
  perform uf_test.ok('past order keeps the charge it was placed with (30)',
    (select service_charge from public.delivery_groups where id = current_setting('uf.group1')::uuid) = 30);

  update public.app_settings set value = '30' where key = 'service_charge';
end $$;

-- ── 4. Pickup: full food amount, no fees ─────────────────────────────
do $$
declare
  v_student uuid := current_setting('uf.student')::uuid;
  v_uni     uuid := '00000000-0000-0000-0000-000000000001';
  v_p1      uuid;
  v_price   numeric;
  v_res     jsonb;
  v_oid     uuid;
begin
  select id, base_price into v_p1, v_price from public.products
   where vendor_id = v_uni and is_available and deleted_at is null limit 1;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_student, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_res := public.create_paid_pickup_order(gen_random_uuid(), '1234', v_uni,
    jsonb_build_array(jsonb_build_object('product_id', v_p1, 'quantity', 2)),
    '[]'::jsonb, null, null);
  reset role;

  v_oid := (v_res ->> 'order_id')::uuid;
  perform uf_test.ok('pickup order created', v_oid is not null);
  perform uf_test.ok('pickup charges exactly the food amount (no delivery fee, no service charge)',
    (v_res ->> 'total_charged')::numeric = v_price * 2);
  perform uf_test.ok('pickup stores service_charge = 0',
    (select service_charge from public.orders where id = v_oid) = 0);
  perform uf_test.ok('pickup row is a pickup, source uniflex',
    (select delivery_type = 'pickup' and source = 'uniflex' from public.orders where id = v_oid));
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_student, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform uf_test.ok('partner vendor cannot be used for pickup',
    uf_test.raises(format($f$select public.create_paid_pickup_order(%L, '1234', %L,
        jsonb_build_array(jsonb_build_object('product_id', %L, 'quantity', 1)))$f$,
        gen_random_uuid(), '00000000-0000-0000-0000-000000000002',
        (select id from public.products
          where vendor_id = '00000000-0000-0000-0000-000000000002' limit 1)),
      'PICKUP_UNIFLEX_ONLY'));
  reset role;
end $$;

-- ── 5. Errand: fee from the category + service charge, never client ──
do $$
declare
  v_student uuid := current_setting('uf.student')::uuid;
  v_fee     numeric;
  v_res     jsonb;
  v_oid     uuid;
begin
  select flat_fee into v_fee from public.errand_categories
   where key = 'errand' and is_active and deleted_at is null;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_student, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_res := public.create_paid_errand(gen_random_uuid(), '1234', 'errand',
    'Block B', '', 'Buy two notebooks', null, null);
  perform uf_test.ok('errand with unknown category rejected',
    uf_test.raises($f$select public.create_paid_errand(gen_random_uuid(), '1234', 'nope', '', '', 'x', null, null)$f$,
      'CATEGORY_NOT_FOUND'));
  reset role;

  v_oid := (v_res ->> 'order_id')::uuid;
  perform uf_test.ok('errand created and already paid',
    (select commitment_fee_paid and is_paid and status = 'placed' from public.orders where id = v_oid));
  perform uf_test.ok('errand total = category fee + service charge',
    (v_res ->> 'total_charged')::numeric = v_fee + 30);
  perform uf_test.ok('errand stores service charge 30',
    (select service_charge from public.orders where id = v_oid) = 30);
  perform set_config('uf.errand', v_oid::text, true);
end $$;

-- ── 6. Client cannot set amounts ─────────────────────────────────────
do $$
begin
  perform uf_test.ok('no payment RPC takes a price/fee/amount/total parameter',
    not exists (
      select 1
        from pg_proc p, unnest(p.proargnames) a
       where p.pronamespace = 'public'::regnamespace
         and p.proname in ('create_paid_delivery_order', 'create_paid_pickup_order', 'create_paid_errand')
         and a ~* '(price|fee|amount|total|charge)'));
  perform uf_test.ok('old create-now-pay-later RPCs are gone',
    not exists (select 1 from pg_proc
                 where pronamespace = 'public'::regnamespace
                   and proname in ('place_multi_vendor_order', 'pay_group_commitment_fee',
                                   'pay_commitment_fee', 'place_errand_order',
                                   'place_errand_with_payment', 'place_partner_food_order',
                                   'place_food_order_with_payment')));
end $$;

-- ── 7. Unpaid (legacy) orders are invisible to everyone ──────────────
do $$
declare
  v_student uuid := current_setting('uf.student')::uuid;
  v_admin   uuid := current_setting('uf.admin')::uuid;
  v_rider   uuid := current_setting('uf.rider')::uuid;
  v_uni     uuid := '00000000-0000-0000-0000-000000000001';
  v_gid     uuid := gen_random_uuid();
  v_leg     uuid := gen_random_uuid();
  v_solo    uuid := gen_random_uuid();
  n int;
begin
  -- What the OLD button left behind: an unpaid group + leg, and an unpaid solo order.
  insert into public.delivery_groups (id, student_id, delivery_type, status, commitment_fee_total, is_paid)
  values (v_gid, v_student, 'delivery', 'placed', 300, false);
  insert into public.orders (id, student_id, vendor_id, source, type, status, delivery_type,
                             total_amount, delivery_group_id, commitment_fee_paid, is_paid)
  values (v_leg, v_student, v_uni, 'uniflex', 'food', 'placed', 'delivery', 500, v_gid, false, false);
  insert into public.orders (id, student_id, vendor_id, source, type, status, delivery_type,
                             total_amount, commitment_fee_paid, is_paid)
  values (v_solo, v_student, v_uni, 'partner', 'food', 'placed', 'delivery', 500, false, false);

  perform set_config('request.jwt.claims', json_build_object('sub', v_student, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.orders where id in (v_leg, v_solo);
  perform uf_test.ok('student does not see their unpaid orders', n = 0);
  select count(*) into n from public.delivery_groups where id = v_gid;
  perform uf_test.ok('student does not see their unpaid group', n = 0);
  reset role;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.orders where id in (v_leg, v_solo);
  perform uf_test.ok('admin (lists/analytics) does not see unpaid orders', n = 0);
  select count(*) into n from public.delivery_groups where id = v_gid;
  perform uf_test.ok('admin does not see the unpaid group', n = 0);
  select count(*) into n from public.orders where student_id = v_student and is_paid;
  perform uf_test.ok('admin still sees the PAID orders', n >= 2);
  reset role;

  perform set_config('request.jwt.claims', json_build_object('sub', v_rider, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.delivery_groups where id = v_gid;
  perform uf_test.ok('rider pool does not contain the unpaid group', n = 0);
  select count(*) into n from public.orders where id in (v_leg, v_solo);
  perform uf_test.ok('rider does not see unpaid orders', n = 0);
  reset role;

  perform uf_test.ok('the read-only legacy query still finds them (superuser view)',
    (select count(*) from public.orders
      where not is_paid and status = 'placed' and id in (v_leg, v_solo)) = 2);
end $$;

-- ── 8. Notifications: rider accept → final price (×2) → paid ─────────
do $$
declare
  v_student uuid := current_setting('uf.student')::uuid;
  v_rider   uuid := current_setting('uf.rider')::uuid;
  v_gid     uuid := current_setting('uf.group1')::uuid;
  v_n       int;
  v_body    text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v_rider, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.accept_delivery_group(v_gid);
  perform public.set_delivery_group_final_price(v_gid, 1500);
  perform public.set_delivery_group_final_price(v_gid, 1800);   -- rider changes the price
  reset role;

  select count(*) into v_n from public.notifications
   where user_id = v_student and type = 'rider_accepted' and group_id = v_gid;
  perform uf_test.ok('student notified: rider accepted', v_n = 1);

  select count(*) into v_n from public.notifications
   where user_id = v_student and type = 'final_price' and group_id = v_gid;
  perform uf_test.ok('student notified for the final price AND again when it changed', v_n = 2);

  select body into v_body from public.notifications
   where user_id = v_student and type = 'final_price' order by created_at desc, id limit 1;
  perform uf_test.ok('final-price message wording', v_body like 'Pay for your order: ₦%. Tap to pay.');
  perform uf_test.ok('final-price message carries the amount',
    exists (select 1 from public.notifications
             where user_id = v_student and body = 'Pay for your order: ₦1,800. Tap to pay.'));

  -- Student pays
  perform set_config('request.jwt.claims', json_build_object('sub', v_student, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.pay_group_final_amount(v_gid, '1234');
  reset role;
  perform uf_test.ok('rider notified: customer has paid',
    exists (select 1 from public.notifications
             where user_id = v_rider and type = 'customer_paid' and group_id = v_gid
               and body = 'Customer has paid. You can deliver.'));

  -- "Mark all read" sticks
  perform set_config('request.jwt.claims', json_build_object('sub', v_student, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform uf_test.ok('student has unread notifications', public.unread_notification_count() > 0);
  perform public.mark_all_notifications_read();
  perform uf_test.ok('mark all read → unread count 0', public.unread_notification_count() = 0);
  reset role;
  perform uf_test.ok('mark all read is stored in the database (read_at set on every row)',
    (select count(*) from public.notifications where user_id = v_student and read_at is null) = 0);
end $$;

-- ── 9. Notifications: decline + admin cancel + errand + pickup ───────
do $$
declare
  v_student uuid := current_setting('uf.student')::uuid;
  v_rider   uuid := current_setting('uf.rider')::uuid;
  v_admin   uuid := current_setting('uf.admin')::uuid;
  v_uni     uuid := '00000000-0000-0000-0000-000000000001';
  v_loc     uuid;
  v_p1      uuid;
  v_g1      uuid;
  v_g2      uuid;
  v_res     jsonb;
  v_errand  uuid := current_setting('uf.errand')::uuid;
begin
  select id into v_loc from public.delivery_locations where is_active limit 1;
  select id into v_p1 from public.products
   where vendor_id = v_uni and is_available and deleted_at is null limit 1;

  -- two more paid groups
  perform set_config('request.jwt.claims', json_build_object('sub', v_student, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_res := public.create_paid_delivery_order(gen_random_uuid(), '1234',
    jsonb_build_array(jsonb_build_object('vendor_id', v_uni,
      'items', jsonb_build_array(jsonb_build_object('product_id', v_p1, 'quantity', 1)))),
    v_loc, 'Room A', null);
  v_g1 := (v_res ->> 'group_id')::uuid;
  v_res := public.create_paid_delivery_order(gen_random_uuid(), '1234',
    jsonb_build_array(jsonb_build_object('vendor_id', v_uni,
      'items', jsonb_build_array(jsonb_build_object('product_id', v_p1, 'quantity', 1)))),
    v_loc, 'Room B', null);
  v_g2 := (v_res ->> 'group_id')::uuid;
  reset role;

  -- rider takes g1, quotes; student DECLINES
  perform set_config('request.jwt.claims', json_build_object('sub', v_rider, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.accept_delivery_group(v_g1);
  perform public.set_delivery_group_final_price(v_g1, 900);
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', v_student, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.decline_group_final_amount(v_g1);
  reset role;
  perform uf_test.ok('rider told: order cancelled by customer (decline)',
    exists (select 1 from public.notifications
             where user_id = v_rider and group_id = v_g1 and body = 'Order cancelled by customer.'));
  perform uf_test.ok('student not told "your order was cancelled" for their own decline',
    not exists (select 1 from public.notifications
                 where user_id = v_student and group_id = v_g1 and type = 'cancelled_by_admin'));

  -- rider takes g2; ADMIN cancels
  perform set_config('request.jwt.claims', json_build_object('sub', v_rider, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.accept_delivery_group(v_g2);
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.admin_cancel_delivery_group(v_g2, 'test');
  reset role;
  perform uf_test.ok('admin cancel → student told',
    exists (select 1 from public.notifications
             where user_id = v_student and group_id = v_g2 and body = 'Your order was cancelled.'));
  perform uf_test.ok('admin cancel → rider told',
    exists (select 1 from public.notifications
             where user_id = v_rider and group_id = v_g2 and body = 'Your order was cancelled.'));

  -- errand accepted + completed
  update public.orders set rider_id = v_rider, status = 'being_sourced' where id = v_errand;
  perform uf_test.ok('errand accepted → student told',
    exists (select 1 from public.notifications
             where user_id = v_student and order_id = v_errand and type = 'rider_accepted'));
  update public.orders set status = 'completed' where id = v_errand;
  perform uf_test.ok('errand completed → student told "delivered"',
    exists (select 1 from public.notifications
             where user_id = v_student and order_id = v_errand and body = 'Your order has been delivered.'));

  -- pickup ready
  update public.orders set status = 'ready_for_pickup'
   where student_id = v_student and delivery_type = 'pickup';
  perform uf_test.ok('pickup ready notification written',
    exists (select 1 from public.notifications
             where user_id = v_student and body = 'Your order is ready for pickup.'));

  -- no notification is ever written for an unpaid (never-paid) row
  perform uf_test.ok('no notifications were created for unpaid rows',
    not exists (select 1 from public.notifications n
                 join public.delivery_groups g on g.id = n.group_id
                where not g.is_paid));
end $$;

-- ── 10. Support chat: all three paths ────────────────────────────────
do $$
declare
  v_student uuid := current_setting('uf.student')::uuid;
  v_admin   uuid := current_setting('uf.admin')::uuid;
  v_errand  uuid := current_setting('uf.errand')::uuid;
  v_gid     uuid := current_setting('uf.group1')::uuid;
  v_res     jsonb;
  v_conv    uuid;
  n         int;
begin
  perform uf_test.ok('exactly ONE send_support_message exists',
    (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
        and proname = 'send_support_message') = 1);
  perform uf_test.ok('exactly one of each other support function',
    (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
        and proname in ('mark_support_read', 'resolve_support_conversation', 'get_support_unread_total')) = 3);

  perform set_config('request.jwt.claims', json_build_object('sub', v_student, 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- (1) direct message, no order — only p_body, exactly as the app calls it
  v_res := public.send_support_message(p_body => 'Hello, I need help');
  v_conv := (v_res ->> 'conversation_id')::uuid;
  perform uf_test.ok('direct student message works', v_conv is not null);

  -- (2) message with an order attached (errand/pickup order id)
  v_res := public.send_support_message(p_body => 'About this errand', p_order_id => v_errand);
  perform uf_test.ok('student message with order attached works', (v_res ->> 'message_id') is not null);

  -- (2b) message with a delivery group attached
  v_res := public.send_support_message(p_body => 'About this delivery', p_group_id => v_gid);
  perform uf_test.ok('student message with delivery group attached works', (v_res ->> 'message_id') is not null);

  perform uf_test.ok('cannot attach someone else''s / a non-existent order',
    uf_test.raises(format($f$select public.send_support_message(p_body => 'x', p_order_id => %L)$f$,
      gen_random_uuid()), 'does not belong'));
  reset role;

  select count(*) into n from public.support_messages where conversation_id = v_conv and order_id = v_errand;
  perform uf_test.ok('order id is stored on the message', n = 1);
  select count(*) into n from public.support_messages where conversation_id = v_conv and delivery_group_id = v_gid;
  perform uf_test.ok('delivery group id is stored on the message', n = 1);

  -- (3) admin reply
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_res := public.send_support_message(p_body => 'We are looking into it', p_conversation_id => v_conv);
  perform uf_test.ok('admin reply works', (v_res ->> 'message_id') is not null);
  perform uf_test.ok('admin unread total counts the student messages', public.get_support_unread_total() >= 3);
  perform public.mark_support_read(v_conv);
  reset role;

  perform uf_test.ok('student unread count incremented by the admin reply',
    (select student_unread_count from public.support_conversations where id = v_conv) = 1);
  perform uf_test.ok('student got an inbox notification for the reply',
    exists (select 1 from public.notifications
             where user_id = v_student and type = 'support' and conversation_id = v_conv));
  perform uf_test.ok('admin got an inbox notification for the student message',
    exists (select 1 from public.notifications
             where user_id = v_admin and type = 'support' and conversation_id = v_conv));
end $$;

-- ── Result ───────────────────────────────────────────────────────────
select line as "Pack 4A test result (all lines must start with PASS)"
from regexp_split_to_table(current_setting('uf.log'), E'\n') as line
where line <> '';

select
  count(*) filter (where line like 'PASS%') as passed,
  count(*) filter (where line like 'FAIL%') as failed
from regexp_split_to_table(current_setting('uf.log'), E'\n') as line
where line <> '';

rollback;   -- nothing above is kept
