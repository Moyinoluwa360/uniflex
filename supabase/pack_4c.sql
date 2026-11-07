-- =====================================================================
-- Uniflex — Pack 4C (additive, safe to run once; re-running is harmless)
--
-- Run AFTER pack_4a.sql, pack_4b.sql and pack_4b_followup.sql.
--
--   1. admin_profile_basics(uuid[])  — Admin can read names/phones of the
--      students and riders on orders and chats (profiles RLS is
--      "read own only", which is why Admin saw blank names).
--   2. Support WhatsApp number       — app_settings key 'support_whatsapp',
--      get_support_whatsapp() for students, admin_set_support_whatsapp().
--   3. delivery_groups.final_paid_at — the moment the final FOOD payment
--      was made, so "food payments today/week/month" can be dated.
--   4. _stat_entries()               — ONE row per checkout (paid only):
--      the single source for every number on the dashboard + analytics.
--   5. get_dashboard_stats()         — rebuilt on _stat_entries().
--   6. get_admin_analytics()         — new; replaces the client-side maths.
--   7. Realtime: nothing to add (orders + delivery_groups are published).
--
-- Days/weeks/months are Africa/Lagos (week starts Monday).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Admin profile basics
-- ---------------------------------------------------------------------
drop function if exists public.admin_profile_basics(uuid[]);
create function public.admin_profile_basics(p_ids uuid[])
returns table (
  id        uuid,
  role      text,
  nickname  text,
  full_name text,
  phone     text,
  email     text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (select public.is_admin()) then
    raise exception 'Unauthorized';
  end if;
  return query
    select p.id, p.role, p.nickname, p.full_name, p.phone, p.email
      from public.profiles p
     where p.id = any (coalesce(p_ids, '{}'::uuid[]));
end;
$$;

revoke all on function public.admin_profile_basics(uuid[]) from public, anon;
grant execute on function public.admin_profile_basics(uuid[]) to authenticated;


-- ---------------------------------------------------------------------
-- 2. Support WhatsApp number (one setting, international digits only)
-- ---------------------------------------------------------------------
-- Stored as digits with the country code, e.g. 2348031234567.
-- Accepts 08031234567, 0803 123 4567, +234 803 123 4567, 2348031234567.
create or replace function public._normalize_ng_phone(p_raw text)
returns text
language plpgsql
immutable
as $$
declare
  v text := regexp_replace(coalesce(p_raw, ''), '[\s\-\(\)\.\+]', '', 'g');
begin
  if v = '' then return null; end if;
  if v !~ '^[0-9]+$' then
    raise exception 'INVALID_PHONE';
  end if;
  if v ~ '^0[0-9]{10}$' then
    return '234' || substr(v, 2);
  elsif v ~ '^234[0-9]{10}$' then
    return v;
  end if;
  raise exception 'INVALID_PHONE';
end;
$$;

create or replace function public.get_support_whatsapp()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select nullif(trim(value), '')
    from public.app_settings where key = 'support_whatsapp';
$$;

revoke all on function public.get_support_whatsapp() from public, anon;
grant execute on function public.get_support_whatsapp() to authenticated;

-- Empty/blank input clears the number (WhatsApp option then hides).
create or replace function public.admin_set_support_whatsapp(p_number text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_digits text;
begin
  if not (select public.is_super_admin()) then
    raise exception 'Unauthorized';
  end if;

  v_digits := public._normalize_ng_phone(p_number);

  if v_digits is null then
    delete from public.app_settings where key = 'support_whatsapp';
    return null;
  end if;

  insert into public.app_settings (key, value, updated_at, updated_by)
  values ('support_whatsapp', v_digits, now(), auth.uid())
  on conflict (key) do update
    set value = excluded.value,
        updated_at = excluded.updated_at,
        updated_by = excluded.updated_by;
  return v_digits;
end;
$$;

revoke all on function public.admin_set_support_whatsapp(text) from public, anon;
grant execute on function public.admin_set_support_whatsapp(text) to authenticated;


-- ---------------------------------------------------------------------
-- 3. delivery_groups.final_paid_at
-- ---------------------------------------------------------------------
alter table public.delivery_groups add column if not exists final_paid_at timestamptz;

-- Back-fill: we never recorded when the final payment happened, so use the
-- best evidence we have (completion time, else last update). Done with the
-- updated_at trigger off so history is not rewritten.
alter table public.delivery_groups disable trigger delivery_groups_updated_at;
update public.delivery_groups
   set final_paid_at = coalesce(completed_at, updated_at)
 where final_payment_paid and final_paid_at is null;
alter table public.delivery_groups enable trigger delivery_groups_updated_at;

create or replace function public._stamp_final_paid_at()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' and old.final_paid_at is not null then
    new.final_paid_at := old.final_paid_at;           -- immutable once set
  elsif new.final_payment_paid and new.final_paid_at is null then
    new.final_paid_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists delivery_groups_final_paid_ts on public.delivery_groups;
create trigger delivery_groups_final_paid_ts
  before insert or update on public.delivery_groups
  for each row execute function public._stamp_final_paid_at();


-- ---------------------------------------------------------------------
-- 4. _stat_entries(): one row per checkout, paid only
-- ---------------------------------------------------------------------
-- kind:
--   group   a delivery checkout (parent delivery_groups row; its vendor
--           parts are never rows here)
--   errand  a standalone errand order
--   pickup  a standalone pickup order
--   other   any other standalone order (legacy)
--
-- fee_amount / fee_at     delivery or commitment fee + service charge,
--                         charged when the checkout was created. Delivery
--                         and errand fees are non-refundable, so cancelled
--                         ones still count. A cancelled pickup counts 0
--                         (it is refunded in full).
-- food_amount / food_at   money paid for the FOOD itself: the final payment
--                         of a delivery group (dated final_paid_at), or a
--                         pickup order's total (dated created_at, 0 when
--                         cancelled because it is refunded).
create or replace function public._stat_entries()
returns table (
  id            uuid,
  kind          text,
  status        text,
  created_at    timestamptz,
  completed_at  timestamptz,
  cancelled_at  timestamptz,
  rider_id      uuid,
  student_id    uuid,
  fee_amount    numeric,
  fee_at        timestamptz,
  food_amount   numeric,
  food_at       timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select g.id, 'group'::text, g.status, g.created_at, g.completed_at,
         g.cancelled_at, g.rider_id, g.student_id,
         coalesce(g.commitment_fee_total, 0) + coalesce(g.service_charge, 0),
         g.created_at,
         case when g.final_payment_paid then coalesce(g.final_amount, 0) else 0 end,
         g.final_paid_at
    from public.delivery_groups g
   where g.is_paid
  union all
  select o.id,
         case when o.type = 'errand' then 'errand'
              when coalesce(o.delivery_type, 'pickup') = 'pickup' then 'pickup'
              else 'other' end,
         o.status, o.created_at, o.completed_at, o.cancelled_at,
         o.rider_id, o.student_id,
         case when o.type <> 'errand'
                   and coalesce(o.delivery_type, 'pickup') = 'pickup'
                   and o.status = 'cancelled' then 0
              else coalesce(o.commitment_fee_amount, 0) + coalesce(o.service_charge, 0) end,
         o.created_at,
         case when o.type = 'errand' then 0
              when coalesce(o.delivery_type, 'pickup') = 'pickup'
                then case when o.status = 'cancelled' then 0
                          else coalesce(o.total_amount, 0) end
              when o.final_payment_paid then coalesce(o.final_amount, 0)
              else 0 end,
         case when coalesce(o.delivery_type, 'pickup') = 'pickup'
                then o.created_at
              else coalesce(o.completed_at, o.updated_at) end
    from public.orders o
   where o.is_paid and o.delivery_group_id is null;
$$;

revoke all on function public._stat_entries() from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 5. get_dashboard_stats()
-- ---------------------------------------------------------------------
create or replace function public.get_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz     constant text := 'Africa/Lagos';
  v_day    timestamptz := date_trunc('day',   now() at time zone v_tz) at time zone v_tz;
  v_week   timestamptz := date_trunc('week',  now() at time zone v_tz) at time zone v_tz;
  v_month  timestamptz := date_trunc('month', now() at time zone v_tz) at time zone v_tz;
  v_stats  jsonb;
begin
  if not (select public.is_super_admin()) then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'orders_today',      count(*) filter (where e.created_at   >= v_day),
    'pending_count',     count(*) filter (where e.status not in ('completed', 'cancelled')),
    'completed_today',   count(*) filter (where e.status = 'completed' and e.completed_at >= v_day),
    'cancelled_today',   count(*) filter (where e.status = 'cancelled' and e.cancelled_at >= v_day),
    'fees_today',        coalesce(sum(e.fee_amount)  filter (where e.fee_at  >= v_day),   0),
    'fees_week',         coalesce(sum(e.fee_amount)  filter (where e.fee_at  >= v_week),  0),
    'fees_month',        coalesce(sum(e.fee_amount)  filter (where e.fee_at  >= v_month), 0),
    'food_today',        coalesce(sum(e.food_amount) filter (where e.food_at >= v_day),   0),
    'food_week',         coalesce(sum(e.food_amount) filter (where e.food_at >= v_week),  0),
    'food_month',        coalesce(sum(e.food_amount) filter (where e.food_at >= v_month), 0),
    'by_status', jsonb_build_object(
      'active',    count(*) filter (where e.status not in ('completed', 'cancelled')),
      'completed', count(*) filter (where e.status = 'completed' and e.completed_at >= v_day),
      'cancelled', count(*) filter (where e.status = 'cancelled' and e.cancelled_at >= v_day))
  )
  into v_stats
  from public._stat_entries() e;

  return v_stats;
end;
$$;

revoke all on function public.get_dashboard_stats() from public, anon;
grant execute on function public.get_dashboard_stats() to authenticated;


-- ---------------------------------------------------------------------
-- 6. get_admin_analytics()
-- ---------------------------------------------------------------------
-- Period = this Lagos month unless noted. Completion rate = completed ÷
-- (completed + cancelled) among checkouts that FINISHED this month.
create or replace function public.get_admin_analytics()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz     constant text := 'Africa/Lagos';
  v_day    timestamptz := date_trunc('day',   now() at time zone v_tz) at time zone v_tz;
  v_week   timestamptz := date_trunc('week',  now() at time zone v_tz) at time zone v_tz;
  v_month  timestamptz := date_trunc('month', now() at time zone v_tz) at time zone v_tz;
  v_core   jsonb;
  v_status jsonb;
  v_items  jsonb;
  v_riders jsonb;
  v_users  jsonb;
  v_done   integer;
  v_cancel integer;
begin
  if not (select public.is_super_admin()) then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    'orders_today',     count(*) filter (where e.created_at >= v_day),
    'orders_week',      count(*) filter (where e.created_at >= v_week),
    'orders_month',     count(*) filter (where e.created_at >= v_month),
    'completed_today',  count(*) filter (where e.status = 'completed' and e.completed_at >= v_day),
    'completed_week',   count(*) filter (where e.status = 'completed' and e.completed_at >= v_week),
    'completed_month',  count(*) filter (where e.status = 'completed' and e.completed_at >= v_month),
    'cancelled_today',  count(*) filter (where e.status = 'cancelled' and e.cancelled_at >= v_day),
    'cancelled_week',   count(*) filter (where e.status = 'cancelled' and e.cancelled_at >= v_week),
    'cancelled_month',  count(*) filter (where e.status = 'cancelled' and e.cancelled_at >= v_month),
    'fees_today',  coalesce(sum(e.fee_amount)  filter (where e.fee_at  >= v_day),   0),
    'fees_week',   coalesce(sum(e.fee_amount)  filter (where e.fee_at  >= v_week),  0),
    'fees_month',  coalesce(sum(e.fee_amount)  filter (where e.fee_at  >= v_month), 0),
    'food_today',  coalesce(sum(e.food_amount) filter (where e.food_at >= v_day),   0),
    'food_week',   coalesce(sum(e.food_amount) filter (where e.food_at >= v_week),  0),
    'food_month',  coalesce(sum(e.food_amount) filter (where e.food_at >= v_month), 0)),
    count(*) filter (where e.status = 'completed' and e.completed_at >= v_month),
    count(*) filter (where e.status = 'cancelled' and e.cancelled_at >= v_month)
  into v_core, v_done, v_cancel
  from public._stat_entries() e;

  -- Orders created this month, by their current status.
  select coalesce(jsonb_object_agg(s.status, s.n), '{}'::jsonb)
    into v_status
    from (select e.status, count(*) as n
            from public._stat_entries() e
           where e.created_at >= v_month
           group by e.status) s;

  -- Top sellers: items on checkouts COMPLETED this month. Each item line
  -- belongs to exactly one vendor part, so a multi-vendor checkout never
  -- double counts.
  select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'quantity', t.qty)
                            order by t.qty desc, t.name), '[]'::jsonb)
    into v_items
    from (select min(oi.product_name) as name, sum(oi.quantity)::int as qty
            from public.order_items oi
            join public.orders o on o.id = oi.order_id
            join public._stat_entries() e
              on e.id = coalesce(o.delivery_group_id, o.id)
           where e.status = 'completed' and e.completed_at >= v_month
           group by coalesce(oi.product_id::text, oi.product_name)
           order by qty desc, name
           limit 10) t;

  -- Rider performance: completed checkouts this month, once per checkout.
  select coalesce(jsonb_agg(jsonb_build_object(
           'rider_id', r.rider_id,
           'name', coalesce(nullif(trim(p.nickname), ''), nullif(trim(p.full_name), ''), 'Rider'),
           'full_name', p.full_name,
           'completed', r.n) order by r.n desc, p.nickname), '[]'::jsonb)
    into v_riders
    from (select e.rider_id, count(*)::int as n
            from public._stat_entries() e
           where e.status = 'completed' and e.completed_at >= v_month
             and e.rider_id is not null
           group by e.rider_id
           order by n desc
           limit 10) r
    left join public.profiles p on p.id = r.rider_id;

  select jsonb_build_object(
           'students', count(*) filter (where role = 'student'),
           'riders',   count(*) filter (where role = 'rider'))
    into v_users from public.profiles;

  return v_core || jsonb_build_object(
    'completion_rate',
      case when v_done + v_cancel = 0 then null
           else round(v_done::numeric * 100 / (v_done + v_cancel), 1) end,
    'by_status', v_status,
    'top_items', v_items,
    'rider_performance', v_riders,
    'users', v_users);
end;
$$;

revoke all on function public.get_admin_analytics() from public, anon;
grant execute on function public.get_admin_analytics() to authenticated;

notify pgrst, 'reload schema';
