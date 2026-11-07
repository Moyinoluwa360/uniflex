-- =====================================================================
-- Pack 4B — one order breakdown everywhere, Rider app fixes, one
--           completion time, one history entry per checkout
--
-- ONE additive block. Safe to run once (every statement is also
-- re-runnable). Run AFTER pack_4a.sql. Nothing is deleted; the only
-- data touched is the new timestamp / price columns (back-filled).
--
-- What it does
--   1. Columns: completed_at / cancelled_at on delivery_groups + orders,
--      price on order_packs (back-filled).
--   2. Triggers: completed_at / cancelled_at are stamped ONCE by the
--      server (now()) the moment a status becomes completed/cancelled,
--      and can never change afterwards.
--   3. get_order_breakdown(): THE one function every role uses to read
--      an order's contents (vendors -> packs -> drinks -> others).
--      Replaces get_group_items() (broken: "column vendor_row does not
--      exist"). get_group_items is NOT dropped here (see Part B audit).
--   4. Rider-safe RPCs (never return fees, phone/email after the job,
--      matric number or the delivery PIN): rider_job_pool(),
--      rider_active_jobs(), rider_history(), rider_history_item(),
--      get_rider_stats() (counts checkouts, not vendor parts).
--   5. 3-active-jobs cap inside accept_delivery_group / accept_order
--      (race-safe: advisory lock per rider + the existing row lock).
--   6. verify_group_delivery / verify_delivery: ONE completed_at for the
--      parent and every internal part; errands no longer need a
--      "picked up" step that no screen can set.
--   7. get_dashboard_stats counts one order per checkout.
-- =====================================================================

-- ── 0. Prerequisite ──────────────────────────────────────────────────
do $$
begin
  if to_regclass('public.app_settings') is null
     or to_regprocedure('public.create_paid_delivery_order(uuid,text,jsonb,uuid,text,text)') is null then
    raise exception 'Run supabase/pack_4a.sql first.';
  end if;
end $$;

-- ── 1. Columns + back-fill ───────────────────────────────────────────
alter table public.delivery_groups add column if not exists completed_at timestamptz;
alter table public.delivery_groups add column if not exists cancelled_at timestamptz;
alter table public.orders          add column if not exists completed_at timestamptz;
alter table public.orders          add column if not exists cancelled_at timestamptz;
alter table public.order_packs     add column if not exists price numeric(10,2);

-- The back-fill must not bump updated_at on old rows.
alter table public.orders          disable trigger orders_updated_at;
alter table public.delivery_groups disable trigger delivery_groups_updated_at;

-- completed_at: the verified-delivery time already recorded per part;
-- otherwise the last update.
update public.orders o
   set completed_at = coalesce(
         (select dr.completed_at from public.delivery_records dr where dr.order_id = o.id),
         o.updated_at)
 where o.status = 'completed' and o.completed_at is null;

update public.delivery_groups g
   set completed_at = coalesce(
         (select min(o.completed_at) from public.orders o
           where o.delivery_group_id = g.id and o.status = 'completed'),
         g.updated_at)
 where g.status = 'completed' and g.completed_at is null;

-- Every part of a completed checkout shares the parent's time.
update public.orders o
   set completed_at = g.completed_at
  from public.delivery_groups g
 where o.delivery_group_id = g.id and g.status = 'completed'
   and o.status = 'completed' and o.completed_at is distinct from g.completed_at;

update public.delivery_records dr
   set completed_at = o.completed_at
  from public.orders o
 where dr.order_id = o.id and o.delivery_group_id is not null
   and o.completed_at is not null and dr.completed_at is distinct from o.completed_at;

update public.orders
   set cancelled_at = updated_at
 where status = 'cancelled' and cancelled_at is null;
update public.delivery_groups
   set cancelled_at = updated_at
 where status = 'cancelled' and cancelled_at is null;

alter table public.orders          enable trigger orders_updated_at;
alter table public.delivery_groups enable trigger delivery_groups_updated_at;

-- Pack prices: recorded per pack from now on; old packs get the price
-- their order was actually charged (pack_fee / pack_count), falling back
-- to the vendor's current pack price only when the order stored no fee.
update public.order_packs op
   set price = case
         when o.pack_count > 0 and o.pack_fee > 0 then round(o.pack_fee / o.pack_count, 2)
         else coalesce(v.pack_price, 0)
       end
  from public.orders o
  left join public.vendors v on v.id = o.vendor_id
 where op.order_id = o.id and op.price is null;

create or replace function public._order_pack_set_price()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.price is null then
    select case
             when o.pack_count > 0 and o.pack_fee > 0 then round(o.pack_fee / o.pack_count, 2)
             else coalesce(v.pack_price, 0)
           end
      into new.price
      from public.orders o
      left join public.vendors v on v.id = o.vendor_id
     where o.id = new.order_id;
  end if;
  return new;
end;
$$;

drop trigger if exists order_packs_set_price on public.order_packs;
create trigger order_packs_set_price
  before insert on public.order_packs
  for each row execute function public._order_pack_set_price();

-- ── 2. One server-side completion / cancellation time ────────────────
create or replace function public._set_terminal_timestamps()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' then
    -- Once stamped, never changed.
    if old.completed_at is not null then new.completed_at := old.completed_at; end if;
    if old.cancelled_at is not null then new.cancelled_at := old.cancelled_at; end if;
  end if;
  if new.status = 'completed' and new.completed_at is null then
    new.completed_at := now();
  end if;
  if new.status = 'cancelled' and new.cancelled_at is null then
    new.cancelled_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists orders_terminal_ts on public.orders;
create trigger orders_terminal_ts
  before insert or update on public.orders
  for each row execute function public._set_terminal_timestamps();

drop trigger if exists delivery_groups_terminal_ts on public.delivery_groups;
create trigger delivery_groups_terminal_ts
  before insert or update on public.delivery_groups
  for each row execute function public._set_terminal_timestamps();

-- ── 3. THE order breakdown ───────────────────────────────────────────
-- One vendor's part of an order. Internal: no access check here, so it
-- is not callable by clients (see the revoke below).
create or replace function public._breakdown_leg(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_o            public.orders%rowtype;
  v_v            public.vendors%rowtype;
  v_packs        jsonb;
  v_packs_total  numeric(10,2);
  v_food         jsonb;
  v_drinks       jsonb;
  v_others       jsonb;
  v_items_total  numeric(10,2);
  v_item_count   int;
begin
  select * into v_o from public.orders where id = p_order_id;
  if not found then return null; end if;
  select * into v_v from public.vendors where id = v_o.vendor_id;

  -- Packs: each with its own price and contents (name x quantity).
  select coalesce(jsonb_agg(jsonb_build_object(
           'index', op.pack_index + 1,
           'price', coalesce(op.price, 0),
           'items', (
             select coalesce(jsonb_agg(jsonb_build_object(
                      'name',     pit.elem ->> 'product_name',
                      'quantity', coalesce((pit.elem ->> 'quantity')::int, 1))
                    order by pit.ord), '[]'::jsonb)
               from jsonb_array_elements(op.items) with ordinality as pit(elem, ord)
           )
         ) order by op.pack_index), '[]'::jsonb),
         coalesce(sum(coalesce(op.price, 0)), 0)
    into v_packs, v_packs_total
    from public.order_packs op
   where op.order_id = p_order_id;

  -- Everything that is not inside a pack, by section.
  with it as (
    select oi.product_name, oi.unit_price, oi.quantity,
           coalesce(p.section, 'others') as section,
           (select coalesce(sum((pit ->> 'quantity')::int), 0)
              from public.order_packs op, jsonb_array_elements(op.items) pit
             where op.order_id = oi.order_id
               and (pit ->> 'product_id') = oi.product_id::text) as packed
      from public.order_items oi
      left join public.products p on p.id = oi.product_id
     where oi.order_id = p_order_id
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
        'name', product_name, 'quantity', quantity - packed,
        'unit_price', unit_price, 'line_total', (quantity - packed) * unit_price)
      order by product_name) filter (where section = 'food' and quantity - packed > 0), '[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object(
        'name', product_name, 'quantity', quantity,
        'unit_price', unit_price, 'line_total', quantity * unit_price)
      order by product_name) filter (where section = 'drinks'), '[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object(
        'name', product_name, 'quantity', quantity,
        'unit_price', unit_price, 'line_total', quantity * unit_price)
      order by product_name) filter (where section not in ('food', 'drinks')), '[]'::jsonb),
    coalesce(sum(quantity * unit_price), 0),
    count(*)
    into v_food, v_drinks, v_others, v_items_total, v_item_count
    from it;

  return jsonb_build_object(
    'order_id',        v_o.id,
    'vendor_id',       v_v.id,
    'vendor_name',     coalesce(v_v.name, 'Vendor'),
    'vendor_location', v_v.description,
    'packs',           v_packs,
    'items',           v_food,
    'drinks',          v_drinks,
    'others',          v_others,
    'item_count',      v_item_count,
    'items_total',     v_items_total,
    'packs_total',     v_packs_total,
    'vendor_total',    v_items_total + v_packs_total);
end;
$$;

revoke all on function public._breakdown_leg(uuid) from public, anon, authenticated;

-- The one function every role calls. p_id is a delivery group, a pickup
-- order, or (for convenience) an internal part, which answers for its
-- parent. NEVER returns delivery / commitment / service fees.
create or replace function public.get_order_breakdown(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_group    public.delivery_groups%rowtype;
  v_order    public.orders%rowtype;
  v_group_id uuid;
  v_kind     text;
  v_allowed  boolean := false;
  v_vendors  jsonb;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;

  select * into v_group from public.delivery_groups where id = p_id;
  if found then
    v_group_id := v_group.id;
    v_kind     := 'delivery';
    v_allowed  := v_group.student_id = v_uid
                  or public.is_admin()
                  or (public.is_rider() and (
                        v_group.rider_id = v_uid
                        -- in the rider pool: items are visible BEFORE accepting
                        or (v_group.rider_id is null
                            and v_group.status = 'commitment_paid'
                            and v_group.is_paid)));
  else
    select * into v_order from public.orders where id = p_id;
    if not found then raise exception 'Order not found'; end if;
    if v_order.delivery_group_id is not null then
      return public.get_order_breakdown(v_order.delivery_group_id);
    end if;
    v_kind    := case when v_order.delivery_type = 'pickup' then 'pickup' else 'order' end;
    v_allowed := v_order.student_id = v_uid
                 or public.is_admin()
                 or (public.is_rider() and v_order.rider_id = v_uid);
  end if;

  if not v_allowed then raise exception 'Unauthorized'; end if;

  select coalesce(jsonb_agg(public._breakdown_leg(o.id)
                            order by (select name from public.vendors v where v.id = o.vendor_id), o.id),
                  '[]'::jsonb)
    into v_vendors
    from public.orders o
   where (v_group_id is not null and o.delivery_group_id = v_group_id and o.status <> 'cancelled')
      or (v_group_id is null and o.id = p_id);

  return jsonb_build_object(
    'order_id', coalesce(v_group_id, p_id),
    'kind',     v_kind,
    'vendors',  v_vendors);
end;
$$;

grant execute on function public.get_order_breakdown(uuid) to authenticated;

-- ── 4. Active-job cap (shared by both accept RPCs) ───────────────────
create or replace function public._rider_active_job_count(p_rider uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*)::int from public.delivery_groups g
      where g.rider_id = p_rider
        and g.status in ('rider_accepted', 'awaiting_final_payment', 'out_for_delivery'))
  + (select count(*)::int from public.orders o
      where o.rider_id = p_rider and o.delivery_group_id is null
        and o.status in ('being_sourced', 'awaiting_final_payment', 'out_for_delivery'));
$$;

revoke all on function public._rider_active_job_count(uuid) from public, anon, authenticated;

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

  -- Serialise this rider's accepts so two taps on two jobs cannot both
  -- pass the cap check.
  perform pg_advisory_xact_lock(hashtextextended('rider_accept:' || v_rider_id::text, 0));
  if public._rider_active_job_count(v_rider_id) >= 3 then
    raise exception 'ACTIVE_JOB_LIMIT'
      using hint = 'You already have 3 active jobs. Finish one before accepting another.';
  end if;

  select * into v_group from public.delivery_groups
   where id = p_group_id
   for update nowait;

  if not found then raise exception 'Group not found'; end if;
  if v_group.rider_id is not null then
    raise exception 'Already accepted by another rider';
  end if;
  if v_group.status <> 'commitment_paid' or not v_group.is_paid then
    raise exception 'Group not available for acceptance';
  end if;

  update public.delivery_groups
     set rider_id = v_rider_id, status = 'rider_accepted', rider_accepted_at = now()
   where id = p_group_id;

  update public.orders set rider_id = v_rider_id
   where delivery_group_id = p_group_id;
end;
$$;

grant execute on function public.accept_delivery_group(uuid) to authenticated;

create or replace function public.accept_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if not public.is_rider() then
    raise exception 'Unauthorized';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('rider_accept:' || auth.uid()::text, 0));
  if public._rider_active_job_count(auth.uid()) >= 3 then
    raise exception 'ACTIVE_JOB_LIMIT'
      using hint = 'You already have 3 active jobs. Finish one before accepting another.';
  end if;

  select * into v_order from public.orders
   where id = p_order_id
   for update nowait;

  if not found then raise exception 'Order not found'; end if;
  if v_order.rider_id is not null then raise exception 'Order already taken'; end if;
  if v_order.delivery_group_id is not null then
    raise exception 'Order is not eligible for acceptance';
  end if;

  if not (
    (v_order.source = 'uniflex' and v_order.status = 'ready'
       and v_order.delivery_type in ('delivery', 'campus_delivery', 'hostel_delivery')
       and v_order.transferred_to_rider_at is not null)
    or (v_order.source = 'partner' and v_order.status = 'being_sourced'
       and v_order.delivery_type in ('delivery', 'campus_delivery', 'hostel_delivery'))
    or (v_order.type = 'errand' and v_order.status = 'placed'
       and v_order.commitment_fee_paid = true and v_order.is_paid)
    or (v_order.type = 'around' and v_order.status = 'being_sourced')
  ) then
    raise exception 'Order is not eligible for acceptance';
  end if;

  update public.orders
     set rider_id       = auth.uid(),
         delivery_stage = 'accepted',
         status         = case
                            when v_order.type = 'errand' then 'being_sourced'
                            when v_order.status = 'being_sourced' then 'being_sourced'
                            else 'out_for_delivery'
                          end
   where id = p_order_id;
end;
$$;

grant execute on function public.accept_order(uuid) to authenticated;

-- ── 5. Completion: one verified PIN -> one completed_at everywhere ───
create or replace function public.verify_group_delivery(p_group_id uuid, p_pin text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider_id uuid := auth.uid();
  v_group    public.delivery_groups%rowtype;
  v_now      timestamptz := now();
begin
  if not public.is_rider() then raise exception 'Unauthorized'; end if;

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

  -- ONE time for the parent, every internal part and the records.
  update public.delivery_groups
     set status = 'completed', delivery_stage = null, completed_at = v_now
   where id = p_group_id;

  update public.orders
     set status = 'completed', delivery_stage = null, completed_at = v_now
   where delivery_group_id = p_group_id and status <> 'cancelled';

  insert into public.delivery_records (rider_id, order_id, completed_at)
  select v_rider_id, id, v_now
    from public.orders
   where delivery_group_id = p_group_id and status = 'completed'
  on conflict (order_id) do nothing;
end;
$$;

grant execute on function public.verify_group_delivery(uuid, text) to authenticated;

create or replace function public.verify_delivery(p_order_id uuid, p_pin text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_now   timestamptz := now();
begin
  if not public.is_rider() then raise exception 'Unauthorized'; end if;

  select * into v_order from public.orders
   where id = p_order_id and rider_id = auth.uid()
   for update;
  if not found then raise exception 'Order not found'; end if;

  if v_order.delivery_group_id is not null then
    raise exception 'Use the group delivery PIN for this order';
  end if;
  if v_order.status in ('completed', 'cancelled') then
    raise exception 'This order is already finished';
  end if;
  -- Errands are completed by the PIN alone (there is no separate
  -- "confirm pickup" step in the app); legacy food keeps its step.
  if v_order.type <> 'errand' and v_order.delivery_stage is distinct from 'picked_up' then
    raise exception 'Confirm pickup before verifying delivery';
  end if;
  if v_order.delivery_pin is null then
    raise exception 'This order has no delivery PIN — contact support';
  end if;
  if p_pin is null or upper(trim(p_pin)) <> upper(v_order.delivery_pin) then
    raise exception 'Incorrect delivery PIN';
  end if;

  update public.orders
     set status = 'completed', delivery_stage = null, completed_at = v_now
   where id = p_order_id;

  insert into public.delivery_records (order_id, rider_id, completed_at)
  values (p_order_id, auth.uid(), v_now)
  on conflict (order_id) do nothing;
end;
$$;

grant execute on function public.verify_delivery(uuid, text) to authenticated;

-- ── 6. Customer info: nothing personal once the job has ended ────────
create or replace function public.get_group_customer_info(p_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group   public.delivery_groups%rowtype;
  v_profile public.profiles%rowtype;
  v_ended   boolean;
begin
  if not public.is_rider() then raise exception 'Unauthorized'; end if;

  select * into v_group from public.delivery_groups where id = p_group_id;
  if not found then raise exception 'Group not found'; end if;
  if v_group.rider_id is distinct from auth.uid() then
    raise exception 'Not your delivery group';
  end if;
  if v_group.status in ('placed', 'commitment_paid') then
    raise exception 'Customer info not available at this stage';
  end if;

  v_ended := v_group.status in ('completed', 'cancelled');
  select * into v_profile from public.profiles where id = v_group.student_id;

  -- Never the matric number, never the delivery PIN. Phone / email /
  -- notes only while the job is live.
  return jsonb_build_object(
    'full_name',         v_profile.full_name,
    'nickname',          v_profile.nickname,
    'phone',             case when v_ended then null else v_profile.phone end,
    'email',             case when v_ended then null else v_profile.email end,
    'delivery_location', v_group.delivery_location,
    'location_details',  case when v_ended then null else v_group.location_details end,
    'student_note',      case when v_ended then null else v_group.student_note end,
    'delivery_pin',      null);
end;
$$;

grant execute on function public.get_group_customer_info(uuid) to authenticated;

create or replace function public.get_customer_info(p_order_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order   public.orders%rowtype;
  v_profile public.profiles%rowtype;
begin
  if not public.is_rider() then raise exception 'Unauthorized'; end if;

  select * into v_order from public.orders
   where id = p_order_id and rider_id = auth.uid();
  if not found then raise exception 'Order not assigned to this rider'; end if;

  select * into v_profile from public.profiles where id = v_order.student_id;

  return json_build_object(
    'full_name', v_profile.full_name,
    'phone',     case when v_order.status in ('completed', 'cancelled')
                      then null else v_profile.phone end);
end;
$$;

grant execute on function public.get_customer_info(uuid) to authenticated;

-- ── 7. Rider-safe lists (one entry per checkout, no fees) ────────────
create or replace function public.rider_job_pool()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_rider() then raise exception 'Unauthorized'; end if;

  return jsonb_build_object(
    'groups', coalesce((
      select jsonb_agg(jsonb_build_object(
               'kind',              'food',
               'id',                g.id,
               'delivery_location', g.delivery_location,
               'student_note',      g.student_note,
               'created_at',        g.created_at,
               'stop_count',        (select count(*) from public.orders o
                                      where o.delivery_group_id = g.id and o.status <> 'cancelled'),
               'vendor_names',      coalesce((select jsonb_agg(distinct v.name)
                                      from public.orders o join public.vendors v on v.id = o.vendor_id
                                     where o.delivery_group_id = g.id and o.status <> 'cancelled'),
                                    '[]'::jsonb)
             ) order by g.created_at desc)
        from public.delivery_groups g
       where g.status = 'commitment_paid' and g.rider_id is null and g.is_paid), '[]'::jsonb),
    'errands', coalesce((
      select jsonb_agg(jsonb_build_object(
               'kind',              'errand',
               'id',                o.id,
               'delivery_location', o.delivery_location,
               'created_at',        o.created_at,
               'category',          er.category,
               'pickup_location',   er.pickup_location,
               'item_description',  er.item_description
             ) order by o.created_at desc)
        from public.orders o
        left join public.errand_requests er on er.order_id = o.id
       where o.type = 'errand' and o.status = 'placed' and o.commitment_fee_paid
         and o.rider_id is null and o.is_paid), '[]'::jsonb));
end;
$$;

grant execute on function public.rider_job_pool() to authenticated;

create or replace function public.rider_active_jobs()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public.is_rider() then raise exception 'Unauthorized'; end if;

  return coalesce((
    select jsonb_agg(j order by (j ->> 'accepted_at') desc nulls last)
      from (
        select jsonb_build_object(
                 'kind',              'food',
                 'id',                g.id,
                 'status',            g.status,
                 'delivery_location', g.delivery_location,
                 'created_at',        g.created_at,
                 'accepted_at',       g.rider_accepted_at,
                 'stop_count',        (select count(*) from public.orders o
                                        where o.delivery_group_id = g.id and o.status <> 'cancelled'),
                 'vendor_names',      coalesce((select jsonb_agg(distinct v.name)
                                        from public.orders o join public.vendors v on v.id = o.vendor_id
                                       where o.delivery_group_id = g.id and o.status <> 'cancelled'),
                                      '[]'::jsonb)) as j
          from public.delivery_groups g
         where g.rider_id = v_uid
           and g.status in ('rider_accepted', 'awaiting_final_payment', 'out_for_delivery')
        union all
        select jsonb_build_object(
                 'kind',              'errand',
                 'id',                o.id,
                 'status',            o.status,
                 'delivery_location', o.delivery_location,
                 'created_at',        o.created_at,
                 'accepted_at',       o.updated_at,
                 'category',          er.category,
                 'pickup_location',   er.pickup_location,
                 'item_description',  er.item_description) as j
          from public.orders o
          left join public.errand_requests er on er.order_id = o.id
         where o.rider_id = v_uid and o.delivery_group_id is null and o.type = 'errand'
           and o.status in ('being_sourced', 'out_for_delivery')
      ) x), '[]'::jsonb);
end;
$$;

grant execute on function public.rider_active_jobs() to authenticated;

-- History: ONE entry per checkout (the parent), completed or cancelled.
create or replace function public.rider_history()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if not public.is_rider() then raise exception 'Unauthorized'; end if;

  return coalesce((
    select jsonb_agg(h order by (h ->> 'ended_at') desc)
      from (
        (select jsonb_build_object(
                  'kind',                'food',
                  'id',                  g.id,
                  'status',              g.status,
                  'ended_at',            coalesce(g.completed_at, g.cancelled_at, g.updated_at),
                  'was_cancelled',       g.status = 'cancelled',
                  'cancelled_by_student', g.cancelled_by_student,
                  'delivery_location',   g.delivery_location,
                  'amount',              g.final_amount,
                  'stop_count',          (select count(*) from public.orders o
                                           where o.delivery_group_id = g.id and o.status <> 'cancelled'),
                  'vendor_names',        coalesce((select jsonb_agg(distinct v.name)
                                           from public.orders o join public.vendors v on v.id = o.vendor_id
                                          where o.delivery_group_id = g.id),
                                         '[]'::jsonb)) as h
           from public.delivery_groups g
          where g.rider_id = v_uid and g.status in ('completed', 'cancelled')
          order by coalesce(g.completed_at, g.cancelled_at, g.updated_at) desc
          limit 100)
        union all
        (select jsonb_build_object(
                  'kind',                'errand',
                  'id',                  o.id,
                  'status',              o.status,
                  'ended_at',            coalesce(o.completed_at, o.cancelled_at, o.updated_at),
                  'was_cancelled',       o.status = 'cancelled',
                  'cancelled_by_student', false,
                  'delivery_location',   o.delivery_location,
                  'amount',              null,
                  'category',            er.category) as h
           from public.orders o
           left join public.errand_requests er on er.order_id = o.id
          where o.rider_id = v_uid and o.delivery_group_id is null and o.type = 'errand'
            and o.status in ('completed', 'cancelled')
          order by coalesce(o.completed_at, o.cancelled_at, o.updated_at) desc
          limit 100)
      ) x), '[]'::jsonb);
end;
$$;

grant execute on function public.rider_history() to authenticated;

-- Read-only details of a finished job: name + location only (no phone,
-- no email, no matric number, no fees).
create or replace function public.rider_history_item(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_group   public.delivery_groups%rowtype;
  v_order   public.orders%rowtype;
  v_name    text;
  v_req     record;
begin
  if not public.is_rider() then raise exception 'Unauthorized'; end if;

  select * into v_group from public.delivery_groups where id = p_id;
  if found then
    if v_group.rider_id is distinct from v_uid
       or v_group.status not in ('completed', 'cancelled') then
      raise exception 'Unauthorized';
    end if;
    select p.full_name into v_name from public.profiles p where p.id = v_group.student_id;
    return jsonb_build_object(
      'kind',                'food',
      'id',                  v_group.id,
      'status',              v_group.status,
      'accepted_at',         v_group.rider_accepted_at,
      'completed_at',        v_group.completed_at,
      'cancelled_at',        v_group.cancelled_at,
      'cancelled_by_student', v_group.cancelled_by_student,
      'customer_name',       v_name,
      'delivery_location',   v_group.delivery_location,
      'amount',              v_group.final_amount);
  end if;

  select * into v_order from public.orders where id = p_id;
  if not found or v_order.rider_id is distinct from v_uid
     or v_order.delivery_group_id is not null
     or v_order.status not in ('completed', 'cancelled') then
    raise exception 'Unauthorized';
  end if;
  select p.full_name into v_name from public.profiles p where p.id = v_order.student_id;
  select category, pickup_location, dropoff_location, item_description
    into v_req from public.errand_requests where order_id = v_order.id;

  return jsonb_build_object(
    'kind',              'errand',
    'id',                v_order.id,
    'status',            v_order.status,
    'completed_at',      v_order.completed_at,
    'cancelled_at',      v_order.cancelled_at,
    'customer_name',     v_name,
    'delivery_location', v_order.delivery_location,
    'category',          v_req.category,
    'pickup_location',   v_req.pickup_location,
    'item_description',  v_req.item_description);
end;
$$;

grant execute on function public.rider_history_item(uuid) to authenticated;

-- Stats count CHECKOUTS (a 3-vendor delivery is 1, not 3) and use the
-- one completed_at, with "today" in Lagos time.
create or replace function public.get_rider_stats()
returns json
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_today date := (now() at time zone 'Africa/Lagos')::date;
  v_stats json;
begin
  if not public.is_rider() then raise exception 'Unauthorized'; end if;

  with done as (
    select completed_at from public.delivery_groups
     where rider_id = v_uid and status = 'completed'
    union all
    select completed_at from public.orders
     where rider_id = v_uid and delivery_group_id is null and status = 'completed'
  )
  select json_build_object(
           'today_completed',
             (select count(*) from done
               where (completed_at at time zone 'Africa/Lagos')::date = v_today),
           'total_completed', (select count(*) from done),
           'active_food',
             (select count(*) from public.delivery_groups g
               where g.rider_id = v_uid
                 and g.status in ('rider_accepted', 'awaiting_final_payment', 'out_for_delivery')),
           'active_errands',
             (select count(*) from public.orders o
               where o.rider_id = v_uid and o.delivery_group_id is null and o.type = 'errand'
                 and o.status in ('being_sourced', 'out_for_delivery')),
           'is_online',
             (select rider_is_online from public.profiles where id = v_uid))
    into v_stats;

  return v_stats;
end;
$$;

grant execute on function public.get_rider_stats() to authenticated;

-- ── 8. Admin dashboard counts: one order per checkout ────────────────
create or replace function public.get_dashboard_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today_start timestamptz := date_trunc('day', now() at time zone 'utc');
  v_stats       jsonb;
begin
  if not (select public.is_super_admin()) then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    -- one per checkout: standalone orders + delivery groups (never the parts)
    'today_orders_total',
      (select count(*) from public.orders
        where is_paid and delivery_group_id is null and created_at >= v_today_start)
    + (select count(*) from public.delivery_groups
        where is_paid and created_at >= v_today_start),
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

notify pgrst, 'reload schema';
