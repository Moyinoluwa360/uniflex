-- =====================================================================
-- Pack 6 — SQL test script (food gifting)
--
-- Paste into the Supabase SQL editor AFTER pack_6.sql. Everything runs in
-- ONE transaction that is ROLLED BACK at the end — no test data survives.
-- Read the result grid at the bottom: every line starts with PASS or FAIL.
--
-- Users are simulated exactly as PostgREST does it: the JWT claims are set
-- and `set local role authenticated` is used, so Row Level Security really
-- applies. If your SQL editor refuses `set local role authenticated`, run the
-- file with the Supabase CLI instead (supabase db query -f ...).
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

-- ── Fixtures ─────────────────────────────────────────────────────────
do $$
declare
  s uuid := gen_random_uuid();   -- sender
  r uuid := gen_random_uuid();   -- recipient
  t uuid := gen_random_uuid();   -- a third student
  a uuid := gen_random_uuid();   -- admin
  r1 uuid := gen_random_uuid();  -- rider
  r2 uuid := gen_random_uuid();  -- another rider
begin
  perform set_config('uf.s', s::text, true);  perform set_config('uf.r', r::text, true);
  perform set_config('uf.t', t::text, true);  perform set_config('uf.a', a::text, true);
  perform set_config('uf.r1', r1::text, true); perform set_config('uf.r2', r2::text, true);

  insert into auth.users (id, email) values
    (s, 'sender6@example.invalid'), (r, 'jane.recipient6@example.invalid'),
    (t, 'third6@example.invalid'), (a, 'admin6@example.invalid'),
    (r1, 'rider6a@example.invalid'), (r2, 'rider6b@example.invalid');

  insert into public.profiles (id, role, email, nickname, full_name, phone, matric_number, onboarding_complete)
  values
    (s,  'student', 'sender6@example.invalid',         'sendy',  'Sade Sender',    '+2348060000001', 'MAT/6/SENDER', true),
    (r,  'student', 'jane.recipient6@example.invalid', 'janey',  'Jane Recipient', '+2348060000002', 'MAT/6/RECIP',  true),
    (t,  'student', 'third6@example.invalid',          'thirdy', 'Third Person',   '+2348060000003', 'MAT/6/THIRD',  true),
    (a,  'admin',   'admin6@example.invalid',          'adm6',   'Test Admin',     '+2348060000004', null, true),
    (r1, 'rider',   'rider6a@example.invalid',         'ride6a', 'Rider Alpha',    '+2348060000005', null, true),
    (r2, 'rider',   'rider6b@example.invalid',         'ride6b', 'Rider Beta',     '+2348060000006', null, true);

  insert into public.wallets (user_id, balance, virtual_account_number) values
    (s, 500000, 'T6-' || left(s::text, 8)), (r, 500000, 'T6-' || left(r::text, 8)),
    (t, 500000, 'T6-' || left(t::text, 8));

  perform uf_test.as_user(s);  set local role authenticated;
  perform public.set_transaction_pin('1234');
  reset role;
  perform uf_test.as_user(r);  set local role authenticated;
  perform public.set_transaction_pin('4321');
  reset role;
end $$;

-- ═════════════ A. lookup_gift_recipient ═════════════
do $$
declare
  s uuid := current_setting('uf.s')::uuid;
  v jsonb; i int;
begin
  perform uf_test.as_user(s); set local role authenticated;
  v := public.lookup_gift_recipient('  Jane.Recipient6@example.invalid ');
  perform uf_test.ok('A1 found: ok + nickname + masked email',
    (v ->> 'ok')::boolean and v ->> 'nickname' = 'janey' and v ->> 'masked_email' = 'j***@example.invalid');
  perform uf_test.ok('A2 the answer has ONLY ok / nickname / masked_email',
    (select array_agg(k order by k) from jsonb_object_keys(v) k) = array['masked_email','nickname','ok']);
  perform uf_test.ok('A3 nothing else about them leaks (name, phone, matric, id, full email)',
    v::text not ilike '%Recipient%' and v::text not like '%2348060000002%'
    and v::text not like '%MAT/6%' and v::text not like '%jane.recipient6%'
    and v::text not like '%' || current_setting('uf.r') || '%');

  perform uf_test.ok('A4 your own email → SELF',
    public.lookup_gift_recipient('sender6@example.invalid') ->> 'reason' = 'SELF');
  perform uf_test.ok('A5 unknown email → NOT_FOUND',
    public.lookup_gift_recipient('nobody@example.invalid') ->> 'reason' = 'NOT_FOUND');
  perform uf_test.ok('A6 a rider / admin email → NOT_FOUND (students only)',
    public.lookup_gift_recipient('rider6a@example.invalid') ->> 'reason' = 'NOT_FOUND'
    and public.lookup_gift_recipient('admin6@example.invalid') ->> 'reason' = 'NOT_FOUND');
  perform uf_test.ok('A7 a not-yet-finished account → NOT_FOUND',
    (select public.lookup_gift_recipient('stub6@example.invalid') ->> 'reason' = 'NOT_FOUND'));

  -- so far: 6 lookups in this hour; 4 more are allowed, the 11th is refused
  for i in 1..4 loop
    v := public.lookup_gift_recipient('nobody@example.invalid');
  end loop;
  perform uf_test.ok('A8 the 10th lookup still answers', v ->> 'reason' = 'NOT_FOUND');
  perform uf_test.ok('A9 the 11th lookup in an hour → RATE_LIMITED (even for a real student)',
    public.lookup_gift_recipient('jane.recipient6@example.invalid') ->> 'reason' = 'RATE_LIMITED');
  reset role;

  perform set_config('request.jwt.claims', '', true);      -- nobody signed in
  perform uf_test.ok('A10 signed-out callers are refused',
    (select uf_test.raises($q$select public.lookup_gift_recipient('x@y.z')$q$, 'Unauthorized')));
end $$;

-- ═════════════ B. placing a gift ═════════════
do $$
declare
  s uuid := current_setting('uf.s')::uuid;
  r uuid := current_setting('uf.r')::uuid;
  v_uni uuid := '00000000-0000-0000-0000-000000000001';
  v_loc uuid;
  p_jol uuid; p_chk uuid; p_wat uuid;
  v jsonb; v_g uuid; v_bal0 numeric; v_bal1 numeric; v_cnt int;
  v_legs jsonb;
  v_key uuid := gen_random_uuid();
begin
  select id into v_loc from public.delivery_locations where is_active limit 1;
  select id into p_jol from public.products where vendor_id = v_uni and name = 'Jollof Rice';
  select id into p_chk from public.products where vendor_id = v_uni and name = 'Chicken';
  select id into p_wat from public.products where vendor_id = v_uni and name = 'Bottled Water';
  v_legs := jsonb_build_array(jsonb_build_object('vendor_id', v_uni,
    'items', jsonb_build_array(
      jsonb_build_object('product_id', p_jol, 'quantity', 2),
      jsonb_build_object('product_id', p_chk, 'quantity', 1),
      jsonb_build_object('product_id', p_wat, 'quantity', 1)),
    'packs', jsonb_build_array(jsonb_build_object('items', jsonb_build_array(
      jsonb_build_object('product_id', p_jol, 'quantity', 1),
      jsonb_build_object('product_id', p_chk, 'quantity', 1))))));
  perform set_config('uf.legs', v_legs::text, true);
  perform set_config('uf.loc', v_loc::text, true);

  perform uf_test.as_user(s); set local role authenticated;

  select count(*) into v_cnt from public.delivery_groups where student_id = s;
  perform uf_test.ok('B1 self-gift refused (no order, no charge)',
    uf_test.raises(format($q$select public.create_paid_gift_order(gen_random_uuid(),'1234',%L::jsonb,%L,'Room 1',null,'sender6@example.invalid','hi')$q$, v_legs, v_loc), 'GIFT_SELF')
    and (select count(*) from public.delivery_groups where student_id = s) = v_cnt);
  perform uf_test.ok('B2 unknown email refused',
    uf_test.raises(format($q$select public.create_paid_gift_order(gen_random_uuid(),'1234',%L::jsonb,%L,'Room 1',null,'nobody@example.invalid','hi')$q$, v_legs, v_loc), 'GIFT_RECIPIENT_NOT_FOUND'));
  perform uf_test.ok('B3 a 201-character message refused',
    uf_test.raises(format($q$select public.create_paid_gift_order(gen_random_uuid(),'1234',%L::jsonb,%L,'Room 1',null,'jane.recipient6@example.invalid',%L)$q$, v_legs, v_loc, repeat('x', 201)), 'GIFT_MESSAGE_TOO_LONG'));

  select balance into v_bal0 from public.wallets where user_id = s;
  v := public.create_paid_gift_order(gen_random_uuid(), '9999', v_legs, v_loc, 'Room 1', null,
         'jane.recipient6@example.invalid', 'Happy birthday!');
  perform uf_test.ok('B4 wrong PIN: error returned, nothing created, nothing charged',
    v ->> 'error' = 'INVALID_PIN'
    and (select balance from public.wallets where user_id = s) = v_bal0
    and (select count(*) from public.delivery_groups where student_id = s) = v_cnt);

  v := public.create_paid_gift_order(v_key, '1234', v_legs, v_loc, 'Room 1', 'note to rider',
         'Jane.Recipient6@example.invalid', 'Happy birthday!');
  v_g := (v ->> 'group_id')::uuid;
  perform set_config('uf.g1', v_g::text, true);
  select balance into v_bal1 from public.wallets where user_id = s;
  perform uf_test.ok('B5 gift placed: is_gift + recipient nickname in the result',
    (v ->> 'is_gift')::boolean and v ->> 'recipient_nickname' = 'janey');
  perform uf_test.ok('B6 charged like any delivery order (fees + service charge, no food)',
    v_bal0 - v_bal1 = (v ->> 'total_charged')::numeric and (v ->> 'total_charged')::numeric > 0);
  perform uf_test.ok('B7 the SENDER is the customer; the gift fields are on the parent order',
    exists (select 1 from public.delivery_groups g
             where g.id = v_g and g.student_id = s and g.is_gift
               and g.gift_recipient_id = r and g.gift_message = 'Happy birthday!'
               and g.gift_recipient_nickname = 'janey' and g.status = 'commitment_paid'));
  perform uf_test.ok('B8 the vendor part(s) belong to the sender too',
    (select bool_and(o.student_id = s) from public.orders o where o.delivery_group_id = v_g));

  v := public.create_paid_gift_order(v_key, '1234', v_legs, v_loc, 'Room 1', 'note to rider',
         'jane.recipient6@example.invalid', 'Happy birthday!');
  perform uf_test.ok('B9 same key again → the same order, no second charge',
    (v ->> 'replayed')::boolean and (v ->> 'group_id')::uuid = v_g
    and (select balance from public.wallets where user_id = s) = v_bal1);
  reset role;

  perform uf_test.ok('B10 the "gifter" badge went to the sender',
    exists (select 1 from public.user_achievements ua join public.achievements ac on ac.id = ua.achievement_id
             where ua.user_id = s and ac.code = 'gifter'));
end $$;

-- ═════════════ C. the recipient sees status — and nothing else ═════════════
do $$
declare
  s uuid := current_setting('uf.s')::uuid;
  r uuid := current_setting('uf.r')::uuid;
  t uuid := current_setting('uf.t')::uuid;
  g uuid := current_setting('uf.g1')::uuid;
  v_row record; v_n int;
begin
  perform uf_test.as_user(r); set local role authenticated;

  select count(*) into v_n from public.gift_deliveries;
  perform uf_test.ok('C1 the recipient can read the mirror row', v_n = 1);
  select * into v_row from public.gift_deliveries where group_id = g;
  perform uf_test.ok('C2 …with sender nickname, message, status and the delivery PIN',
    v_row.sender_nickname = 'sendy' and v_row.message = 'Happy birthday!'
    and v_row.status = 'placed' and v_row.delivery_pin is not null);
  perform uf_test.ok('C3 …and the items have NO prices / fees anywhere',
    v_row.items::text not ilike '%price%' and v_row.items::text not ilike '%total%'
    and v_row.items::text not like '%₦%' and v_row.items::text not like '%fee%'
    and v_row.items::text like '%Jollof Rice%' and v_row.items::text like '%Chicken%');
  perform uf_test.ok('C4 the mirror has no money columns at all',
    not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'gift_deliveries'
                   and (column_name ilike '%amount%' or column_name ilike '%fee%'
                        or column_name ilike '%price%' or column_name ilike '%charge%'
                        or column_name ilike '%paid%' or column_name = 'student_id')));

  perform uf_test.ok('C5 the recipient CANNOT read the sender''s order row',
    (select count(*) from public.delivery_groups where id = g) = 0);
  perform uf_test.ok('C6 …nor its vendor parts, items, packs',
    (select count(*) from public.orders where delivery_group_id = g) = 0
    and (select count(*) from public.order_items oi join public.orders o on o.id = oi.order_id
          where o.delivery_group_id = g) = 0
    and (select count(*) from public.order_packs) = 0);
  perform uf_test.ok('C7 …nor the sender''s wallet / payment records',
    (select count(*) from public.wallet_transactions where user_id = s) = 0
    and (select count(*) from public.wallets where user_id = s) = 0
    and (select count(*) from public.order_payment_attempts where student_id = s) = 0);
  perform uf_test.ok('C8 …nor the sender''s profile',
    (select count(*) from public.profiles where id = s) = 0);
  perform uf_test.ok('C9 the shared breakdown function refuses the recipient',
    uf_test.raises(format($q$select public.get_order_breakdown(%L)$q$, g), 'Unauthorized'));

  perform uf_test.ok('C10 the recipient cannot pay the final price',
    uf_test.raises(format($q$select public.pay_group_final_amount(%L,'4321')$q$, g), 'Unauthorized')
    or uf_test.raises(format($q$select public.pay_group_final_amount(%L,'4321')$q$, g), 'not awaiting'));
  perform uf_test.ok('C11 the recipient cannot cancel',
    uf_test.raises(format($q$select public.student_cancel_delivery_group(%L)$q$, g), 'Unauthorized'));
  perform uf_test.ok('C12 the recipient cannot decline',
    uf_test.raises(format($q$select public.decline_group_final_amount(%L)$q$, g), 'Unauthorized')
    or uf_test.raises(format($q$select public.decline_group_final_amount(%L)$q$, g), 'not awaiting'));
  perform uf_test.ok('C13 the recipient cannot write to the mirror',
    uf_test.raises(format($q$update public.gift_deliveries set status='delivered' where group_id=%L$q$, g), 'permission denied'));
  perform uf_test.ok('C14 the recipient cannot read the lookup ledger or the OTP tables',
    uf_test.raises($q$select * from public.gift_lookup_log$q$, 'permission denied'));

  -- notification
  perform uf_test.ok('C15 the recipient got a "gift received" notification with sender + message',
    exists (select 1 from public.notifications n
             where n.user_id = r and n.type = 'gift_received' and n.group_id = g
               and n.body like '%sendy%' and n.body like '%Happy birthday!%'));
  reset role;

  -- a third student
  perform uf_test.as_user(t); set local role authenticated;
  perform uf_test.ok('C16 a third student can read neither the mirror nor the order',
    (select count(*) from public.gift_deliveries) = 0
    and (select count(*) from public.delivery_groups where id = g) = 0
    and (select count(*) from public.notifications where type like 'gift%') = 0);
  reset role;

  -- the sender
  perform uf_test.as_user(s); set local role authenticated;
  perform uf_test.ok('C17 the sender sees their own order but NOT the recipient''s mirror',
    (select count(*) from public.delivery_groups where id = g) = 1
    and (select count(*) from public.gift_deliveries) = 0);
  perform uf_test.ok('C18 the sender got no "gift received" notification',
    not exists (select 1 from public.notifications where user_id = s and type = 'gift_received'));
  reset role;
end $$;

-- ═════════════ D. the rider ═════════════
do $$
declare
  s uuid := current_setting('uf.s')::uuid;
  r uuid := current_setting('uf.r')::uuid;
  r1 uuid := current_setting('uf.r1')::uuid;
  r2 uuid := current_setting('uf.r2')::uuid;
  g uuid := current_setting('uf.g1')::uuid;
  v jsonb; v_pool jsonb; v_info jsonb;
begin
  perform uf_test.as_user(r1); set local role authenticated;
  v_pool := public.rider_job_pool();
  perform uf_test.ok('D1 the pool card is tagged GIFT',
    exists (select 1 from jsonb_array_elements(v_pool -> 'groups') x
             where x ->> 'id' = g::text and (x ->> 'is_gift')::boolean));
  perform uf_test.ok('D2 the pool shows NO personal details (no names, phones, emails, matrics)',
    v_pool::text not like '%Sade%' and v_pool::text not like '%Jane%'
    and v_pool::text not like '%2348060%' and v_pool::text not like '%example.invalid%'
    and v_pool::text not like '%MAT/6%' and v_pool::text not ilike '%sendy%' and v_pool::text not ilike '%janey%');
  perform uf_test.ok('D3 contact details are refused before accepting',
    uf_test.raises(format($q$select public.get_group_customer_info(%L)$q$, g), 'Not your delivery group'));

  perform public.accept_delivery_group(g);
  v_info := public.get_group_customer_info(g);
  perform uf_test.ok('D4 after accepting: "Deliver to" = the recipient with phone + email + location details',
    v_info #>> '{gift,recipient,full_name}' = 'Jane Recipient'
    and v_info #>> '{gift,recipient,phone}' = '+2348060000002'
    and v_info #>> '{gift,recipient,email}' = 'jane.recipient6@example.invalid'
    and v_info #>> '{gift,recipient,location_details}' = 'Room 1');
  perform uf_test.ok('D5 after accepting: "Paid by" = the sender with phone + email',
    v_info #>> '{gift,sender,full_name}' = 'Sade Sender'
    and v_info #>> '{gift,sender,phone}' = '+2348060000001'
    and v_info #>> '{gift,sender,email}' = 'sender6@example.invalid');
  perform uf_test.ok('D6 NEVER a matric number, never the PIN',
    v_info::text not ilike '%MAT/6%' and v_info::text not ilike '%matric%'
    and v_info ->> 'delivery_pin' is null and not (v_info::text ilike '%delivery_pin%' and (v_info ->> 'delivery_pin') is not null)
    and not (v_info -> 'gift' -> 'recipient' ? 'delivery_pin'));
  reset role;

  perform uf_test.as_user(r2); set local role authenticated;
  perform uf_test.ok('D7 another rider cannot read the contacts',
    uf_test.raises(format($q$select public.get_group_customer_info(%L)$q$, g), 'Not your delivery group'));
  reset role;

  -- recipient's status follows
  perform uf_test.as_user(r); set local role authenticated;
  perform uf_test.ok('D8 the recipient''s status moved to "preparing"',
    (select status from public.gift_deliveries where group_id = g) = 'preparing');
  reset role;

  -- rider sends the final price; ONLY the sender pays it
  perform uf_test.as_user(r1); set local role authenticated;
  perform public.set_delivery_group_final_price(g, 3000);
  reset role;

  perform uf_test.as_user(r); set local role authenticated;
  perform uf_test.ok('D9 the recipient still cannot pay the final price',
    uf_test.raises(format($q$select public.pay_group_final_amount(%L,'4321')$q$, g), 'Unauthorized'));
  perform uf_test.ok('D10 …and was not told about the price (no notification of it)',
    not exists (select 1 from public.notifications where user_id = r and type = 'final_price')
    and (select count(*) from public.notifications where user_id = r) = 1);
  reset role;

  perform uf_test.as_user(s); set local role authenticated;
  v := public.pay_group_final_amount(g, '1234');
  reset role;
  perform uf_test.ok('D11 the sender pays the final price', (v ->> 'total_paid')::numeric = 3000);

  perform uf_test.as_user(r); set local role authenticated;
  perform uf_test.ok('D12 the recipient is told it is on its way, status on_the_way, PIN still visible',
    (select status from public.gift_deliveries where group_id = g) = 'on_the_way'
    and (select delivery_pin from public.gift_deliveries where group_id = g) is not null
    and exists (select 1 from public.notifications where user_id = r and type = 'gift_on_the_way'));
  perform set_config('uf.pin', (select delivery_pin from public.gift_deliveries where group_id = g), true);
  reset role;

  perform uf_test.as_user(r1); set local role authenticated;
  perform uf_test.ok('D13 a wrong PIN does not complete it',
    uf_test.raises(format($q$select public.verify_group_delivery(%L,'0000x')$q$, g), 'Incorrect delivery PIN'));
  perform public.verify_group_delivery(g, current_setting('uf.pin'));
  reset role;

  perform uf_test.as_user(r); set local role authenticated;
  perform uf_test.ok('D14 the recipient''s PIN completes it: delivered, notified, PIN cleared',
    (select status from public.gift_deliveries where group_id = g) = 'delivered'
    and (select delivery_pin from public.gift_deliveries where group_id = g) is null
    and exists (select 1 from public.notifications where user_id = r and type = 'gift_delivered'));
  reset role;

  perform uf_test.as_user(s); set local role authenticated;
  perform uf_test.ok('D15 the sender is told delivered the normal way',
    exists (select 1 from public.notifications where user_id = s and type = 'delivered' and group_id = g));
  reset role;
end $$;

-- ═════════════ E. cancellation ═════════════
do $$
declare
  s uuid := current_setting('uf.s')::uuid;
  r uuid := current_setting('uf.r')::uuid;
  a uuid := current_setting('uf.a')::uuid;
  r1 uuid := current_setting('uf.r1')::uuid;
  v_legs jsonb := current_setting('uf.legs')::jsonb;
  v_loc uuid := current_setting('uf.loc')::uuid;
  g2 uuid; g3 uuid; g4 uuid;
begin
  perform uf_test.as_user(s); set local role authenticated;
  g2 := (public.create_paid_gift_order(gen_random_uuid(), '1234', v_legs, v_loc, 'Room 2', null, 'jane.recipient6@example.invalid', null) ->> 'group_id')::uuid;
  g3 := (public.create_paid_gift_order(gen_random_uuid(), '1234', v_legs, v_loc, 'Room 3', null, 'jane.recipient6@example.invalid', 'second') ->> 'group_id')::uuid;
  g4 := (public.create_paid_gift_order(gen_random_uuid(), '1234', v_legs, v_loc, 'Room 4', null, 'jane.recipient6@example.invalid', 'third') ->> 'group_id')::uuid;
  perform public.student_cancel_delivery_group(g2);          -- sender cancels before a rider accepts
  reset role;

  perform uf_test.as_user(a); set local role authenticated;
  perform public.admin_cancel_delivery_group(g3, 'test');    -- admin cancels
  perform uf_test.ok('E1 admin can read the gift fields on the order',
    (select is_gift and gift_message = 'second' and gift_recipient_nickname = 'janey'
       from public.delivery_groups where id = g3));
  reset role;

  perform uf_test.as_user(r1); set local role authenticated;
  perform public.accept_delivery_group(g4);
  perform public.set_delivery_group_final_price(g4, 2500);
  reset role;
  perform uf_test.as_user(s); set local role authenticated;
  perform public.decline_group_final_amount(g4);             -- sender declines the final price
  reset role;

  perform uf_test.as_user(r); set local role authenticated;
  perform uf_test.ok('E2 cancelled by sender / by admin / by declining: all three mirrors say cancelled',
    (select count(*) from public.gift_deliveries where status = 'cancelled'
        and group_id in (g2, g3, g4)) = 3);
  perform uf_test.ok('E3 the recipient was notified of each cancellation, naming the sender',
    (select count(*) from public.notifications
      where user_id = r and type = 'gift_cancelled' and body like '%sendy%') = 3);
  perform uf_test.ok('E4 cancelled gifts show no PIN',
    (select bool_and(delivery_pin is null) from public.gift_deliveries where status = 'cancelled'));
  reset role;
end $$;

-- ═════════════ F. a normal order is untouched; old RPC is off ═════════════
do $$
declare
  t uuid := current_setting('uf.t')::uuid;
  r uuid := current_setting('uf.r')::uuid;
  v_legs jsonb := current_setting('uf.legs')::jsonb;
  v_loc uuid := current_setting('uf.loc')::uuid;
  v jsonb; g uuid;
begin
  perform uf_test.as_user(t); set local role authenticated;
  perform public.set_transaction_pin('1111');
  v := public.create_paid_delivery_order(gen_random_uuid(), '1111', v_legs, v_loc, 'Room 9', null);
  g := (v ->> 'group_id')::uuid;
  reset role;
  perform uf_test.ok('F1 a normal order is not a gift and has no mirror row',
    not (select is_gift from public.delivery_groups where id = g)
    and not exists (select 1 from public.gift_deliveries where group_id = g));
  perform uf_test.ok('F2 the old send_gift() cannot be executed by app users',
    not exists (select 1 from pg_proc p where p.proname = 'send_gift'
                 and (has_function_privilege('authenticated', p.oid, 'execute')
                      or has_function_privilege('anon', p.oid, 'execute'))));
  perform uf_test.ok('F3 anon cannot call the new functions',
    not has_function_privilege('anon', 'public.lookup_gift_recipient(text)', 'execute')
    and not has_function_privilege('anon', 'public.create_paid_gift_order(uuid,text,jsonb,uuid,text,text,text,text)', 'execute'));
  perform uf_test.ok('F4 internal helpers are not callable by app users',
    not has_function_privilege('authenticated', 'public._gift_publish(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public._gift_sync_group()', 'execute'));
end $$;

-- ── Result grid ──────────────────────────────────────────────────────
select unnest(string_to_array(current_setting('uf.log', true), E'\n')) as result
 where true
 order by 1 asc;

rollback;
