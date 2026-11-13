-- =====================================================================
-- Pack 2 — security hardening (2026-11-12)
--
-- Run AFTER pack1_wallet_funding_fixes.sql / pack1_vendor_ordering_style.sql.
-- Idempotent: safe to re-run. No data is changed — only policies,
-- function privileges and function bodies. Test: pack2_security_hardening_test.sql.
-- Rollback: pack2_security_hardening_ROLLBACK.sql (restores the old
-- policies, grants and bodies exactly as they were on live on 2026-11-12).
--
-- Found on the live project (docs/security-audit.md, IDs in brackets):
--
-- [S-01] Students could INSERT order rows directly (policy "orders: insert
--   own", plus "order_items: insert own" and "errand_requests: insert own").
--   orders.is_paid defaults to TRUE, so a hand-made row looked like a paid
--   order: a "paid" pickup order with any items appeared to admins as food to
--   prepare, a "paid" errand pushed "New errand job" to riders, and the
--   _after_order_placed trigger raised lifetime spending / points / tier
--   (and so birthday credits). The app never writes these tables directly —
--   every order goes through the SECURITY DEFINER checkout functions, which
--   bypass RLS — so the three policies are simply dropped.
-- [S-02] The old 5-argument checkout_group_order (no PIN, no search_path)
--   was still callable: it debited p_my_total as sent by the client (a
--   negative total ADDED money) and stored client-supplied unit prices.
--   Dropped. The group-order screens are unreachable in the app, so the
--   remaining group-order RPCs are revoked from app users too.
-- [S-03] _insert_order_items(order_id, items) was callable by any signed-in
--   user and appended items to ANY order (e.g. free extra food on a prepaid
--   pickup order). Internal helpers are revoked from app users.
-- [S-04] Transaction-PIN guessing without a lockout:
--   * verify_transaction_pin(pin) answered true/false with no attempt
--     counter — revoked (the app never calls it);
--   * pay_final_amount used it, so errand payments had no lockout;
--   * pay_group_final_amount RAISED on a wrong PIN, which rolled back the
--     failed-attempt counter _check_transaction_pin had just written;
--   * set_transaction_pin compared the current PIN with no counter.
--   All three now use _check_transaction_pin and RETURN {"error": ...}
--   (like the checkout functions already do) so the counter and the
--   15-minute lockout after 5 wrong PINs persist.
-- [S-05] Students could read their own referral code and reward amounts
--   (referral_codes owner policy, referral_credits, referrals,
--   my_referral_code(), get_referral_leaderboard()). Admin-only now.
-- [S-06] process_birthday_rewards() and can_notify_order() were callable by
--   app users; service role / pg_cron only now (pg_cron runs as postgres).
-- [S-07] profiles "insert own row" let a freshly created auth user write
--   their own profile with server-owned columns (tier, points, phone
--   verified, onboarding complete). Sign-up creates profiles server-side
--   (signup Edge Function / complete_student_onboarding), so it is dropped.
-- [S-08] group_orders "creator update" let a creator change bulk discount /
--   status directly. Dropped with the dead group-order feature.
-- [S-09] Functions without a fixed search_path get one.
-- [B-01] search_products listed deleted products and deleted vendors.
-- =====================================================================

-- ── S-01 / S-07 / S-08: direct table writes ──────────────────────────
drop policy if exists "orders: insert own"          on public.orders;
drop policy if exists "order_items: insert own"     on public.order_items;
drop policy if exists "errand_requests: insert own" on public.errand_requests;
drop policy if exists "profiles: insert own row"    on public.profiles;
drop policy if exists "group_orders: creator update" on public.group_orders;

-- ── S-02: group orders (feature unreachable in the app) ───────────────
drop function if exists public.checkout_group_order(uuid, jsonb, numeric, text, text);
revoke all on function public.checkout_group_order(uuid, jsonb, numeric, text, text, text) from public, anon, authenticated;
revoke all on function public.create_group_order(uuid, numeric) from public, anon, authenticated;
revoke all on function public.join_group_order(uuid)            from public, anon, authenticated;
grant execute on function public.checkout_group_order(uuid, jsonb, numeric, text, text, text) to service_role;
grant execute on function public.create_group_order(uuid, numeric) to service_role;
grant execute on function public.join_group_order(uuid)            to service_role;

-- ── S-03 / S-06: internal helpers and server-only functions ───────────
revoke all on function public._insert_order_items(uuid, jsonb)     from public, anon, authenticated;
revoke all on function public._line_items_subtotal(uuid, jsonb)    from public, anon, authenticated;
revoke all on function public._delivery_fee(uuid, text)            from public, anon, authenticated;
revoke all on function public._check_transaction_pin(text)         from public, anon, authenticated;
revoke all on function public.verify_transaction_pin(text)         from public, anon, authenticated;
revoke all on function public.process_birthday_rewards()           from public, anon, authenticated;
revoke all on function public.can_notify_order(uuid, uuid)         from public, anon, authenticated;
revoke all on function public.get_gifts()                          from public, anon, authenticated;
grant execute on function public._insert_order_items(uuid, jsonb)  to service_role;
grant execute on function public._line_items_subtotal(uuid, jsonb) to service_role;
grant execute on function public._delivery_fee(uuid, text)         to service_role;
grant execute on function public._check_transaction_pin(text)      to service_role;
grant execute on function public.verify_transaction_pin(text)      to service_role;
grant execute on function public.process_birthday_rewards()        to service_role;
grant execute on function public.can_notify_order(uuid, uuid)      to service_role;
grant execute on function public.get_gifts()                       to service_role;

-- ── S-05: referral codes and amounts are admin-only ───────────────────
drop policy if exists "referral_codes: owner reads own" on public.referral_codes;
drop policy if exists "referral_codes: admin read"      on public.referral_codes;
create policy "referral_codes: admin read" on public.referral_codes
  for select to authenticated using (public.is_admin());

drop policy if exists "referral_credits: own records" on public.referral_credits;
drop policy if exists "referral_credits: admin read"  on public.referral_credits;
create policy "referral_credits: admin read" on public.referral_credits
  for select to authenticated using (public.is_admin());

drop policy if exists "referrals: read rows referencing me" on public.referrals;
drop policy if exists "referrals: admin read"               on public.referrals;
create policy "referrals: admin read" on public.referrals
  for select to authenticated using (public.is_admin());

revoke all on function public.my_referral_code()         from public, anon, authenticated;
revoke all on function public.get_referral_leaderboard() from public, anon, authenticated;
grant execute on function public.my_referral_code()         to service_role;
grant execute on function public.get_referral_leaderboard() to service_role;

-- ── S-09: fixed search_path ───────────────────────────────────────────
alter function public.get_gifts()                set search_path = public;
alter function public.get_referral_leaderboard() set search_path = public;
alter function public.get_student_stats()        set search_path = public;
alter function public.get_user_achievements()    set search_path = public;
alter function public.join_group_order(uuid)     set search_path = public;
alter function public.toggle_rider_online(boolean) set search_path = public;
alter function public.send_gift(text, uuid, jsonb, numeric, text, text, text) set search_path = public;

-- ── S-04: PIN-protected payments keep the failed-attempt counter ──────

-- Errand final payment. Same behaviour as before, except the PIN check
-- counts attempts / locks, and a PIN problem is RETURNED, not raised.
create or replace function public.pay_final_amount(p_order_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_student_id uuid := auth.uid();
  v_pin_status text;
  v_order      public.orders%rowtype;
  v_wallet     public.wallets%rowtype;
begin
  if v_student_id is null then raise exception 'Unauthorized'; end if;

  -- Returned (not raised) so the failed-attempt counter is kept.
  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status <> 'ok' then
    return jsonb_build_object('error', case v_pin_status
      when 'locked'  then 'PIN_LOCKED'
      when 'not_set' then 'PIN_NOT_SET'
      else 'INVALID_PIN' end);
  end if;

  select * into v_order from public.orders
   where id = p_order_id for update;

  if not found then raise exception 'Order not found'; end if;
  if v_order.student_id <> v_student_id then raise exception 'Unauthorized'; end if;
  if v_order.status <> 'awaiting_final_payment' then
    raise exception 'Order is not awaiting final payment';
  end if;
  if v_order.final_payment_paid then raise exception 'Final payment already made'; end if;
  if v_order.final_amount is null then raise exception 'Final amount not set by rider'; end if;

  select * into v_wallet from public.wallets
   where user_id = v_student_id for update;

  if not found then raise exception 'Wallet not found'; end if;
  if v_wallet.balance < v_order.final_amount then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.wallets
     set balance = balance - v_order.final_amount
   where user_id = v_student_id;

  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_student_id, 'debit', v_order.final_amount, 'order_payment', p_order_id,
     v_wallet.balance - v_order.final_amount);

  update public.orders
     set final_payment_paid = true,
         total_amount       = v_order.commitment_fee_amount + v_order.final_amount,
         status             = 'out_for_delivery'
   where id = p_order_id;

  return jsonb_build_object(
    'balance_after', v_wallet.balance - v_order.final_amount
  );
end;
$$;

-- Food delivery final payment (one per checkout).
create or replace function public.pay_group_final_amount(p_group_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_student_id uuid := auth.uid();
  v_pin_status text;
  v_group      public.delivery_groups%rowtype;
  v_wallet     public.wallets%rowtype;
  v_amount     numeric(10,2);
begin
  if v_student_id is null then raise exception 'Unauthorized'; end if;

  -- Returned (not raised) so the failed-attempt counter is kept.
  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status <> 'ok' then
    return jsonb_build_object('error', case v_pin_status
      when 'locked'  then 'PIN_LOCKED'
      when 'not_set' then 'PIN_NOT_SET'
      else 'INVALID_PIN' end);
  end if;

  select * into v_group from public.delivery_groups
   where id = p_group_id for update;

  if not found then raise exception 'Group not found'; end if;
  if v_group.student_id <> v_student_id then raise exception 'Unauthorized'; end if;
  if v_group.status <> 'awaiting_final_payment' then
    raise exception 'Group is not awaiting final payment (status: %)', v_group.status;
  end if;

  v_amount := v_group.final_amount;
  if v_amount is null or v_amount <= 0 then
    raise exception 'Final amount has not been set by the rider';
  end if;

  select * into v_wallet from public.wallets
   where user_id = v_student_id for update;
  if not found then raise exception 'Wallet not found'; end if;
  if v_wallet.balance < v_amount then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.wallets
     set balance = balance - v_amount
   where user_id = v_student_id;

  insert into public.wallet_transactions
    (user_id, type, amount, source, balance_after)
  values
    (v_student_id, 'debit', v_amount, 'order_payment', v_wallet.balance - v_amount);

  update public.delivery_groups
     set final_payment_paid = true,
         status             = 'out_for_delivery'
   where id = p_group_id;

  update public.orders
     set final_payment_paid = true,
         status             = 'out_for_delivery'
   where delivery_group_id = p_group_id
     and status <> 'cancelled';

  return jsonb_build_object(
    'balance_after', v_wallet.balance - v_amount,
    'total_paid',    v_amount
  );
end;
$$;

-- Set / change the transaction PIN. The return type changes from void to
-- jsonb ({"ok": true} or {"error": "INVALID_CURRENT_PIN" | "PIN_LOCKED"}),
-- so the function is dropped and recreated.
drop function if exists public.set_transaction_pin(text, text);
create function public.set_transaction_pin(p_pin text, p_current_pin text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid := auth.uid();
  v_status  text;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;
  if p_pin is null or p_pin !~ '^[0-9]{4}$' then
    raise exception 'PIN must be exactly 4 digits';
  end if;

  if exists (select 1 from public.transaction_pins where user_id = v_user_id) then
    -- Counts the attempt and honours the lockout (returned, not raised).
    v_status := public._check_transaction_pin(p_current_pin);
    if v_status = 'locked' then
      return jsonb_build_object('error', 'PIN_LOCKED');
    elsif v_status <> 'ok' then
      return jsonb_build_object('error', 'INVALID_CURRENT_PIN');
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

  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.set_transaction_pin(text, text) from public, anon;
grant execute on function public.set_transaction_pin(text, text) to authenticated, service_role;

revoke all on function public.pay_final_amount(uuid, text)       from public, anon;
revoke all on function public.pay_group_final_amount(uuid, text) from public, anon;
grant execute on function public.pay_final_amount(uuid, text)       to authenticated, service_role;
grant execute on function public.pay_group_final_amount(uuid, text) to authenticated, service_role;

-- ── B-01: search hides deleted products / vendors; wildcards are literal ─
create or replace function public.search_products(p_query text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
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
      and p.deleted_at is null
      and v.is_active = true
      and v.deleted_at is null
      and length(trim(coalesce(p_query, ''))) between 1 and 60
      and p.name ilike '%' || replace(replace(replace(trim(p_query),
            '\', '\\'), '%', '\%'), '_', '\_') || '%'
    order by v.name, p.name
    limit 50
  ) r;
$$;
