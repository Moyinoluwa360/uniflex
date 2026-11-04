-- =====================================================================
-- Round 8 Bug-fix Migration
--
-- Run once in the Supabase SQL editor after round8_migration.sql.
-- All blocks are idempotent — safe to re-run.
--
-- Fixes:
--   1. delivery_groups.delivery_type CHECK missing 'delivery'
--   2. place_errand_with_payment RPC (single-payment errand flow)
--   3. pay_commitment_fee must reject errand orders
--   4. job_pool_read policy — include type='errand' + status='placed' + commitment_fee_paid=true
--   5. accept_order — handle type='errand', set status='being_sourced'
--   6. confirm_pickup — set status='out_for_delivery' for errand orders
-- =====================================================================


-- ─────────────────────────────────────────────────────────────────────
-- Fix 1: delivery_groups.delivery_type CHECK
-- Existing test rows (if any) used 'campus_delivery'/'hostel_delivery'.
-- Round 8 client sends 'delivery' for all location-based food orders.
-- Migrate old variants → 'delivery', then narrow the constraint.
-- ─────────────────────────────────────────────────────────────────────

-- Drop the old constraint first so the UPDATE below is not blocked by it.
alter table public.delivery_groups
  drop constraint if exists delivery_groups_delivery_type_check;

-- Migrate existing rows that used the old delivery_type values.
update public.delivery_groups
set delivery_type = 'delivery'
where delivery_type in ('campus_delivery', 'hostel_delivery');

-- Add the new constraint that allows only 'pickup' and 'delivery'.
alter table public.delivery_groups
  add constraint delivery_groups_delivery_type_check
  check (delivery_type in ('pickup', 'delivery'));


-- ─────────────────────────────────────────────────────────────────────
-- Fix 2: place_errand_with_payment RPC
-- Single-payment errand flow:
--   • Validates PIN (with lockout via _check_transaction_pin)
--   • Deducts errand flat fee from wallet
--   • Creates orders row (type='errand', commitment_fee_paid=true)
--   • Creates errand_requests row
--   • Returns order_id + balance_after
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.place_errand_with_payment(
  p_category               text,
  p_pickup_location        text,
  p_dropoff_location       text,
  p_item_description       text,
  p_flat_fee               numeric(10,2),
  p_pin                    text,
  p_delivery_location_id   uuid    default null,
  p_location_details       text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_student_id  uuid    := auth.uid();
  v_pin_status  text;
  v_balance     numeric;
  v_new_balance numeric;
  v_order_id    uuid;
begin
  if v_student_id is null then
    raise exception 'Unauthorized';
  end if;

  -- Lockout-aware PIN check.
  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status = 'not_set' then
    raise exception 'PIN_NOT_SET';
  end if;
  if v_pin_status = 'locked' then
    raise exception 'PIN_LOCKED';
  end if;
  if v_pin_status = 'invalid' then
    raise exception 'INVALID_PIN';
  end if;
  -- v_pin_status = 'ok' — proceed.

  -- Validate category exists and is active.
  if not exists (
    select 1 from public.errand_categories
    where key = p_category and is_active = true
  ) then
    raise exception 'Errand category not found or inactive: %', p_category;
  end if;

  -- Lock wallet and check balance.
  select balance into v_balance
  from public.wallets
  where user_id = v_student_id
  for update;

  if not found then
    raise exception 'WALLET_NOT_FOUND';
  end if;

  if v_balance < p_flat_fee then
    raise exception 'INSUFFICIENT_BALANCE';
  end if;

  -- Deduct fee.
  update public.wallets
  set balance = balance - p_flat_fee
  where user_id = v_student_id
  returning balance into v_new_balance;

  -- Create order. commitment_fee_paid=true because fee is paid upfront.
  -- status = 'placed' — rider pool picks it up via job_pool_read policy.
  insert into public.orders
    (student_id, source, type, status, delivery_type,
     total_amount, estimated_time,
     commitment_fee_paid, commitment_fee_amount,
     delivery_location_id, location_details)
  values
    (v_student_id, 'uniflex', 'errand', 'placed', 'delivery',
     p_flat_fee, '15–25 min',
     true, p_flat_fee,
     p_delivery_location_id, p_location_details)
  returning id into v_order_id;

  -- Create errand request detail row.
  insert into public.errand_requests
    (order_id, category, pickup_location, dropoff_location, item_description)
  values
    (v_order_id, p_category, p_pickup_location, p_dropoff_location, p_item_description);

  -- Record wallet transaction.
  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_student_id, 'debit', p_flat_fee, 'order_payment', v_order_id, v_new_balance);

  return jsonb_build_object(
    'order_id',      v_order_id,
    'balance_after', v_new_balance
  );
end;
$$;

grant execute on function public.place_errand_with_payment(
  text, text, text, text, numeric, text, uuid, text
) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- Fix 3: pay_commitment_fee — reject errand orders
-- Errand orders pay upfront via place_errand_with_payment; they must
-- never reach this function. Add an explicit guard at the top.
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.pay_commitment_fee(
  p_order_id uuid,
  p_pin      text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_student_id uuid;
  v_order      public.orders%rowtype;
  v_wallet     public.wallets%rowtype;
  v_fee        numeric(10,2) := 300.00;
  v_pin_status text;
begin
  v_student_id := auth.uid();

  -- Use lockout-aware PIN check.
  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status = 'not_set' then
    raise exception 'PIN_NOT_SET';
  end if;
  if v_pin_status = 'locked' then
    raise exception 'PIN_LOCKED';
  end if;
  if v_pin_status = 'invalid' then
    raise exception 'INVALID_PIN';
  end if;
  -- v_pin_status = 'ok' — proceed.

  -- Lock order row.
  select * into v_order from public.orders
  where id = p_order_id for update;

  if not found then raise exception 'Order not found'; end if;
  if v_order.student_id <> v_student_id then raise exception 'Unauthorized'; end if;
  if v_order.commitment_fee_paid then raise exception 'Commitment fee already paid'; end if;
  if v_order.status <> 'placed' then raise exception 'Order is not in placed state'; end if;

  -- Guard: errand orders pay upfront; this function must not charge them.
  if v_order.type in ('errand', 'around') then
    raise exception 'Commitment fee does not apply to errand orders';
  end if;

  -- Guard: Uniflex food orders are pay-now, no commitment fee.
  if v_order.source = 'uniflex' and v_order.type = 'food' then
    raise exception 'Commitment fee does not apply to Uniflex orders';
  end if;

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
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_student_id, 'debit', v_fee, 'commitment_fee', p_order_id,
     v_wallet.balance - v_fee);

  -- Advance order.
  update public.orders
  set
    commitment_fee_paid   = true,
    commitment_fee_amount = v_fee,
    status                = 'being_sourced'
  where id = p_order_id;

  return jsonb_build_object(
    'balance_after', v_wallet.balance - v_fee
  );
end;
$$;

grant execute on function public.pay_commitment_fee(uuid, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- Fix 4: job_pool_read RLS policy — include errand orders
-- Errands are pool-eligible when:
--   type = 'errand' AND status = 'placed' AND commitment_fee_paid = true
-- (Errand fee is paid upfront, so status stays 'placed' — not 'being_sourced')
-- ─────────────────────────────────────────────────────────────────────

drop policy if exists "job_pool_read" on public.orders;
create policy "job_pool_read" on public.orders
  for select to authenticated
  using (
    -- student sees own orders
    student_id = auth.uid()
    -- admin sees all orders
    or (select public.is_admin())
    -- rider sees their own assigned orders
    or rider_id = auth.uid()
    -- Uniflex delivery: pool-eligible after admin "Transfer to Rider"
    or (source = 'uniflex' and status = 'ready'
        and delivery_type in ('delivery', 'campus_delivery', 'hostel_delivery')
        and transferred_to_rider_at is not null)
    -- partner food: pool-eligible once commitment fee paid (being_sourced)
    or (source = 'partner' and status = 'being_sourced'
        and delivery_type in ('delivery', 'campus_delivery', 'hostel_delivery'))
    -- errand orders: pool-eligible once fee is paid upfront (status stays 'placed')
    or (type = 'errand' and status = 'placed' and commitment_fee_paid = true)
    -- legacy around orders (backward compat for any pre-migration rows)
    or (type = 'around' and status = 'being_sourced')
  );


-- ─────────────────────────────────────────────────────────────────────
-- Fix 5: accept_order — handle type='errand'
-- Errand acceptance:
--   • Eligibility: type='errand' AND status='placed' AND commitment_fee_paid=true
--   • After accept: status → 'being_sourced' (= "Rider assigned" in timeline)
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.accept_order(p_order_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if not public.is_rider() then
    raise exception 'Unauthorized';
  end if;

  select * into v_order from public.orders
  where id = p_order_id
  for update nowait;

  if not found then raise exception 'Order not found'; end if;
  if v_order.rider_id is not null then raise exception 'Order already taken'; end if;

  if not (
    -- Uniflex delivery: admin transferred to rider pool
    (v_order.source = 'uniflex' and v_order.status = 'ready'
       and v_order.delivery_type in ('delivery', 'campus_delivery', 'hostel_delivery')
       and v_order.transferred_to_rider_at is not null)
    -- partner food: commitment fee paid, awaiting rider
    or (v_order.source = 'partner' and v_order.status = 'being_sourced'
       and v_order.delivery_type in ('delivery', 'campus_delivery', 'hostel_delivery'))
    -- errand: fee paid upfront, status = 'placed'
    or (v_order.type = 'errand' and v_order.status = 'placed'
       and v_order.commitment_fee_paid = true)
    -- legacy around (backward compat)
    or (v_order.type = 'around' and v_order.status = 'being_sourced')
  ) then
    raise exception 'Order is not eligible for acceptance';
  end if;

  update public.orders
  set
    rider_id       = auth.uid(),
    delivery_stage = 'accepted',
    status         = case
                       -- errand accepted → "Rider assigned"
                       when v_order.type = 'errand' then 'being_sourced'
                       -- partner food stays being_sourced; uniflex ready → out_for_delivery
                       when v_order.status = 'being_sourced' then 'being_sourced'
                       else 'out_for_delivery'
                     end
  where id = p_order_id;
end;
$$;

grant execute on function public.accept_order(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- Fix 6: confirm_pickup — advance errand to out_for_delivery
-- For errand orders, "pickup confirmed" means the rider has collected
-- whatever they need (or is setting off). Advance status to
-- 'out_for_delivery' so the student timeline shows "On the way".
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.confirm_pickup(p_order_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if not public.is_rider() then
    raise exception 'Unauthorized';
  end if;

  select * into v_order from public.orders
  where id = p_order_id
    and rider_id = auth.uid()
    and delivery_stage = 'accepted';

  if not found then
    raise exception 'Order not found or not in accepted stage';
  end if;

  update public.orders
  set
    delivery_stage = 'picked_up',
    -- Errand: advance to "On the way" when rider sets off.
    status = case
               when v_order.type = 'errand' then 'out_for_delivery'
               else status
             end
  where id = p_order_id;
end;
$$;

grant execute on function public.confirm_pickup(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- Diagnostic: wallet balances for errand test orders
-- (Read-only — comment out after verification)
-- ─────────────────────────────────────────────────────────────────────
/*
select
  o.id,
  o.type,
  o.status,
  o.commitment_fee_paid,
  o.total_amount,
  o.created_at,
  w.balance as student_wallet_balance
from public.orders o
join public.wallets w on w.user_id = o.student_id
where o.type in ('errand', 'around')
order by o.created_at desc
limit 10;
*/
