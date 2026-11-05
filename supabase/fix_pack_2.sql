-- =====================================================================
-- Fix Pack 2 — Delivery Flow Overhaul
--
-- Run once in the Supabase SQL editor.
-- All blocks are idempotent — safe to re-run.
--
-- Changes:
--   1.  Add `rider_accepted` status to delivery_groups + two new columns
--   2.  Rider RLS on delivery_groups (pool + assigned)
--   3.  Rider RLS on orders (via accepted delivery group)
--   4.  Replace accept_delivery_group RPC
--   5.  Add set_delivery_group_final_price RPC
--   6.  Replace pay_group_final_amount RPC
--   7.  Add decline_group_final_amount RPC
--   8.  Add cancel_delivery_group_before_accept RPC
--   9.  Add get_group_customer_info RPC
--  10.  Add get_group_items RPC
--  11.  Replace pay_group_commitment_fee (remove source-based branching)
--  12.  Update place_multi_vendor_order (reject scheduled_for on delivery)
--  13.  Update verify_group_delivery (graceful delivery_records INSERT)
--  14.  Ensure delivery_groups is in Realtime publication
--  15.  Comment block: now-unused RPCs / tables
-- =====================================================================


-- ─────────────────────────────────────────────────────────────────────
-- 1. Add `rider_accepted` status + new columns to delivery_groups
--
-- The old constraint only had 6 values. We drop and recreate it to
-- add 'rider_accepted' between 'commitment_paid' and
-- 'awaiting_final_payment'.
-- ─────────────────────────────────────────────────────────────────────

alter table public.delivery_groups
  drop constraint if exists delivery_groups_status_check;

alter table public.delivery_groups
  add constraint delivery_groups_status_check
  check (status in (
    'placed',
    'commitment_paid',
    'rider_accepted',
    'awaiting_final_payment',
    'out_for_delivery',
    'completed',
    'cancelled'
  ));

-- When a rider accepted the group.
alter table public.delivery_groups
  add column if not exists rider_accepted_at timestamptz;

-- True when the student cancelled by declining the final price.
alter table public.delivery_groups
  add column if not exists cancelled_by_student boolean not null default false;


-- ─────────────────────────────────────────────────────────────────────
-- 2. Rider RLS on delivery_groups
--
-- Replace the old `dg_rider_read` and `dg_pool_read` policies with a
-- single combined policy that covers both the pool view and the
-- assigned-group view. Drop old policies by name, then create the new
-- one idempotently.
-- ─────────────────────────────────────────────────────────────────────

-- Remove old policies that this supersedes.
drop policy if exists "dg_rider_read" on public.delivery_groups;
drop policy if exists "dg_pool_read"  on public.delivery_groups;
drop policy if exists "delivery_groups: rider pool and assigned" on public.delivery_groups;

create policy "delivery_groups: rider pool and assigned"
  on public.delivery_groups
  for select
  to authenticated
  using (
    public.is_rider()
    and (
      -- Pool: unassigned commitment_paid groups
      (status = 'commitment_paid' and rider_id is null)
      -- Assigned: any group this rider accepted
      or rider_id = auth.uid()
    )
  );


-- ─────────────────────────────────────────────────────────────────────
-- 3. Rider RLS on orders — via accepted delivery group
--
-- Allow rider to SELECT orders that belong to a delivery group they
-- accepted (rider_id = auth.uid() on the group), or errand orders
-- directly assigned to them (existing policy covers that via
-- "orders: rider read own assigned").
--
-- We add a new policy for group-leg visibility; the existing
-- "orders: rider read own assigned" (rider_id = auth.uid() on the
-- order itself) stays in place for standalone + errand orders.
-- ─────────────────────────────────────────────────────────────────────

drop policy if exists "orders: rider read group legs" on public.orders;

create policy "orders: rider read group legs"
  on public.orders
  for select
  to authenticated
  using (
    public.is_rider()
    and delivery_group_id is not null
    and exists (
      select 1 from public.delivery_groups dg
      where dg.id = orders.delivery_group_id
        and dg.rider_id = auth.uid()
    )
  );


-- ─────────────────────────────────────────────────────────────────────
-- 4. Replace accept_delivery_group
--
-- New behaviour vs old:
--   • Status check: 'commitment_paid' (unchanged)
--   • Transitions group to 'rider_accepted' (was: left in commitment_paid,
--     only set delivery_stage = 'accepted')
--   • Sets rider_accepted_at = now()
--   • Sets rider_id on ALL legs (no source-based special-casing)
--   • Removes per-leg status/delivery_stage changes (group status is
--     canonical; legs stay as-is)
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.accept_delivery_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider_id uuid := auth.uid();
  v_group    public.delivery_groups%rowtype;
begin
  if not public.is_rider() then
    raise exception 'Unauthorized';
  end if;

  select * into v_group from public.delivery_groups
  where id = p_group_id
  for update nowait;

  if not found then
    raise exception 'Group not found';
  end if;

  if v_group.rider_id is not null then
    raise exception 'Already accepted by another rider';
  end if;

  if v_group.status <> 'commitment_paid' then
    raise exception 'Group not available for acceptance';
  end if;

  -- Advance the group.
  update public.delivery_groups
  set
    rider_id          = v_rider_id,
    status            = 'rider_accepted',
    rider_accepted_at = now()
  where id = p_group_id;

  -- Assign rider to ALL legs (regardless of source).
  update public.orders
  set rider_id = v_rider_id
  where delivery_group_id = p_group_id;
end;
$$;

grant execute on function public.accept_delivery_group(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 5. set_delivery_group_final_price
--
-- Rider sets the total food cost for the whole group. Allowed until the
-- student has paid (status can be corrected while awaiting_final_payment).
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.set_delivery_group_final_price(
  p_group_id     uuid,
  p_final_amount numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.delivery_groups%rowtype;
begin
  if not public.is_rider() then
    raise exception 'Unauthorized';
  end if;

  -- Validate amount before touching the DB.
  if p_final_amount is null or p_final_amount <= 0 then
    raise exception 'final_amount must be greater than 0';
  end if;
  if p_final_amount > 500000 then
    raise exception 'final_amount exceeds maximum allowed value (500000)';
  end if;

  select * into v_group from public.delivery_groups
  where id = p_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if v_group.rider_id is distinct from auth.uid() then
    raise exception 'Not your delivery group';
  end if;

  if v_group.status not in ('rider_accepted', 'awaiting_final_payment') then
    raise exception 'Cannot set final price at this stage (status: %)', v_group.status;
  end if;

  update public.delivery_groups
  set
    final_amount = p_final_amount,
    status       = 'awaiting_final_payment'
  where id = p_group_id;

  return jsonb_build_object(
    'group_id',     p_group_id,
    'final_amount', p_final_amount
  );
end;
$$;

grant execute on function public.set_delivery_group_final_price(uuid, numeric) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 6. Replace pay_group_final_amount
--
-- Uses the group-level final_amount (set by rider) rather than summing
-- leg final_amounts.
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.pay_group_final_amount(
  p_group_id uuid,
  p_pin      text
)
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
$$;

grant execute on function public.pay_group_final_amount(uuid, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 7. decline_group_final_amount
--
-- Student declines the final price quoted by the rider. Cancels the
-- whole group and flags it as student-initiated cancellation.
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.decline_group_final_amount(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.delivery_groups%rowtype;
begin
  select * into v_group from public.delivery_groups
  where id = p_group_id for update;

  if not found then raise exception 'Group not found'; end if;
  if v_group.student_id <> auth.uid() then raise exception 'Unauthorized'; end if;
  if v_group.status <> 'awaiting_final_payment' then
    raise exception 'Group is not awaiting final payment (status: %)', v_group.status;
  end if;

  -- Cancel group, flag as student-initiated.
  update public.delivery_groups
  set
    status               = 'cancelled',
    cancelled_by_student = true
  where id = p_group_id;

  -- Cancel all non-cancelled legs.
  update public.orders
  set status = 'cancelled'
  where delivery_group_id = p_group_id
    and status <> 'cancelled';
end;
$$;

grant execute on function public.decline_group_final_amount(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 8. cancel_delivery_group_before_accept
--
-- Student cancels before any rider accepts. Race-safe with
-- accept_delivery_group via FOR UPDATE NOWAIT on the group row.
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.cancel_delivery_group_before_accept(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.delivery_groups%rowtype;
begin
  select * into v_group from public.delivery_groups
  where id = p_group_id for update nowait;

  if not found then raise exception 'Group not found'; end if;
  if v_group.student_id <> auth.uid() then raise exception 'Unauthorized'; end if;

  if v_group.status <> 'commitment_paid' or v_group.rider_id is not null then
    raise exception 'Group can no longer be cancelled (a rider may have already accepted)';
  end if;

  update public.delivery_groups
  set status = 'cancelled'
  where id = p_group_id;

  update public.orders
  set status = 'cancelled'
  where delivery_group_id = p_group_id
    and status <> 'cancelled';
end;
$$;

grant execute on function public.cancel_delivery_group_before_accept(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 9. get_group_customer_info
--
-- Rider fetches contact details for the student who placed a group.
-- delivery_pin is only exposed after the student has paid (out_for_delivery).
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.get_group_customer_info(p_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group   public.delivery_groups%rowtype;
  v_profile public.profiles%rowtype;
begin
  if not public.is_rider() then
    raise exception 'Unauthorized';
  end if;

  select * into v_group from public.delivery_groups
  where id = p_group_id;

  if not found then
    raise exception 'Group not found';
  end if;

  if v_group.rider_id is distinct from auth.uid() then
    raise exception 'Not your delivery group';
  end if;

  -- Only available after rider has accepted (not in placed/cancelled).
  if v_group.status in ('placed', 'cancelled') then
    raise exception 'Customer info not available at this stage';
  end if;

  select * into v_profile from public.profiles
  where id = v_group.student_id;

  return jsonb_build_object(
    'full_name',          v_profile.full_name,
    'nickname',           v_profile.nickname,
    'phone',              v_profile.phone,
    'email',              v_profile.email,
    'delivery_location',  v_group.delivery_location,
    'location_details',   v_group.location_details,
    'student_note',       v_group.student_note,
    -- PIN only after student has confirmed payment.
    'delivery_pin',       case
                            when v_group.status = 'out_for_delivery'
                            then v_group.delivery_pin
                            else null
                          end
  );
end;
$$;

grant execute on function public.get_group_customer_info(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 10. get_group_items
--
-- Returns the full item breakdown for a delivery group for rider,
-- student, or admin display. Groups items by vendor, includes packs
-- from order_packs, and returns a subtotal per vendor.
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.get_group_items(p_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group      public.delivery_groups%rowtype;
  v_caller_id  uuid := auth.uid();
  v_result     jsonb;
begin
  select * into v_group from public.delivery_groups
  where id = p_group_id;

  if not found then
    raise exception 'Group not found';
  end if;

  -- Access check: student who owns it, assigned rider, or admin.
  if v_group.student_id <> v_caller_id
     and not (public.is_rider() and v_group.rider_id = v_caller_id)
     and not public.is_admin()
  then
    raise exception 'Unauthorized';
  end if;

  select coalesce(jsonb_agg(vendor_row order by vendor_name), '[]'::jsonb)
  into v_result
  from (
    select
      v.id                                                   as vendor_id,
      v.name                                                 as vendor_name,
      v.description                                          as vendor_location,
      -- Line items for this vendor's leg.
      coalesce(
        (
          select jsonb_agg(jsonb_build_object(
            'product_name',      oi.product_name,
            'quantity',          oi.quantity,
            'unit_price',        oi.unit_price,
            'section',           p.section,
            'food_subsection',   p.food_subsection,
            'selected_options',  oi.selected_options
          ) order by oi.product_name)
          from public.order_items oi
          left join public.products p on p.id = oi.product_id
          where oi.order_id = o.id
        ),
        '[]'::jsonb
      )                                                      as items,
      -- Packs for this vendor's leg.
      coalesce(
        (
          select jsonb_agg(jsonb_build_object(
            'pack_index', op.pack_index,
            'items',      op.items
          ) order by op.pack_index)
          from public.order_packs op
          where op.order_id = o.id
        ),
        '[]'::jsonb
      )                                                      as packs,
      o.total_amount                                         as subtotal
    from public.orders o
    join public.vendors v on v.id = o.vendor_id
    where o.delivery_group_id = p_group_id
      and o.status <> 'cancelled'
  ) sub(vendor_id, vendor_name, vendor_location, items, packs, subtotal);

  return v_result;
end;
$$;

grant execute on function public.get_group_items(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 11. Replace pay_group_commitment_fee
--
-- Removes source-based branching entirely. ALL legs go to 'placed'
-- (the group status is the canonical lifecycle indicator now).
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.pay_group_commitment_fee(
  p_group_id uuid,
  p_pin      text
)
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
  v_fee        numeric(10,2);
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
  if v_group.status <> 'placed' then raise exception 'Already paid or cancelled'; end if;

  v_fee := v_group.commitment_fee_total;

  -- Pickup orders have no fee — just advance.
  if v_fee > 0 then
    -- Lock wallet.
    select * into v_wallet from public.wallets
    where user_id = v_student_id for update;
    if not found then raise exception 'Wallet not found'; end if;
    if v_wallet.balance < v_fee then raise exception 'INSUFFICIENT_BALANCE'; end if;

    -- Deduct.
    update public.wallets
    set balance = balance - v_fee
    where user_id = v_student_id;

    -- Record transaction.
    insert into public.wallet_transactions
      (user_id, type, amount, source, balance_after)
    values
      (v_student_id, 'debit', v_fee, 'commitment_fee',
       v_wallet.balance - v_fee);
  end if;

  -- Advance group status.
  update public.delivery_groups
  set status = 'commitment_paid'
  where id = p_group_id;

  -- ALL legs: set commitment_fee_paid = true, status stays 'placed'.
  -- (Group status is canonical; legs do not need independent status.)
  update public.orders
  set commitment_fee_paid = true
  where delivery_group_id = p_group_id;

  return jsonb_build_object(
    'balance_after', case when v_fee > 0 then v_wallet.balance - v_fee else null end
  );
end;
$$;

grant execute on function public.pay_group_commitment_fee(uuid, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 12. Update place_multi_vendor_order
--
-- Reject p_scheduled_for when delivery_type is not 'pickup'.
-- Preserves the full latest body from round8_migration.sql.
-- ─────────────────────────────────────────────────────────────────────

-- Drop old 5-argument signature first (round7 version may still be registered).
drop function if exists public.place_multi_vendor_order(text, text, text, timestamptz, jsonb);

create or replace function public.place_multi_vendor_order(
  p_delivery_type          text default 'delivery',
  p_delivery_location      text default null,
  p_student_note           text default null,
  p_scheduled_for          timestamptz default null,
  p_legs                   jsonb default '[]'::jsonb,
  p_delivery_location_id   uuid default null,
  p_location_details       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_student_id     uuid    := auth.uid();
  v_group_id       uuid;
  v_location_price numeric(10,2) := 0;
  v_total_fee      numeric(10,2) := 0;
  v_leg            jsonb;
  v_order_id       uuid;
  v_item           jsonb;
  v_pack           jsonb;
  v_pack_idx       int;
  v_leg_count      int;
  v_capacity       int;
  v_leg_packs      int;
  v_leg_fee        numeric(10,2);
begin
  if v_student_id is null then
    raise exception 'Not authenticated';
  end if;

  -- Scheduled delivery is not supported; only pickup orders may be scheduled.
  if p_delivery_type <> 'pickup' and p_scheduled_for is not null then
    raise exception 'Scheduled delivery is not supported. Use pickup type for scheduled orders.';
  end if;

  v_leg_count := jsonb_array_length(p_legs);
  if v_leg_count = 0 then
    raise exception 'No vendor legs provided';
  end if;

  -- Look up delivery fee from location (new) or settings (fallback).
  if p_delivery_type = 'pickup' then
    v_location_price := 0;
  elsif p_delivery_location_id is not null then
    select price into v_location_price
    from public.delivery_locations
    where id = p_delivery_location_id and is_active = true;
    if v_location_price is null then
      raise exception 'Delivery location not found or inactive';
    end if;
  else
    -- Fallback to settings for backward compat.
    v_location_price := public._delivery_fee_from_settings(p_delivery_type);
  end if;

  -- Calculate per-vendor fees using pack brackets.
  -- Per vendor: location_price * ceil(food_packs / 3). Zero packs = 1×.
  v_total_fee := 0;
  for v_leg in select * from jsonb_array_elements(p_legs)
  loop
    v_leg_packs := jsonb_array_length(coalesce(v_leg -> 'packs', '[]'::jsonb));
    if v_leg_packs <= 0 then
      v_leg_fee := v_location_price;
    else
      v_leg_fee := v_location_price * ceil(v_leg_packs::numeric / 3);
    end if;
    v_total_fee := v_total_fee + v_leg_fee;
  end loop;

  -- Look up pack capacity.
  select value::int into v_capacity from public.delivery_settings where key = 'pack_meal_capacity';
  if v_capacity is null then v_capacity := 8; end if;

  -- Create the delivery group.
  insert into public.delivery_groups
    (student_id, delivery_type, delivery_location, student_note,
     commitment_fee_total, scheduled_for, status,
     delivery_location_id, location_details)
  values
    (v_student_id, p_delivery_type, p_delivery_location, p_student_note,
     v_total_fee, p_scheduled_for, 'placed',
     p_delivery_location_id, p_location_details)
  returning id into v_group_id;

  -- Create one order (leg) per vendor.
  for v_leg in select * from jsonb_array_elements(p_legs)
  loop
    -- Validate vendor exists.
    if not exists (select 1 from public.vendors where id = (v_leg ->> 'vendor_id')::uuid) then
      raise exception 'Vendor not found: %', v_leg ->> 'vendor_id';
    end if;

    -- Server-side pack capacity validation.
    if jsonb_array_length(coalesce(v_leg -> 'packs', '[]'::jsonb)) > 0 then
      for v_pack in select * from jsonb_array_elements(v_leg -> 'packs')
      loop
        declare
          v_meal_spoons int := 0;
          v_pack_item   jsonb;
        begin
          for v_pack_item in select * from jsonb_array_elements(coalesce(v_pack -> 'items', '[]'::jsonb))
          loop
            if exists (
              select 1 from public.products
              where id = (v_pack_item ->> 'product_id')::uuid
                and section = 'food' and food_subsection = 'meal'
            ) then
              v_meal_spoons := v_meal_spoons + coalesce((v_pack_item ->> 'quantity')::int, 1);
            end if;
          end loop;

          if v_meal_spoons > v_capacity then
            raise exception 'Pack exceeds meal capacity (% spoons, max %)', v_meal_spoons, v_capacity;
          end if;
        end;
      end loop;
    end if;

    -- Calculate this vendor's delivery fee.
    v_leg_packs := jsonb_array_length(coalesce(v_leg -> 'packs', '[]'::jsonb));
    if v_leg_packs <= 0 then
      v_leg_fee := v_location_price;
    else
      v_leg_fee := v_location_price * ceil(v_leg_packs::numeric / 3);
    end if;

    insert into public.orders
      (student_id, vendor_id, source, type, status, delivery_type,
       delivery_location, total_amount, estimated_time, scheduled_for,
       pack_count, pack_fee, notes, delivery_group_id,
       commitment_fee_amount, delivery_location_id, location_details)
    values
      (v_student_id,
       (v_leg ->> 'vendor_id')::uuid,
       coalesce(v_leg ->> 'source', 'partner'),
       'food',
       'placed',
       p_delivery_type,
       p_delivery_location,
       coalesce((v_leg ->> 'total_amount')::numeric, 0),
       coalesce(v_leg ->> 'estimated_time', '20-30 min'),
       p_scheduled_for,
       jsonb_array_length(coalesce(v_leg -> 'packs', '[]'::jsonb)),
       coalesce((v_leg ->> 'pack_fee')::numeric, 0),
       p_student_note,
       v_group_id,
       v_leg_fee,
       p_delivery_location_id,
       p_location_details)
    returning id into v_order_id;

    -- Insert line items.
    for v_item in select * from jsonb_array_elements(coalesce(v_leg -> 'line_items', '[]'::jsonb))
    loop
      insert into public.order_items
        (order_id, product_id, product_name, quantity, unit_price, selected_options)
      values
        (v_order_id,
         (v_item ->> 'product_id')::uuid,
         v_item ->> 'product_name',
         (v_item ->> 'quantity')::int,
         (v_item ->> 'unit_price')::numeric,
         coalesce(v_item -> 'selected_options', '[]'::jsonb));
    end loop;

    -- Insert packs.
    v_pack_idx := 0;
    for v_pack in select * from jsonb_array_elements(coalesce(v_leg -> 'packs', '[]'::jsonb))
    loop
      insert into public.order_packs (order_id, pack_index, items)
      values (v_order_id, v_pack_idx, coalesce(v_pack -> 'items', '[]'::jsonb));
      v_pack_idx := v_pack_idx + 1;
    end loop;
  end loop;

  return jsonb_build_object(
    'group_id',             v_group_id,
    'commitment_fee_total', v_total_fee,
    'vendor_count',         v_leg_count
  );
end;
$$;

grant execute on function public.place_multi_vendor_order(text, text, text, timestamptz, jsonb, uuid, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 13. Update verify_group_delivery
--
-- Keeps the existing PIN + out_for_delivery check. Wraps the
-- delivery_records INSERT in a BEGIN/EXCEPTION so the function still
-- succeeds if that table is missing or the INSERT fails for any reason
-- (e.g. schema not yet fully deployed).
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.verify_group_delivery(
  p_group_id uuid,
  p_pin      text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider_id uuid := auth.uid();
  v_group    public.delivery_groups%rowtype;
begin
  if not public.is_rider() then
    raise exception 'Unauthorized';
  end if;

  select * into v_group from public.delivery_groups
  where id = p_group_id for update;

  if not found then raise exception 'Group not found'; end if;
  if v_group.rider_id is distinct from v_rider_id then raise exception 'Not your delivery'; end if;
  if v_group.status <> 'out_for_delivery' then
    raise exception 'Group is not out for delivery (status: %)', v_group.status;
  end if;

  if v_group.delivery_pin is null then
    raise exception 'This group has no delivery PIN — contact support';
  end if;
  if p_pin is null or upper(trim(p_pin)) <> upper(v_group.delivery_pin) then
    raise exception 'Incorrect delivery PIN';
  end if;

  -- Complete the group.
  update public.delivery_groups
  set status = 'completed', delivery_stage = null
  where id = p_group_id;

  -- Complete all non-cancelled legs.
  update public.orders
  set status = 'completed', delivery_stage = null
  where delivery_group_id = p_group_id
    and status <> 'cancelled';

  -- Write delivery records — gracefully skip if table is unavailable.
  begin
    insert into public.delivery_records (rider_id, order_id, completed_at)
    select v_rider_id, id, now()
    from public.orders
    where delivery_group_id = p_group_id
      and status = 'completed'
    on conflict (order_id) do nothing;
  exception when undefined_table or others then
    -- delivery_records table missing or insert failed — non-fatal.
    null;
  end;
end;
$$;

grant execute on function public.verify_group_delivery(uuid, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 14. Ensure delivery_groups is in the Realtime publication
-- ─────────────────────────────────────────────────────────────────────

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname    = 'supabase_realtime'
      and schemaname = 'public'
      and tablename  = 'delivery_groups'
  ) then
    execute 'alter publication supabase_realtime add table public.delivery_groups';
  end if;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────
-- 15. Now-unused RPCs / tables
--
-- The following objects still exist in the database but are no longer
-- called by any active code path as of Fix Pack 2. They are intentionally
-- left in place (safe to drop later after a full data audit). Do NOT
-- call them from new client code.
--
--   confirm_group_leg_pickup(uuid)
--     — per-vendor pickup confirmation removed; group-level
--       verify_group_delivery() is the single completion step.
--
--   confirm_group_leg_sourcing(uuid, numeric)
--     — superseded by set_delivery_group_final_price(uuid, numeric),
--       which sets the total on the group row directly.
--
--   confirm_sourced_items(uuid, numeric)
--     — standalone order version of sourcing confirmation; superseded
--       for the multi-vendor flow. Still technically callable for legacy
--       single-order partner flow but should be migrated out.
--
--   flag_item_unavailable(...)
--     — removed from the rider flow in this overhaul.
--
--   add_custom_item(...)
--     — removed from the rider flow in this overhaul.
--
--   order_item_flags (table)
--     — still exists, no active writes after this migration.
--
--   order_custom_items (table)
--     — still exists, no active writes after this migration.
--
--   confirm_pickup(uuid)
--     — still exists and is used for standalone errand orders; it is
--       NOT called for delivery_group legs any more.
-- ─────────────────────────────────────────────────────────────────────
