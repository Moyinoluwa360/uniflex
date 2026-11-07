-- =====================================================================
-- Pack 4B follow-up (APPROVED by the owner 2026-11-07)
-- =====================================================================
-- Run AFTER supabase/pack_4b.sql. One transaction: if anything fails nothing
-- is changed. Contents:
--   R1-R4  remove the old sourcing / custom-item chain, get_group_items,
--          unused helpers, the kitchen -> group hand-off trigger
--   R6     riders can no longer read delivery_groups / orders / errand_requests
--          directly (they exposed delivery_pin and fee columns). Riders use
--          the rider-safe functions only; live refresh comes from the
--          id-only table rider_job_signals.
--   R7     verify_* stop writing delivery_records, then it is dropped
--   R8     profile order counter counts once per checkout, not per vendor part
--   (R5 is replaced by R6; R9 test data is NOT touched.)
-- =====================================================================

do $$ begin
  if not exists (select 1 from pg_proc where proname = 'get_order_breakdown') then
    raise exception 'Run supabase/pack_4b.sql first.';
  end if;
end $$;

begin;

-- ── R7 (part 1): stop writing delivery_records ───────────────────────
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
  -- Only errands are delivered as a single order. Food deliveries are
  -- completed through verify_group_delivery (the per-part pickup step
  -- was removed in Pack 4B follow-up).
  if v_order.type <> 'errand' then
    raise exception 'Use the group delivery PIN for this order';
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

end;
$$;

grant execute on function public.verify_delivery(uuid, text) to authenticated;

-- ── R8: count a checkout once ────────────────────────────────────────
create or replace function public._after_order_placed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
     set total_orders      = total_orders + case
                               when new.delivery_group_id is not null
                                and exists (select 1 from public.orders o2
                                             where o2.delivery_group_id = new.delivery_group_id
                                               and o2.id <> new.id)
                               then 0 else 1 end,
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
$function$;

-- ── R6: rider live-refresh signal (ids only, no personal/fee data) ───
create table if not exists public.rider_job_signals (
  id         bigint generated always as identity primary key,
  kind       text        not null,
  ref_id     uuid        not null,
  created_at timestamptz not null default now()
);
create index if not exists rider_job_signals_created_idx
  on public.rider_job_signals (created_at);

alter table public.rider_job_signals enable row level security;
revoke all on public.rider_job_signals from anon, authenticated;
grant select on public.rider_job_signals to authenticated;
drop policy if exists "rider_job_signals: riders read" on public.rider_job_signals;
create policy "rider_job_signals: riders read"
  on public.rider_job_signals for select
  using (public.is_rider());

create or replace function public._signal_rider_jobs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_table_name = 'delivery_groups' then
    if tg_op = 'INSERT'
       or old.status is distinct from new.status
       or old.rider_id is distinct from new.rider_id
       or old.final_amount is distinct from new.final_amount then
      insert into public.rider_job_signals (kind, ref_id) values ('food', new.id);
    end if;
  elsif new.delivery_group_id is null and new.type = 'errand' then
    if tg_op = 'INSERT'
       or old.status is distinct from new.status
       or old.rider_id is distinct from new.rider_id then
      insert into public.rider_job_signals (kind, ref_id) values ('errand', new.id);
    end if;
  end if;
  -- keep the table tiny: the signal only means "refetch now"
  delete from public.rider_job_signals where created_at < now() - interval '1 hour';
  return null;
end;
$$;

drop trigger if exists delivery_groups_signal on public.delivery_groups;
create trigger delivery_groups_signal
  after insert or update on public.delivery_groups
  for each row execute function public._signal_rider_jobs();

drop trigger if exists orders_signal on public.orders;
create trigger orders_signal
  after insert or update on public.orders
  for each row execute function public._signal_rider_jobs();

do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and tablename = 'rider_job_signals') then
    execute 'alter publication supabase_realtime add table public.rider_job_signals';
  end if;
end $$;

-- The assigned rider's view of ONE of their food jobs (no PIN, no fees).
create or replace function public.rider_group_detail(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  g public.delivery_groups%rowtype;
  v_over boolean;
begin
  if not public.is_rider() then raise exception 'Unauthorized'; end if;
  select * into g from public.delivery_groups
   where id = p_id and rider_id = auth.uid();
  if not found then return null; end if;
  v_over := g.status in ('completed', 'cancelled');
  return jsonb_build_object(
    'id',                   g.id,
    'status',               g.status,
    'delivery_location',    g.delivery_location,
    'student_note',         case when v_over then null else g.student_note end,
    'cancelled_by_student', coalesce(g.cancelled_by_student, false),
    'final_amount',         g.final_amount,
    'created_at',           g.created_at,
    'completed_at',         g.completed_at,
    'cancelled_at',         g.cancelled_at);
end;
$$;

grant execute on function public.rider_group_detail(uuid) to authenticated;

-- Riders no longer read these tables at all.
drop policy if exists "delivery_groups: rider pool and assigned" on public.delivery_groups;
drop policy if exists "orders: rider read group legs"           on public.orders;
drop policy if exists "orders: rider read own assigned"         on public.orders;
drop policy if exists "orders: rider read pool"                 on public.orders;
drop policy if exists "job_pool_read"                           on public.orders;
drop policy if exists "errand_requests: rider read pool or assigned" on public.errand_requests;

-- ── R1 / R2 / R3 / R4 ────────────────────────────────────────────────
drop function if exists public.get_group_items(uuid);

drop function if exists public.confirm_pickup(uuid);
drop function if exists public.confirm_group_leg_pickup(uuid);
drop function if exists public.confirm_group_leg_sourcing(uuid, numeric);
drop function if exists public.confirm_sourced_items(uuid, numeric);
drop function if exists public.flag_item_unavailable(uuid, uuid, text, integer);
drop function if exists public.add_custom_item(uuid, text, numeric);
drop function if exists public.approve_custom_item(uuid);
drop function if exists public.reject_custom_item(uuid);
drop table    if exists public.order_item_flags;
drop table    if exists public.order_custom_items;

drop function if exists public.cancel_delivery_group_before_accept(uuid);
drop function if exists public.any_riders_available();
drop function if exists public._delivery_fee_from_settings(text);

drop trigger  if exists check_group_ready on public.orders;
drop function if exists public._check_group_ready_after_kitchen();

-- ── R7 (part 2): delivery_records is no longer written or read ───────
drop table if exists public.delivery_records;

notify pgrst, 'reload schema';

commit;
