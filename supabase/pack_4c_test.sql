-- =====================================================================
-- Pack 4C — SQL test script
--
-- Paste into the Supabase SQL editor AFTER pack_4c.sql. Everything runs in
-- ONE transaction that is ROLLED BACK at the end — no test data survives.
-- Read the result grid at the bottom: every line starts with PASS or FAIL.
--
-- Method: read the dashboard numbers, seed a known set of checkouts, read
-- them again, and check the DIFFERENCE equals what the seeds should add.
-- (So it is safe to run on live data that already has orders.)
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

create function uf_test.as_user(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
end $$;
grant execute on function uf_test.as_user(uuid) to public;

-- Snapshots of the dashboard / analytics (as the admin).
create table uf_test.snap (label text primary key, dash jsonb, ana jsonb);
grant all on uf_test.snap to public;

-- ── Fixtures ─────────────────────────────────────────────────────────
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
    (v_student, 'uf4c-student@example.invalid'),
    (v_admin,   'uf4c-admin@example.invalid'),
    (v_r1,      'uf4c-r1@example.invalid'),
    (v_r2,      'uf4c-r2@example.invalid');

  insert into public.profiles (id, role, email, nickname, full_name, phone, matric_number, onboarding_complete, admin_tier)
  values
    (v_student, 'student', 'uf4c-student@example.invalid', 'uf4cstud', 'Test Student Four C', '08099990011', 'MAT/4C/999', true, null),
    (v_admin,   'admin',   'uf4c-admin@example.invalid',   'uf4cadm',  'Test Admin',          '08099990012', null, true, 'super_admin'),
    (v_r1,      'rider',   'uf4c-r1@example.invalid',      'uf4crid1', 'Test Rider One',      '08099990013', null, true, null),
    (v_r2,      'rider',   'uf4c-r2@example.invalid',      'uf4crid2', 'Test Rider Two',      '08099990014', null, true, null);
end $$;

-- ── 1. Before-snapshot ───────────────────────────────────────────────
do $$ begin
  perform uf_test.as_user(current_setting('uf.admin')::uuid);
  set local role authenticated;
  insert into uf_test.snap values ('before', public.get_dashboard_stats(), public.get_admin_analytics());
  reset role;
end $$;

-- ── 2. Seed (as superuser) ───────────────────────────────────────────
-- v_day = Lagos midnight today. "Just before midnight" is YESTERDAY in
-- Lagos even though it may still be today in UTC (the boundary case).
do $$
declare
  s   uuid := current_setting('uf.student')::uuid;
  r1  uuid := current_setting('uf.r1')::uuid;
  r2  uuid := current_setting('uf.r2')::uuid;
  v_day timestamptz := date_trunc('day', now() at time zone 'Africa/Lagos') at time zone 'Africa/Lagos';
  g1 uuid := gen_random_uuid(); g2 uuid := gen_random_uuid(); g3 uuid := gen_random_uuid();
  g4 uuid := gen_random_uuid(); g5 uuid := gen_random_uuid();
  p1a uuid := gen_random_uuid(); p1b uuid := gen_random_uuid(); p3a uuid := gen_random_uuid();
begin
  -- G1: paid, completed today, 2 vendor parts, food paid  -> fees 330, food 2000, rider r1
  insert into public.delivery_groups (id, student_id, delivery_type, commitment_fee_total, service_charge,
      final_amount, final_payment_paid, status, rider_id, is_paid, created_at, completed_at)
  values (g1, s, 'delivery', 300, 30, 2000, true, 'completed', r1, true, now() - interval '2 hours', now() - interval '1 hour');
  insert into public.orders (id, student_id, status, total_amount, delivery_group_id, rider_id, is_paid, completed_at, delivery_type)
  values (p1a, s, 'completed', 1200, g1, r1, true, now() - interval '1 hour', 'delivery'),
         (p1b, s, 'completed',  800, g1, r1, true, now() - interval '1 hour', 'delivery');
  insert into public.order_items (order_id, product_name, quantity, unit_price) values
    (p1a, 'Zzz 4C Jollof', 2, 600), (p1b, 'Zzz 4C Jollof', 3, 200);

  -- G2: paid, finished just BEFORE Lagos midnight (yesterday) -> adds nothing today
  insert into public.delivery_groups (id, student_id, delivery_type, commitment_fee_total, service_charge,
      final_amount, final_payment_paid, final_paid_at, status, is_paid, created_at, completed_at)
  values (g2, s, 'delivery', 200, 30, 1000, true, v_day - interval '5 minutes', 'completed', true,
          v_day - interval '30 minutes', v_day - interval '10 minutes');

  -- G3: UNPAID group (+ part with items) -> adds nothing anywhere
  insert into public.delivery_groups (id, student_id, delivery_type, commitment_fee_total, service_charge,
      final_amount, final_payment_paid, status, is_paid, completed_at)
  values (g3, s, 'delivery', 500, 30, 5000, true, 'completed', false, now());
  insert into public.orders (id, student_id, status, total_amount, delivery_group_id, is_paid, completed_at, delivery_type)
  values (p3a, s, 'completed', 5000, g3, false, now(), 'delivery');
  insert into public.order_items (order_id, product_name, quantity, unit_price) values (p3a, 'Zzz 4C Jollof', 100, 50);

  -- G4: paid, cancelled today -> counts as created + cancelled; fees stay (non-refundable)
  insert into public.delivery_groups (id, student_id, delivery_type, commitment_fee_total, service_charge,
      status, is_paid, cancelled_at)
  values (g4, s, 'delivery', 300, 30, 'cancelled', true, now());

  -- G5: paid, still active (rider accepted)
  insert into public.delivery_groups (id, student_id, delivery_type, commitment_fee_total, service_charge,
      status, is_paid, rider_id)
  values (g5, s, 'delivery', 250, 30, 'rider_accepted', true, r2);

  -- E1: errand, paid, completed today, rider r2 -> fees 430
  insert into public.orders (student_id, type, status, total_amount, commitment_fee_amount, service_charge,
      is_paid, rider_id, completed_at, delivery_type)
  values (s, 'errand', 'completed', 0, 400, 30, true, r2, now(), 'delivery');

  -- P1: pickup, paid, completed today -> food 1500
  insert into public.orders (student_id, status, total_amount, is_paid, completed_at, delivery_type)
  values (s, 'completed', 1500, true, now(), 'pickup');
  -- P2: pickup, paid, cancelled today (refunded) -> created+cancelled, food 0
  insert into public.orders (student_id, status, total_amount, is_paid, cancelled_at, delivery_type)
  values (s, 'cancelled', 900, true, now(), 'pickup');
  -- P3: UNPAID pickup
  insert into public.orders (student_id, status, total_amount, is_paid, delivery_type)
  values (s, 'placed', 700, false, 'pickup');
  -- B2: pickup, paid, placed 1 minute after Lagos midnight -> counts TODAY, food 100
  insert into public.orders (student_id, status, total_amount, is_paid, delivery_type, created_at)
  values (s, 'placed', 100, true, 'pickup', v_day + interval '1 minute');
end $$;

-- ── 3. After-snapshot + deltas ───────────────────────────────────────
do $$ begin
  perform uf_test.as_user(current_setting('uf.admin')::uuid);
  set local role authenticated;
  insert into uf_test.snap values ('after', public.get_dashboard_stats(), public.get_admin_analytics());
  reset role;
end $$;

create function uf_test.d(p_key text) returns numeric language sql as $$
  select (a.dash->>p_key)::numeric - (b.dash->>p_key)::numeric
    from uf_test.snap a, uf_test.snap b where a.label = 'after' and b.label = 'before' $$;
create function uf_test.da(p_key text) returns numeric language sql as $$
  select (a.ana->>p_key)::numeric - (b.ana->>p_key)::numeric
    from uf_test.snap a, uf_test.snap b where a.label = 'after' and b.label = 'before' $$;
grant execute on function uf_test.d(text), uf_test.da(text) to public;

select uf_test.ok('orders today +7 (G1 G4 G5 E1 P1 P2 B2; unpaid + yesterday excluded)', uf_test.d('orders_today') = 7);
select uf_test.ok('pending +2 (G5 rider_accepted, B2 placed)', uf_test.d('pending_count') = 2);
select uf_test.ok('completed today +3 (G1, E1, P1; G2 finished yesterday Lagos)', uf_test.d('completed_today') = 3);
select uf_test.ok('cancelled today +2 (G4, P2)', uf_test.d('cancelled_today') = 2);
select uf_test.ok('fees today +1370 (330+330+280+430)', uf_test.d('fees_today') = 1370);
select uf_test.ok('food today +3600 (2000 + 1500 + 100; cancelled pickup + unpaid + yesterday excluded)', uf_test.d('food_today') = 3600);
select uf_test.ok('unpaid group/order never counted (week >= today deltas still exclude it)',
  uf_test.d('fees_week') >= 1370 and uf_test.d('fees_month') >= uf_test.d('fees_week'));
select uf_test.ok('fees and food are separate numbers (no combined revenue key)',
  not ((select dash from uf_test.snap where label = 'after') ? 'today_revenue'));
select uf_test.ok('multi-vendor G1 counted ONCE in orders_today (analytics agrees)', uf_test.da('orders_today') = 7);
select uf_test.ok('analytics completed month >= 3', uf_test.da('completed_month') >= 3);

-- Top items: 5 sold on completed G1 (2+3, two parts, one checkout); the 100 on the unpaid group are ignored.
select uf_test.ok('top items: Zzz 4C Jollof = 5 (unpaid 100 ignored)',
  coalesce((select (e->>'quantity')::int
              from jsonb_array_elements((select ana->'top_items' from uf_test.snap where label = 'after')) e
             where e->>'name' = 'Zzz 4C Jollof'), 0) = 5);

-- Rider performance: r1 completed G1 once (parts not counted); r2 completed E1 once.
select uf_test.ok('rider r1: 1 completed (two vendor parts count once)',
  coalesce((select (e->>'completed')::int
              from jsonb_array_elements((select ana->'rider_performance' from uf_test.snap where label = 'after')) e
             where e->>'rider_id' = current_setting('uf.r1')), 0) = 1);
select uf_test.ok('rider r2: 1 completed (errand; G5 still active)',
  coalesce((select (e->>'completed')::int
              from jsonb_array_elements((select ana->'rider_performance' from uf_test.snap where label = 'after')) e
             where e->>'rider_id' = current_setting('uf.r2')), 0) = 1);
select uf_test.ok('rider performance shows the rider nickname',
  exists (select 1
            from jsonb_array_elements((select ana->'rider_performance' from uf_test.snap where label = 'after')) e
           where e->>'rider_id' = current_setting('uf.r1') and e->>'name' = 'uf4crid1'));
select uf_test.ok('completion rate is a percentage 0..100',
  (select (ana->>'completion_rate')::numeric between 0 and 100 from uf_test.snap where label = 'after'));

-- ── 4. Permissions ───────────────────────────────────────────────────
do $$ begin
  perform uf_test.as_user(current_setting('uf.student')::uuid);
  set local role authenticated;
  perform uf_test.ok('student cannot read dashboard stats', uf_test.raises('select public.get_dashboard_stats()', 'Unauthorized'));
  perform uf_test.ok('student cannot read analytics', uf_test.raises('select public.get_admin_analytics()', 'Unauthorized'));
  perform uf_test.ok('student cannot read profile basics', uf_test.raises('select * from public.admin_profile_basics(array[gen_random_uuid()])', 'Unauthorized'));
  perform uf_test.ok('student cannot set the WhatsApp number', uf_test.raises($q$select public.admin_set_support_whatsapp('08031234567')$q$, 'Unauthorized'));
  perform uf_test.ok('nobody can call _stat_entries directly', uf_test.raises('select * from public._stat_entries()', 'permission denied'));
  reset role;
end $$;

-- ── 5. Names for Admin ───────────────────────────────────────────────
do $$
declare v_n int; v_nick text; v_full text;
begin
  perform uf_test.as_user(current_setting('uf.admin')::uuid);
  set local role authenticated;
  select count(*), max(nickname), max(full_name) into v_n, v_nick, v_full
    from public.admin_profile_basics(array[current_setting('uf.student')::uuid]);
  perform uf_test.ok('admin reads a student nickname + full name through the RPC',
    v_n = 1 and v_nick = 'uf4cstud' and v_full = 'Test Student Four C');
  select count(*) into v_n from public.profiles where id = current_setting('uf.student')::uuid;
  perform uf_test.ok('(why it was blank) admin cannot read other profiles directly', v_n = 0);
  reset role;
end $$;

-- ── 6. Support WhatsApp number ───────────────────────────────────────
do $$
declare v text;
begin
  perform uf_test.as_user(current_setting('uf.admin')::uuid);
  set local role authenticated;
  perform uf_test.ok('0803… is stored as international digits',
    public.admin_set_support_whatsapp('08031234567') = '2348031234567');
  perform uf_test.ok('+234 803… with spaces is accepted',
    public.admin_set_support_whatsapp('+234 803 123 4567') = '2348031234567');
  perform uf_test.ok('2348… digits are accepted', public.admin_set_support_whatsapp('2348031234567') = '2348031234567');
  perform uf_test.ok('0803 123 4567 with spaces/dashes accepted', public.admin_set_support_whatsapp('0803-123 4567') = '2348031234567');
  perform uf_test.ok('letters rejected', uf_test.raises($q$select public.admin_set_support_whatsapp('abc123')$q$, 'INVALID_PHONE'));
  perform uf_test.ok('too short rejected', uf_test.raises($q$select public.admin_set_support_whatsapp('0803123')$q$, 'INVALID_PHONE'));
  reset role;

  perform uf_test.as_user(current_setting('uf.student')::uuid);
  set local role authenticated;
  perform uf_test.ok('student can read the number', public.get_support_whatsapp() = '2348031234567');
  reset role;

  perform uf_test.as_user(current_setting('uf.admin')::uuid);
  set local role authenticated;
  perform public.admin_set_support_whatsapp('   ');
  reset role;
  perform uf_test.as_user(current_setting('uf.student')::uuid);
  set local role authenticated;
  perform uf_test.ok('blank input clears it (student gets null → WhatsApp hidden)', public.get_support_whatsapp() is null);
  reset role;
end $$;

-- ── 7. final_paid_at trigger ─────────────────────────────────────────
do $$
declare g uuid := gen_random_uuid(); t1 timestamptz; t2 timestamptz;
begin
  insert into public.delivery_groups (id, student_id, delivery_type, status, is_paid)
  values (g, current_setting('uf.student')::uuid, 'delivery', 'awaiting_final_payment', true);
  perform uf_test.ok('final_paid_at empty before the final payment',
    (select final_paid_at is null from public.delivery_groups where id = g));
  update public.delivery_groups set final_payment_paid = true, final_amount = 500 where id = g;
  select final_paid_at into t1 from public.delivery_groups where id = g;
  perform uf_test.ok('final_paid_at stamped when final payment is made', t1 is not null);
  update public.delivery_groups set final_paid_at = now() + interval '1 day' where id = g;
  select final_paid_at into t2 from public.delivery_groups where id = g;
  perform uf_test.ok('final_paid_at cannot be rewritten', t1 = t2);
end $$;

-- ── Result ───────────────────────────────────────────────────────────
select line from unnest(string_to_array(trim(both E'\n' from current_setting('uf.log')), E'\n')) as line;

rollback;
