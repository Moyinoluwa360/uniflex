-- Push: staff alerts (2026-11-12)
--
--   Riders  → "New delivery job" / "New errand job" the moment a paid job
--             lands in the rider pool. Sent to every ACTIVE rider who is
--             ONLINE (profiles.rider_is_online) — offline riders get nothing.
--   Admins  → "New order" when a paid checkout is placed (food delivery,
--             gift, errand, pickup), and "Order cancelled" when one is
--             cancelled. Every active admin (super admin + kitchen staff),
--             except the admin who did the cancelling.
--
-- How: two DEFERRED constraint triggers (they run at COMMIT, after the whole
-- checkout has been written), so they see the finished order — its shops,
-- the gift flag and the errand details — not a half-built one. A failure in
-- here is swallowed: a notification problem must never block a checkout or
-- a cancel. The existing notifications → push-notification path does the
-- actual sending, so nothing changes in the Edge Functions.
--
-- Notification types added: new_job (rider), admin_new_order,
-- admin_order_cancelled (admin).
--
-- Safe to re-run. Apply:
--   supabase db query --linked --project-ref <ref> -f supabase/push_staff_alerts.sql
-- Test (rolled back): supabase/push_staff_alerts_test.sql

-- ── helpers ──────────────────────────────────────────────────────────

create or replace function public._naira(p numeric)
returns text language sql immutable as $$
  select '₦' || trim(to_char(coalesce(p, 0), 'FM999,999,990'))
$$;

-- Queue one notification for every online, active rider.
create or replace function public._notify_online_riders(
  p_title text, p_body text, p_order_id uuid, p_group_id uuid
) returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in
    select id from public.profiles
     where role = 'rider' and is_active and coalesce(rider_is_online, false)
  loop
    perform public.queue_notification(r.id, p_title, p_body, 'new_job',
                                      p_order_id, p_group_id);
  end loop;
end $$;

-- Queue one notification for every active admin except whoever is acting.
create or replace function public._notify_admins(
  p_title text, p_body text, p_type text, p_order_id uuid, p_group_id uuid
) returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in
    select id from public.profiles
     where role = 'admin' and is_active
       and id is distinct from auth.uid()
  loop
    perform public.queue_notification(r.id, p_title, p_body, p_type,
                                      p_order_id, p_group_id);
  end loop;
end $$;

-- Who cancelled, in words, for the admin message.
create or replace function public._cancel_actor(p_student uuid, p_by_student boolean)
returns text language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(p_by_student, false) or auth.uid() = p_student then
    return ' by the customer';
  elsif public.is_admin() then
    return ' by an admin';
  end if;
  return '';
end $$;

-- ── food delivery checkouts (delivery_groups) ────────────────────────

create or replace function public._notify_staff_group()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  g         public.delivery_groups%rowtype;
  v_was     boolean;
  v_now     boolean;
  v_shops   text;
  v_food    numeric;
  v_name    text;
  v_kind    text;
begin
  -- The row as it is at COMMIT (gift flag, rider, status all final).
  select * into g from public.delivery_groups where id = new.id;
  if not found or not coalesce(g.is_paid, false) then return null; end if;

  select string_agg(distinct v.name, ', '), sum(o.total_amount)
    into v_shops, v_food
    from public.orders o join public.vendors v on v.id = o.vendor_id
   where o.delivery_group_id = g.id and o.status <> 'cancelled';
  select coalesce(nickname, full_name, 'A student') into v_name
    from public.profiles where id = g.student_id;
  v_kind := case when g.is_gift then 'Gift delivery' else 'Food delivery' end;

  -- Rider: this event put the job in the pool, and it is still there.
  v_now := new.status = 'commitment_paid' and new.rider_id is null
           and coalesce(new.is_paid, false);
  v_was := tg_op = 'UPDATE' and old.status = 'commitment_paid'
           and old.rider_id is null and coalesce(old.is_paid, false);
  if v_now and not v_was
     and g.status = 'commitment_paid' and g.rider_id is null then
    perform public._notify_online_riders(
      'New delivery job',
      v_kind || ' to ' || coalesce(g.delivery_location, 'campus')
        || coalesce(' · ' || v_shops, '') || '. Tap to view.',
      null, g.id);
  end if;

  -- Admin: new paid checkout.
  if tg_op = 'INSERT' and g.status <> 'cancelled' then
    perform public._notify_admins(
      'New order',
      v_name || ' · ' || v_kind || coalesce(' · ' || v_shops, '')
        || coalesce(' · ' || public._naira(v_food), ''),
      'admin_new_order', null, g.id);
  end if;

  -- Admin: checkout cancelled.
  if tg_op = 'UPDATE' and new.status = 'cancelled'
     and old.status is distinct from 'cancelled' then
    perform public._notify_admins(
      'Order cancelled',
      v_name || '''s ' || lower(v_kind) || ' order was cancelled'
        || public._cancel_actor(g.student_id, g.cancelled_by_student) || '.',
      'admin_order_cancelled', null, g.id);
  end if;

  return null;
exception when others then
  return null;
end $$;

drop trigger if exists delivery_groups_staff_alerts on public.delivery_groups;
create constraint trigger delivery_groups_staff_alerts
  after insert or update on public.delivery_groups
  deferrable initially deferred
  for each row execute function public._notify_staff_group();

-- ── errands, pickup orders, and single shops inside a checkout ───────

create or replace function public._notify_staff_order()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  o       public.orders%rowtype;
  er      record;
  v_was   boolean;
  v_now   boolean;
  v_name  text;
  v_shop  text;
  v_grp   text;
  v_desc  text;
begin
  select * into o from public.orders where id = new.id;
  if not found or not coalesce(o.is_paid, false) then return null; end if;

  select coalesce(nickname, full_name, 'A student') into v_name
    from public.profiles where id = o.student_id;
  select name into v_shop from public.vendors where id = o.vendor_id;
  select coalesce(c.title, r.category) as category, r.pickup_location, r.dropoff_location
    into er
    from public.errand_requests r
    left join public.errand_categories c on c.key = r.category
   where r.order_id = o.id limit 1;

  v_desc := case
    when o.type = 'errand' then
      'Errand' || coalesce(' (' || er.category || ')', '')
    when o.delivery_type = 'pickup' then
      'Pickup order' || coalesce(' from ' || v_shop, '')
    else initcap(coalesce(o.type, 'order'))
  end;

  -- Rider: a paid errand just entered the pool and is still there.
  if o.delivery_group_id is null then
    v_now := new.type = 'errand' and new.status = 'placed'
             and coalesce(new.commitment_fee_paid, false)
             and new.rider_id is null and coalesce(new.is_paid, false);
    v_was := tg_op = 'UPDATE' and old.type = 'errand' and old.status = 'placed'
             and coalesce(old.commitment_fee_paid, false)
             and old.rider_id is null and coalesce(old.is_paid, false);
    if v_now and not v_was and o.status = 'placed' and o.rider_id is null then
      perform public._notify_online_riders(
        'New errand job',
        coalesce(er.category, 'Errand')
          || coalesce(': ' || er.pickup_location, '')
          || coalesce(' → ' || coalesce(er.dropoff_location, o.delivery_location), '')
          || '. Tap to view.',
        o.id, null);
    end if;

    -- Admin: new paid errand / pickup order (food deliveries are announced
    -- once, by the checkout trigger above).
    if tg_op = 'INSERT' and o.status <> 'cancelled' then
      perform public._notify_admins(
        'New order',
        v_name || ' · ' || v_desc || ' · ' || public._naira(o.total_amount),
        'admin_new_order', o.id, null);
    end if;
  end if;

  -- Admin: cancelled.
  if tg_op = 'UPDATE' and new.status = 'cancelled'
     and old.status is distinct from 'cancelled' then
    if o.delivery_group_id is null then
      perform public._notify_admins(
        'Order cancelled',
        v_name || '''s ' || lower(v_desc) || ' was cancelled'
          || public._cancel_actor(o.student_id, false) || '.',
        'admin_order_cancelled', o.id, null);
    else
      -- One shop inside a checkout. If the whole checkout was cancelled the
      -- checkout trigger already said so — don't repeat it per shop.
      select status into v_grp from public.delivery_groups
       where id = o.delivery_group_id;
      if v_grp is distinct from 'cancelled' then
        perform public._notify_admins(
          'Order cancelled',
          coalesce(v_shop, 'One shop') || ' was cancelled in ' || v_name
            || '''s order' || public._cancel_actor(o.student_id, false) || '.',
          'admin_order_cancelled', o.id, o.delivery_group_id);
      end if;
    end if;
  end if;

  return null;
exception when others then
  return null;
end $$;

drop trigger if exists orders_staff_alerts on public.orders;
create constraint trigger orders_staff_alerts
  after insert or update on public.orders
  deferrable initially deferred
  for each row execute function public._notify_staff_order();

-- Internal only: never callable from the app.
revoke all on function public._naira(numeric) from public, anon, authenticated;
revoke all on function public._notify_online_riders(text, text, uuid, uuid) from public, anon, authenticated;
revoke all on function public._notify_admins(text, text, text, uuid, uuid) from public, anon, authenticated;
revoke all on function public._cancel_actor(uuid, boolean) from public, anon, authenticated;
revoke all on function public._notify_staff_group() from public, anon, authenticated;
revoke all on function public._notify_staff_order() from public, anon, authenticated;
