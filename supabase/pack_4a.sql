-- =====================================================================
-- Pack 4A — Payment-first checkout, ₦30 service charge, one
--           notification pipeline, support-chat repair
--
-- Run ONCE in the Supabase SQL editor. One additive block.
--
-- PREREQUISITES (already applied if you followed earlier rounds):
--   schema.sql, phase9_security_hardening.sql, phase10_admin_features.sql,
--   round8_migration.sql, round8_bugfix.sql, round9_cancel.sql,
--   support_chat.sql, fix_pack_1.sql, fix_pack_2.sql, fix_pack_3.sql
--
-- WHAT THIS DOES
--   1.  app_settings table + editable ₦30 service charge
--   2.  New columns (service_charge, is_paid) + order_payment_attempts
--   3.  Hides never-paid (legacy) orders at the database level
--   4.  Three atomic "verify PIN + debit + create" RPCs
--         create_paid_delivery_order / create_paid_pickup_order /
--         create_paid_errand
--       and DROPS the old "create now, pay later" RPCs
--   5.  One notification pipeline: DB triggers write the inbox row,
--       a trigger on the inbox calls the push Edge Function
--   6.  Support chat: drops every old overload, creates exactly one
--       of each function
--   7.  Dashboard stats ignore unpaid orders
--
-- NOTHING IS DELETED. Tables/columns that hold data are kept; what is
-- now unused is listed at the bottom of this file.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Prerequisite check + helper
-- ---------------------------------------------------------------------
do $$
begin
  if to_regclass('public.delivery_groups') is null
     or to_regclass('public.support_conversations') is null
     or to_regclass('public.errand_categories') is null
     or to_regclass('public.delivery_locations') is null then
    raise exception
      'Pack 4A prerequisites missing — run round8_migration.sql, '
      'support_chat.sql and fix_pack_1/2/3.sql first.';
  end if;
end $$;

-- Soft-delete columns (no-ops if Fix Pack 3 already added them).
alter table public.products          add column if not exists deleted_at timestamptz;
alter table public.vendors           add column if not exists deleted_at timestamptz;
alter table public.errand_categories add column if not exists deleted_at timestamptz;

-- Drops EVERY overload of the named public functions. Used because
-- `create or replace` with a different parameter list creates a second
-- function instead of replacing the first. (A normal function, not a
-- session-temporary one, so it works however the SQL editor batches the
-- script; it is dropped again at the end.)
create or replace function public._pack4a_drop_overloads(p_names text[])
returns void language plpgsql as $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = any (p_names)
  loop
    execute 'drop function ' || r.sig;
  end loop;
end $$;


-- ---------------------------------------------------------------------
-- 1. app_settings + service charge
-- ---------------------------------------------------------------------
create table if not exists public.app_settings (
  key         text primary key,
  value       text not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles (id) on delete set null
);

alter table public.app_settings enable row level security;
-- No policies on purpose: nobody reads or writes this table directly.
-- Reads go through get_service_charge(); writes through
-- admin_set_service_charge().

insert into public.app_settings (key, value)
values ('service_charge', '30')
on conflict (key) do nothing;

create or replace function public._service_charge()
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select nullif(trim(value), '')::numeric
       from public.app_settings where key = 'service_charge'),
    30);
$$;

revoke all on function public._service_charge() from public, anon, authenticated;

create or replace function public.get_service_charge()
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select public._service_charge();
$$;

grant execute on function public.get_service_charge() to authenticated;

create or replace function public.admin_set_service_charge(p_amount integer)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Unauthorized';
  end if;
  if p_amount is null or p_amount < 0 or p_amount > 100000 then
    raise exception 'INVALID_AMOUNT';
  end if;

  insert into public.app_settings (key, value, updated_at, updated_by)
  values ('service_charge', p_amount::text, now(), auth.uid())
  on conflict (key) do update
    set value = excluded.value,
        updated_at = excluded.updated_at,
        updated_by = excluded.updated_by;

  return p_amount;
end;
$$;

grant execute on function public.admin_set_service_charge(integer) to authenticated;


-- ---------------------------------------------------------------------
-- 2. Columns + idempotency table
-- ---------------------------------------------------------------------
-- The service charge actually charged on each order (never recomputed,
-- so changing the setting later cannot alter past orders). Deliveries
-- store it on the group (once per checkout); errands on the order.
alter table public.delivery_groups
  add column if not exists service_charge numeric(10,2) not null default 0;
alter table public.orders
  add column if not exists service_charge numeric(10,2) not null default 0;

-- false = this row was created by the old "create first, pay later"
-- button and was never paid. Hidden from every list (section 3).
alter table public.delivery_groups
  add column if not exists is_paid boolean not null default true;
alter table public.orders
  add column if not exists is_paid boolean not null default true;

create table if not exists public.order_payment_attempts (
  idempotency_key uuid primary key,
  student_id      uuid not null references public.profiles (id) on delete cascade,
  kind            text not null check (kind in ('delivery', 'pickup', 'errand')),
  result          jsonb not null,
  created_at      timestamptz not null default now()
);

alter table public.order_payment_attempts enable row level security;
-- No policies: only the RPCs (security definer) touch this table.


-- ---------------------------------------------------------------------
-- 3. Legacy unpaid orders: flag + hide (nothing deleted)
-- ---------------------------------------------------------------------
-- Unpaid delivery group = still 'placed' (pay_group_commitment_fee was
-- the only thing that ever moved it on).
update public.delivery_groups
   set is_paid = false
 where status = 'placed'
   and is_paid = true;

-- Legs of an unpaid group.
update public.orders o
   set is_paid = false
 where o.is_paid = true
   and o.delivery_group_id is not null
   and exists (select 1 from public.delivery_groups g
                where g.id = o.delivery_group_id and g.is_paid = false);

-- Standalone orders that were never paid: not pickup, commitment fee
-- not paid, still placed, and no wallet debit ever recorded for them.
update public.orders o
   set is_paid = false
 where o.is_paid = true
   and o.delivery_group_id is null
   and coalesce(o.delivery_type, '') <> 'pickup'
   and coalesce(o.commitment_fee_paid, false) = false
   and o.status = 'placed'
   and not exists (select 1 from public.wallet_transactions wt
                    where wt.order_id = o.id and wt.type = 'debit');

-- RESTRICTIVE policies are AND-ed with every existing policy, so no
-- student / rider / admin SELECT (including Realtime streams) can see an
-- unpaid row no matter which permissive policy would have allowed it.
-- Security-definer RPCs and the SQL editor are not affected.
drop policy if exists "orders: hide unpaid" on public.orders;
create policy "orders: hide unpaid" on public.orders
  as restrictive for select to authenticated
  using (is_paid);

drop policy if exists "delivery_groups: hide unpaid" on public.delivery_groups;
create policy "delivery_groups: hide unpaid" on public.delivery_groups
  as restrictive for select to authenticated
  using (is_paid);

create index if not exists orders_unpaid_idx
  on public.orders (created_at) where is_paid = false;


-- ---------------------------------------------------------------------
-- 4. Atomic paid-order RPCs
--
-- Every one of them, in ONE transaction:
--   idempotency check → PIN → compute every amount server-side →
--   lock wallet + balance check → debit → create the whole order.
--
-- The client sends only choices (ids, quantities, pack allocation,
-- location id). It can never send a price or a fee.
--
-- PIN problems (invalid / locked / not set) are RETURNED as
-- {"error": "..."} instead of raised: a raise would roll back the
-- failed-attempt counter that drives the 15-minute lockout.
-- Every other failure RAISES, which rolls the whole thing back, so a
-- failed payment can never leave a partial order or a debit.
-- ---------------------------------------------------------------------

-- Remove the old create-now-pay-later split (all overloads).
select public._pack4a_drop_overloads(array[
  'place_multi_vendor_order',
  'pay_group_commitment_fee',
  'pay_commitment_fee',
  'place_errand_order',
  'place_errand_with_payment',
  'place_around_order',
  'place_around_with_payment',
  'place_partner_food_order',
  'place_food_order_with_payment'
]);

-- set_transaction_pin was defined twice with different parameter lists
-- (schema.sql: (text); later: (text, text default null)). A first-time
-- "set my PIN" call that sends only p_pin matches BOTH and fails as
-- ambiguous — the same overload bug as send_support_message — which
-- would block the pay flow for any student without a PIN. Keep ONE.
select public._pack4a_drop_overloads(array['set_transaction_pin']);

create or replace function public.set_transaction_pin(
  p_pin         text,
  p_current_pin text default null
)
returns void language plpgsql security definer
set search_path = public, extensions
as $$
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

-- The lockout-aware PIN checker every paid RPC below relies on. Re-created
-- here (identical to the Round 5 version) so it is guaranteed to have
-- `extensions` on its search_path — an older definition without it cannot
-- see pgcrypto's crypt() and would fail every payment.
create or replace function public._check_transaction_pin(p_pin text)
returns text language plpgsql security definer
set search_path = public, extensions
as $$
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

-- Pack brackets: 0–3 packs = 1×, 4–6 = 2×, … (0 packs still 1×).
create or replace function public._pack_brackets(p_packs int)
returns int
language sql
immutable
as $$
  select case when coalesce(p_packs, 0) <= 0 then 1
              else ((p_packs + 2) / 3) end;
$$;

-- ── 4a. Delivery (food) ──────────────────────────────────────────────
create or replace function public.create_paid_delivery_order(
  p_idempotency_key      uuid,
  p_pin                  text,
  p_legs                 jsonb,
  p_delivery_location_id uuid,
  p_location_details     text default null,
  p_student_note         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_student      uuid := auth.uid();
  v_existing     jsonb;
  v_pin_status   text;
  v_loc          record;
  v_vendor       record;
  v_product      record;
  v_service      numeric(10,2);
  v_capacity     int;
  v_leg          jsonb;
  v_item         jsonb;
  v_pack         jsonb;
  v_pack_item    jsonb;
  v_prepared     jsonb := '[]'::jsonb;
  v_items_out    jsonb;
  v_packs_out    jsonb;
  v_pack_items   jsonb;
  v_vendor_seen  uuid[] := '{}';
  v_qty          int;
  v_spoons       int;
  v_leg_packs    int;
  v_leg_fee      numeric(10,2);
  v_leg_sub      numeric(10,2);
  v_leg_pack_fee numeric(10,2);
  v_fee_total    numeric(10,2) := 0;
  v_total        numeric(10,2);
  v_balance      numeric;
  v_new_balance  numeric;
  v_group_id     uuid;
  v_order_id     uuid;
  v_order_ids    uuid[] := '{}';
  v_idx          int;
  v_details      text := nullif(trim(coalesce(p_location_details, '')), '');
  v_note         text := nullif(trim(coalesce(p_student_note, '')), '');
  v_result       jsonb;
begin
  if v_student is null then raise exception 'Unauthorized'; end if;
  if p_idempotency_key is null then raise exception 'IDEMPOTENCY_KEY_REQUIRED'; end if;

  -- Serialise concurrent retries of the same key.
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));

  select result into v_existing
    from public.order_payment_attempts
   where idempotency_key = p_idempotency_key and student_id = v_student;
  if found then
    return v_existing || jsonb_build_object('replayed', true);
  end if;
  if exists (select 1 from public.order_payment_attempts
              where idempotency_key = p_idempotency_key) then
    raise exception 'IDEMPOTENCY_KEY_IN_USE';
  end if;

  -- PIN (returned, not raised — see header comment).
  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status <> 'ok' then
    return jsonb_build_object('error', case v_pin_status
      when 'locked'  then 'PIN_LOCKED'
      when 'not_set' then 'PIN_NOT_SET'
      else 'INVALID_PIN' end);
  end if;

  -- ── Validate + compute everything (no writes yet) ──────────────────
  if p_legs is null or jsonb_typeof(p_legs) <> 'array'
     or jsonb_array_length(p_legs) = 0 then
    raise exception 'EMPTY_ORDER';
  end if;
  if jsonb_array_length(p_legs) > 10 then
    raise exception 'TOO_MANY_VENDORS';
  end if;
  if v_details is null then raise exception 'LOCATION_DETAILS_REQUIRED'; end if;
  if char_length(v_details) > 300 or char_length(coalesce(v_note, '')) > 500 then
    raise exception 'TEXT_TOO_LONG';
  end if;

  select id, name, price into v_loc
    from public.delivery_locations
   where id = p_delivery_location_id and is_active = true;
  if not found then raise exception 'LOCATION_NOT_FOUND'; end if;

  v_service := public._service_charge();

  select coalesce((select value::numeric::int from public.delivery_settings
                    where key = 'pack_meal_capacity'), 8)
    into v_capacity;

  for v_leg in select * from jsonb_array_elements(p_legs)
  loop
    select id, name, pack_price,
           (is_featured and badge_label = 'Major') as is_uniflex
      into v_vendor
      from public.vendors
     where id = (v_leg ->> 'vendor_id')::uuid
       and is_active = true and deleted_at is null;
    if not found then raise exception 'VENDOR_NOT_FOUND'; end if;
    if v_vendor.id = any (v_vendor_seen) then raise exception 'DUPLICATE_VENDOR'; end if;
    v_vendor_seen := v_vendor_seen || v_vendor.id;

    -- Items: price comes from the products table, never from the client.
    v_items_out := '[]'::jsonb;
    v_leg_sub   := 0;
    if coalesce(jsonb_typeof(v_leg -> 'items'), '') <> 'array'
       or jsonb_array_length(v_leg -> 'items') = 0 then
      raise exception 'EMPTY_ORDER';
    end if;
    for v_item in select * from jsonb_array_elements(v_leg -> 'items')
    loop
      v_qty := (v_item ->> 'quantity')::int;
      if v_qty is null or v_qty < 1 or v_qty > 99 then
        raise exception 'INVALID_QUANTITY';
      end if;
      select id, name, base_price, is_available, deleted_at
        into v_product
        from public.products
       where id = (v_item ->> 'product_id')::uuid
         and vendor_id = v_vendor.id;
      if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
      if not v_product.is_available or v_product.deleted_at is not null then
        raise exception 'PRODUCT_UNAVAILABLE';
      end if;
      v_leg_sub := v_leg_sub + v_product.base_price * v_qty;
      v_items_out := v_items_out || jsonb_build_object(
        'product_id', v_product.id, 'product_name', v_product.name,
        'quantity', v_qty, 'unit_price', v_product.base_price);
    end loop;

    -- Packs: contents must be this vendor's products that are in the
    -- order, never more of a product than was ordered, and within the
    -- meal-spoon capacity.
    v_packs_out := '[]'::jsonb;
    v_leg_packs := 0;
    for v_pack in select * from jsonb_array_elements(
                    coalesce(v_leg -> 'packs', '[]'::jsonb))
    loop
      v_pack_items := '[]'::jsonb;
      v_spoons := 0;
      for v_pack_item in select * from jsonb_array_elements(
                           coalesce(v_pack -> 'items', '[]'::jsonb))
      loop
        v_qty := (v_pack_item ->> 'quantity')::int;
        if v_qty is null or v_qty < 1 or v_qty > 99 then
          raise exception 'INVALID_QUANTITY';
        end if;
        select id, name, section, food_subsection into v_product
          from public.products
         where id = (v_pack_item ->> 'product_id')::uuid
           and vendor_id = v_vendor.id;
        if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
        if v_product.section = 'food' and v_product.food_subsection = 'meal' then
          v_spoons := v_spoons + v_qty;
        end if;
        v_pack_items := v_pack_items || jsonb_build_object(
          'product_id', v_product.id, 'product_name', v_product.name,
          'quantity', v_qty);
      end loop;
      if v_spoons > v_capacity then raise exception 'PACK_OVER_CAPACITY'; end if;
      v_packs_out := v_packs_out || jsonb_build_object('items', v_pack_items);
      v_leg_packs := v_leg_packs + 1;
    end loop;

    -- No product may appear in packs more often than it was ordered.
    if exists (
      select 1
        from (select (pit ->> 'product_id') as pid, sum((pit ->> 'quantity')::int) as q
                from jsonb_array_elements(v_packs_out) pk,
                     jsonb_array_elements(pk -> 'items') pit
               group by 1) packed
        left join (select (it ->> 'product_id') as pid, sum((it ->> 'quantity')::int) as q
                     from jsonb_array_elements(v_items_out) it
                    group by 1) ordered using (pid)
       where packed.q > coalesce(ordered.q, 0)
    ) then
      raise exception 'PACK_MISMATCH';
    end if;

    v_leg_pack_fee := v_leg_packs * coalesce(v_vendor.pack_price, 0);
    v_leg_fee      := v_loc.price * public._pack_brackets(v_leg_packs);
    v_fee_total    := v_fee_total + v_leg_fee;

    v_prepared := v_prepared || jsonb_build_object(
      'vendor_id',     v_vendor.id,
      'source',        case when v_vendor.is_uniflex then 'uniflex' else 'partner' end,
      'items',         v_items_out,
      'packs',         v_packs_out,
      'pack_count',    v_leg_packs,
      'pack_fee',      v_leg_pack_fee,
      'subtotal',      v_leg_sub,
      'delivery_fee',  v_leg_fee);
  end loop;

  v_total := v_fee_total + v_service;

  -- ── Wallet ─────────────────────────────────────────────────────────
  select balance into v_balance from public.wallets
   where user_id = v_student for update;
  if not found then raise exception 'WALLET_NOT_FOUND'; end if;
  if v_balance < v_total then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.wallets set balance = balance - v_total
   where user_id = v_student returning balance into v_new_balance;

  insert into public.wallet_transactions
    (user_id, type, amount, source, balance_after)
  values
    (v_student, 'debit', v_total, 'commitment_fee', v_new_balance);

  -- ── Create the group (already paid → enters the rider pool) ────────
  insert into public.delivery_groups
    (student_id, delivery_type, delivery_location, student_note,
     commitment_fee_total, service_charge, status,
     delivery_location_id, location_details)
  values
    (v_student, 'delivery', v_loc.name, v_note,
     v_fee_total, v_service, 'commitment_paid',
     v_loc.id, v_details)
  returning id into v_group_id;

  for v_leg in select * from jsonb_array_elements(v_prepared)
  loop
    insert into public.orders
      (student_id, vendor_id, source, type, status, delivery_type,
       delivery_location, total_amount, estimated_time,
       pack_count, pack_fee, notes, delivery_group_id,
       commitment_fee_paid, commitment_fee_amount,
       delivery_location_id, location_details)
    values
      (v_student,
       (v_leg ->> 'vendor_id')::uuid,
       v_leg ->> 'source',
       'food', 'placed', 'delivery',
       v_loc.name,
       (v_leg ->> 'subtotal')::numeric + (v_leg ->> 'pack_fee')::numeric,
       '20–30 min',
       (v_leg ->> 'pack_count')::int,
       (v_leg ->> 'pack_fee')::numeric,
       v_note,
       v_group_id,
       true, (v_leg ->> 'delivery_fee')::numeric,
       v_loc.id, v_details)
    returning id into v_order_id;
    v_order_ids := v_order_ids || v_order_id;

    for v_item in select * from jsonb_array_elements(v_leg -> 'items')
    loop
      insert into public.order_items
        (order_id, product_id, product_name, quantity, unit_price, selected_options)
      values
        (v_order_id, (v_item ->> 'product_id')::uuid, v_item ->> 'product_name',
         (v_item ->> 'quantity')::int, (v_item ->> 'unit_price')::numeric,
         '[]'::jsonb);
    end loop;

    v_idx := 0;
    for v_pack in select * from jsonb_array_elements(v_leg -> 'packs')
    loop
      insert into public.order_packs (order_id, pack_index, items)
      values (v_order_id, v_idx, v_pack -> 'items');
      v_idx := v_idx + 1;
    end loop;
  end loop;

  v_result := jsonb_build_object(
    'kind',               'delivery',
    'order_id',           v_group_id,
    'group_id',           v_group_id,
    'order_ids',          to_jsonb(v_order_ids),
    'delivery_fee_total', v_fee_total,
    'service_charge',     v_service,
    'total_charged',      v_total,
    'balance_after',      v_new_balance);

  insert into public.order_payment_attempts (idempotency_key, student_id, kind, result)
  values (p_idempotency_key, v_student, 'delivery', v_result);

  return v_result;
end;
$$;

grant execute on function public.create_paid_delivery_order(
  uuid, text, jsonb, uuid, text, text) to authenticated;


-- ── 4b. Pickup (Uniflex-only cart; full food amount, no fees) ────────
create or replace function public.create_paid_pickup_order(
  p_idempotency_key uuid,
  p_pin             text,
  p_vendor_id       uuid,
  p_items           jsonb,
  p_packs           jsonb default '[]'::jsonb,
  p_scheduled_for   timestamptz default null,
  p_notes           text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_student      uuid := auth.uid();
  v_existing     jsonb;
  v_pin_status   text;
  v_vendor       record;
  v_product      record;
  v_capacity     int;
  v_item         jsonb;
  v_pack         jsonb;
  v_pack_item    jsonb;
  v_items_out    jsonb := '[]'::jsonb;
  v_packs_out    jsonb := '[]'::jsonb;
  v_pack_items   jsonb;
  v_qty          int;
  v_spoons       int;
  v_subtotal     numeric(10,2) := 0;
  v_pack_count   int := 0;
  v_pack_fee     numeric(10,2);
  v_total        numeric(10,2);
  v_balance      numeric;
  v_new_balance  numeric;
  v_order_id     uuid;
  v_idx          int := 0;
  v_note         text := nullif(trim(coalesce(p_notes, '')), '');
  v_plan_id      uuid;
  v_plan_period  text;
  v_plan_budget  numeric;
  v_plan_spent   numeric;
  v_period_start timestamptz;
  v_period_end   timestamptz;
  v_new_spent    numeric;
  v_plan_over    boolean := false;
  v_result       jsonb;
begin
  if v_student is null then raise exception 'Unauthorized'; end if;
  if p_idempotency_key is null then raise exception 'IDEMPOTENCY_KEY_REQUIRED'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));

  select result into v_existing
    from public.order_payment_attempts
   where idempotency_key = p_idempotency_key and student_id = v_student;
  if found then
    return v_existing || jsonb_build_object('replayed', true);
  end if;
  if exists (select 1 from public.order_payment_attempts
              where idempotency_key = p_idempotency_key) then
    raise exception 'IDEMPOTENCY_KEY_IN_USE';
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
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'EMPTY_ORDER';
  end if;
  if char_length(coalesce(v_note, '')) > 500 then raise exception 'TEXT_TOO_LONG'; end if;

  select id, pack_price, (is_featured and badge_label = 'Major') as is_uniflex
    into v_vendor
    from public.vendors
   where id = p_vendor_id and is_active = true and deleted_at is null;
  if not found then raise exception 'VENDOR_NOT_FOUND'; end if;
  if not v_vendor.is_uniflex then raise exception 'PICKUP_UNIFLEX_ONLY'; end if;

  select coalesce((select value::numeric::int from public.delivery_settings
                    where key = 'pack_meal_capacity'), 8)
    into v_capacity;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item ->> 'quantity')::int;
    if v_qty is null or v_qty < 1 or v_qty > 99 then
      raise exception 'INVALID_QUANTITY';
    end if;
    select id, name, base_price, is_available, deleted_at into v_product
      from public.products
     where id = (v_item ->> 'product_id')::uuid and vendor_id = v_vendor.id;
    if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
    if not v_product.is_available or v_product.deleted_at is not null then
      raise exception 'PRODUCT_UNAVAILABLE';
    end if;
    v_subtotal := v_subtotal + v_product.base_price * v_qty;
    v_items_out := v_items_out || jsonb_build_object(
      'product_id', v_product.id, 'product_name', v_product.name,
      'quantity', v_qty, 'unit_price', v_product.base_price);
  end loop;

  for v_pack in select * from jsonb_array_elements(
                  coalesce(p_packs, '[]'::jsonb))
  loop
    v_pack_items := '[]'::jsonb;
    v_spoons := 0;
    for v_pack_item in select * from jsonb_array_elements(
                         coalesce(v_pack -> 'items', '[]'::jsonb))
    loop
      v_qty := (v_pack_item ->> 'quantity')::int;
      if v_qty is null or v_qty < 1 or v_qty > 99 then
        raise exception 'INVALID_QUANTITY';
      end if;
      select id, name, section, food_subsection into v_product
        from public.products
       where id = (v_pack_item ->> 'product_id')::uuid and vendor_id = v_vendor.id;
      if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
      if v_product.section = 'food' and v_product.food_subsection = 'meal' then
        v_spoons := v_spoons + v_qty;
      end if;
      v_pack_items := v_pack_items || jsonb_build_object(
        'product_id', v_product.id, 'product_name', v_product.name,
        'quantity', v_qty);
    end loop;
    if v_spoons > v_capacity then raise exception 'PACK_OVER_CAPACITY'; end if;
    v_packs_out := v_packs_out || jsonb_build_object('items', v_pack_items);
    v_pack_count := v_pack_count + 1;
  end loop;

  if exists (
    select 1
      from (select (pit ->> 'product_id') as pid, sum((pit ->> 'quantity')::int) as q
              from jsonb_array_elements(v_packs_out) pk,
                   jsonb_array_elements(pk -> 'items') pit
             group by 1) packed
      left join (select (it ->> 'product_id') as pid, sum((it ->> 'quantity')::int) as q
                   from jsonb_array_elements(v_items_out) it
                  group by 1) ordered using (pid)
     where packed.q > coalesce(ordered.q, 0)
  ) then
    raise exception 'PACK_MISMATCH';
  end if;

  v_pack_fee := v_pack_count * coalesce(v_vendor.pack_price, 0);
  v_total    := v_subtotal + v_pack_fee;     -- pickup: no delivery fee, no service charge

  select balance into v_balance from public.wallets
   where user_id = v_student for update;
  if not found then raise exception 'WALLET_NOT_FOUND'; end if;
  if v_balance < v_total then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.wallets set balance = balance - v_total
   where user_id = v_student returning balance into v_new_balance;

  insert into public.orders
    (student_id, vendor_id, source, type, status, delivery_type,
     total_amount, estimated_time, scheduled_for,
     pack_count, pack_fee, notes)
  values
    (v_student, v_vendor.id, 'uniflex', 'food', 'placed', 'pickup',
     v_total,
     case when p_scheduled_for is not null then 'Scheduled' else '20–30 min' end,
     p_scheduled_for, v_pack_count, v_pack_fee, v_note)
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(v_items_out)
  loop
    insert into public.order_items
      (order_id, product_id, product_name, quantity, unit_price, selected_options)
    values
      (v_order_id, (v_item ->> 'product_id')::uuid, v_item ->> 'product_name',
       (v_item ->> 'quantity')::int, (v_item ->> 'unit_price')::numeric,
       '[]'::jsonb);
  end loop;

  for v_pack in select * from jsonb_array_elements(v_packs_out)
  loop
    insert into public.order_packs (order_id, pack_index, items)
    values (v_order_id, v_idx, v_pack -> 'items');
    v_idx := v_idx + 1;
  end loop;

  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_student, 'debit', v_total, 'order_payment', v_order_id, v_new_balance);

  -- Saving plan (lazy period reset) — unchanged behaviour.
  select id, period, budget, spent, period_start
    into v_plan_id, v_plan_period, v_plan_budget, v_plan_spent, v_period_start
    from public.saving_plans
   where user_id = v_student and is_active
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

  v_result := jsonb_build_object(
    'kind',             'pickup',
    'order_id',         v_order_id,
    'service_charge',   0,
    'total_charged',    v_total,
    'balance_after',    v_new_balance,
    'plan_over_budget', v_plan_over);

  insert into public.order_payment_attempts (idempotency_key, student_id, kind, result)
  values (p_idempotency_key, v_student, 'pickup', v_result);

  return v_result;
end;
$$;

grant execute on function public.create_paid_pickup_order(
  uuid, text, uuid, jsonb, jsonb, timestamptz, text) to authenticated;


-- ── 4c. Errand (flat fee from the category + service charge) ─────────
create or replace function public.create_paid_errand(
  p_idempotency_key      uuid,
  p_pin                  text,
  p_category             text,
  p_pickup_location      text,
  p_dropoff_location     text,
  p_item_description     text,
  p_delivery_location_id uuid default null,
  p_location_details     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_student      uuid := auth.uid();
  v_existing     jsonb;
  v_pin_status   text;
  v_cat          record;
  v_service      numeric(10,2);
  v_total        numeric(10,2);
  v_balance      numeric;
  v_new_balance  numeric;
  v_order_id     uuid;
  v_loc_id       uuid;
  v_pickup       text := coalesce(trim(p_pickup_location), '');
  v_dropoff      text := coalesce(trim(p_dropoff_location), '');
  v_desc         text := trim(coalesce(p_item_description, ''));
  v_details      text := nullif(trim(coalesce(p_location_details, '')), '');
  v_result       jsonb;
begin
  if v_student is null then raise exception 'Unauthorized'; end if;
  if p_idempotency_key is null then raise exception 'IDEMPOTENCY_KEY_REQUIRED'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));

  select result into v_existing
    from public.order_payment_attempts
   where idempotency_key = p_idempotency_key and student_id = v_student;
  if found then
    return v_existing || jsonb_build_object('replayed', true);
  end if;
  if exists (select 1 from public.order_payment_attempts
              where idempotency_key = p_idempotency_key) then
    raise exception 'IDEMPOTENCY_KEY_IN_USE';
  end if;

  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status <> 'ok' then
    return jsonb_build_object('error', case v_pin_status
      when 'locked'  then 'PIN_LOCKED'
      when 'not_set' then 'PIN_NOT_SET'
      else 'INVALID_PIN' end);
  end if;

  if v_desc = '' then raise exception 'DESCRIPTION_REQUIRED'; end if;
  if char_length(v_desc) > 1000 or char_length(v_pickup) > 300
     or char_length(v_dropoff) > 300 or char_length(coalesce(v_details, '')) > 300 then
    raise exception 'TEXT_TOO_LONG';
  end if;

  -- The fee is read from the category row — never from the client.
  select key, flat_fee into v_cat
    from public.errand_categories
   where key = p_category and is_active = true and deleted_at is null;
  if not found then raise exception 'CATEGORY_NOT_FOUND'; end if;

  if p_delivery_location_id is not null then
    select id into v_loc_id from public.delivery_locations
     where id = p_delivery_location_id and is_active = true;
    if not found then raise exception 'LOCATION_NOT_FOUND'; end if;
  end if;

  v_service := public._service_charge();
  v_total   := v_cat.flat_fee + v_service;

  select balance into v_balance from public.wallets
   where user_id = v_student for update;
  if not found then raise exception 'WALLET_NOT_FOUND'; end if;
  if v_balance < v_total then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.wallets set balance = balance - v_total
   where user_id = v_student returning balance into v_new_balance;

  insert into public.orders
    (student_id, source, type, status, delivery_type,
     total_amount, estimated_time,
     commitment_fee_paid, commitment_fee_amount, service_charge,
     delivery_location_id, location_details)
  values
    (v_student, 'uniflex', 'errand', 'placed', 'delivery',
     v_cat.flat_fee, '15–25 min',
     true, v_cat.flat_fee, v_service,
     v_loc_id, v_details)
  returning id into v_order_id;

  insert into public.errand_requests
    (order_id, category, pickup_location, dropoff_location, item_description)
  values
    (v_order_id, v_cat.key, v_pickup, v_dropoff, v_desc);

  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_student, 'debit', v_total, 'order_payment', v_order_id, v_new_balance);

  v_result := jsonb_build_object(
    'kind',           'errand',
    'order_id',       v_order_id,
    'errand_fee',     v_cat.flat_fee,
    'service_charge', v_service,
    'total_charged',  v_total,
    'balance_after',  v_new_balance);

  insert into public.order_payment_attempts (idempotency_key, student_id, kind, result)
  values (p_idempotency_key, v_student, 'errand', v_result);

  return v_result;
end;
$$;

grant execute on function public.create_paid_errand(
  uuid, text, text, text, text, text, uuid, text) to authenticated;


-- ---------------------------------------------------------------------
-- 5. ONE notification pipeline
--
--   event (DB trigger) → queue_notification() → INSERT into notifications
--   INSERT into notifications (DB trigger) → push-notification Edge Fn → FCM
--
-- The inbox row and the push therefore always come from the same place,
-- whether the app is open, backgrounded or closed.
-- ---------------------------------------------------------------------

-- Defensive: phase10 created this table; keep the pack runnable without it.
create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  title      text not null,
  body       text not null,
  kind       text not null default 'message'
               check (kind in ('order_status', 'message')),
  order_id   uuid references public.orders (id) on delete set null,
  sent_by    uuid references public.profiles (id) on delete set null,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);

alter table public.notifications add column if not exists type text;
alter table public.notifications
  add column if not exists group_id uuid
    references public.delivery_groups (id) on delete set null;
alter table public.notifications
  add column if not exists conversation_id uuid
    references public.support_conversations (id) on delete set null;

create index if not exists notifications_unread_idx
  on public.notifications (user_id) where read_at is null;

alter table public.notifications enable row level security;
drop policy if exists "notifications: read own" on public.notifications;
create policy "notifications: read own"
  on public.notifications for select to authenticated
  using (user_id = auth.uid());

-- Internal: nobody but triggers/RPCs may call this.
create or replace function public.queue_notification(
  p_user_id         uuid,
  p_title           text,
  p_body            text,
  p_type            text,
  p_order_id        uuid default null,
  p_group_id        uuid default null,
  p_conversation_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if p_user_id is null then return null; end if;
  insert into public.notifications
    (user_id, title, body, kind, type, order_id, group_id, conversation_id)
  values
    (p_user_id, p_title, p_body,
     case when p_type = 'support' then 'message' else 'order_status' end,
     p_type, p_order_id, p_group_id, p_conversation_id)
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.queue_notification(
  uuid, text, text, text, uuid, uuid, uuid) from public, anon, authenticated;

-- Read / unread RPCs (re-created so they exist with the right shape).
create or replace function public.mark_notification_read(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.notifications
     set read_at = coalesce(read_at, now())
   where id = p_id and user_id = auth.uid();
end;
$$;
grant execute on function public.mark_notification_read(uuid) to authenticated;

create or replace function public.mark_all_notifications_read()
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.notifications
     set read_at = now()
   where user_id = auth.uid() and read_at is null;
end;
$$;
grant execute on function public.mark_all_notifications_read() to authenticated;

create or replace function public.unread_notification_count()
returns int language sql security definer set search_path = public stable as $$
  select count(*)::int from public.notifications
   where user_id = auth.uid() and read_at is null;
$$;
grant execute on function public.unread_notification_count() to authenticated;

-- ── 5a. Group (delivery) events ─────────────────────────────────────
create or replace function public._notify_group_events()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_did boolean;
begin
  if not new.is_paid then return new; end if;

  -- Rider accepted.
  if new.status = 'rider_accepted' and old.status is distinct from 'rider_accepted' then
    perform public.queue_notification(
      new.student_id, 'Rider accepted',
      'A rider has accepted your order.', 'rider_accepted',
      null, new.id);
  end if;

  -- Final price sent — and again every time the rider changes it.
  if new.status = 'awaiting_final_payment'
     and new.final_amount is not null
     and (old.status is distinct from 'awaiting_final_payment'
          or old.final_amount is distinct from new.final_amount) then
    perform public.queue_notification(
      new.student_id, 'Pay for your order',
      'Pay for your order: ₦' || trim(to_char(new.final_amount, 'FM999,999,990'))
        || '. Tap to pay.',
      'final_price', null, new.id);
  end if;

  -- Student paid the final price → tell the rider.
  if new.status = 'out_for_delivery' and old.status = 'awaiting_final_payment'
     and new.rider_id is not null then
    perform public.queue_notification(
      new.rider_id, 'Customer has paid',
      'Customer has paid. You can deliver.', 'customer_paid',
      null, new.id);
  end if;

  -- Cancelled.
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    v_student_did := coalesce(new.cancelled_by_student, false)
                     or auth.uid() = new.student_id;
    if v_student_did then
      if new.rider_id is not null then
        perform public.queue_notification(
          new.rider_id, 'Order cancelled',
          'Order cancelled by customer.', 'cancelled_by_customer',
          null, new.id);
      end if;
    else
      perform public.queue_notification(
        new.student_id, 'Order cancelled',
        'Your order was cancelled.', 'cancelled_by_admin',
        null, new.id);
      if new.rider_id is not null then
        perform public.queue_notification(
          new.rider_id, 'Order cancelled',
          'Your order was cancelled.', 'cancelled_by_admin',
          null, new.id);
      end if;
    end if;
  end if;

  -- Delivered.
  if new.status = 'completed' and old.status is distinct from 'completed' then
    perform public.queue_notification(
      new.student_id, 'Order delivered',
      'Your order has been delivered.', 'delivered',
      null, new.id);
  end if;

  return new;
end;
$$;

drop trigger if exists delivery_groups_notify on public.delivery_groups;
create trigger delivery_groups_notify
  after update on public.delivery_groups
  for each row execute function public._notify_group_events();

-- ── 5b. Standalone-order events (errands + pickup) ──────────────────
-- Delivery-group legs are skipped: the group row notifies once.
create or replace function public._notify_order_events()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_did boolean;
begin
  if new.delivery_group_id is not null or not new.is_paid then
    return new;
  end if;

  -- Errand accepted by a rider.
  if new.type = 'errand' and old.rider_id is null and new.rider_id is not null then
    perform public.queue_notification(
      new.student_id, 'Rider accepted',
      'A rider has accepted your order.', 'rider_accepted',
      new.id, null);
  end if;

  -- Student paid a final amount on a standalone order → tell the rider.
  if coalesce(old.final_payment_paid, false) = false
     and coalesce(new.final_payment_paid, false) = true
     and new.rider_id is not null then
    perform public.queue_notification(
      new.rider_id, 'Customer has paid',
      'Customer has paid. You can deliver.', 'customer_paid',
      new.id, null);
  end if;

  -- Cancelled.
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    v_student_did := auth.uid() = new.student_id;
    if v_student_did then
      if new.rider_id is not null then
        perform public.queue_notification(
          new.rider_id, 'Order cancelled',
          'Order cancelled by customer.', 'cancelled_by_customer',
          new.id, null);
      end if;
    else
      perform public.queue_notification(
        new.student_id, 'Order cancelled',
        'Your order was cancelled.', 'cancelled_by_admin',
        new.id, null);
      if new.rider_id is not null then
        perform public.queue_notification(
          new.rider_id, 'Order cancelled',
          'Your order was cancelled.', 'cancelled_by_admin',
          new.id, null);
      end if;
    end if;
  end if;

  -- Delivered / errand completed.
  if new.status = 'completed' and old.status is distinct from 'completed'
     and coalesce(new.delivery_type, '') <> 'pickup' then
    perform public.queue_notification(
      new.student_id, 'Order delivered',
      'Your order has been delivered.', 'delivered',
      new.id, null);
  end if;

  -- Pickup order ready.
  if new.status = 'ready_for_pickup' and old.status is distinct from 'ready_for_pickup' then
    perform public.queue_notification(
      new.student_id, 'Ready for pickup',
      'Your order is ready for pickup.', 'ready_for_pickup',
      new.id, null);
  end if;

  return new;
end;
$$;

drop trigger if exists orders_notify on public.orders;
create trigger orders_notify
  after update on public.orders
  for each row execute function public._notify_order_events();

-- ── 5c. Push: every inbox row is pushed by the Edge Function ────────
-- Uses the same two database settings the support-chat trigger already
-- relied on (alter database postgres set app.supabase_project_url / _service_role_key).
-- If they are missing the row is still stored; only the push is skipped.
create or replace function public._trigger_push_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_key text;
begin
  -- Preferred: Supabase Vault (secrets named push_project_url / push_secret_key).
  begin
    select decrypted_secret into v_url
      from vault.decrypted_secrets where name = 'push_project_url' limit 1;
    select decrypted_secret into v_key
      from vault.decrypted_secrets where name = 'push_secret_key' limit 1;
  exception when others then
    v_url := null;
    v_key := null;
  end;
  -- Fallback: the old database settings (hosted Supabase no longer lets
  -- you set these, but self-hosted / older projects may still have them).
  if v_url is null or v_url = '' or v_key is null or v_key = '' then
    begin
      v_url := current_setting('app.supabase_project_url', true);
      v_key := current_setting('app.supabase_service_role_key', true);
    exception when others then
      return new;
    end;
  end if;
  if v_url is null or v_url = '' or v_key is null or v_key = '' then
    return new;
  end if;

  perform net.http_post(
    url     := v_url || '/functions/v1/push-notification',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_key),
    body    := jsonb_build_object(
      'notification_id', new.id,
      'user_id',         new.user_id,
      'title',           new.title,
      'body',            new.body,
      'type',            new.type,
      'order_id',        new.order_id,
      'group_id',        new.group_id,
      'conversation_id', new.conversation_id));
  return new;
exception when others then
  -- pg_net missing / any failure: never block the insert.
  return new;
end;
$$;

drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push
  after insert on public.notifications
  for each row execute function public._trigger_push_notification();

-- Make sure the inbox streams live.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public'
       and tablename = 'notifications') then
    execute 'alter publication supabase_realtime add table public.notifications';
  end if;
end $$;


-- ---------------------------------------------------------------------
-- 6. Support chat — drop every old overload, create exactly one
--
-- Root cause of "direct message / admin reply fail": support_chat.sql
-- created send_support_message(text, uuid, uuid) and fix_pack_1.sql then
-- created send_support_message(text, uuid, uuid, uuid) — a SECOND
-- function, because the parameter list changed. A call that omits
-- p_group_id (direct student message, admin reply, order-only message)
-- matches BOTH, so PostgREST answers "could not choose the best
-- candidate function" and nothing is sent. Only calls that pass
-- p_group_id matched a single overload, which is why a group-attached
-- message "went through" (and then showed no chip, because the bubble
-- ignored delivery_group_id).
-- ---------------------------------------------------------------------
select public._pack4a_drop_overloads(array[
  'send_support_message',
  'mark_support_read',
  'resolve_support_conversation',
  'get_support_unread_total'
]);

create or replace function public.send_support_message(
  p_body            text,
  p_order_id        uuid default null,
  p_group_id        uuid default null,
  p_conversation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_caller_id   uuid := auth.uid();
  v_conv_id     uuid;
  v_sender_role text;
  v_sender_name text;
  v_msg_id      uuid;
  v_msg_count   int;
begin
  if v_caller_id is null then raise exception 'Unauthorized'; end if;

  p_body := trim(coalesce(p_body, ''));
  if char_length(p_body) = 0 then raise exception 'Message body cannot be empty'; end if;
  if char_length(p_body) > 2000 then raise exception 'Message too long (2000 characters max)'; end if;
  if p_order_id is not null and p_group_id is not null then
    raise exception 'Provide either p_order_id or p_group_id, not both';
  end if;

  select count(*) into v_msg_count
    from public.support_messages
   where sender_id = v_caller_id and created_at > now() - interval '1 minute';
  if v_msg_count >= 20 then raise exception 'RATE_LIMITED'; end if;

  if public.is_admin() then
    -- ── Admin reply ────────────────────────────────────────────────
    if p_conversation_id is null then
      raise exception 'p_conversation_id is required for admin messages';
    end if;
    if not exists (select 1 from public.support_conversations
                    where id = p_conversation_id) then
      raise exception 'Conversation not found';
    end if;
    v_conv_id     := p_conversation_id;
    v_sender_role := 'admin';
    select coalesce(nickname, full_name, 'Admin') into v_sender_name
      from public.profiles where id = v_caller_id;
  else
    -- ── Student (direct or with an order / group attached) ─────────
    -- Race-safe find-or-create (unique student_id).
    insert into public.support_conversations (student_id)
    values (v_caller_id)
    on conflict (student_id) do update set student_id = excluded.student_id
    returning id into v_conv_id;

    v_sender_role := 'student';
    select coalesce(nickname, full_name, 'Student') into v_sender_name
      from public.profiles where id = v_caller_id;

    if p_order_id is not null and not exists (
         select 1 from public.orders
          where id = p_order_id and student_id = v_caller_id) then
      raise exception 'Order not found or does not belong to you';
    end if;
    if p_group_id is not null and not exists (
         select 1 from public.delivery_groups
          where id = p_group_id and student_id = v_caller_id) then
      raise exception 'Delivery group not found or does not belong to you';
    end if;

    update public.support_conversations
       set status = 'open', resolved_at = null, resolved_by = null
     where id = v_conv_id and status = 'resolved';
  end if;

  insert into public.support_messages
    (conversation_id, sender_id, sender_role, sender_name, body,
     order_id, delivery_group_id)
  values
    (v_conv_id, v_caller_id, v_sender_role, v_sender_name, p_body,
     p_order_id, p_group_id)
  returning id into v_msg_id;

  update public.support_conversations
     set last_message_at      = now(),
         last_message_preview = left(p_body, 100),
         admin_unread_count   = case when v_sender_role = 'student'
                                     then admin_unread_count + 1
                                     else admin_unread_count end,
         student_unread_count = case when v_sender_role = 'admin'
                                     then student_unread_count + 1
                                     else student_unread_count end
   where id = v_conv_id;

  return jsonb_build_object('message_id', v_msg_id, 'conversation_id', v_conv_id);
end;
$$;

grant execute on function public.send_support_message(text, uuid, uuid, uuid)
  to authenticated;

create or replace function public.mark_support_read(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_caller_id uuid := auth.uid();
begin
  if v_caller_id is null then raise exception 'Unauthorized'; end if;

  if public.is_admin() then
    update public.support_conversations
       set admin_unread_count = 0
     where id = p_conversation_id;
  else
    update public.support_conversations
       set student_unread_count = 0
     where id = p_conversation_id and student_id = v_caller_id;
  end if;

  -- Opening the chat also clears the matching inbox rows.
  update public.notifications
     set read_at = now()
   where user_id = v_caller_id
     and type = 'support'
     and conversation_id = p_conversation_id
     and read_at is null;
end;
$$;

grant execute on function public.mark_support_read(uuid) to authenticated;

create or replace function public.resolve_support_conversation(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Unauthorized'; end if;

  update public.support_conversations
     set status = 'resolved', resolved_at = now(), resolved_by = auth.uid()
   where id = p_conversation_id;
  if not found then raise exception 'Conversation not found'; end if;
end;
$$;

grant execute on function public.resolve_support_conversation(uuid) to authenticated;

create or replace function public.get_support_unread_total()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
  v_count     int;
begin
  if v_caller_id is null then return 0; end if;
  if public.is_admin() then
    select coalesce(sum(admin_unread_count)::int, 0) into v_count
      from public.support_conversations;
  else
    select coalesce(student_unread_count, 0) into v_count
      from public.support_conversations where student_id = v_caller_id;
    if not found then v_count := 0; end if;
  end if;
  return v_count;
end;
$$;

grant execute on function public.get_support_unread_total() to authenticated;

-- Chat notifications now go through the same pipeline: the trigger
-- writes inbox rows; notifications_push (above) sends the push.
-- (support-notify is no longer called — see the owner checklist.)
create or replace function public._trigger_support_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid;
  v_admin   record;
  v_title   text;
  v_preview text := left(new.body, 100);
begin
  if new.sender_role = 'student' then
    for v_admin in
      select id from public.profiles where role = 'admin' and is_active
    loop
      perform public.queue_notification(
        v_admin.id, new.sender_name, v_preview, 'support',
        null, null, new.conversation_id);
    end loop;
  else
    select student_id into v_student
      from public.support_conversations where id = new.conversation_id;
    v_title := 'Uniflex Support (' || split_part(new.sender_name, ' ', 1) || ')';
    perform public.queue_notification(
      v_student, v_title, v_preview, 'support',
      null, null, new.conversation_id);
  end if;
  return new;
exception when others then
  -- A notification problem must never block a chat message.
  return new;
end;
$$;

drop trigger if exists on_support_message_insert on public.support_messages;
create trigger on_support_message_insert
  after insert on public.support_messages
  for each row execute function public._trigger_support_notify();


-- ---------------------------------------------------------------------
-- 7. Dashboard stats: ignore never-paid orders
-- ---------------------------------------------------------------------
create or replace function public.get_dashboard_stats()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_today_start timestamptz := date_trunc('day', now() at time zone 'utc');
  v_stats       jsonb;
begin
  if not (select public.is_super_admin()) then
    raise exception 'Unauthorized';
  end if;
  select jsonb_build_object(
    'today_orders_total', count(*) filter (where created_at >= v_today_start),
    'today_revenue', coalesce(sum(total_amount) filter (
      where source = 'uniflex' and status not in ('cancelled') and created_at >= v_today_start), 0),
    'pending_count', count(*) filter (
      where source = 'uniflex' and status in ('placed', 'preparing')),
    'by_status', jsonb_build_object(
      'placed',    count(*) filter (where source = 'uniflex' and status = 'placed'),
      'preparing', count(*) filter (where source = 'uniflex' and status = 'preparing'),
      'ready',     count(*) filter (where source = 'uniflex' and status = 'ready'),
      'completed', count(*) filter (where source = 'uniflex' and status = 'completed' and created_at >= v_today_start)))
  into v_stats from public.orders
  where is_paid;
  return v_stats;
end;
$$;
grant execute on function public.get_dashboard_stats() to authenticated;


-- ---------------------------------------------------------------------
-- 8. Tidy up + refresh PostgREST's schema cache so dropped overloads vanish
-- ---------------------------------------------------------------------
drop function if exists public._pack4a_drop_overloads(text[]);

notify pgrst, 'reload schema';


-- =====================================================================
-- NOW UNUSED (kept, nothing dropped except the functions listed in §4):
--   delivery_groups statuses 'placed' (no new row is ever 'placed')
--   orders.commitment_fee_paid on group legs (still set true)
--   delivery_settings keys campus/hostel fee (superseded in Round 8)
--   pay_final_amount / confirm_sourced_items (legacy single-order flow)
--   Edge Functions: support-notify (replaced by push-notification),
--                   notify-user 'order_status' mode (no client calls it)
--   Client: placeMultiVendorOrder / placeFoodOrder / placeErrand* /
--           placePartnerFoodOrder and the old CommitmentFeeScreen modes
-- =====================================================================
