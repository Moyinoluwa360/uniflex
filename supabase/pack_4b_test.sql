-- =====================================================================
-- Pack 4B — SQL test script
--
-- Paste into the Supabase SQL editor AFTER running pack_4a.sql and
-- pack_4b.sql. Everything runs inside ONE transaction that is ROLLED
-- BACK at the end, so no test data survives. It builds its own student,
-- admin and two riders and simulates each one with the JWT claim +
-- `set local role authenticated`, exactly as PostgREST does.
--
-- Read the result at the bottom: every line starts with PASS or FAIL.
-- (Each check also RAISEs a NOTICE if the result grid is hidden.)
--
-- If `set local role authenticated` is refused in your editor, run the
-- script from the Supabase CLI / psql as the `postgres` user instead —
-- that is the closest safe alternative; nothing else changes.
--
-- Limits of this script (be honest): it runs in one transaction, so it
-- cannot race two real connections. The 3-job cap is proven here
-- sequentially (the 4th accept fails, a freed slot works again); the
-- race-safety comes from the per-rider advisory lock + row lock in the
-- accept RPCs and is not exercised by two parallel sessions here.
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
grant execute on function uf_test.ok(text, boolean) to public;

create function uf_test.raises(p_sql text, p_expect text) returns boolean
language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return position(p_expect in sqlerrm) > 0;
end $$;
grant execute on function uf_test.raises(text, text) to public;

-- True if the statement raises p_msg AND carries exactly p_hint as its HINT.
create function uf_test.raises_hint(p_sql text, p_msg text, p_hint text) returns boolean
language plpgsql as $$
declare v_hint text;
begin
  execute p_sql;
  return false;
exception when others then
  get stacked diagnostics v_hint = pg_exception_hint;
  return position(p_msg in sqlerrm) > 0 and v_hint = p_hint;
end $$;
grant execute on function uf_test.raises_hint(text, text, text) to public;

create function uf_test.as_user(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
end $$;
grant execute on function uf_test.as_user(uuid) to public;

-- ── Fixtures (as the SQL-editor superuser) ───────────────────────────
do $$
declare
  v_student uuid := gen_random_uuid();
  v_admin   uuid := gen_random_uuid();
  v_r1      uuid := gen_random_uuid();
  v_r2      uuid := gen_random_uuid();
begin
  perform set_config('uf.student', v_student::text, true);
  perform set_config('uf.admin',   v_admin::text,   true);
  perform set_config('uf.r1',      v_r1::text,      true);
  perform set_config('uf.r2',      v_r2::text,      true);

  insert into auth.users (id, email) values
    (v_student, 'uf4b-student@example.invalid'),
    (v_admin,   'uf4b-admin@example.invalid'),
    (v_r1,      'uf4b-r1@example.invalid'),
    (v_r2,      'uf4b-r2@example.invalid');

  insert into public.profiles (id, role, email, nickname, full_name, phone, matric_number, onboarding_complete)
  values
    (v_student, 'student', 'uf4b-student@example.invalid', 'tstud', 'Test Student', '08099990001', 'MAT/4B/999', true),
    (v_admin,   'admin',   'uf4b-admin@example.invalid',   'tadm',  'Test Admin',   '08099990002', null, true),
    (v_r1,      'rider',   'uf4b-r1@example.invalid',      'trid1', 'Test Rider One', '08099990003', null, true),
    (v_r2,      'rider',   'uf4b-r2@example.invalid',      'trid2', 'Test Rider Two', '08099990004', null, true);

  insert into public.wallets (user_id, balance, virtual_account_number)
  values (v_student, 500000, 'TEST4B-' || left(v_student::text, 8));

  -- An "others" product so the Others list can be exercised.
  insert into public.products (vendor_id, name, category, base_price, section)
  values ('00000000-0000-0000-0000-000000000001', 'Test Napkins', 'others', 100, 'others');

  perform uf_test.as_user(v_student);
  set local role authenticated;
  perform public.set_transaction_pin('1234');
  reset role;
end $$;

-- ── 1. Orders: A = single vendor with packs, B = 3 vendors, C/D/E/F single ─
do $$
declare
  v_student uuid := current_setting('uf.student')::uuid;
  v_uni  uuid := '00000000-0000-0000-0000-000000000001';
  v_mama uuid := '00000000-0000-0000-0000-000000000002';
  v_smoo uuid := '00000000-0000-0000-0000-000000000004';
  v_loc  uuid;
  p_jol  uuid; p_chk uuid; p_wat uuid; p_nap uuid; p_banga uuid; p_berry uuid;
  v_res  jsonb;
  v_ga uuid; v_gb uuid; v_gc uuid; v_gd uuid; v_ge uuid;
  v_i int;
begin
  select id into v_loc from public.delivery_locations where is_active limit 1;
  select id into p_jol   from public.products where vendor_id = v_uni  and name = 'Jollof Rice';
  select id into p_chk   from public.products where vendor_id = v_uni  and name = 'Chicken';
  select id into p_wat   from public.products where vendor_id = v_uni  and name = 'Bottled Water';
  select id into p_nap   from public.products where vendor_id = v_uni  and name = 'Test Napkins';
  select id into p_banga from public.products where vendor_id = v_mama and name = 'Banga Soup + Starch';
  select id into p_berry from public.products where vendor_id = v_smoo and name = 'Berry Blast Smoothie';

  perform uf_test.as_user(v_student);
  set local role authenticated;

  -- A: ONE vendor, 2 packs, 1 loose Jollof, drinks, others.
  v_res := public.create_paid_delivery_order(gen_random_uuid(), '1234',
    jsonb_build_array(jsonb_build_object('vendor_id', v_uni,
      'items', jsonb_build_array(
        jsonb_build_object('product_id', p_jol, 'quantity', 3),
        jsonb_build_object('product_id', p_chk, 'quantity', 2),
        jsonb_build_object('product_id', p_wat, 'quantity', 2),
        jsonb_build_object('product_id', p_nap, 'quantity', 1)),
      'packs', jsonb_build_array(
        jsonb_build_object('items', jsonb_build_array(
          jsonb_build_object('product_id', p_jol, 'quantity', 1),
          jsonb_build_object('product_id', p_chk, 'quantity', 1))),
        jsonb_build_object('items', jsonb_build_array(
          jsonb_build_object('product_id', p_jol, 'quantity', 1),
          jsonb_build_object('product_id', p_chk, 'quantity', 1)))))),
    v_loc, 'Room 1', null);
  v_ga := (v_res ->> 'group_id')::uuid;
  perform set_config('uf.ga', v_ga::text, true);

  -- B: THREE vendors (Uniflex 1 pack, Mama Tee 1 pack, Smoothies no packs).
  v_res := public.create_paid_delivery_order(gen_random_uuid(), '1234',
    jsonb_build_array(
      jsonb_build_object('vendor_id', v_uni,
        'items', jsonb_build_array(jsonb_build_object('product_id', p_jol, 'quantity', 1)),
        'packs', jsonb_build_array(jsonb_build_object('items', jsonb_build_array(
          jsonb_build_object('product_id', p_jol, 'quantity', 1))))),
      jsonb_build_object('vendor_id', v_mama,
        'items', jsonb_build_array(jsonb_build_object('product_id', p_banga, 'quantity', 1)),
        'packs', jsonb_build_array(jsonb_build_object('items', jsonb_build_array(
          jsonb_build_object('product_id', p_banga, 'quantity', 1))))),
      jsonb_build_object('vendor_id', v_smoo,
        'items', jsonb_build_array(jsonb_build_object('product_id', p_berry, 'quantity', 2)))),
    v_loc, 'Room 2', null);
  v_gb := (v_res ->> 'group_id')::uuid;
  perform set_config('uf.gb', v_gb::text, true);

  -- C, D, E: small single-vendor deliveries.
  for v_i in 1..3 loop
    v_res := public.create_paid_delivery_order(gen_random_uuid(), '1234',
      jsonb_build_array(jsonb_build_object('vendor_id', v_uni,
        'items', jsonb_build_array(jsonb_build_object('product_id', p_wat, 'quantity', 1)))),
      v_loc, 'Room ' || (v_i + 2), null);
    perform set_config('uf.g' || chr(98 + v_i), (v_res ->> 'group_id'), true);  -- gc, gd, ge
  end loop;

  -- F: an errand.
  v_res := public.create_paid_errand(gen_random_uuid(), '1234',
    (select key from public.errand_categories limit 1),
    'Library', 'Hostel A', 'Collect a parcel', v_loc, 'Room 9');
  perform set_config('uf.errand', (v_res ->> 'order_id'), true);
  reset role;

  -- Push the creation time into the past so a history entry that wrongly
  -- showed created_at could never equal the completion time.
  update public.delivery_groups set created_at = now() - interval '3 hours'
   where id in (v_ga, v_gb, current_setting('uf.gc')::uuid,
                current_setting('uf.gd')::uuid, current_setting('uf.ge')::uuid);

  perform uf_test.ok('A (single vendor) was created', v_ga is not null);
  perform uf_test.ok('B (3 vendors) has 3 internal parts',
    (select count(*) from public.orders where delivery_group_id = v_gb) = 3);
  perform uf_test.ok('A has 2 order_packs rows, each with a recorded price of 200',
    (select count(*) from public.order_packs op join public.orders o on o.id = op.order_id
      where o.delivery_group_id = v_ga and op.price = 200) = 2);
end $$;

-- ── 2. get_order_breakdown: shape, pack prices, same for every role ───
do $$
declare
  v_student uuid := current_setting('uf.student')::uuid;
  v_admin   uuid := current_setting('uf.admin')::uuid;
  v_r1      uuid := current_setting('uf.r1')::uuid;
  v_r2      uuid := current_setting('uf.r2')::uuid;
  v_ga      uuid := current_setting('uf.ga')::uuid;
  v_gb      uuid := current_setting('uf.gb')::uuid;
  v_bs jsonb; v_ba jsonb; v_br1 jsonb; v_bb jsonb; v_v jsonb;
  v_leg_total numeric;
begin
  perform uf_test.as_user(v_student);
  set local role authenticated;
  v_bs := public.get_order_breakdown(v_ga);
  v_bb := public.get_order_breakdown(v_gb);
  reset role;

  v_v := v_bs -> 'vendors' -> 0;
  perform uf_test.ok('A: exactly one vendor', jsonb_array_length(v_bs -> 'vendors') = 1);
  perform uf_test.ok('A: two packs, titled by index', jsonb_array_length(v_v -> 'packs') = 2
    and (v_v -> 'packs' -> 0 ->> 'index') = '1' and (v_v -> 'packs' -> 1 ->> 'index') = '2');
  perform uf_test.ok('A: pack price is 200 each, NOT 0',
    (v_v -> 'packs' -> 0 ->> 'price')::numeric = 200 and (v_v -> 'packs' -> 1 ->> 'price')::numeric = 200);
  perform uf_test.ok('A: a pack lists exactly what is inside it (name x quantity)',
    (v_v -> 'packs' -> 0 -> 'items' -> 0 ->> 'name') = 'Jollof Rice'
    and (v_v -> 'packs' -> 0 -> 'items' -> 0 ->> 'quantity') = '1'
    and (v_v -> 'packs' -> 0 -> 'items' -> 1 ->> 'name') = 'Chicken');
  perform uf_test.ok('A: drinks are a plain list (Bottled Water x2)',
    jsonb_array_length(v_v -> 'drinks') = 1 and (v_v -> 'drinks' -> 0 ->> 'quantity') = '2');
  perform uf_test.ok('A: others are a plain list (Test Napkins)',
    jsonb_array_length(v_v -> 'others') = 1 and (v_v -> 'others' -> 0 ->> 'name') = 'Test Napkins');
  perform uf_test.ok('A: food that is NOT in a pack stays visible (Jollof 3 ordered - 2 packed = 1)',
    jsonb_array_length(v_v -> 'items') = 1 and (v_v -> 'items' -> 0 ->> 'quantity') = '1');
  select total_amount into v_leg_total from public.orders where delivery_group_id = v_ga;
  perform uf_test.ok('A: vendor_total = what the order stored for that vendor',
    (v_v ->> 'vendor_total')::numeric = v_leg_total);
  perform uf_test.ok('A: packs_total = 400', (v_v ->> 'packs_total')::numeric = 400);

  perform uf_test.ok('B: three vendors', jsonb_array_length(v_bb -> 'vendors') = 3);
  perform uf_test.ok('B: the no-pack vendor returns an empty packs list',
    exists (select 1 from jsonb_array_elements(v_bb -> 'vendors') x
             where x ->> 'vendor_name' = 'Campus Smoothies' and jsonb_array_length(x -> 'packs') = 0));
  perform uf_test.ok('B: every vendor with packs has priced packs (no zero)',
    not exists (select 1 from jsonb_array_elements(v_bb -> 'vendors') x,
                       jsonb_array_elements(x -> 'packs') pk
                 where (pk ->> 'price')::numeric <= 0));

  -- Same function, same answer for the student, an admin and (in the pool) a rider.
  perform uf_test.as_user(v_admin);
  set local role authenticated;
  v_ba := public.get_order_breakdown(v_ga);
  reset role;
  perform uf_test.as_user(v_r1);
  set local role authenticated;
  v_br1 := public.get_order_breakdown(v_ga);   -- group A is in the pool: items readable BEFORE accepting
  reset role;
  perform uf_test.ok('student, admin and rider get the identical breakdown',
    v_bs = v_ba and v_bs = v_br1);

  -- A leg id answers for its parent (legs are internal).
  perform uf_test.as_user(v_student);
  set local role authenticated;
  perform uf_test.ok('a leg id returns the parent breakdown',
    public.get_order_breakdown((select id from public.orders where delivery_group_id = v_gb limit 1)) = v_bb);
  reset role;

  -- Another rider cannot read it once it is NOT in the pool and not theirs: checked after accepts.
  perform uf_test.ok('breakdown JSON carries no fee keys',
    (v_bs::text || v_bb::text) !~* '(delivery_fee|commitment|service|"fee)');
end $$;

-- ── 3. Rider sees items before accepting, but NOT customer details ────
do $$
declare
  v_r2 uuid := current_setting('uf.r2')::uuid;
  v_gb uuid := current_setting('uf.gb')::uuid;
  v_pool jsonb;
  v_txt text;
begin
  perform uf_test.as_user(v_r2);
  set local role authenticated;
  v_pool := public.rider_job_pool();
  perform uf_test.ok('pool lists B once (one entry per checkout, not per vendor)',
    (select count(*) from jsonb_array_elements(v_pool -> 'groups') g where g ->> 'id' = v_gb::text) = 1);
  perform uf_test.ok('pool B shows its 3 stops and 3 vendor names',
    (select (g ->> 'stop_count')::int = 3 and jsonb_array_length(g -> 'vendor_names') = 3
       from jsonb_array_elements(v_pool -> 'groups') g where g ->> 'id' = v_gb::text));
  perform uf_test.ok('rider CAN read items before accepting',
    jsonb_array_length(public.get_order_breakdown(v_gb) -> 'vendors') = 3);
  perform uf_test.ok('rider CANNOT read customer details before accepting',
    uf_test.raises(format('select public.get_group_customer_info(%L)', v_gb), 'Not your delivery group'));
  perform uf_test.ok('rider cannot read the student profile row directly (no matric)',
    (select count(*) from public.profiles where id = current_setting('uf.student')::uuid) = 0);
  v_txt := v_pool::text;
  reset role;
  perform uf_test.ok('pool JSON has no phone, email, matric, PIN or fee',
    v_txt !~* '(08099990001|MAT/4B/999|matric|delivery_pin|fee|charge|commitment|email)');
end $$;

-- ── 4. The 3-active-jobs cap ──────────────────────────────────────────
do $$
declare
  v_r1 uuid := current_setting('uf.r1')::uuid;
  v_r2 uuid := current_setting('uf.r2')::uuid;
  v_ga uuid := current_setting('uf.ga')::uuid;
  v_gb uuid := current_setting('uf.gb')::uuid;
  v_gc uuid := current_setting('uf.gc')::uuid;
  v_gd uuid := current_setting('uf.gd')::uuid;
begin
  perform uf_test.as_user(v_r1);
  set local role authenticated;
  perform public.accept_delivery_group(v_ga);
  perform public.accept_delivery_group(v_gb);
  perform public.accept_delivery_group(v_gc);
  perform uf_test.ok('the 4th accept is refused with ACTIVE_JOB_LIMIT and the human sentence',
    uf_test.raises_hint(format('select public.accept_delivery_group(%L)', v_gd), 'ACTIVE_JOB_LIMIT',
      'You already have 3 active jobs. Finish one before accepting another.'));
  reset role;
  perform uf_test.ok('the refused job is still in the pool (nothing half-assigned)',
    (select status = 'commitment_paid' and rider_id is null from public.delivery_groups where id = v_gd));

  -- The cap is per rider: rider two can take it.
  perform uf_test.as_user(v_r2);
  set local role authenticated;
  perform public.accept_delivery_group(v_gd);
  perform uf_test.ok('items stay readable to the assigned rider AFTER accepting',
    jsonb_array_length(public.get_order_breakdown(v_gd) -> 'vendors') = 1);
  perform uf_test.ok('a rider who does not hold the job can no longer read it',
    uf_test.raises(format('select public.get_order_breakdown(%L)', v_gb), 'Unauthorized'));
  reset role;

  perform uf_test.ok('a different rider is not affected by the first rider''s cap',
    (select rider_id = v_r2 and status = 'rider_accepted' from public.delivery_groups where id = v_gd));
  perform uf_test.ok('active count for rider one is 3',
    public._rider_active_job_count(v_r1) = 3);
end $$;

-- ── 5. Customer details after accepting (still no matric / PIN) ───────
do $$
declare
  v_r1 uuid := current_setting('uf.r1')::uuid;
  v_ga uuid := current_setting('uf.ga')::uuid;
  v_info jsonb;
begin
  perform uf_test.as_user(v_r1);
  set local role authenticated;
  v_info := public.get_group_customer_info(v_ga);
  reset role;
  perform uf_test.ok('accepted rider gets name, phone, location details',
    v_info ->> 'full_name' = 'Test Student' and v_info ->> 'phone' = '08099990001'
    and v_info ->> 'location_details' = 'Room 1');
  perform uf_test.ok('...but never the matric number or the delivery PIN',
    v_info::text !~* 'MAT/4B/999' and (v_info -> 'delivery_pin') = 'null'::jsonb);
end $$;

-- ── 6. Flow for A and B: final price -> pay -> PIN -> ONE completion ──
do $$
declare
  v_student uuid := current_setting('uf.student')::uuid;
  v_r1 uuid := current_setting('uf.r1')::uuid;
  v_ga uuid := current_setting('uf.ga')::uuid;
  v_gb uuid := current_setting('uf.gb')::uuid;
  v_pin_a text; v_pin_b text;
  v_leg uuid;
begin
  select delivery_pin into v_pin_a from public.delivery_groups where id = v_ga;
  select delivery_pin into v_pin_b from public.delivery_groups where id = v_gb;

  perform uf_test.as_user(v_r1);
  set local role authenticated;
  perform public.set_delivery_group_final_price(v_ga, 3000);
  perform public.set_delivery_group_final_price(v_gb, 4500);
  reset role;

  perform uf_test.as_user(v_student);
  set local role authenticated;
  perform public.pay_group_final_amount(v_ga, '1234');
  perform public.pay_group_final_amount(v_gb, '1234');
  reset role;

  select id into v_leg from public.orders where delivery_group_id = v_gb limit 1;
  perform uf_test.as_user(v_r1);
  set local role authenticated;

  perform uf_test.ok('a wrong PIN is refused and completes nothing',
    uf_test.raises(format('select public.verify_group_delivery(%L, %L)', v_ga, 'ZZZZ'), 'Incorrect delivery PIN'));
  perform uf_test.ok('a part of a group cannot be completed on its own',
    uf_test.raises(format('select public.verify_delivery(%L, %L)', v_leg, v_pin_b), 'group delivery PIN'));

  perform public.verify_group_delivery(v_ga, v_pin_a);
  -- A is done: rider one holds B and C only, so one slot is free again.
  perform public.accept_delivery_group(current_setting('uf.ge')::uuid);
  perform public.verify_group_delivery(v_gb, v_pin_b);
  reset role;

  perform uf_test.ok('a slot freed by completing A can be used right away (E accepted)',
    (select rider_id = v_r1 from public.delivery_groups where id = current_setting('uf.ge')::uuid));

  perform uf_test.ok('A completed', (select status = 'completed' from public.delivery_groups where id = v_ga));
  perform uf_test.ok('B and all 3 of its parts completed',
    (select status = 'completed' from public.delivery_groups where id = v_gb)
    and (select count(*) = 3 and bool_and(status = 'completed') from public.orders where delivery_group_id = v_gb));
end $$;

-- ── 7. ONE completed_at on every record and every screen source ───────
do $$
declare
  v_r1 uuid := current_setting('uf.r1')::uuid;
  v_ga uuid := current_setting('uf.ga')::uuid;
  v_gb uuid := current_setting('uf.gb')::uuid;
  v_group_ts timestamptz;
  v_hist jsonb; v_item jsonb;
begin
  select completed_at into v_group_ts from public.delivery_groups where id = v_gb;

  perform uf_test.ok('B: completed_at is set on the parent', v_group_ts is not null);
  perform uf_test.ok('B: every internal part carries the SAME completed_at',
    (select count(*) = 3 and bool_and(completed_at = v_group_ts)
       from public.orders where delivery_group_id = v_gb));

  perform uf_test.as_user(v_r1);
  set local role authenticated;
  v_hist := public.rider_history();
  v_item := public.rider_history_item(v_gb);
  reset role;

  perform uf_test.ok('history: B appears exactly ONCE (not 1 + 3)',
    (select count(*) from jsonb_array_elements(v_hist) h where h ->> 'id' = v_gb::text) = 1
    and (select count(*) from jsonb_array_elements(v_hist) h
          where h ->> 'id' in (select id::text from public.orders where delivery_group_id = v_gb)) = 0);
  perform uf_test.ok('history shows completed_at, NOT created_at (created_at was 3h earlier)',
    (select (h ->> 'ended_at')::timestamptz = v_group_ts and (h ->> 'ended_at')::timestamptz <>
            (select created_at from public.delivery_groups where id = v_gb)
       from jsonb_array_elements(v_hist) h where h ->> 'id' = v_gb::text));
  perform uf_test.ok('history details read the same completed_at',
    (v_item ->> 'completed_at')::timestamptz = v_group_ts);
  perform uf_test.ok('history details: name and location, NO phone / email / matric / fee',
    v_item ->> 'customer_name' = 'Test Student' and v_item ->> 'delivery_location' is not null
    and v_item::text !~* '(08099990001|MAT/4B/999|phone|email|matric|fee|charge|commitment)');
end $$;

do $$
declare
  v_r1 uuid := current_setting('uf.r1')::uuid;
  v_ga uuid := current_setting('uf.ga')::uuid;
  v_info jsonb; v_ok boolean;
begin
  perform uf_test.as_user(v_r1);
  set local role authenticated;
  v_info := public.get_group_customer_info(v_ga);
  v_ok := (v_info ->> 'phone') is null and (v_info ->> 'email') is null
          and (v_info ->> 'location_details') is null and (v_info ->> 'student_note') is null;
  reset role;
  perform uf_test.ok('ended job: phone, email, details and note are withheld', v_ok);
end $$;

-- ── 8. completed_at can never be changed afterwards ───────────────────
do $$
declare
  v_gb uuid := current_setting('uf.gb')::uuid;
  v_before timestamptz; v_after timestamptz;
begin
  select completed_at into v_before from public.delivery_groups where id = v_gb;
  update public.delivery_groups set completed_at = now() + interval '5 hours' where id = v_gb;
  update public.orders set completed_at = now() + interval '5 hours' where delivery_group_id = v_gb;
  select completed_at into v_after from public.delivery_groups where id = v_gb;
  perform uf_test.ok('completed_at is immutable once stamped (group)', v_after = v_before);
  perform uf_test.ok('completed_at is immutable once stamped (parts)',
    (select bool_and(completed_at = v_before) from public.orders where delivery_group_id = v_gb));
end $$;

-- ── 9. Customer declines after the final price: ONE cancelled entry ───
do $$
declare
  v_student uuid := current_setting('uf.student')::uuid;
  v_r1 uuid := current_setting('uf.r1')::uuid;
  v_gc uuid := current_setting('uf.gc')::uuid;
  v_hist jsonb; v_item jsonb;
begin
  perform uf_test.as_user(v_r1);
  set local role authenticated;
  perform public.set_delivery_group_final_price(v_gc, 1200);
  reset role;
  perform uf_test.as_user(v_student);
  set local role authenticated;
  perform public.decline_group_final_amount(v_gc);
  reset role;

  perform uf_test.ok('declined group has a server-stamped cancelled_at',
    (select cancelled_at is not null and status = 'cancelled' and cancelled_by_student
       from public.delivery_groups where id = v_gc));

  perform uf_test.as_user(v_r1);
  set local role authenticated;
  v_hist := public.rider_history();
  v_item := public.rider_history_item(v_gc);
  reset role;
  perform uf_test.ok('cancelled job appears once in history, marked cancelled by the customer',
    (select count(*) from jsonb_array_elements(v_hist) h
      where h ->> 'id' = v_gc::text and (h ->> 'was_cancelled')::boolean
        and (h ->> 'cancelled_by_student')::boolean) = 1);
  perform uf_test.ok('cancelled details are read-only and carry no phone/email',
    v_item ->> 'status' = 'cancelled' and v_item::text !~* '(phone|email|08099990001)');
  perform uf_test.ok('after A, B completed and C cancelled, rider one holds only E',
    public._rider_active_job_count(v_r1) = 1);
end $$;

-- ── 10. Errand: accept -> PIN -> completed once; stats count checkouts ─
do $$
declare
  v_r2 uuid := current_setting('uf.r2')::uuid;
  v_errand uuid := current_setting('uf.errand')::uuid;
  v_pin text;
  v_ts timestamptz;
  v_stats json; v_hist jsonb;
begin
  select delivery_pin into v_pin from public.orders where id = v_errand;

  perform uf_test.as_user(v_r2);
  set local role authenticated;
  perform uf_test.ok('errand appears in the pool with no fee in it',
    (select count(*) from jsonb_array_elements(public.rider_job_pool() -> 'errands') e
      where e ->> 'id' = v_errand::text) = 1
    and public.rider_job_pool()::text !~* '(fee|charge|commitment)');
  perform public.accept_order(v_errand);
  perform uf_test.ok('a wrong PIN does not complete the errand',
    uf_test.raises(format('select public.verify_delivery(%L, %L)', v_errand, 'ZZZZ'), 'Incorrect delivery PIN'));
  perform public.verify_delivery(v_errand, v_pin);
  v_stats := public.get_rider_stats();
  v_hist := public.rider_history();
  reset role;

  select completed_at into v_ts from public.orders where id = v_errand;
  perform uf_test.ok('errand: completed once with a server completed_at',
    (select status = 'completed' from public.orders where id = v_errand) and v_ts is not null);
  perform uf_test.ok('errand: appears once in history',
    (select count(*) from jsonb_array_elements(v_hist) h where h ->> 'id' = v_errand::text) = 1);
  perform uf_test.ok('rider two stats: 1 completed checkout (the errand), 1 active (group D)',
    (v_stats ->> 'total_completed')::int = 1 and (v_stats ->> 'active_food')::int = 1
    and (v_stats ->> 'active_errands')::int = 0);
end $$;

do $$
declare
  v_r1 uuid := current_setting('uf.r1')::uuid;
  v_stats json;
begin
  perform uf_test.as_user(v_r1);
  set local role authenticated;
  v_stats := public.get_rider_stats();
  reset role;
  perform uf_test.ok('rider one stats count CHECKOUTS: A + B = 2 (B has 3 parts but counts once)',
    (v_stats ->> 'total_completed')::int = 2 and (v_stats ->> 'today_completed')::int = 2);
end $$;

-- ── 11. Admin dashboard counts one per checkout ───────────────────────
do $$
declare
  v_admin uuid := current_setting('uf.admin')::uuid;
  v_stats jsonb; v_expect int;
begin
  update public.profiles set admin_tier = null where id = v_admin;
  perform uf_test.as_user(v_admin);
  set local role authenticated;
  v_stats := public.get_dashboard_stats();
  reset role;
  select (select count(*) from public.orders
           where is_paid and delivery_group_id is null
             and created_at >= date_trunc('day', now() at time zone 'utc'))
       + (select count(*) from public.delivery_groups
           where is_paid and created_at >= date_trunc('day', now() at time zone 'utc'))
    into v_expect;
  perform uf_test.ok('dashboard today_orders_total = checkouts, not internal parts',
    (v_stats ->> 'today_orders_total')::int = v_expect);
end $$;

-- ── 12. Admin cancel stamps cancelled_at too ──────────────────────────
do $$
declare
  v_admin uuid := current_setting('uf.admin')::uuid;
  v_gd uuid := current_setting('uf.gd')::uuid;
begin
  perform uf_test.as_user(v_admin);
  set local role authenticated;
  perform public.admin_cancel_delivery_group(v_gd, 'test');
  reset role;
  perform uf_test.ok('admin cancel: group and parts get a cancelled_at',
    (select cancelled_at is not null from public.delivery_groups where id = v_gd)
    and (select bool_and(cancelled_at is not null) from public.orders where delivery_group_id = v_gd));
end $$;

-- ── 13. Riders cannot read the tables (PIN / fee exposure closed) ────
do $$
declare
  v_student uuid := current_setting('uf.student')::uuid;
  v_admin   uuid := current_setting('uf.admin')::uuid;
  v_r1 uuid := current_setting('uf.r1')::uuid;
  v_r2 uuid := current_setting('uf.r2')::uuid;
    v_ge uuid := current_setting('uf.ge')::uuid;
  v_n_groups int; v_n_orders int; v_n_errands int; v_n_signals int;
  v_pin text; v_detail jsonb; v_other jsonb;
begin
  -- r1 is ASSIGNED to group E (still active at this point).
  perform uf_test.as_user(v_r1);
  set local role authenticated;
  select count(*) into v_n_groups from public.delivery_groups;
  select count(*) into v_n_orders from public.orders;
  select count(*) into v_n_errands from public.errand_requests;
  select delivery_pin into v_pin from public.delivery_groups where id = v_ge;
  select count(*) into v_n_signals from public.rider_job_signals;
  v_detail := public.rider_group_detail(v_ge);
  reset role;
  perform uf_test.as_user(v_r2);
  set local role authenticated;
  v_other := public.rider_group_detail(v_ge);   -- belongs to rider one
  reset role;

  perform uf_test.ok('assigned rider reads NO rows from delivery_groups / orders / errand_requests',
    v_n_groups = 0 and v_n_orders = 0 and v_n_errands = 0);
  perform uf_test.ok('...so the delivery PIN cannot be read from the table', v_pin is null);
  perform uf_test.ok('rider_group_detail: the assigned rider gets status/location, no PIN or fees',
    v_detail ->> 'status' = 'rider_accepted' and v_detail ->> 'delivery_location' is not null
    and v_detail::text !~* '(delivery_pin|fee|charge|commitment|matric|phone|email)');
  perform uf_test.ok('rider_group_detail: someone else''s job returns nothing', v_other is null);
  perform uf_test.ok('riders can read the id-only live-refresh signals', v_n_signals > 0);

  perform uf_test.as_user(v_student);
  set local role authenticated;
  select count(*) into v_n_signals from public.rider_job_signals;
  select delivery_pin into v_pin from public.delivery_groups where id = v_ge;
  select count(*) into v_n_groups from public.delivery_groups;
  select count(*) into v_n_orders from public.orders;
  reset role;
  perform uf_test.ok('students cannot read the signals', v_n_signals = 0);
  perform uf_test.ok('the student still reads their own groups, orders and delivery PIN',
    v_n_groups >= 5 and v_n_orders >= 5 and v_pin is not null);

  perform uf_test.as_user(v_admin);
  set local role authenticated;
  select count(*) into v_n_groups from public.delivery_groups;
  reset role;
  perform uf_test.ok('admin still reads every group', v_n_groups >= 5);
end $$;

-- ── 14. Counting once per checkout; old kitchen hand-off gone ────────
do $$
declare
  v_student uuid := current_setting('uf.student')::uuid;
  v_ge uuid := current_setting('uf.ge')::uuid;
  v_before text; v_after text;
begin
  perform uf_test.ok('profile total_orders counts CHECKOUTS (one per group), not vendor parts',
    (select total_orders from public.profiles where id = v_student)
      = (select count(*) from public.delivery_groups where student_id = v_student));

  select status into v_before from public.delivery_groups where id = v_ge;
  update public.orders set status = 'ready' where delivery_group_id = v_ge;
  select status into v_after from public.delivery_groups where id = v_ge;
  perform uf_test.ok('a kitchen "ready" on the parts no longer moves the group',
    v_before = v_after and v_after = 'rider_accepted');

  perform uf_test.ok('removed objects are really gone',
    not exists (select 1 from pg_proc where proname in
      ('get_group_items','confirm_pickup','flag_item_unavailable','add_custom_item','_check_group_ready_after_kitchen'))
    and to_regclass('public.delivery_records') is null
    and to_regclass('public.order_item_flags') is null
    and to_regclass('public.order_custom_items') is null);
end $$;

-- ── Result ────────────────────────────────────────────────────────────
select 'RESULT' as "—", current_setting('uf.log') as report;
select count(*) filter (where line like 'PASS%') as passed,
       count(*) filter (where line like 'FAIL%') as failed
  from unnest(string_to_array(current_setting('uf.log'), E'\n')) as line
 where line <> '';

rollback;
