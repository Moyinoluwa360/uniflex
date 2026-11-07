-- =====================================================================
-- Pack 4C — side-by-side metric check (read-only; nothing is changed)
--
-- Paste into the Supabase SQL editor AFTER pack_4c.sql. For every number on
-- the Admin dashboard / Analytics screen it shows:
--   raw_tables    computed straight from delivery_groups + orders, with
--                 hand-written filters (does NOT use pack_4c's helper)
--   via_function  what get_dashboard_stats() / get_admin_analytics() return
--   match         true when they agree
-- Every row should say match = true. If one says false, send it to Claude.
--
-- The SQL editor has no logged-in user, so the script pretends to be the
-- first active super-admin for this one transaction, then rolls back.
-- Days/weeks/months are Africa/Lagos (week starts Monday).
-- =====================================================================
begin;

select set_config('request.jwt.claims',
  json_build_object(
    'sub', (select id from public.profiles
             where role = 'admin' and is_active
               and (admin_tier is null or admin_tier = 'super_admin')
             order by created_at limit 1),
    'role', 'authenticated')::text, true);

with b as (
  select date_trunc('day',   now() at time zone 'Africa/Lagos') at time zone 'Africa/Lagos' as d,
         date_trunc('week',  now() at time zone 'Africa/Lagos') at time zone 'Africa/Lagos' as w,
         date_trunc('month', now() at time zone 'Africa/Lagos') at time zone 'Africa/Lagos' as m
),
dash as (select public.get_dashboard_stats() as j),
ana  as (select public.get_admin_analytics() as j),
raw as (
  select
    -- one entry per checkout: paid delivery groups + paid standalone orders
    (select count(*) from public.delivery_groups g, b where g.is_paid and g.created_at >= b.d)
  + (select count(*) from public.orders o, b where o.is_paid and o.delivery_group_id is null and o.created_at >= b.d)
      as orders_today,
    (select count(*) from public.delivery_groups g where g.is_paid and g.status not in ('completed','cancelled'))
  + (select count(*) from public.orders o where o.is_paid and o.delivery_group_id is null and o.status not in ('completed','cancelled'))
      as pending,
    (select count(*) from public.delivery_groups g, b where g.is_paid and g.status = 'completed' and g.completed_at >= b.d)
  + (select count(*) from public.orders o, b where o.is_paid and o.delivery_group_id is null and o.status = 'completed' and o.completed_at >= b.d)
      as completed_today,
    (select count(*) from public.delivery_groups g, b where g.is_paid and g.status = 'cancelled' and g.cancelled_at >= b.d)
  + (select count(*) from public.orders o, b where o.is_paid and o.delivery_group_id is null and o.status = 'cancelled' and o.cancelled_at >= b.d)
      as cancelled_today,
    -- fees: group commitment + service; standalone commitment + service
    -- (a cancelled PICKUP is refunded in full, so it counts 0)
    (select coalesce(sum(commitment_fee_total + service_charge),0) from public.delivery_groups g, b where g.is_paid and g.created_at >= b.d)
  + (select coalesce(sum(commitment_fee_amount + service_charge),0) from public.orders o, b
      where o.is_paid and o.delivery_group_id is null and o.created_at >= b.d
        and not (o.type <> 'errand' and coalesce(o.delivery_type,'pickup') = 'pickup' and o.status = 'cancelled'))
      as fees_today,
    (select coalesce(sum(commitment_fee_total + service_charge),0) from public.delivery_groups g, b where g.is_paid and g.created_at >= b.w)
  + (select coalesce(sum(commitment_fee_amount + service_charge),0) from public.orders o, b
      where o.is_paid and o.delivery_group_id is null and o.created_at >= b.w
        and not (o.type <> 'errand' and coalesce(o.delivery_type,'pickup') = 'pickup' and o.status = 'cancelled'))
      as fees_week,
    (select coalesce(sum(commitment_fee_total + service_charge),0) from public.delivery_groups g, b where g.is_paid and g.created_at >= b.m)
  + (select coalesce(sum(commitment_fee_amount + service_charge),0) from public.orders o, b
      where o.is_paid and o.delivery_group_id is null and o.created_at >= b.m
        and not (o.type <> 'errand' and coalesce(o.delivery_type,'pickup') = 'pickup' and o.status = 'cancelled'))
      as fees_month,
    -- food payments: final payment of groups + paid, non-cancelled pickups
    (select coalesce(sum(final_amount),0) from public.delivery_groups g, b where g.is_paid and g.final_payment_paid and g.final_paid_at >= b.d)
  + (select coalesce(sum(total_amount),0) from public.orders o, b where o.is_paid and o.delivery_group_id is null and o.type <> 'errand' and coalesce(o.delivery_type,'pickup') = 'pickup' and o.status <> 'cancelled' and o.created_at >= b.d)
      as food_today,
    (select coalesce(sum(final_amount),0) from public.delivery_groups g, b where g.is_paid and g.final_payment_paid and g.final_paid_at >= b.w)
  + (select coalesce(sum(total_amount),0) from public.orders o, b where o.is_paid and o.delivery_group_id is null and o.type <> 'errand' and coalesce(o.delivery_type,'pickup') = 'pickup' and o.status <> 'cancelled' and o.created_at >= b.w)
      as food_week,
    (select coalesce(sum(final_amount),0) from public.delivery_groups g, b where g.is_paid and g.final_payment_paid and g.final_paid_at >= b.m)
  + (select coalesce(sum(total_amount),0) from public.orders o, b where o.is_paid and o.delivery_group_id is null and o.type <> 'errand' and coalesce(o.delivery_type,'pickup') = 'pickup' and o.status <> 'cancelled' and o.created_at >= b.m)
      as food_month
)
select m.metric, m.raw_tables, m.via_function,
       (m.raw_tables is not distinct from m.via_function) as match
from (
  select 'orders_today'    as metric, raw.orders_today::numeric    as raw_tables, (dash.j->>'orders_today')::numeric    as via_function from raw, dash union all
  select 'pending',          raw.pending,          (dash.j->>'pending_count')::numeric   from raw, dash union all
  select 'completed_today',  raw.completed_today,  (dash.j->>'completed_today')::numeric from raw, dash union all
  select 'cancelled_today',  raw.cancelled_today,  (dash.j->>'cancelled_today')::numeric from raw, dash union all
  select 'fees_today',       raw.fees_today,       (dash.j->>'fees_today')::numeric      from raw, dash union all
  select 'fees_week',        raw.fees_week,        (dash.j->>'fees_week')::numeric       from raw, dash union all
  select 'fees_month',       raw.fees_month,       (dash.j->>'fees_month')::numeric      from raw, dash union all
  select 'food_today',       raw.food_today,       (dash.j->>'food_today')::numeric      from raw, dash union all
  select 'food_week',        raw.food_week,        (dash.j->>'food_week')::numeric       from raw, dash union all
  select 'food_month',       raw.food_month,       (dash.j->>'food_month')::numeric      from raw, dash union all
  -- the analytics screen must agree with the dashboard
  select 'analytics orders_today',    raw.orders_today,    (ana.j->>'orders_today')::numeric    from raw, ana union all
  select 'analytics completed_today', raw.completed_today, (ana.j->>'completed_today')::numeric from raw, ana union all
  select 'analytics cancelled_today', raw.cancelled_today, (ana.j->>'cancelled_today')::numeric from raw, ana union all
  select 'analytics fees_month',      raw.fees_month,      (ana.j->>'fees_month')::numeric      from raw, ana union all
  select 'analytics food_month',      raw.food_month,      (ana.j->>'food_month')::numeric      from raw, ana
) m;

rollback;
