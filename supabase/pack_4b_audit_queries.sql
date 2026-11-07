-- Pack 4B Part B — READ-ONLY audit queries for the LIVE database.
-- Safe to run: every statement is a SELECT. Paste into the Supabase SQL
-- editor and send back the results (they decide which cleanups are safe).

-- 1. Orders sitting in statuses the current flow no longer produces.
select type, status, delivery_type, source, delivery_group_id is not null as is_leg,
       count(*) as n, min(created_at) as oldest, max(created_at) as newest
from public.orders
group by 1,2,3,4,5
order by n desc;

-- 2. Food orders that are NOT part of a delivery group and are not pickup
--    (leftovers from the pre-group delivery flow).
select id, status, delivery_type, source, created_at
from public.orders
where type = 'food' and delivery_group_id is null and delivery_type <> 'pickup'
order by created_at desc limit 50;

-- 3. Legs whose group is missing / groups with no legs.
select 'leg without group' as problem, o.id::text as ref
from public.orders o
where o.delivery_group_id is not null
  and not exists (select 1 from public.delivery_groups g where g.id = o.delivery_group_id)
union all
select 'group without legs', g.id::text
from public.delivery_groups g
where not exists (select 1 from public.orders o where o.delivery_group_id = g.id);

-- 4. Groups whose legs disagree with the group (status / completion time).
select g.id, g.status as group_status, g.completed_at as group_completed_at,
       array_agg(distinct o.status) as leg_statuses,
       count(distinct o.completed_at) as distinct_leg_completed_at
from public.delivery_groups g
join public.orders o on o.delivery_group_id = g.id
group by g.id, g.status, g.completed_at
having (g.status = 'completed' and (count(distinct o.completed_at) <> 1
                                    or bool_or(o.completed_at is distinct from g.completed_at)))
    or (g.status = 'cancelled' and bool_or(o.status <> 'cancelled'));

-- 5. Old sourcing / custom-item data (tables proposed for removal).
select 'order_item_flags' as tbl, count(*) from public.order_item_flags
union all select 'order_custom_items', count(*) from public.order_custom_items;

-- 6. delivery_records: written by the verify functions, read by nothing.
select count(*) as records, count(rating) as with_rating from public.delivery_records;

-- 7. Likely test accounts / test data (names, matric patterns). Review by eye.
select p.id, p.full_name, p.role, p.matric_number, p.created_at,
       (select count(*) from public.orders o where o.student_id = p.id) as orders
from public.profiles p
where p.full_name ilike '%test%' or p.matric_number ilike '%test%'
   or p.matric_number ilike 'MAT/%'
order by p.created_at desc limit 50;

-- 8. Triggers and policies on the order tables (to confirm what is live).
select event_object_table as tbl, trigger_name, action_timing, event_manipulation
from information_schema.triggers
where event_object_schema = 'public' and event_object_table in ('orders','delivery_groups')
order by 1,2;

select tablename, policyname, cmd
from pg_policies
where schemaname = 'public' and tablename in ('orders','delivery_groups','order_items','order_packs')
order by 1,2;

-- 9. Can a rider read the delivery PIN / fees straight from the tables?
--    (Local test says YES for the assigned rider.) Policies that allow it:
select tablename, policyname, qual
from pg_policies
where schemaname = 'public' and tablename in ('orders','delivery_groups')
  and (qual ilike '%is_rider%' or policyname ilike '%rider%');
