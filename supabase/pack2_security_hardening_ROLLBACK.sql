-- =====================================================================
-- ROLLBACK for pack2_security_hardening.sql — EMERGENCY USE ONLY.
-- Restores the policies, grants and function bodies exactly as they were on
-- the live project on 2026-11-12 (dumped with pg_get_functiondef). This
-- RE-OPENS every hole the migration closed (S-01 … S-09, B-01). Old app
-- builds expect set_transaction_pin to return void; new builds handle both.
-- =====================================================================

create policy "orders: insert own" on public.orders for insert with check (auth.uid() = student_id);
create policy "order_items: insert own" on public.order_items for insert with check (exists (select 1 from public.orders where orders.id = order_items.order_id and orders.student_id = auth.uid()));
create policy "errand_requests: insert own" on public.errand_requests for insert to authenticated with check (exists (select 1 from public.orders o where o.id = errand_requests.order_id and o.student_id = auth.uid()));
create policy "profiles: insert own row" on public.profiles for insert to authenticated with check (auth.uid() = id and role = 'student' and admin_tier is null);
create policy "group_orders: creator update" on public.group_orders for update using (auth.uid() = creator_id);
drop policy if exists "referral_codes: admin read" on public.referral_codes;
create policy "referral_codes: owner reads own" on public.referral_codes for select to authenticated using (owner_id = auth.uid() or public.is_admin());
drop policy if exists "referral_credits: admin read" on public.referral_credits;
create policy "referral_credits: own records" on public.referral_credits for select using (referrer_id = auth.uid());
drop policy if exists "referrals: admin read" on public.referrals;
create policy "referrals: read rows referencing me" on public.referrals for select using (auth.uid() = referrer_id or auth.uid() = referred_id);

CREATE OR REPLACE FUNCTION public.checkout_group_order(p_group_id uuid, p_line_items jsonb, p_my_total numeric, p_delivery_type text DEFAULT 'pickup'::text, p_delivery_location text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_uid          uuid := auth.uid();
  v_group        public.group_orders;
  v_balance      numeric;
  v_new_balance  numeric;
  v_order_id     uuid;
  v_is_uniflex   boolean;
  v_source       text;
begin
  select * into v_group from public.group_orders where id = p_group_id;
  if not found then raise exception 'GROUP_NOT_FOUND'; end if;
  if v_group.status = 'cancelled' then raise exception 'GROUP_CANCELLED'; end if;

  if not exists (
    select 1 from public.group_order_members
    where group_order_id = p_group_id and student_id = v_uid
  ) then raise exception 'NOT_A_MEMBER'; end if;

  if exists (
    select 1 from public.group_order_members
    where group_order_id = p_group_id and student_id = v_uid and paid = true
  ) then raise exception 'ALREADY_CHECKED_OUT'; end if;

  select balance into v_balance from public.wallets
  where user_id = v_uid for update;
  if not found then raise exception 'WALLET_NOT_FOUND'; end if;
  if v_balance < p_my_total then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.wallets set balance = balance - p_my_total
  where user_id = v_uid returning balance into v_new_balance;

  select (is_featured and badge_label = 'Major') into v_is_uniflex
    from public.vendors where id = v_group.vendor_id;
  v_source := case when v_is_uniflex then 'uniflex' else 'partner' end;

  insert into public.orders
    (student_id, vendor_id, source, type, status, delivery_type,
     delivery_location, total_amount, estimated_time,
     group_order_id, bulk_discount_pct)
  values
    (v_uid, v_group.vendor_id, v_source, 'food', 'placed',
     coalesce(p_delivery_type, v_group.delivery_type),
     coalesce(p_delivery_location, v_group.delivery_location),
     p_my_total, '20–30 min', p_group_id, v_group.bulk_discount_pct)
  returning id into v_order_id;

  insert into public.order_items
    (order_id, product_id, product_name, quantity, unit_price, selected_options)
  select
    v_order_id,
    (item->>'product_id')::uuid,
    item->>'product_name',
    (item->>'quantity')::int,
    (item->>'unit_price')::numeric,
    coalesce((item->'selected_options')::jsonb, '[]'::jsonb)
  from jsonb_array_elements(p_line_items) as item;

  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_uid, 'debit', p_my_total, 'group_order_payment', v_order_id, v_new_balance);

  update public.group_order_members
    set order_id = v_order_id, paid = true
  where group_order_id = p_group_id and student_id = v_uid;

  return jsonb_build_object('order_id', v_order_id);
end;
$function$;

drop function if exists public.set_transaction_pin(text, text);

CREATE OR REPLACE FUNCTION public.set_transaction_pin(p_pin text, p_current_pin text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_user_id  uuid := auth.uid();
  v_existing text;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;
  if p_pin !~ '^[0-9]{4}$' then
    raise exception 'PIN must be exactly 4 digits';
  end if;

  select pin_hash into v_existing
    from public.transaction_pins where user_id = v_user_id;

  if v_existing is not null then
    if p_current_pin is null
       or crypt(p_current_pin, v_existing) <> v_existing then
      raise exception 'INVALID_CURRENT_PIN';
    end if;
  end if;

  insert into public.transaction_pins
    (user_id, pin_hash, failed_attempts, locked_until, updated_at)
  values (v_user_id, crypt(p_pin, gen_salt('bf')), 0, null, now())
  on conflict (user_id) do update
    set pin_hash        = excluded.pin_hash,
        failed_attempts = 0,
        locked_until    = null,
        updated_at      = now();
end;
$function$;

CREATE OR REPLACE FUNCTION public.pay_final_amount(p_order_id uuid, p_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_student_id uuid;
  v_order      public.orders%rowtype;
  v_wallet     public.wallets%rowtype;
begin
  v_student_id := auth.uid();

  -- Verify transaction PIN.
  if not (select public.verify_transaction_pin(p_pin)) then
    raise exception 'INVALID_PIN';
  end if;

  -- Lock order.
  select * into v_order from public.orders
  where id = p_order_id for update;

  if not found then raise exception 'Order not found'; end if;
  if v_order.student_id <> v_student_id then raise exception 'Unauthorized'; end if;
  if v_order.status <> 'awaiting_final_payment' then
    raise exception 'Order is not awaiting final payment';
  end if;
  if v_order.final_payment_paid then raise exception 'Final payment already made'; end if;
  if v_order.final_amount is null then raise exception 'Final amount not set by rider'; end if;

  -- Lock wallet.
  select * into v_wallet from public.wallets
  where user_id = v_student_id for update;

  if not found then raise exception 'Wallet not found'; end if;
  if v_wallet.balance < v_order.final_amount then raise exception 'INSUFFICIENT_BALANCE'; end if;

  -- Deduct.
  update public.wallets
  set balance = balance - v_order.final_amount
  where user_id = v_student_id;

  -- Record transaction.
  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_student_id, 'debit', v_order.final_amount, 'order_payment', p_order_id,
     v_wallet.balance - v_order.final_amount);

  -- Update order total to reflect actual amount paid.
  update public.orders
  set
    final_payment_paid = true,
    total_amount       = v_order.commitment_fee_amount + v_order.final_amount,
    status             = 'out_for_delivery'
  where id = p_order_id;

  return jsonb_build_object(
    'balance_after', v_wallet.balance - v_order.final_amount
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.pay_group_final_amount(p_group_id uuid, p_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_student_id uuid := auth.uid();
  v_pin_status text;
  v_group      public.delivery_groups%rowtype;
  v_wallet     public.wallets%rowtype;
  v_amount     numeric(10,2);
begin
  -- PIN check.
  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status = 'not_set' then raise exception 'PIN_NOT_SET'; end if;
  if v_pin_status = 'locked'  then raise exception 'PIN_LOCKED'; end if;
  if v_pin_status = 'invalid' then raise exception 'INVALID_PIN'; end if;

  -- Lock group.
  select * into v_group from public.delivery_groups
  where id = p_group_id for update;

  if not found then raise exception 'Group not found'; end if;
  if v_group.student_id <> v_student_id then raise exception 'Unauthorized'; end if;
  if v_group.status <> 'awaiting_final_payment' then
    raise exception 'Group is not awaiting final payment (status: %)', v_group.status;
  end if;

  -- Use the group-level final_amount the rider set.
  v_amount := v_group.final_amount;
  if v_amount is null or v_amount <= 0 then
    raise exception 'Final amount has not been set by the rider';
  end if;

  -- Lock wallet.
  select * into v_wallet from public.wallets
  where user_id = v_student_id for update;
  if not found then raise exception 'Wallet not found'; end if;
  if v_wallet.balance < v_amount then raise exception 'INSUFFICIENT_BALANCE'; end if;

  -- Debit wallet.
  update public.wallets
  set balance = balance - v_amount
  where user_id = v_student_id;

  -- Record transaction.
  insert into public.wallet_transactions
    (user_id, type, amount, source, balance_after)
  values
    (v_student_id, 'debit', v_amount, 'order_payment',
     v_wallet.balance - v_amount);

  -- Advance group.
  update public.delivery_groups
  set
    final_payment_paid = true,
    status             = 'out_for_delivery'
  where id = p_group_id;

  -- Advance all non-cancelled legs.
  update public.orders
  set
    final_payment_paid = true,
    status             = 'out_for_delivery'
  where delivery_group_id = p_group_id
    and status <> 'cancelled';

  return jsonb_build_object(
    'balance_after', v_wallet.balance - v_amount,
    'total_paid',    v_amount
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.search_products(p_query text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb)
  from (
    select
      p.id as product_id,
      p.name as product_name,
      p.description,
      p.base_price,
      p.section,
      p.food_subsection,
      p.image_url,
      v.id as vendor_id,
      v.name as vendor_name,
      v.is_active as vendor_active
    from public.products p
    join public.vendors v on v.id = p.vendor_id
    where p.is_available = true
      and v.is_active = true
      and p.name ilike '%' || p_query || '%'
    order by v.name, p.name
    limit 50
  ) r;
$function$;

grant execute on function public.checkout_group_order(uuid, jsonb, numeric, text, text) to public, anon, authenticated, service_role;
grant execute on function public.checkout_group_order(uuid, jsonb, numeric, text, text, text) to public, anon, authenticated, service_role;
grant execute on function public.create_group_order(uuid, numeric) to public, anon, authenticated, service_role;
grant execute on function public.join_group_order(uuid) to public, anon, authenticated, service_role;
grant execute on function public._insert_order_items(uuid, jsonb) to public, anon, authenticated, service_role;
grant execute on function public._line_items_subtotal(uuid, jsonb) to public, anon, authenticated, service_role;
grant execute on function public._delivery_fee(uuid, text) to public, anon, authenticated, service_role;
grant execute on function public._check_transaction_pin(text) to public, anon, authenticated, service_role;
grant execute on function public.verify_transaction_pin(text) to public, anon, authenticated, service_role;
grant execute on function public.process_birthday_rewards() to public, anon, authenticated, service_role;
grant execute on function public.can_notify_order(uuid, uuid) to public, anon, authenticated, service_role;
grant execute on function public.get_gifts() to public, anon, authenticated, service_role;
grant execute on function public.my_referral_code() to public, anon, authenticated, service_role;
grant execute on function public.get_referral_leaderboard() to public, anon, authenticated, service_role;
grant execute on function public.set_transaction_pin(text, text) to public, anon, authenticated, service_role;
grant execute on function public.pay_final_amount(uuid, text) to public, anon, authenticated, service_role;
grant execute on function public.pay_group_final_amount(uuid, text) to public, anon, authenticated, service_role;
