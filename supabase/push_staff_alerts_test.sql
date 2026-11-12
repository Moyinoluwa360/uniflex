-- Staff alerts — SQL test. The block ends by RAISING its results, so
-- everything it did is rolled back (no rows and no pushes survive: pg_net
-- requests are only queued inside the transaction). The PASS/FAIL list is
-- the error message. Counts only look at the test users (real admins and
-- online riders also get the rolled-back alerts). Run AFTER push_staff_alerts.sql:
--   supabase db query --linked --project-ref <ref> -f supabase/push_staff_alerts_test.sql
do $$
declare
  stu uuid := gen_random_uuid();
  r_on uuid := gen_random_uuid();  r_off uuid := gen_random_uuid();
  adm1 uuid := gen_random_uuid();  adm2 uuid := gen_random_uuid();
  ven uuid;
  grp uuid; o1 uuid; o2 uuid; err uuid; pk uuid;
  n int;
  v_log text := E'\n';
begin
  insert into auth.users (id, email) values
    (stu, 'sa_stu@test.local'), (r_on, 'sa_ron@test.local'), (r_off, 'sa_roff@test.local'),
    (adm1, 'sa_a1@test.local'), (adm2, 'sa_a2@test.local');
  insert into public.profiles (id, email, role) select x.id, x.e, x.r from (values
    (stu, 'sa_stu@test.local', 'student'), (r_on, 'sa_ron@test.local', 'rider'),
    (r_off, 'sa_roff@test.local', 'rider'), (adm1, 'sa_a1@test.local', 'admin'),
    (adm2, 'sa_a2@test.local', 'admin')) x(id, e, r)
   where not exists (select 1 from public.profiles p where p.id = x.id);
  update public.profiles set role = 'student', nickname = 'SA Student', is_active = true where id = stu;
  update public.profiles set role = 'rider', is_active = true, rider_is_online = true  where id = r_on;
  update public.profiles set role = 'rider', is_active = true, rider_is_online = false where id = r_off;
  update public.profiles set role = 'admin', is_active = true where id in (adm1, adm2);

  select id into ven from public.vendors limit 1;

  -- ── 1. Food delivery checkout (group + 2 legs), then a gift flag ──
  insert into public.delivery_groups (student_id, delivery_type, delivery_location, status, commitment_fee_total)
  values (stu, 'delivery', 'Test Hall', 'commitment_paid', 500) returning id into grp;
  insert into public.orders (student_id, vendor_id, source, type, status, delivery_type, total_amount, delivery_group_id, commitment_fee_paid)
  values (stu, ven, 'uniflex', 'food', 'placed', 'delivery', 1500, grp, true) returning id into o1;
  insert into public.orders (student_id, vendor_id, source, type, status, delivery_type, total_amount, delivery_group_id, commitment_fee_paid)
  values (stu, ven, 'uniflex', 'food', 'placed', 'delivery', 700, grp, true) returning id into o2;
  update public.delivery_groups set is_gift = true where id = grp;
  set constraints all immediate;
  set constraints all deferred;

  select count(*) into n from public.notifications where group_id = grp and type = 'new_job' and user_id = r_on;
  v_log := v_log || case when n = 1 then 'PASS' else 'FAIL' end || '  food: online rider gets exactly 1 new_job (got ' || n || ')' || E'\n';
  select count(*) into n from public.notifications where type = 'new_job' and user_id = r_off;
  v_log := v_log || case when n = 0 then 'PASS' else 'FAIL' end || '  food: offline rider gets none' || E'\n';
  select count(*) into n from public.notifications where group_id = grp and type = 'new_job' and user_id = r_on and body like 'Gift delivery to Test Hall%';
  v_log := v_log || case when n = 1 then 'PASS' else 'FAIL' end || '  food: job text sees the gift flag + location (written later in the same checkout)' || E'\n';
  select count(*) into n from public.notifications where group_id = grp and type = 'admin_new_order' and user_id in (adm1, adm2);
  v_log := v_log || case when n = 2 then 'PASS' else 'FAIL' end || '  food: each admin gets 1 "New order" (got ' || n || ')' || E'\n';
  select count(*) into n from public.notifications where group_id = grp and type = 'admin_new_order' and user_id in (adm1, adm2) and body like '%₦2,200%';
  v_log := v_log || case when n = 2 then 'PASS' else 'FAIL' end || '  food: admin text has the food total (₦2,200)' || E'\n';
  select count(*) into n from public.notifications where order_id in (o1, o2) and type = 'admin_new_order' and user_id in (adm1, adm2);
  v_log := v_log || case when n = 0 then 'PASS' else 'FAIL' end || '  food: no extra "New order" per shop' || E'\n';

  -- ── 2. Rider accepts: no new alerts ──
  update public.delivery_groups set rider_id = r_on, status = 'rider_accepted' where id = grp;
  set constraints all immediate; set constraints all deferred;
  select count(*) into n from public.notifications where group_id = grp and type = 'new_job' and user_id = r_on;
  v_log := v_log || case when n = 1 then 'PASS' else 'FAIL' end || '  accept: no second new_job' || E'\n';

  -- ── 3. One shop cancelled by admin 1 (group still live) ──
  perform set_config('request.jwt.claims', json_build_object('sub', adm1, 'role', 'authenticated')::text, true);
  update public.orders set status = 'cancelled' where id = o2;
  set constraints all immediate; set constraints all deferred;
  select count(*) into n from public.notifications where order_id = o2 and type = 'admin_order_cancelled' and user_id = adm2;
  v_log := v_log || case when n = 1 then 'PASS' else 'FAIL' end || '  shop cancel: the other admin is told' || E'\n';
  select count(*) into n from public.notifications where order_id = o2 and type = 'admin_order_cancelled' and user_id = adm1;
  v_log := v_log || case when n = 0 then 'PASS' else 'FAIL' end || '  shop cancel: the admin who cancelled is not' || E'\n';

  -- ── 4. Whole checkout cancelled by the student: one alert, not one per shop ──
  perform set_config('request.jwt.claims', json_build_object('sub', stu, 'role', 'authenticated')::text, true);
  update public.delivery_groups set status = 'cancelled' where id = grp;
  update public.orders set status = 'cancelled' where id = o1;
  set constraints all immediate; set constraints all deferred;
  select count(*) into n from public.notifications where group_id = grp and type = 'admin_order_cancelled' and order_id is null and user_id in (adm1, adm2);
  v_log := v_log || case when n = 2 then 'PASS' else 'FAIL' end || '  group cancel: each admin told once (got ' || n || ')' || E'\n';
  select count(*) into n from public.notifications where order_id = o1 and type = 'admin_order_cancelled';
  v_log := v_log || case when n = 0 then 'PASS' else 'FAIL' end || '  group cancel: no per-shop repeat' || E'\n';
  select count(*) into n from public.notifications where group_id = grp and type = 'admin_order_cancelled' and user_id in (adm1, adm2) and body like '%by the customer%';
  v_log := v_log || case when n = 2 then 'PASS' else 'FAIL' end || '  group cancel: says "by the customer"' || E'\n';
  perform set_config('request.jwt.claims', '', true);

  -- ── 5. Errand ──
  insert into public.orders (student_id, source, type, status, delivery_type, total_amount, commitment_fee_paid)
  values (stu, 'uniflex', 'errand', 'placed', 'delivery', 800, true) returning id into err;
  insert into public.errand_requests (order_id, category, pickup_location, dropoff_location, item_description)
  values (err, 'laundry', 'Main Gate', 'Test Hall', 'bread');
  set constraints all immediate; set constraints all deferred;
  select count(*) into n from public.notifications where order_id = err and type = 'new_job' and user_id = r_on and body like 'Laundry Pickup & Dropoff: Main Gate → Test Hall%';
  v_log := v_log || case when n = 1 then 'PASS' else 'FAIL' end || '  errand: online rider gets new_job with pickup place' || E'\n';
  select count(*) into n from public.notifications where order_id = err and type = 'admin_new_order' and user_id in (adm1, adm2);
  v_log := v_log || case when n = 2 then 'PASS' else 'FAIL' end || '  errand: admins get "New order"' || E'\n';

  -- ── 6. Pickup order: admins yes, riders no ──
  insert into public.orders (student_id, vendor_id, source, type, status, delivery_type, total_amount)
  values (stu, ven, 'uniflex', 'food', 'placed', 'pickup', 1200) returning id into pk;
  set constraints all immediate; set constraints all deferred;
  select count(*) into n from public.notifications where order_id = pk and type = 'admin_new_order' and user_id in (adm1, adm2);
  v_log := v_log || case when n = 2 then 'PASS' else 'FAIL' end || '  pickup: admins get "New order"' || E'\n';
  select count(*) into n from public.notifications where order_id = pk and type = 'new_job';
  v_log := v_log || case when n = 0 then 'PASS' else 'FAIL' end || '  pickup: riders get nothing' || E'\n';

  -- ── 7. Errand cancelled by admin 2 ──
  perform set_config('request.jwt.claims', json_build_object('sub', adm2, 'role', 'authenticated')::text, true);
  update public.orders set status = 'cancelled' where id = err;
  set constraints all immediate; set constraints all deferred;
  select count(*) into n from public.notifications where order_id = err and type = 'admin_order_cancelled' and user_id = adm1 and body like '%by an admin%';
  v_log := v_log || case when n = 1 then 'PASS' else 'FAIL' end || '  errand cancel: other admin told, "by an admin"' || E'\n';
  perform set_config('request.jwt.claims', '', true);

  -- ── 8. Unpaid (legacy) checkout: silence ──
  insert into public.delivery_groups (student_id, delivery_type, status, is_paid)
  values (stu, 'delivery', 'placed', false) returning id into grp;
  set constraints all immediate; set constraints all deferred;
  select count(*) into n from public.notifications where group_id = grp;
  v_log := v_log || case when n = 0 then 'PASS' else 'FAIL' end || '  unpaid checkout: nobody notified' || E'\n';

  raise exception 'STAFF ALERT TEST RESULTS (rolled back):%', v_log;
end $$;
