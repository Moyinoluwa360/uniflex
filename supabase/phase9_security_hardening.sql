-- =====================================================================
-- PHASE 9 — Security & logic hardening (audit of 2026-09-27)
-- =====================================================================
-- Run this ONCE in the Supabase SQL editor, after schema.sql.
-- Every block is idempotent, so re-running is safe.
--
-- This closes the server-side findings from the full audit. Each section
-- is numbered with the audit finding it fixes. The client-side and Edge
-- Function halves of some fixes live in the Flutter app and
-- supabase/functions/ respectively — see the notes inline.
--
-- ORDER OF OPERATIONS MATTERS for one thing only: deploy the updated
-- `phone-otp` Edge Function (or at least create the otp_send_log table in
-- section 0) before shipping a client build that calls it.
-- =====================================================================


-- =====================================================================
-- 0. Supporting tables
-- =====================================================================

-- Rate-limit ledger for the phone-otp Edge Function. Termii bills per
-- message, so OTP sends are capped per user per rolling hour. Written
-- only by the Edge Function (service role); no client policy at all.
create table if not exists public.otp_send_log (
  id      uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  sent_at timestamptz not null default now()
);

create index if not exists otp_send_log_user_sent_idx
  on public.otp_send_log (user_id, sent_at desc);

alter table public.otp_send_log enable row level security;

-- One birthday reward per student per calendar year. Without this,
-- process_birthday_rewards() credited every eligible student on every
-- call (audit #5).
create table if not exists public.birthday_rewards_log (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  reward_year int  not null,
  amount      numeric(12,2) not null,
  credited_at timestamptz not null default now(),
  unique (user_id, reward_year)
);

alter table public.birthday_rewards_log enable row level security;


-- =====================================================================
-- 1. Audit #7 — students could write their own privileged profile columns
-- =====================================================================
-- "profiles: update own row" had no column restrictions, so a student
-- could self-award membership_tier / reward_points / lifetime_spending /
-- referral_count, re-activate an account an admin had deactivated, or
-- forge phone_verified_at.
--
-- No client code updates profiles directly (verified across lib/) — every
-- legitimate write goes through a SECURITY DEFINER RPC, which bypasses
-- RLS. So the blanket UPDATE policy is simply removed rather than
-- narrowed. If a future "edit my profile" screen is added, give it its own
-- RPC that whitelists the editable columns.
drop policy if exists "profiles: update own row" on public.profiles;

-- Defence in depth: keep the existing role/admin_tier guard trigger and
-- widen it to every server-owned column, so even a service-role mistake
-- or a future policy regression can't silently move these.
create or replace function public.guard_profile_privileged_columns()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_jwt_role text := coalesce(
    (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'role'), '');
  v_changed text;
begin
  -- A SECURITY DEFINER RPC that legitimately owns these columns sets this
  -- transaction-local flag before writing them.
  if coalesce(current_setting('uniflex.trusted_write', true), '') = 'on' then
    return new;
  end if;

  if v_jwt_role = 'service_role' then
    return new;
  end if;

  v_changed := case
    when new.role              is distinct from old.role              then 'role'
    when new.admin_tier        is distinct from old.admin_tier        then 'admin_tier'
    when new.is_active         is distinct from old.is_active         then 'is_active'
    when new.reward_points     is distinct from old.reward_points     then 'reward_points'
    when new.membership_tier   is distinct from old.membership_tier   then 'membership_tier'
    when new.lifetime_spending is distinct from old.lifetime_spending then 'lifetime_spending'
    when new.total_orders      is distinct from old.total_orders      then 'total_orders'
    when new.referral_count    is distinct from old.referral_count    then 'referral_count'
    when new.referral_code     is distinct from old.referral_code     then 'referral_code'
    when new.referred_by_code  is distinct from old.referred_by_code  then 'referred_by_code'
    when new.phone             is distinct from old.phone             then 'phone'
    when new.phone_verified_at is distinct from old.phone_verified_at then 'phone_verified_at'
    when new.onboarding_complete is distinct from old.onboarding_complete then 'onboarding_complete'
    else null
  end;

  if v_changed is not null then
    raise exception
      '% is server-owned and cannot be changed by a client (attempted by %)',
      v_changed, coalesce(nullif(v_jwt_role, ''), 'unknown');
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_profile_privileged_columns on public.profiles;
create trigger trg_guard_profile_privileged_columns
  before update on public.profiles
  for each row execute function public.guard_profile_privileged_columns();


-- =====================================================================
-- 2. Audit #8 — students could UPDATE their own orders directly
-- =====================================================================
-- "orders: update own" let a student set status='completed' (bypassing the
-- rider PIN workflow that update_order_status was hardened to enforce),
-- reassign rider_id, or rewrite total_amount. No client code updates the
-- orders table directly — reads only — so the policy is removed.
drop policy if exists "orders: update own" on public.orders;


-- =====================================================================
-- 3. Audit #11 — deactivated staff kept full API access
-- =====================================================================
-- is_admin()/is_super_admin()/is_rider() ignored profiles.is_active, so a
-- rider "removed" via admin_set_rider_active() could still call
-- accept_order/verify_delivery/get_customer_info straight against the API.
create or replace function public.is_admin()
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and is_active
  );
$$;

create or replace function public.is_super_admin()
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and is_active
      and (admin_tier is null or admin_tier = 'super_admin')
  );
$$;

create or replace function public.is_rider()
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'rider' and is_active
  );
$$;

-- is_active is a guarded column as of section 1, so the one RPC that
-- legitimately owns it has to declare itself a trusted write — otherwise
-- admin rider activate/deactivate starts failing.
create or replace function public.admin_set_rider_active(
  p_rider_id uuid,
  p_active   boolean
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Unauthorized';
  end if;

  perform set_config('uniflex.trusted_write', 'on', true);

  update public.profiles
     set is_active = p_active
   where id = p_rider_id and role = 'rider';

  if not found then
    perform set_config('uniflex.trusted_write', 'off', true);
    raise exception 'Rider not found';
  end if;

  perform set_config('uniflex.trusted_write', 'off', true);
end;
$$;

grant execute on function public.admin_set_rider_active(uuid, boolean) to authenticated;


-- =====================================================================
-- 4. Audit #16 — credit_wallet idempotency was a race
-- =====================================================================
-- The "has this reference been credited?" check was an EXISTS followed by
-- an INSERT, so two concurrent verify calls could both pass it and credit
-- twice. A partial unique index makes the database enforce it.
create unique index if not exists wallet_transactions_credit_reference_uniq
  on public.wallet_transactions (reference)
  where type = 'credit' and reference is not null;


-- =====================================================================
-- 5. Audit #20 — delivery fees were hardcoded in the Flutter client
-- =====================================================================
-- Needed as real data before the server can validate an order total at
-- all (section 7). Defaults match the values the client used.
alter table public.vendors
  add column if not exists campus_delivery_fee numeric(10,2) not null default 200;
alter table public.vendors
  add column if not exists hostel_delivery_fee numeric(10,2) not null default 300;


-- =====================================================================
-- 6. Audit #21 — gift orders credited the recipient's spending, not the payer's
-- =====================================================================
-- _refund_order() (section 17) reads this column, so it must exist before
-- Phase 9 finishes — not only once Phase 10 runs, or cancelling an order in
-- between the two would fail at runtime.
alter table public.orders
  add column if not exists gifted_by uuid references public.profiles (id) on delete set null;


-- =====================================================================
-- 7. Audit #3 — order totals were whatever the client said they were
-- =====================================================================
-- Every placement RPC took p_total_amount from the client and debited
-- exactly that, with no reference to products.base_price. A modified
-- client could buy a ₦5,000 order for ₦0.01.
--
-- These helpers recompute the authoritative total server-side. The RPCs
-- below then compare the client's figure against it and refuse the order
-- on a mismatch (rather than silently charging a different amount than
-- the student was shown — that surfaces genuine price drift, e.g. an
-- admin editing a price mid-checkout, instead of hiding it).

-- Per-vendor delivery fee for a given delivery type. 0 for pickup.
create or replace function public._delivery_fee(
  p_vendor_id     uuid,
  p_delivery_type text
)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare
  v_vendor public.vendors%rowtype;
begin
  if p_delivery_type is null or p_delivery_type = 'pickup' then
    return 0;
  end if;

  select * into v_vendor from public.vendors where id = p_vendor_id;
  if not found then
    raise exception 'VENDOR_NOT_FOUND';
  end if;

  return case p_delivery_type
    when 'campus_delivery' then v_vendor.campus_delivery_fee
    when 'hostel_delivery' then v_vendor.hostel_delivery_fee
    -- Legacy plain 'delivery' (Around requests, pre-Phase-6 food orders)
    when 'delivery'        then v_vendor.campus_delivery_fee
    else 0
  end;
end;
$$;

-- Sum of (products.base_price × quantity) for a client-supplied line-item
-- array, validating every product belongs to the vendor being ordered
-- from and is currently available.
create or replace function public._line_items_subtotal(
  p_vendor_id  uuid,
  p_line_items jsonb
)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare
  v_subtotal numeric := 0;
  v_item     jsonb;
  v_product  public.products%rowtype;
  v_qty      int;
begin
  if p_line_items is null or jsonb_array_length(p_line_items) = 0 then
    raise exception 'EMPTY_ORDER';
  end if;

  for v_item in select * from jsonb_array_elements(p_line_items) loop
    v_qty := (v_item ->> 'quantity')::int;
    if v_qty is null or v_qty < 1 or v_qty > 99 then
      raise exception 'INVALID_QUANTITY';
    end if;

    select * into v_product from public.products
     where id = (v_item ->> 'product_id')::uuid;

    if not found then
      raise exception 'PRODUCT_NOT_FOUND';
    end if;
    if v_product.vendor_id is distinct from p_vendor_id then
      raise exception 'PRODUCT_VENDOR_MISMATCH';
    end if;
    if not v_product.is_available then
      raise exception 'PRODUCT_UNAVAILABLE';
    end if;

    v_subtotal := v_subtotal + (v_product.base_price * v_qty);
  end loop;

  return v_subtotal;
end;
$$;

-- Inserts order_items for an order using SERVER prices, ignoring whatever
-- unit_price the client sent.
create or replace function public._insert_order_items(
  p_order_id   uuid,
  p_line_items jsonb
)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.order_items
    (order_id, product_id, product_name, quantity, unit_price, selected_options)
  select
    p_order_id,
    p.id,
    p.name,
    (item ->> 'quantity')::int,
    p.base_price,
    coalesce(item -> 'selected_options', '[]'::jsonb)
  from jsonb_array_elements(p_line_items) as item
  join public.products p on p.id = (item ->> 'product_id')::uuid;
end;
$$;


-- =====================================================================
-- 8. Audit #10 — transaction PIN could be reset without the old one,
--                and brute-forced with unlimited attempts
-- =====================================================================
alter table public.transaction_pins
  add column if not exists failed_attempts int not null default 0;
alter table public.transaction_pins
  add column if not exists locked_until timestamptz;

-- Setting a PIN for the first time needs nothing; CHANGING one now
-- requires the current PIN. Previously a stolen session could silently
-- replace the PIN and then spend freely.
create or replace function public.set_transaction_pin(
  p_pin         text,
  p_current_pin text default null
)
returns void language plpgsql security definer set search_path = public as $$
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
$$;

grant execute on function public.set_transaction_pin(text, text) to authenticated;

-- Checks a PIN and maintains the lockout counter. Returns a status string
-- rather than raising, because the callers must COMMIT the updated attempt
-- counter — a RAISE would roll the counter back and make the lockout
-- unenforceable.
--   'ok' | 'invalid' | 'locked' | 'not_set'
create or replace function public._check_transaction_pin(p_pin text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_row public.transaction_pins%rowtype;
begin
  select * into v_row from public.transaction_pins
   where user_id = auth.uid() for update;

  if not found then
    return 'not_set';
  end if;

  if v_row.locked_until is not null and v_row.locked_until > now() then
    return 'locked';
  end if;

  if p_pin is not null and crypt(p_pin, v_row.pin_hash) = v_row.pin_hash then
    update public.transaction_pins
       set failed_attempts = 0, locked_until = null
     where user_id = auth.uid();
    return 'ok';
  end if;

  update public.transaction_pins
     set failed_attempts = v_row.failed_attempts + 1,
         locked_until    = case
           when v_row.failed_attempts + 1 >= 5 then now() + interval '15 minutes'
           else null
         end
   where user_id = auth.uid();

  return 'invalid';
end;
$$;


-- =====================================================================
-- 9. Audit #3 + #9 — place_food_order_with_payment
-- =====================================================================
-- Same 13-argument signature the Flutter client already calls, so no
-- client change is required for the price validation itself.
--
-- Changes: server-recomputed total, server-priced line items, PIN lockout
-- handling, and bulk discount forced to 0 (it was client-supplied, so a
-- student could have sent 100 and paid nothing — nothing in the app sets
-- it, and when bulk pricing is built it needs an admin-controlled source).
create or replace function public.place_food_order_with_payment(
  p_vendor_id         uuid,
  p_source            text,
  p_delivery_type     text,
  p_delivery_location text,
  p_total_amount      numeric,
  p_estimated_time    text,
  p_line_items        jsonb,
  p_scheduled_for     timestamptz default null,
  p_is_bulk           boolean     default false,
  p_bulk_discount_pct numeric     default 0,
  p_pin               text        default null,
  p_pack_fee          numeric     default 0,
  p_packs             jsonb       default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id   uuid := auth.uid();
  v_pin_status   text;
  v_balance      numeric;
  v_new_balance  numeric;
  v_order_id     uuid;
  v_subtotal     numeric;
  v_delivery_fee numeric;
  v_pack_count   int;
  v_pack_fee     numeric;
  v_total        numeric;
  v_is_uniflex   boolean;
  v_source       text;
  v_pack         jsonb;
  v_pack_idx     int := 0;
  v_plan_id      uuid;
  v_plan_period  text;
  v_plan_budget  numeric;
  v_plan_spent   numeric;
  v_period_start timestamptz;
  v_period_end   timestamptz;
  v_new_spent    numeric;
  v_plan_over    boolean := false;
begin
  if v_student_id is null then
    raise exception 'Not authenticated';
  end if;

  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status <> 'ok' then
    return jsonb_build_object('error', case v_pin_status
      when 'locked'  then 'PIN_LOCKED'
      when 'not_set' then 'PIN_NOT_SET'
      else 'INVALID_PIN' end);
  end if;

  if p_scheduled_for is not null and p_scheduled_for <= now() then
    raise exception 'SCHEDULE_IN_PAST';
  end if;

  -- `source` decides whether an order goes through the kitchen or straight
  -- to the rider pool, so it must not come from the caller: sending
  -- 'partner' on a Uniflex order would dispatch food to a rider that the
  -- kitchen never made. Derive it from the vendor, as send_gift does.
  select (is_featured and badge_label = 'Major') into v_is_uniflex
    from public.vendors where id = p_vendor_id;
  if not found then
    raise exception 'VENDOR_NOT_FOUND';
  end if;
  v_source := case when v_is_uniflex then 'uniflex' else 'partner' end;

  -- ── Authoritative total ────────────────────────────────────────────
  v_subtotal     := public._line_items_subtotal(p_vendor_id, p_line_items);
  v_delivery_fee := public._delivery_fee(p_vendor_id, p_delivery_type);
  v_pack_count   := coalesce(jsonb_array_length(p_packs), 0);
  v_pack_fee     := v_pack_count *
                    (select pack_price from public.vendors where id = p_vendor_id);
  v_total        := v_subtotal + v_delivery_fee + v_pack_fee;

  if abs(v_total - coalesce(p_total_amount, -1)) > 0.01 then
    raise exception 'TOTAL_MISMATCH: expected %, got %', v_total, p_total_amount;
  end if;

  -- ── Wallet ─────────────────────────────────────────────────────────
  select balance into v_balance from public.wallets
   where user_id = v_student_id for update;
  if not found then
    raise exception 'WALLET_NOT_FOUND';
  end if;
  if v_balance < v_total then
    raise exception 'INSUFFICIENT_BALANCE';
  end if;

  update public.wallets set balance = balance - v_total
   where user_id = v_student_id returning balance into v_new_balance;

  -- ── Order ──────────────────────────────────────────────────────────
  insert into public.orders
    (student_id, vendor_id, source, type, status, delivery_type,
     delivery_location, total_amount, estimated_time, scheduled_for,
     is_bulk, bulk_discount_pct, pack_count, pack_fee)
  values
    (v_student_id, p_vendor_id, v_source, 'food', 'placed', p_delivery_type,
     p_delivery_location, v_total, p_estimated_time, p_scheduled_for,
     p_is_bulk, 0, v_pack_count, v_pack_fee)
  returning id into v_order_id;

  perform public._insert_order_items(v_order_id, p_line_items);

  for v_pack in select * from jsonb_array_elements(p_packs) loop
    insert into public.order_packs (order_id, pack_index, items)
    values (v_order_id, v_pack_idx, coalesce(v_pack -> 'items', '[]'::jsonb));
    v_pack_idx := v_pack_idx + 1;
  end loop;

  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_student_id, 'debit', v_total, 'order_payment', v_order_id, v_new_balance);

  -- ── Saving plan (lazy period reset) ────────────────────────────────
  select id, period, budget, spent, period_start
    into v_plan_id, v_plan_period, v_plan_budget, v_plan_spent, v_period_start
  from public.saving_plans
  where user_id = v_student_id and is_active
  limit 1;

  if v_plan_id is not null then
    v_period_end := case v_plan_period
      when 'daily'  then v_period_start + interval '1 day'
      when 'weekly' then v_period_start + interval '7 days'
      else               v_period_start + interval '1 month'
    end;

    if now() >= v_period_end then
      v_period_start := date_trunc('day', now());
      v_new_spent    := v_total;
    else
      v_new_spent    := v_plan_spent + v_total;
    end if;

    update public.saving_plans
       set spent = v_new_spent, period_start = v_period_start, updated_at = now()
     where id = v_plan_id;

    v_plan_over := v_new_spent > v_plan_budget;
  end if;

  return jsonb_build_object(
    'order_id',          v_order_id,
    'balance_after',     v_new_balance,
    'plan_over_budget',  v_plan_over,
    'plan_period_reset', false
  );
end;
$$;

grant execute on function public.place_food_order_with_payment(
  uuid, text, text, text, numeric, text, jsonb, timestamptz, boolean, numeric, text, numeric, jsonb
) to authenticated;


-- =====================================================================
-- 10. Audit #3 + #9 — place_around_with_payment
-- =====================================================================
-- The fee is now taken from around_categories.flat_fee, not from the
-- client.
create or replace function public.place_around_with_payment(
  p_category         text,
  p_pickup_location  text,
  p_dropoff_location text,
  p_item_description text,
  p_total_amount     numeric,
  p_pin              text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id   uuid := auth.uid();
  v_pin_status   text;
  v_fee          numeric;
  v_is_active    boolean;
  v_balance      numeric;
  v_new_balance  numeric;
  v_order_id     uuid;
  v_plan_id      uuid;
  v_plan_period  text;
  v_plan_budget  numeric;
  v_plan_spent   numeric;
  v_period_start timestamptz;
  v_period_end   timestamptz;
  v_new_spent    numeric;
  v_plan_over    boolean := false;
begin
  if v_student_id is null then
    raise exception 'Not authenticated';
  end if;

  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status <> 'ok' then
    return jsonb_build_object('error', case v_pin_status
      when 'locked'  then 'PIN_LOCKED'
      when 'not_set' then 'PIN_NOT_SET'
      else 'INVALID_PIN' end);
  end if;

  select flat_fee, is_active into v_fee, v_is_active
    from public.around_categories where key = p_category;
  if not found then
    raise exception 'CATEGORY_NOT_FOUND';
  end if;
  if not v_is_active then
    raise exception 'CATEGORY_INACTIVE';
  end if;

  if abs(v_fee - coalesce(p_total_amount, -1)) > 0.01 then
    raise exception 'TOTAL_MISMATCH: expected %, got %', v_fee, p_total_amount;
  end if;

  select balance into v_balance from public.wallets
   where user_id = v_student_id for update;
  if not found then
    raise exception 'WALLET_NOT_FOUND';
  end if;
  if v_balance < v_fee then
    raise exception 'INSUFFICIENT_BALANCE';
  end if;

  update public.wallets set balance = balance - v_fee
   where user_id = v_student_id returning balance into v_new_balance;

  insert into public.orders
    (student_id, source, type, status, delivery_type, total_amount, estimated_time)
  values
    (v_student_id, 'uniflex', 'around', 'placed', 'delivery', v_fee, '15–25 min')
  returning id into v_order_id;

  insert into public.around_requests
    (order_id, category, pickup_location, dropoff_location,
     item_description, estimated_fee)
  values
    (v_order_id, p_category, p_pickup_location, p_dropoff_location,
     p_item_description, v_fee);

  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_student_id, 'debit', v_fee, 'order_payment', v_order_id, v_new_balance);

  select id, period, budget, spent, period_start
    into v_plan_id, v_plan_period, v_plan_budget, v_plan_spent, v_period_start
  from public.saving_plans
  where user_id = v_student_id and is_active
  limit 1;

  if v_plan_id is not null then
    v_period_end := case v_plan_period
      when 'daily'  then v_period_start + interval '1 day'
      when 'weekly' then v_period_start + interval '7 days'
      else               v_period_start + interval '1 month'
    end;

    if now() >= v_period_end then
      v_period_start := date_trunc('day', now());
      v_new_spent    := v_fee;
    else
      v_new_spent    := v_plan_spent + v_fee;
    end if;

    update public.saving_plans
       set spent = v_new_spent, period_start = v_period_start, updated_at = now()
     where id = v_plan_id;

    v_plan_over := v_new_spent > v_plan_budget;
  end if;

  return jsonb_build_object(
    'order_id',          v_order_id,
    'balance_after',     v_new_balance,
    'plan_over_budget',  v_plan_over,
    'plan_period_reset', false
  );
end;
$$;

grant execute on function public.place_around_with_payment(
  text, text, text, text, numeric, text
) to authenticated;


-- =====================================================================
-- 11. Audit #3 + #9 + #21 — send_gift
-- =====================================================================
-- Adds server-side pricing, the transaction-PIN gate (gifting was a
-- complete bypass of it), and gifted_by so the PAYER gets the spending /
-- points credit instead of the recipient.
--
-- NOTE: this adds a required p_pin argument. The gift flow is currently
-- unreachable from the UI (audit #26), so nothing breaks today — but
-- whoever wires up the Send Gift screen must collect a PIN and pass it.
create or replace function public.send_gift(
  p_recipient_matric  text,
  p_vendor_id         uuid,
  p_line_items        jsonb,
  p_total_amount      numeric,
  p_message           text default null,
  p_delivery_type     text default 'pickup',
  p_delivery_location text default null,
  p_pin               text default null
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_sender_id    uuid := auth.uid();
  v_pin_status   text;
  v_recipient_id uuid;
  v_order_id     uuid;
  v_balance      numeric;
  v_new_balance  numeric;
  v_gift_id      uuid;
  v_is_uniflex   boolean;
  v_source       text;
  v_subtotal     numeric;
  v_delivery_fee numeric;
  v_total        numeric;
begin
  if v_sender_id is null then
    raise exception 'Not authenticated';
  end if;

  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status <> 'ok' then
    return jsonb_build_object('error', case v_pin_status
      when 'locked'  then 'PIN_LOCKED'
      when 'not_set' then 'PIN_NOT_SET'
      else 'INVALID_PIN' end);
  end if;

  select id into v_recipient_id
    from public.profiles
   where matric_number = p_recipient_matric and role = 'student' and is_active;
  if not found then raise exception 'RECIPIENT_NOT_FOUND'; end if;
  if v_recipient_id = v_sender_id then raise exception 'CANNOT_GIFT_SELF'; end if;

  v_subtotal     := public._line_items_subtotal(p_vendor_id, p_line_items);
  v_delivery_fee := public._delivery_fee(p_vendor_id, p_delivery_type);
  v_total        := v_subtotal + v_delivery_fee;

  if abs(v_total - coalesce(p_total_amount, -1)) > 0.01 then
    raise exception 'TOTAL_MISMATCH: expected %, got %', v_total, p_total_amount;
  end if;

  select balance into v_balance
    from public.wallets where user_id = v_sender_id for update;
  if not found then raise exception 'WALLET_NOT_FOUND'; end if;
  if v_balance < v_total then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.wallets set balance = balance - v_total
    where user_id = v_sender_id returning balance into v_new_balance;

  select (is_featured and badge_label = 'Major') into v_is_uniflex
    from public.vendors where id = p_vendor_id;
  v_source := case when v_is_uniflex then 'uniflex' else 'partner' end;

  insert into public.orders
    (student_id, vendor_id, source, type, status,
     delivery_type, delivery_location, total_amount, estimated_time, gifted_by)
  values
    (v_recipient_id, p_vendor_id, v_source, 'food', 'placed',
     p_delivery_type, p_delivery_location, v_total, '20–30 min', v_sender_id)
  returning id into v_order_id;

  perform public._insert_order_items(v_order_id, p_line_items);

  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_sender_id, 'debit', v_total, 'gift_payment', v_order_id, v_new_balance);

  insert into public.gifts (sender_id, recipient_id, order_id, message)
  values (v_sender_id, v_recipient_id, v_order_id, p_message)
  returning id into v_gift_id;

  perform set_config('uniflex.trusted_write', 'on', true);
  insert into public.user_achievements (user_id, achievement_id)
  select v_sender_id, id from public.achievements where code = 'gifter'
  on conflict (user_id, achievement_id) do nothing;
  perform set_config('uniflex.trusted_write', 'off', true);

  return jsonb_build_object(
    'gift_id',            v_gift_id,
    'order_id',           v_order_id,
    'recipient_nickname', (select coalesce(nickname, full_name)
                            from public.profiles where id = v_recipient_id)
  );
end;
$$;

grant execute on function public.send_gift(
  text, uuid, jsonb, numeric, text, text, text, text
) to authenticated;


-- =====================================================================
-- 12. Audit #3 + #9 + #25 — checkout_group_order
-- =====================================================================
-- Server-side pricing, PIN gate, and it now requires the group to still
-- be 'open' (it previously only rejected 'cancelled', so members could
-- keep checking out after the group closed).
--
-- NOTE: also gains a required p_pin. Group checkout is currently
-- unreachable from the UI (audit #27) — same caveat as send_gift.
create or replace function public.checkout_group_order(
  p_group_id          uuid,
  p_line_items        jsonb,
  p_my_total          numeric,
  p_delivery_type     text default 'pickup',
  p_delivery_location text default null,
  p_pin               text default null
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid          uuid := auth.uid();
  v_pin_status   text;
  v_group        public.group_orders;
  v_balance      numeric;
  v_new_balance  numeric;
  v_order_id     uuid;
  v_is_uniflex   boolean;
  v_source       text;
  v_subtotal     numeric;
  v_delivery_fee numeric;
  v_total        numeric;
  v_delivery     text;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status <> 'ok' then
    return jsonb_build_object('error', case v_pin_status
      when 'locked'  then 'PIN_LOCKED'
      when 'not_set' then 'PIN_NOT_SET'
      else 'INVALID_PIN' end);
  end if;

  select * into v_group from public.group_orders where id = p_group_id;
  if not found then raise exception 'GROUP_NOT_FOUND'; end if;
  if v_group.status <> 'open' then raise exception 'GROUP_CLOSED'; end if;

  if not exists (
    select 1 from public.group_order_members
    where group_order_id = p_group_id and student_id = v_uid
  ) then raise exception 'NOT_A_MEMBER'; end if;

  if exists (
    select 1 from public.group_order_members
    where group_order_id = p_group_id and student_id = v_uid and paid
  ) then raise exception 'ALREADY_CHECKED_OUT'; end if;

  v_delivery     := coalesce(p_delivery_type, v_group.delivery_type, 'pickup');
  v_subtotal     := public._line_items_subtotal(v_group.vendor_id, p_line_items);
  v_delivery_fee := public._delivery_fee(v_group.vendor_id, v_delivery);
  v_total        := v_subtotal + v_delivery_fee;

  if abs(v_total - coalesce(p_my_total, -1)) > 0.01 then
    raise exception 'TOTAL_MISMATCH: expected %, got %', v_total, p_my_total;
  end if;

  select balance into v_balance from public.wallets
   where user_id = v_uid for update;
  if not found then raise exception 'WALLET_NOT_FOUND'; end if;
  if v_balance < v_total then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.wallets set balance = balance - v_total
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
     v_delivery,
     coalesce(p_delivery_location, v_group.delivery_location),
     v_total, '20–30 min', p_group_id, 0)
  returning id into v_order_id;

  perform public._insert_order_items(v_order_id, p_line_items);

  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_uid, 'debit', v_total, 'group_order_payment', v_order_id, v_new_balance);

  update public.group_order_members
     set order_id = v_order_id, paid = true
   where group_order_id = p_group_id and student_id = v_uid;

  return jsonb_build_object('order_id', v_order_id);
end;
$$;

grant execute on function public.checkout_group_order(
  uuid, jsonb, numeric, text, text, text
) to authenticated;

-- Bulk discount is no longer taken from the caller — it was a free-order
-- lever (create a group at 100% off, then check out). Nothing in the app
-- sets it; when bulk pricing is built it needs an admin-owned source.
create or replace function public.create_group_order(
  p_vendor_id     uuid,
  p_bulk_discount numeric default 0
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid      uuid := auth.uid();
  v_group_id uuid;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if not exists (select 1 from public.vendors where id = p_vendor_id and is_active) then
    raise exception 'VENDOR_NOT_FOUND';
  end if;

  insert into public.group_orders (creator_id, vendor_id, bulk_discount_pct)
  values (v_uid, p_vendor_id, 0)
  returning id into v_group_id;

  insert into public.group_order_members (group_order_id, student_id)
  values (v_group_id, v_uid);

  return v_group_id;
end;
$$;

grant execute on function public.create_group_order(uuid, numeric) to authenticated;


-- =====================================================================
-- 13. Audit #21 — attribute order stats to whoever actually paid
-- =====================================================================
create or replace function public._after_order_placed()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_new_spending numeric;
  v_new_tier     text;
  v_new_orders   int;
  v_subject      uuid;
begin
  if new.type not in ('food','around') then
    return new;
  end if;

  -- A gift order is placed under the recipient, but the sender paid — so
  -- the sender is the one whose spending/points/tier should move.
  v_subject := coalesce(new.gifted_by, new.student_id);

  perform set_config('uniflex.trusted_write', 'on', true);

  update public.profiles
     set total_orders      = total_orders + 1,
         lifetime_spending = lifetime_spending + new.total_amount,
         reward_points     = reward_points + floor(new.total_amount / 100)::int
   where id = v_subject
  returning lifetime_spending, total_orders into v_new_spending, v_new_orders;

  v_new_tier := case
    when v_new_spending >= 50000 then 'Platinum'
    when v_new_spending >= 20000 then 'Gold'
    when v_new_spending >= 5000  then 'Silver'
    else                              'Bronze'
  end;

  update public.profiles set membership_tier = v_new_tier
   where id = v_subject and membership_tier <> v_new_tier;

  if v_new_tier = 'Silver' then
    insert into public.user_achievements (user_id, achievement_id)
    select v_subject, id from public.achievements where code = 'silver_tier'
    on conflict (user_id, achievement_id) do nothing;
  elsif v_new_tier = 'Gold' then
    insert into public.user_achievements (user_id, achievement_id)
    select v_subject, id from public.achievements where code = 'gold_tier'
    on conflict (user_id, achievement_id) do nothing;
  elsif v_new_tier = 'Platinum' then
    insert into public.user_achievements (user_id, achievement_id)
    select v_subject, id from public.achievements where code = 'platinum_tier'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if v_new_orders = 1 then
    insert into public.user_achievements (user_id, achievement_id)
    select v_subject, id from public.achievements where code = 'first_order'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_new_orders = 10 then
    insert into public.user_achievements (user_id, achievement_id)
    select v_subject, id from public.achievements where code = 'ten_orders'
    on conflict (user_id, achievement_id) do nothing;
  end if;
  if v_new_orders = 50 then
    insert into public.user_achievements (user_id, achievement_id)
    select v_subject, id from public.achievements where code = 'fifty_orders'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  perform set_config('uniflex.trusted_write', 'off', true);
  return new;
end;
$$;


-- =====================================================================
-- 14. Audit #13 — self-referral, and re-runnable onboarding
-- =====================================================================
-- complete_student_onboarding() had no "already onboarded" guard, so a
-- student could re-run it to regenerate their referral code (invalidating
-- any they had already shared) and — because they now HAD a code — pass
-- their own, creating a self-referral worth ₦500.
create or replace function public.complete_student_onboarding(
  p_nickname           text,
  p_full_name          text,
  p_matric_number      text,
  p_school             text,
  p_date_of_birth      date,
  p_referral_code_used text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id     uuid := auth.uid();
  v_new_code    text;
  v_referrer_id uuid;
  v_profile     public.profiles;
  v_done        boolean;
begin
  if v_user_id is null then
    raise exception 'Not signed in';
  end if;

  select onboarding_complete into v_done
    from public.profiles where id = v_user_id;
  if not found then
    raise exception 'No profile row for %; Step One (create account) must run first', v_user_id;
  end if;
  if v_done then
    raise exception 'ALREADY_ONBOARDED';
  end if;

  if p_referral_code_used is not null and length(trim(p_referral_code_used)) > 0 then
    select id into v_referrer_id
      from public.profiles
     where referral_code = upper(trim(p_referral_code_used));

    if v_referrer_id is null then
      raise exception 'Referral code % not found', p_referral_code_used;
    end if;
    if v_referrer_id = v_user_id then
      raise exception 'CANNOT_REFER_SELF';
    end if;
  end if;

  loop
    v_new_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from public.profiles where referral_code = v_new_code);
  end loop;

  perform set_config('uniflex.trusted_write', 'on', true);

  update public.profiles set
    role                = 'student',
    nickname            = p_nickname,
    full_name           = p_full_name,
    matric_number       = p_matric_number,
    school              = p_school,
    date_of_birth       = p_date_of_birth,
    referral_code       = v_new_code,
    referred_by_code    = case when v_referrer_id is not null
                               then upper(trim(p_referral_code_used)) end,
    onboarding_complete = true
  where id = v_user_id
  returning * into v_profile;

  insert into public.wallets (user_id, balance, virtual_account_number, tier)
  values (
    v_user_id, 0,
    'UFX-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
    'Bronze'
  )
  on conflict (user_id) do nothing;

  if v_referrer_id is not null then
    insert into public.referrals (referrer_id, referred_id, referral_code_used)
    values (v_referrer_id, v_user_id, upper(trim(p_referral_code_used)))
    on conflict (referred_id) do nothing;
  end if;

  perform set_config('uniflex.trusted_write', 'off', true);
  return v_profile;
end;
$$;

grant execute on function public.complete_student_onboarding(
  text, text, text, text, date, text
) to authenticated;

-- Belt and braces: never pay a referral bonus to the referred student.
create or replace function public._after_order_completed()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_referrer_id     uuid;
  v_completed_count bigint;
  v_credit          numeric := 500;
begin
  if new.status <> 'completed' or old.status = 'completed' then
    return new;
  end if;

  select referrer_id into v_referrer_id
    from public.referrals where referred_id = new.student_id;

  if v_referrer_id is null or v_referrer_id = new.student_id then
    return new;
  end if;

  select count(*) into v_completed_count
    from public.orders
   where student_id = new.student_id and status = 'completed' and id <> new.id;
  if v_completed_count > 0 then return new; end if;

  if exists (
    select 1 from public.referral_credits
    where referrer_id = v_referrer_id and referred_id = new.student_id
  ) then return new; end if;

  update public.wallets set balance = balance + v_credit
   where user_id = v_referrer_id;

  insert into public.wallet_transactions
    (user_id, type, amount, source, balance_after)
  select v_referrer_id, 'credit', v_credit, 'referral_bonus', balance
    from public.wallets where user_id = v_referrer_id;

  perform set_config('uniflex.trusted_write', 'on', true);
  update public.profiles
     set reward_points  = reward_points + 50,
         referral_count = referral_count + 1
   where id = v_referrer_id;

  insert into public.user_achievements (user_id, achievement_id)
  select v_referrer_id, id from public.achievements where code = 'first_referral'
  on conflict (user_id, achievement_id) do nothing;
  perform set_config('uniflex.trusted_write', 'off', true);

  insert into public.referral_credits (referrer_id, referred_id, credit_amount)
  values (v_referrer_id, new.student_id, v_credit);

  return new;
end;
$$;


-- =====================================================================
-- 15. Audit #5 — unlimited birthday credits
-- =====================================================================
-- Was granted to `authenticated` with no idempotency guard, so ANY signed-in
-- student could call it in a loop and credit every eligible student each
-- time. Now: one reward per student per calendar year, and only the cron /
-- service role may call it.
revoke execute on function public.process_birthday_rewards() from authenticated;

create or replace function public.process_birthday_rewards()
returns void language plpgsql security definer set search_path = public as $$
declare
  rec      record;
  v_credit numeric;
  v_year   int := date_part('year', current_date)::int;
begin
  for rec in
    select p.id, p.membership_tier
    from   public.profiles p
    join   public.wallets  w on w.user_id = p.id
    where  p.role = 'student'
      and  p.is_active
      and  p.membership_tier in ('Silver','Gold','Platinum')
      and  date_part('month', p.date_of_birth) = date_part('month', current_date)
      and  date_part('day',   p.date_of_birth) = date_part('day',   current_date)
  loop
    v_credit := case rec.membership_tier
      when 'Silver'   then 500
      when 'Gold'     then 1000
      when 'Platinum' then 2000
      else 0
    end;

    if v_credit <= 0 then
      continue;
    end if;

    -- The unique (user_id, reward_year) constraint is what makes repeated
    -- calls harmless: the second insert does nothing, so we skip the credit.
    insert into public.birthday_rewards_log (user_id, reward_year, amount)
    values (rec.id, v_year, v_credit)
    on conflict (user_id, reward_year) do nothing;

    if not found then
      continue;
    end if;

    update public.wallets set balance = balance + v_credit where user_id = rec.id;

    insert into public.wallet_transactions
      (user_id, type, amount, source, balance_after)
    select rec.id, 'credit', v_credit, 'birthday_reward', balance
      from public.wallets where user_id = rec.id;

    insert into public.user_achievements (user_id, achievement_id)
    select rec.id, id from public.achievements where code = 'birthday_bonus'
    on conflict (user_id, achievement_id) do nothing;
  end loop;
end;
$$;

grant execute on function public.process_birthday_rewards() to service_role;
grant execute on function public.process_birthday_rewards() to postgres;


-- =====================================================================
-- 16. Audit #18 — verify_delivery completed orders with no PIN
-- =====================================================================
-- `upper(trim(p_pin)) != upper(NULL)` evaluates to NULL, so the IF never
-- fired and the order was marked completed without any PIN check.
create or replace function public.verify_delivery(
  p_order_id uuid,
  p_pin      text
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders%rowtype;
begin
  if not public.is_rider() then
    raise exception 'Unauthorized';
  end if;

  select * into v_order from public.orders
   where id = p_order_id and rider_id = auth.uid();
  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.delivery_stage is distinct from 'picked_up' then
    raise exception 'Confirm pickup before verifying delivery';
  end if;

  if v_order.delivery_pin is null then
    raise exception 'This order has no delivery PIN — contact support';
  end if;
  if p_pin is null or upper(trim(p_pin)) <> upper(v_order.delivery_pin) then
    raise exception 'Incorrect delivery PIN';
  end if;

  update public.orders
     set status = 'completed', delivery_stage = null
   where id = p_order_id;

  insert into public.delivery_records (order_id, rider_id, completed_at)
  values (p_order_id, auth.uid(), now())
  on conflict (order_id) do nothing;
end;
$$;

grant execute on function public.verify_delivery(uuid, text) to authenticated;


-- =====================================================================
-- 17. Audit #12 + #22 — cancelling an order kept the student's money,
--                       and never reversed their stats
-- =====================================================================
-- There was no refund path anywhere in the system: update_order_status
-- set status='cancelled' and the wallet debit simply stayed. Cancelling
-- now refunds whoever actually paid (found via the debit transaction, so
-- gift orders refund the sender, not the recipient) and unwinds the
-- spending/points/tier the placement trigger added.
create or replace function public._refund_order(p_order_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_order      public.orders%rowtype;
  v_payer_id   uuid;
  v_amount     numeric;
  v_balance    numeric;
  v_subject    uuid;
  v_spending   numeric;
  v_orders     int;
  v_tier       text;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found';
  end if;

  -- Who actually paid, and how much. Covers order_payment, gift_payment
  -- and group_order_payment alike.
  select user_id, amount into v_payer_id, v_amount
    from public.wallet_transactions
   where order_id = p_order_id and type = 'debit'
   order by created_at
   limit 1;

  if v_payer_id is null then
    return;   -- nothing was ever charged for this order
  end if;

  if exists (
    select 1 from public.wallet_transactions
    where order_id = p_order_id and type = 'credit' and source = 'refund'
  ) then
    return;   -- already refunded
  end if;

  update public.wallets set balance = balance + v_amount
   where user_id = v_payer_id returning balance into v_balance;

  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_payer_id, 'credit', v_amount, 'refund', p_order_id, v_balance);

  -- Unwind the stats _after_order_placed() granted.
  v_subject := coalesce(v_order.gifted_by, v_order.student_id);

  perform set_config('uniflex.trusted_write', 'on', true);

  update public.profiles
     set total_orders      = greatest(total_orders - 1, 0),
         lifetime_spending = greatest(lifetime_spending - v_order.total_amount, 0),
         reward_points     = greatest(
                               reward_points - floor(v_order.total_amount / 100)::int, 0)
   where id = v_subject
  returning lifetime_spending, total_orders into v_spending, v_orders;

  v_tier := case
    when v_spending >= 50000 then 'Platinum'
    when v_spending >= 20000 then 'Gold'
    when v_spending >= 5000  then 'Silver'
    else                          'Bronze'
  end;

  update public.profiles set membership_tier = v_tier
   where id = v_subject and membership_tier <> v_tier;

  perform set_config('uniflex.trusted_write', 'off', true);
end;
$$;

create or replace function public.update_order_status(
  p_order_id   uuid,
  p_new_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if not (select public.is_admin()) then
    raise exception 'Unauthorized';
  end if;

  if p_new_status not in (
    'placed', 'preparing', 'ready',
    'out_for_delivery', 'ready_for_pickup',
    'completed', 'cancelled'
  ) then
    raise exception 'Invalid status: %', p_new_status;
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if not found then
    raise exception 'Order not found: %', p_order_id;
  end if;

  if (
       v_order.type = 'around'
       or (v_order.type = 'food'
           and v_order.delivery_type in ('delivery','campus_delivery','hostel_delivery'))
     )
     and p_new_status in ('out_for_delivery', 'completed') then
    raise exception 'Delivery orders can only reach that status through the rider workflow';
  end if;

  if v_order.type = 'food' and v_order.delivery_type = 'pickup'
     and p_new_status = 'completed' and v_order.status <> 'ready_for_pickup' then
    raise exception 'Pickup orders must be Ready for Pickup before they can be completed';
  end if;

  if v_order.status = 'completed' and p_new_status = 'cancelled' then
    raise exception 'A completed order cannot be cancelled — issue a refund out of band';
  end if;

  -- Refund BEFORE flipping the status, so _refund_order sees the original
  -- row and the "already refunded" guard stays meaningful.
  if p_new_status = 'cancelled' and v_order.status <> 'cancelled' then
    perform public._refund_order(p_order_id);
  end if;

  update public.orders set status = p_new_status where id = p_order_id;
end;
$$;

grant execute on function public.update_order_status(uuid, text) to authenticated;


-- =====================================================================
-- 18. Realtime — publish the tables the new flows touch
-- =====================================================================
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'wallets'
  ) then
    execute 'alter publication supabase_realtime add table public.wallets';
  end if;
end;
$$;
