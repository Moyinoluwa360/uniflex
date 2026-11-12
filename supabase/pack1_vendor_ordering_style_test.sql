-- =====================================================================
-- Pack 1 / Part 3 — SQL test for vendor ordering styles.
--
-- Run AFTER pack1_vendor_ordering_style.sql, with the Supabase CLI:
--   supabase db query --linked -f supabase/pack1_vendor_ordering_style_test.sql
-- Everything runs in ONE transaction and the last block RAISES the result
-- log, which rolls the whole thing back: the test cafeteria, its menu, the
-- test users and their orders never exist outside this run. Every line of the
-- error text reads PASS or FAIL.
--
-- Users are simulated as PostgREST does it (JWT claims + role authenticated),
-- so Row Level Security really applies.
-- =====================================================================
begin;

create schema uf_t1;
grant usage on schema uf_t1 to public;

create function uf_t1.ok(p_name text, p_cond boolean) returns void
language plpgsql as $$
begin
  perform set_config('uf.log',
    coalesce(current_setting('uf.log', true), '') ||
    case when coalesce(p_cond, false) then 'PASS  ' else 'FAIL  ' end ||
    p_name || E'\n', true);
end $$;
grant execute on function uf_t1.ok(text, boolean) to public;

create function uf_t1.raises(p_sql text, p_expect text) returns boolean
language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  perform set_config('uf.last_err', sqlerrm, true);
  return position(p_expect in sqlerrm) > 0;
end $$;
grant execute on function uf_t1.raises(text, text) to public;

create function uf_t1.as_user(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
end $$;
grant execute on function uf_t1.as_user(uuid) to public;

-- ═════════════ M. Migration ═════════════
do $$
begin
  perform uf_t1.ok('M1 every existing vendor is pack_based',
    not exists (select 1 from public.vendors where ordering_style <> 'pack_based'));
  perform uf_t1.ok('M2 column is NOT NULL with default pack_based',
    exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'vendors'
               and column_name = 'ordering_style' and is_nullable = 'NO'
               and column_default like '%pack_based%'));
end $$;

-- ── Fixtures (all rolled back) ───────────────────────────────────────
do $$
declare
  st uuid := gen_random_uuid();   -- student
  rd uuid := gen_random_uuid();   -- rider
  sa uuid := gen_random_uuid();   -- super admin
  ks uuid := gen_random_uuid();   -- kitchen staff (admin, not super)
  vf uuid := gen_random_uuid();   -- test cafeteria (fixed menu)
  vp uuid := gen_random_uuid();   -- test pack vendor
  vd uuid := gen_random_uuid();   -- vendor inserted with no style
begin
  perform set_config('uf.st', st::text, true); perform set_config('uf.rd', rd::text, true);
  perform set_config('uf.sa', sa::text, true); perform set_config('uf.ks', ks::text, true);
  perform set_config('uf.vf', vf::text, true); perform set_config('uf.vp', vp::text, true);

  insert into auth.users (id, email) values
    (st, 'p1student@example.invalid'), (rd, 'p1rider@example.invalid'),
    (sa, 'p1super@example.invalid'),   (ks, 'p1kitchen@example.invalid');
  insert into public.profiles (id, role, admin_tier, email, nickname, full_name, phone, matric_number, onboarding_complete)
  values
    (st, 'student', null,            'p1student@example.invalid', 'p1stu', 'P1 Student', '+2348070000001', 'MAT/P1/1', true),
    (rd, 'rider',   null,            'p1rider@example.invalid',   'p1rid', 'P1 Rider',   '+2348070000002', null, true),
    (sa, 'admin',   'super_admin',   'p1super@example.invalid',   'p1sa',  'P1 Super',   '+2348070000003', null, true),
    (ks, 'admin',   'kitchen_staff', 'p1kitchen@example.invalid', 'p1ks',  'P1 Kitchen', '+2348070000004', null, true);
  insert into public.wallets (user_id, balance, virtual_account_number)
  values (st, 1000000, 'P1-' || left(st::text, 8));

  insert into public.vendors (id, name, description, is_featured, badge_label, is_active, pack_price, ordering_style)
  values (vf, 'P1 Test Cafeteria', 'test', false, 'Partner', true, 200, 'fixed_menu'),
         (vp, 'P1 Test Pack Vendor', 'test', false, 'Partner', true, 250, 'pack_based');
  insert into public.vendors (id, name, description, is_featured, badge_label, is_active)
  values (vd, 'P1 Default Vendor', 'test', false, 'Partner', true);
  perform uf_t1.ok('M3 a vendor inserted without a style gets pack_based',
    (select ordering_style from public.vendors where id = vd) = 'pack_based');
  perform uf_t1.ok('M4 the check constraint rejects other values',
    uf_t1.raises(format($q$update public.vendors set ordering_style = 'buffet' where id = %L$q$, vd),
                 'vendors_ordering_style_check'));

  -- Test cafeteria menu (fixed prices).
  insert into public.products (id, vendor_id, name, description, category, base_price, is_available, section, food_subsection)
  values
    ('00000000-0000-4000-a000-0000000000a1', vf, 'Rice with chicken', '', 'Rice',   3500, true,  'drinks', null),
    ('00000000-0000-4000-a000-0000000000a2', vf, 'Amala and ewedu',   '', 'Swallow',2500, true,  'food', 'meal'),
    ('00000000-0000-4000-a000-0000000000a3', vf, 'Coke 50cl',         '', 'Drinks',  500, true,  'drinks', null),
    ('00000000-0000-4000-a000-0000000000a4', vf, 'Sold-out stew',     '', 'Rice',   1000, false, 'food', 'meal');
  -- Pack vendor menu.
  insert into public.products (id, vendor_id, name, description, category, base_price, is_available, requires_pack, section, food_subsection)
  values
    ('00000000-0000-4000-a000-0000000000b1', vp, 'Jollof (spoon)', '', 'Meals', 300, true, true, 'food', 'meal'),
    ('00000000-0000-4000-a000-0000000000b2', vp, 'Fanta',          '', 'Drinks', 400, true, false, 'drinks', null);

  perform uf_t1.as_user(st); set local role authenticated;
  perform public.set_transaction_pin('2468');
  reset role;
end $$;

-- ═════════════ P. Permissions ═════════════
do $$
declare
  st uuid := current_setting('uf.st')::uuid;
  rd uuid := current_setting('uf.rd')::uuid;
  sa uuid := current_setting('uf.sa')::uuid;
  ks uuid := current_setting('uf.ks')::uuid;
  vp uuid := current_setting('uf.vp')::uuid;
  v_ok boolean;
begin
  -- Student / rider / kitchen staff: RLS lets them update nothing, so the
  -- style stays as it is (and inserting a vendor is refused outright).
  perform uf_t1.as_user(st); set local role authenticated;
  update public.vendors set ordering_style = 'fixed_menu' where id = vp;
  v_ok := uf_t1.raises($q$insert into public.vendors (name, description, is_featured, is_active, ordering_style)
                          values ('x','x',false,true,'fixed_menu')$q$, 'NOT_ALLOWED')
       or position('row-level security' in current_setting('uf.last_err', true)) > 0;
  reset role;
  perform uf_t1.ok('P1 a student cannot change the style', (select ordering_style from public.vendors where id = vp) = 'pack_based');
  perform uf_t1.ok('P2 a student cannot create a vendor with a style', v_ok);

  perform uf_t1.as_user(rd); set local role authenticated;
  update public.vendors set ordering_style = 'fixed_menu' where id = vp;
  reset role;
  perform uf_t1.ok('P3 a rider cannot change the style', (select ordering_style from public.vendors where id = vp) = 'pack_based');

  perform uf_t1.as_user(ks); set local role authenticated;
  update public.vendors set ordering_style = 'fixed_menu' where id = vp;
  reset role;
  perform uf_t1.ok('P4 kitchen staff (the only other staff role; there is no vendor-user role) cannot change it',
    (select ordering_style from public.vendors where id = vp) = 'pack_based');

  -- The guard itself, even if a policy were ever loosened.
  perform uf_t1.as_user(st);
  perform uf_t1.ok('P5 trigger refuses a non-admin change (NOT_ALLOWED)',
    uf_t1.raises(format($q$update public.vendors set ordering_style = 'fixed_menu' where id = %L$q$, vp), 'NOT_ALLOWED'));

  perform uf_t1.as_user(sa); set local role authenticated;
  update public.vendors set ordering_style = 'fixed_menu' where id = vp;
  reset role;
  perform uf_t1.ok('P6 a super admin can change it (no active orders)',
    (select ordering_style from public.vendors where id = vp) = 'fixed_menu');
  update public.vendors set ordering_style = 'pack_based' where id = vp;   -- back (service role)
  perform uf_t1.ok('P7 everyone signed in can read the style',
    (select ordering_style from public.vendors where id = vp) = 'pack_based');
end $$;

-- ═════════════ X. Pricing and validation ═════════════
do $$
declare
  st uuid := current_setting('uf.st')::uuid;
  sa uuid := current_setting('uf.sa')::uuid;
  vf uuid := current_setting('uf.vf')::uuid;
  vp uuid := current_setting('uf.vp')::uuid;
  rice uuid := '00000000-0000-4000-a000-0000000000a1';
  amala uuid := '00000000-0000-4000-a000-0000000000a2';
  coke uuid := '00000000-0000-4000-a000-0000000000a3';
  soldout uuid := '00000000-0000-4000-a000-0000000000a4';
  jollof uuid := '00000000-0000-4000-a000-0000000000b1';
  fanta uuid := '00000000-0000-4000-a000-0000000000b2';
  v_loc record; v_service numeric;
  v jsonb; g uuid; o uuid; bal0 numeric; bal1 numeric;
  legs jsonb; bd jsonb;
begin
  select id, price into v_loc from public.delivery_locations where is_active order by price limit 1;
  v_service := public._service_charge();

  perform uf_t1.as_user(st); set local role authenticated;

  -- X1 fixed-menu only: 2 × 3500 + 1 × 500, tampered unit_price ignored.
  select balance into bal0 from public.wallets where user_id = st;
  legs := jsonb_build_array(jsonb_build_object(
    'vendor_id', vf, 'ordering_style', 'fixed_menu', 'packs', '[]'::jsonb,
    'items', jsonb_build_array(
      jsonb_build_object('product_id', rice, 'quantity', 2, 'unit_price', 1),
      jsonb_build_object('product_id', coke, 'quantity', 1, 'price', 1))));
  v := public.create_paid_delivery_order(gen_random_uuid(), '2468', legs, v_loc.id, 'Room 1', null);
  g := (v ->> 'group_id')::uuid;
  select id into o from public.orders where delivery_group_id = g;
  select balance into bal1 from public.wallets where user_id = st;
  perform uf_t1.ok('X1 fixed menu: food total = 2×3500 + 1×500 = 7500, no pack fee',
    (select total_amount = 7500 and pack_count = 0 and pack_fee = 0 from public.orders where id = o));
  perform uf_t1.ok('X2 fixed menu: delivery fee = 1 bracket; wallet charged fee + service only',
    (v ->> 'delivery_fee_total')::numeric = v_loc.price
    and bal0 - bal1 = v_loc.price + v_service);
  perform uf_t1.ok('X3 tampered client prices are ignored (server prices used)',
    (select sum(unit_price * quantity) from public.order_items where order_id = o) = 7500);
  perform uf_t1.ok('X4 snapshot stored: name, unit price, quantity per line',
    (select count(*) from public.order_items
      where order_id = o and ((product_name = 'Rice with chicken' and unit_price = 3500 and quantity = 2)
                           or (product_name = 'Coke 50cl' and unit_price = 500 and quantity = 1))) = 2);
  perform uf_t1.ok('X5 no pack rows for a fixed-menu order',
    not exists (select 1 from public.order_packs where order_id = o));
  bd := public.get_order_breakdown(g);
  perform uf_t1.ok('X6 breakdown: plain item lines, no packs (student/rider/admin views)',
    jsonb_array_length(bd -> 'vendors' -> 0 -> 'packs') = 0
    and jsonb_array_length(bd -> 'vendors' -> 0 -> 'items') = 2
    and (bd -> 'vendors' -> 0 ->> 'vendor_total')::numeric = 7500);

  -- X7 another mix: 20 × 2500 (the max) + 3 × 500.
  legs := jsonb_build_array(jsonb_build_object(
    'vendor_id', vf, 'ordering_style', 'fixed_menu',
    'items', jsonb_build_array(
      jsonb_build_object('product_id', amala, 'quantity', 20),
      jsonb_build_object('product_id', coke, 'quantity', 3))));
  v := public.create_paid_delivery_order(gen_random_uuid(), '2468', legs, v_loc.id, 'Room 2', null);
  perform uf_t1.ok('X7 20 × 2500 + 3 × 500 = 51500 (20 is allowed)',
    (select total_amount from public.orders where delivery_group_id = (v ->> 'group_id')::uuid) = 51500);

  -- X8 mixed cart: fixed-menu leg + pack-based leg (one pack, no declared
  -- style = an older app build) — works like two pack vendors do today.
  legs := jsonb_build_array(
    jsonb_build_object('vendor_id', vf, 'ordering_style', 'fixed_menu',
      'items', jsonb_build_array(jsonb_build_object('product_id', rice, 'quantity', 1))),
    jsonb_build_object('vendor_id', vp,
      'items', jsonb_build_array(jsonb_build_object('product_id', jollof, 'quantity', 4),
                                 jsonb_build_object('product_id', fanta, 'quantity', 1)),
      'packs', jsonb_build_array(jsonb_build_object('items',
                 jsonb_build_array(jsonb_build_object('product_id', jollof, 'quantity', 4))))));
  v := public.create_paid_delivery_order(gen_random_uuid(), '2468', legs, v_loc.id, 'Room 3', null);
  g := (v ->> 'group_id')::uuid;
  perform uf_t1.ok('X8 mixed cart: one checkout, two vendor orders',
    (select count(*) from public.orders where delivery_group_id = g) = 2);
  perform uf_t1.ok('X9 mixed cart: fixed leg 3500 no packs; pack leg 4×300 + 400 + 1 pack × 250 = 1850',
    (select total_amount = 3500 and pack_count = 0 from public.orders where delivery_group_id = g and vendor_id = vf)
    and (select total_amount = 1850 and pack_count = 1 and pack_fee = 250 from public.orders where delivery_group_id = g and vendor_id = vp));
  perform uf_t1.ok('X10 mixed cart: delivery fee = one bracket per vendor',
    (v ->> 'delivery_fee_total')::numeric = 2 * v_loc.price);

  -- Rejections.
  perform uf_t1.ok('X11 quantity 0 is rejected',
    uf_t1.raises(format($q$select public.create_paid_delivery_order(gen_random_uuid(), '2468', %L::jsonb, %L, 'R', null)$q$,
      jsonb_build_array(jsonb_build_object('vendor_id', vf, 'ordering_style', 'fixed_menu',
        'items', jsonb_build_array(jsonb_build_object('product_id', rice, 'quantity', 0)))), v_loc.id), 'INVALID_QUANTITY'));
  perform uf_t1.ok('X12 quantity 21 is rejected (QUANTITY_TOO_HIGH)',
    uf_t1.raises(format($q$select public.create_paid_delivery_order(gen_random_uuid(), '2468', %L::jsonb, %L, 'R', null)$q$,
      jsonb_build_array(jsonb_build_object('vendor_id', vf, 'ordering_style', 'fixed_menu',
        'items', jsonb_build_array(jsonb_build_object('product_id', rice, 'quantity', 21)))), v_loc.id), 'QUANTITY_TOO_HIGH'));
  perform uf_t1.ok('X13 the max cannot be dodged with two lines of the same item (15 + 15)',
    uf_t1.raises(format($q$select public.create_paid_delivery_order(gen_random_uuid(), '2468', %L::jsonb, %L, 'R', null)$q$,
      jsonb_build_array(jsonb_build_object('vendor_id', vf,
        'items', jsonb_build_array(jsonb_build_object('product_id', rice, 'quantity', 15),
                                   jsonb_build_object('product_id', rice, 'quantity', 15)))), v_loc.id), 'QUANTITY_TOO_HIGH'));
  perform uf_t1.ok('X14 an unavailable item is rejected',
    uf_t1.raises(format($q$select public.create_paid_delivery_order(gen_random_uuid(), '2468', %L::jsonb, %L, 'R', null)$q$,
      jsonb_build_array(jsonb_build_object('vendor_id', vf,
        'items', jsonb_build_array(jsonb_build_object('product_id', soldout, 'quantity', 1)))), v_loc.id), 'PRODUCT'));
  perform uf_t1.ok('X15 an item from another vendor is rejected',
    uf_t1.raises(format($q$select public.create_paid_delivery_order(gen_random_uuid(), '2468', %L::jsonb, %L, 'R', null)$q$,
      jsonb_build_array(jsonb_build_object('vendor_id', vf,
        'items', jsonb_build_array(jsonb_build_object('product_id', fanta, 'quantity', 1)))), v_loc.id), 'PRODUCT_NOT_FOUND'));
  perform uf_t1.ok('X16 pack-style lines for a fixed-menu vendor are rejected (PACKS_NOT_ALLOWED)',
    uf_t1.raises(format($q$select public.create_paid_delivery_order(gen_random_uuid(), '2468', %L::jsonb, %L, 'R', null)$q$,
      jsonb_build_array(jsonb_build_object('vendor_id', vf,
        'items', jsonb_build_array(jsonb_build_object('product_id', amala, 'quantity', 2)),
        'packs', jsonb_build_array(jsonb_build_object('items',
                   jsonb_build_array(jsonb_build_object('product_id', amala, 'quantity', 2)))))), v_loc.id), 'PACKS_NOT_ALLOWED'));
  perform uf_t1.ok('X17 a cart built as pack-based for a fixed-menu vendor → VENDOR_STYLE_CHANGED',
    uf_t1.raises(format($q$select public.create_paid_delivery_order(gen_random_uuid(), '2468', %L::jsonb, %L, 'R', null)$q$,
      jsonb_build_array(jsonb_build_object('vendor_id', vf, 'ordering_style', 'pack_based',
        'items', jsonb_build_array(jsonb_build_object('product_id', rice, 'quantity', 1)))), v_loc.id), 'VENDOR_STYLE_CHANGED'));
  perform uf_t1.ok('X18 the reverse (fixed-menu cart for a pack vendor) → VENDOR_STYLE_CHANGED',
    uf_t1.raises(format($q$select public.create_paid_delivery_order(gen_random_uuid(), '2468', %L::jsonb, %L, 'R', null)$q$,
      jsonb_build_array(jsonb_build_object('vendor_id', vp, 'ordering_style', 'fixed_menu',
        'items', jsonb_build_array(jsonb_build_object('product_id', fanta, 'quantity', 1)))), v_loc.id), 'VENDOR_STYLE_CHANGED'));
  perform uf_t1.ok('X19 a rejected checkout charged nothing',
    (select count(*) from public.delivery_groups where student_id = st) = 3);
  reset role;

  -- X20 snapshot survives a later price change.
  update public.products set base_price = 9999 where id = rice;
  perform uf_t1.ok('X20 later price edits never change past orders',
    not exists (select 1 from public.order_items where product_id = rice and unit_price <> 3500));

  -- X21 order_packs guard (belt and braces).
  select id into o from public.orders where vendor_id = vf limit 1;
  perform uf_t1.ok('X21 pack rows can never be attached to a fixed-menu order',
    uf_t1.raises(format($q$insert into public.order_packs (order_id, pack_index, items) values (%L, 0, '[]')$q$, o), 'PACKS_NOT_ALLOWED'));

  -- X22 menu item validation for a fixed-menu vendor.
  perform uf_t1.as_user(sa); set local role authenticated;
  perform uf_t1.ok('X22 price 0 is rejected', uf_t1.raises(format($q$insert into public.products (vendor_id, name, description, category, base_price) values (%L, 'Free', '', 'Rice', 0)$q$, vf), 'INVALID_PRICE'));
  perform uf_t1.ok('X23 price above ₦500,000 is rejected', uf_t1.raises(format($q$insert into public.products (vendor_id, name, description, category, base_price) values (%L, 'Gold', '', 'Rice', 500001)$q$, vf), 'INVALID_PRICE'));
  perform uf_t1.ok('X24 a name is required', uf_t1.raises(format($q$insert into public.products (vendor_id, name, description, category, base_price) values (%L, '  ', '', 'Rice', 100)$q$, vf), 'NAME_REQUIRED'));
  perform uf_t1.ok('X25 a category is required', uf_t1.raises(format($q$insert into public.products (vendor_id, name, description, category, base_price) values (%L, 'Beans', '', ' ', 100)$q$, vf), 'CATEGORY_REQUIRED'));
  insert into public.products (vendor_id, name, description, category, base_price, requires_pack, section, food_subsection)
  values (vf, ' Beans ', '', ' Beans ', 1200, true, 'drinks', null);
  perform uf_t1.ok('X26 a fixed-menu item is stored as a plain item (no pack, trimmed)',
    exists (select 1 from public.products where vendor_id = vf and name = 'Beans'
             and category = 'Beans' and not requires_pack and section = 'food'));

  reset role;
  -- P8 change blocked while the vendor has active orders (claims = super admin).
  perform uf_t1.ok('P8 an admin change is blocked while orders are active (VENDOR_HAS_ACTIVE_ORDERS)',
    uf_t1.raises(format($q$update public.vendors set ordering_style = 'pack_based' where id = %L$q$, vf), 'VENDOR_HAS_ACTIVE_ORDERS')
    and (select ordering_style from public.vendors where id = vf) = 'fixed_menu');

  perform uf_t1.ok('X27 the helpers are not callable by app users',
    not has_function_privilege('authenticated', 'public._check_leg_style(uuid,text,jsonb,jsonb)', 'execute')
    and not has_function_privilege('anon', 'public._check_leg_style(uuid,text,jsonb,jsonb)', 'execute'));
end $$;

-- ── Result (raised so everything above rolls back) ───────────────────
do $$
begin
  raise exception 'PACK1 PART3 TEST RESULTS (rolled back):%', E'\n' || current_setting('uf.log', true);
end $$;
