-- =====================================================================
-- Round 9 — Cancel RPCs (Phase A)
--
-- Run once in the Supabase SQL editor. Idempotent (CREATE OR REPLACE).
--
-- Adds four cancel functions:
--   student_cancel_order           — student cancels standalone order before rider accepts
--   student_cancel_delivery_group  — student cancels multi-vendor checkout before rider accepts
--   admin_cancel_order             — admin cancels any non-terminal standalone order
--   admin_cancel_delivery_group    — admin cancels any non-terminal delivery group + its legs
--
-- Design rules:
--   • No automatic refunds of any fee (existing policy).
--   • Students can only cancel before a rider accepts (race-safe lock).
--   • Admin can cancel at any non-terminal stage.
--   • Cancelled orders/groups leave the rider pool immediately
--     (job_pool_read policy excludes non-placed/being_sourced orders).
-- =====================================================================


-- ─────────────────────────────────────────────────────────────────────
-- student_cancel_order
-- Cancel a standalone order (errand / pickup) before a rider accepts.
-- Uses FOR UPDATE to race-safely check that no rider has taken it.
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.student_cancel_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  select * into v_order from public.orders
  where id = p_order_id for update;

  if not found then
    raise exception 'Order not found';
  end if;
  if v_order.student_id <> auth.uid() then
    raise exception 'Unauthorized';
  end if;
  if v_order.status in ('completed', 'cancelled') then
    raise exception 'ORDER_ALREADY_TERMINAL';
  end if;
  if v_order.rider_id is not null then
    raise exception 'ORDER_ALREADY_ACCEPTED';
  end if;

  update public.orders
  set status = 'cancelled'
  where id = p_order_id;
end;
$$;

grant execute on function public.student_cancel_order(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- student_cancel_delivery_group
-- Cancel a multi-vendor delivery checkout before a rider accepts.
-- Cancels the group row and all non-terminal leg orders.
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.student_cancel_delivery_group(p_group_id uuid)
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

  if not found then
    raise exception 'Delivery group not found';
  end if;
  if v_group.student_id <> auth.uid() then
    raise exception 'Unauthorized';
  end if;
  if v_group.status in ('completed', 'cancelled') then
    raise exception 'ORDER_ALREADY_TERMINAL';
  end if;
  if v_group.rider_id is not null then
    raise exception 'ORDER_ALREADY_ACCEPTED';
  end if;

  update public.delivery_groups
  set status = 'cancelled'
  where id = p_group_id;

  -- Cancel all non-terminal legs.
  update public.orders
  set status = 'cancelled'
  where delivery_group_id = p_group_id
    and status not in ('completed', 'cancelled');
end;
$$;

grant execute on function public.student_cancel_delivery_group(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- admin_cancel_order
-- Admin cancels any non-terminal standalone order at any stage.
-- Optional reason is appended to the order notes field.
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.admin_cancel_order(
  p_order_id uuid,
  p_reason   text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Unauthorized';
  end if;

  select * into v_order from public.orders
  where id = p_order_id for update;

  if not found then
    raise exception 'Order not found';
  end if;
  if v_order.status in ('completed', 'cancelled') then
    raise exception 'ORDER_ALREADY_TERMINAL';
  end if;

  update public.orders
  set
    status = 'cancelled',
    notes  = case
               when p_reason is not null
                 then coalesce(notes || ' | ', '') || 'Cancelled by admin: ' || p_reason
               else notes
             end
  where id = p_order_id;
end;
$$;

grant execute on function public.admin_cancel_order(uuid, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- admin_cancel_delivery_group
-- Admin cancels a multi-vendor group and all its non-terminal legs.
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.admin_cancel_delivery_group(
  p_group_id uuid,
  p_reason   text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.delivery_groups%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Unauthorized';
  end if;

  select * into v_group from public.delivery_groups
  where id = p_group_id for update;

  if not found then
    raise exception 'Delivery group not found';
  end if;
  if v_group.status in ('completed', 'cancelled') then
    raise exception 'ORDER_ALREADY_TERMINAL';
  end if;

  update public.delivery_groups
  set status = 'cancelled'
  where id = p_group_id;

  update public.orders
  set
    status = 'cancelled',
    notes  = case
               when p_reason is not null
                 then coalesce(notes || ' | ', '') || 'Cancelled by admin: ' || p_reason
               else notes
             end
  where delivery_group_id = p_group_id
    and status not in ('completed', 'cancelled');
end;
$$;

grant execute on function public.admin_cancel_delivery_group(uuid, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- Verification query (read-only, run manually to confirm)
-- ─────────────────────────────────────────────────────────────────────
/*
select routine_name, routine_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'student_cancel_order',
    'student_cancel_delivery_group',
    'admin_cancel_order',
    'admin_cancel_delivery_group'
  )
order by routine_name;
-- Expected: 4 rows, all FUNCTION
*/
