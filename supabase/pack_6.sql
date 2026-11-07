-- =====================================================================
-- Uniflex — Pack 6: Food gifting ("Send as a gift")
-- (additive, safe to run once; re-running is harmless)
--
-- Run AFTER pack_4a.sql, pack_4b.sql, pack_4b_followup.sql, pack_4c.sql.
--
-- A gift is a NORMAL food delivery order whose recipient is somebody else.
-- Nothing new about payment: the sender pays the delivery fee + service
-- charge through the same PIN-gated RPC, later pays/declines the final
-- price, and is the only person who can cancel or contact support.
--
--   1. delivery_groups gets is_gift / gift_recipient_id /
--      gift_recipient_nickname / gift_message  (the "parent order").
--   2. gift_deliveries — a small MIRROR the recipient can read (status,
--      sender nickname, message, delivery PIN, item names — no prices, no
--      fees, no payment data). The recipient has NO access to the sender's
--      order rows; Supabase Realtime works on the mirror.
--   3. lookup_gift_recipient(email) — nickname + masked email only, rate
--      limited (10 / hour / user), refuses yourself.
--   4. create_paid_gift_order(...) — validates the recipient, then calls
--      the unchanged create_paid_delivery_order(), then marks the group as a
--      gift and notifies the recipient.
--   5. Triggers keep the mirror + recipient notifications in sync
--      (on the way / delivered / cancelled).
--   6. Rider: pool + active-job tags (is_gift) and get_group_customer_info()
--      returns BOTH contacts (recipient "Deliver to", sender "Paid by"),
--      only after the rider accepted. Never a matric number.
--   7. The old matric-number send_gift() RPC is switched off (execute
--      revoked). The old gifts table / get_gifts() are left, unused.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Gift columns on the parent order
-- ---------------------------------------------------------------------
alter table public.delivery_groups
  add column if not exists is_gift                  boolean not null default false,
  add column if not exists gift_recipient_id        uuid references public.profiles (id) on delete set null,
  add column if not exists gift_recipient_nickname  text,
  add column if not exists gift_message             text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'delivery_groups_gift_message_len') then
    alter table public.delivery_groups
      add constraint delivery_groups_gift_message_len
      check (gift_message is null or char_length(gift_message) <= 200);
  end if;
end $$;

create index if not exists delivery_groups_gift_recipient_idx
  on public.delivery_groups (gift_recipient_id) where is_gift;

-- ---------------------------------------------------------------------
-- 2. The recipient's mirror
-- ---------------------------------------------------------------------
create table if not exists public.gift_deliveries (
  group_id          uuid primary key references public.delivery_groups (id) on delete cascade,
  recipient_id      uuid not null references public.profiles (id) on delete cascade,
  sender_nickname   text not null,
  message           text,
  -- placed | preparing | on_the_way | delivered | cancelled
  status            text not null default 'placed',
  delivery_pin      text,             -- cleared once delivered / cancelled
  delivery_location text,
  location_details  text,
  items             jsonb not null default '{}'::jsonb,   -- breakdown WITHOUT prices
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index if not exists gift_deliveries_recipient_idx
  on public.gift_deliveries (recipient_id, created_at desc);

alter table public.gift_deliveries enable row level security;

drop policy if exists "gift_deliveries: recipient reads" on public.gift_deliveries;
create policy "gift_deliveries: recipient reads"
  on public.gift_deliveries for select
  to authenticated
  using (recipient_id = auth.uid());

-- read-only for clients; only the SECURITY DEFINER functions below write
revoke all on table public.gift_deliveries from public, anon, authenticated;
grant select on table public.gift_deliveries to authenticated;

do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime'
                        and schemaname = 'public' and tablename = 'gift_deliveries') then
    alter publication supabase_realtime add table public.gift_deliveries;
  end if;
end $$;

-- lookup rate-limit ledger (service functions only)
create table if not exists public.gift_lookup_log (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists gift_lookup_log_idx on public.gift_lookup_log (user_id, created_at desc);
alter table public.gift_lookup_log enable row level security;
revoke all on table public.gift_lookup_log from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------
-- Removes every price-like key from a breakdown (any depth).
create or replace function public._gift_strip_prices(j jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  k text; v jsonb; out jsonb;
begin
  if j is null then return null; end if;
  if jsonb_typeof(j) = 'object' then
    out := '{}'::jsonb;
    for k, v in select * from jsonb_each(j) loop
      if k in ('unit_price', 'line_total', 'price', 'items_total',
               'packs_total', 'vendor_total', 'order_id') then
        continue;
      end if;
      out := out || jsonb_build_object(k, public._gift_strip_prices(v));
    end loop;
    return out;
  elsif jsonb_typeof(j) = 'array' then
    return coalesce((select jsonb_agg(public._gift_strip_prices(e) order by ord)
                       from jsonb_array_elements(j) with ordinality as t(e, ord)),
                    '[]'::jsonb);
  end if;
  return j;
end $$;

create or replace function public._gift_status(p_group_status text)
returns text
language sql
immutable
as $$
  select case p_group_status
    when 'out_for_delivery' then 'on_the_way'
    when 'completed'        then 'delivered'
    when 'cancelled'        then 'cancelled'
    when 'rider_accepted'          then 'preparing'
    when 'awaiting_final_payment'  then 'preparing'
    else 'placed' end;
$$;

-- ---------------------------------------------------------------------
-- 3. Recipient lookup — nickname + masked email, nothing else
-- ---------------------------------------------------------------------
create or replace function public.lookup_gift_recipient(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text := lower(trim(coalesce(p_email, '')));
  v_count int;
  r       record;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;

  -- One lookup at a time per user, so the count below cannot be raced.
  perform pg_advisory_xact_lock(hashtextextended('gift_lookup:' || v_uid::text, 0));
  select count(*) into v_count from public.gift_lookup_log
   where user_id = v_uid and created_at > now() - interval '1 hour';
  if v_count >= 10 then
    return jsonb_build_object('ok', false, 'reason', 'RATE_LIMITED');
  end if;
  insert into public.gift_lookup_log (user_id) values (v_uid);

  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND');
  end if;

  select id, nickname, email into r
    from public.profiles
   where lower(email) = v_email
     and role = 'student' and onboarding_complete and is_active
   limit 1;
  if not found or r.nickname is null then
    return jsonb_build_object('ok', false, 'reason', 'NOT_FOUND');
  end if;
  if r.id = v_uid then
    return jsonb_build_object('ok', false, 'reason', 'SELF');
  end if;

  return jsonb_build_object(
    'ok', true,
    'nickname', r.nickname,
    'masked_email', left(r.email, 1) || '***@' || split_part(r.email, '@', 2));
end $$;

-- ---------------------------------------------------------------------
-- 4. Publish a gift to the recipient (mirror row + first notification)
-- ---------------------------------------------------------------------
create or replace function public._gift_publish(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  g        public.delivery_groups%rowtype;
  v_sender text;
  v_items  jsonb;
  v_body   text;
begin
  select * into g from public.delivery_groups where id = p_group_id;
  if not found or not g.is_gift or g.gift_recipient_id is null then return; end if;

  select coalesce(nullif(nickname, ''), 'Someone') into v_sender
    from public.profiles where id = g.student_id;

  select jsonb_build_object(
           'order_id', g.id, 'kind', 'delivery',
           'vendors', coalesce(jsonb_agg(public._gift_strip_prices(public._breakdown_leg(o.id))
                                 order by o.created_at, o.id), '[]'::jsonb))
    into v_items
    from public.orders o
   where o.delivery_group_id = g.id and o.status <> 'cancelled';

  insert into public.gift_deliveries
    (group_id, recipient_id, sender_nickname, message, status, delivery_pin,
     delivery_location, location_details, items)
  values
    (g.id, g.gift_recipient_id, v_sender, g.gift_message,
     public._gift_status(g.status), g.delivery_pin,
     g.delivery_location, g.location_details, coalesce(v_items, '{}'::jsonb))
  on conflict (group_id) do nothing;

  v_body := v_sender || ' sent you a food gift 🎁';
  if g.gift_message is not null then
    v_body := v_body || ': "' || g.gift_message || '"';
  end if;
  perform public.queue_notification(
    g.gift_recipient_id, 'You got a food gift 🎁', v_body, 'gift_received',
    null, g.id);
end $$;

-- ---------------------------------------------------------------------
-- 5. THE gift order: validate the recipient, then the normal delivery order
-- ---------------------------------------------------------------------
create or replace function public.create_paid_gift_order(
  p_idempotency_key      uuid,
  p_pin                  text,
  p_legs                 jsonb,
  p_delivery_location_id uuid,
  p_location_details     text,
  p_student_note         text,
  p_recipient_email      text,
  p_gift_message         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_sender   uuid := auth.uid();
  v_existing jsonb;
  v_email    text := lower(trim(coalesce(p_recipient_email, '')));
  v_msg      text := nullif(trim(coalesce(p_gift_message, '')), '');
  rec        record;
  v_result   jsonb;
  v_group    uuid;
begin
  if v_sender is null then raise exception 'Unauthorized'; end if;
  if p_idempotency_key is null then raise exception 'IDEMPOTENCY_KEY_REQUIRED'; end if;

  -- Same retry rule as every other order: a repeated key returns the order
  -- that already exists.
  select result into v_existing
    from public.order_payment_attempts
   where idempotency_key = p_idempotency_key and student_id = v_sender;
  if found then
    return v_existing || jsonb_build_object('replayed', true);
  end if;

  if v_msg is not null and char_length(v_msg) > 200 then
    raise exception 'GIFT_MESSAGE_TOO_LONG';
  end if;

  -- Re-validate the recipient now; never trust the earlier lookup.
  select id, nickname into rec
    from public.profiles
   where lower(email) = v_email
     and role = 'student' and onboarding_complete and is_active
   limit 1;
  if not found or rec.nickname is null then raise exception 'GIFT_RECIPIENT_NOT_FOUND'; end if;
  if rec.id = v_sender then raise exception 'GIFT_SELF'; end if;

  -- The normal paid delivery order (PIN, amounts, wallet, group, legs).
  v_result := public.create_paid_delivery_order(
    p_idempotency_key, p_pin, p_legs, p_delivery_location_id,
    p_location_details, p_student_note);

  -- A wrong PIN etc. is RETURNED, not raised: nothing was created.
  if v_result ? 'error' or coalesce((v_result ->> 'replayed')::boolean, false) then
    return v_result;
  end if;

  v_group := (v_result ->> 'group_id')::uuid;

  update public.delivery_groups
     set is_gift = true,
         gift_recipient_id = rec.id,
         gift_recipient_nickname = rec.nickname,
         gift_message = v_msg
   where id = v_group;

  perform public._gift_publish(v_group);

  -- "Gifter" badge now goes to people who really send a gift.
  insert into public.user_achievements (user_id, achievement_id)
  select v_sender, id from public.achievements where code = 'gifter'
  on conflict (user_id, achievement_id) do nothing;

  v_result := v_result || jsonb_build_object(
    'is_gift', true, 'recipient_nickname', rec.nickname);
  update public.order_payment_attempts
     set result = v_result
   where idempotency_key = p_idempotency_key and student_id = v_sender;
  return v_result;
end $$;

-- ---------------------------------------------------------------------
-- 6. Keep the mirror + the recipient's notifications in step
-- ---------------------------------------------------------------------
create or replace function public._gift_sync_group()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_sender text;
begin
  if not new.is_gift or new.gift_recipient_id is null then return new; end if;

  v_status := public._gift_status(new.status);
  update public.gift_deliveries
     set status = v_status,
         delivery_pin = case when v_status in ('delivered', 'cancelled')
                             then null else new.delivery_pin end,
         updated_at = now()
   where group_id = new.id;

  if new.status is distinct from old.status then
    select coalesce(nullif(nickname, ''), 'Someone') into v_sender
      from public.profiles where id = new.student_id;

    if new.status = 'out_for_delivery' then
      perform public.queue_notification(
        new.gift_recipient_id, 'Your gift is on its way 🎁',
        'Your food gift from ' || v_sender || ' is on its way. '
          || 'Have your delivery PIN ready.',
        'gift_on_the_way', null, new.id);
    elsif new.status = 'completed' then
      perform public.queue_notification(
        new.gift_recipient_id, 'Gift delivered 🎁',
        'Your food gift from ' || v_sender || ' has been delivered. Enjoy!',
        'gift_delivered', null, new.id);
    elsif new.status = 'cancelled' then
      perform public.queue_notification(
        new.gift_recipient_id, 'Gift cancelled',
        'The food gift from ' || v_sender || ' was cancelled.',
        'gift_cancelled', null, new.id);
    end if;
  end if;
  return new;
end $$;

drop trigger if exists delivery_groups_gift_sync on public.delivery_groups;
create trigger delivery_groups_gift_sync
  after update on public.delivery_groups
  for each row execute function public._gift_sync_group();

-- ---------------------------------------------------------------------
-- 7. Rider: tags + both contacts (after accepting only)
-- ---------------------------------------------------------------------
create or replace function public.get_group_customer_info(p_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group   public.delivery_groups%rowtype;
  v_profile public.profiles%rowtype;
  v_rec     public.profiles%rowtype;
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
  -- notes only while the job is live. For a gift the top-level fields stay
  -- the PAYER (sender); "gift" adds the recipient to deliver to.
  return jsonb_build_object(
    'full_name',         v_profile.full_name,
    'nickname',          v_profile.nickname,
    'phone',             case when v_ended then null else v_profile.phone end,
    'email',             case when v_ended then null else v_profile.email end,
    'delivery_location', v_group.delivery_location,
    'location_details',  case when v_ended then null else v_group.location_details end,
    'student_note',      case when v_ended then null else v_group.student_note end,
    'delivery_pin',      null,
    'is_gift',           v_group.is_gift,
    'gift', case when v_group.is_gift and v_group.gift_recipient_id is not null then
      (select jsonb_build_object(
                'recipient', jsonb_build_object(
                  'full_name',        rp.full_name,
                  'nickname',         rp.nickname,
                  'phone',            case when v_ended then null else rp.phone end,
                  'email',            case when v_ended then null else rp.email end,
                  'location_details', case when v_ended then null else v_group.location_details end),
                'sender', jsonb_build_object(
                  'full_name', v_profile.full_name,
                  'nickname',  v_profile.nickname,
                  'phone',     case when v_ended then null else v_profile.phone end,
                  'email',     case when v_ended then null else v_profile.email end))
         from public.profiles rp where rp.id = v_group.gift_recipient_id)
      else null end);
end $$;

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
               'is_gift',           g.is_gift,
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
end $$;

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
                 'is_gift',           g.is_gift,
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
end $$;

-- ---------------------------------------------------------------------
-- 8. Switch off the old matric-number gift RPC (it was never wired to a
--    screen). Old tables / get_gifts() are left in place, unused.
-- ---------------------------------------------------------------------
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname = 'send_gift'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 9. Grants
-- ---------------------------------------------------------------------
revoke all on function public._gift_strip_prices(jsonb) from public, anon, authenticated;
revoke all on function public._gift_status(text)        from public, anon, authenticated;
revoke all on function public._gift_publish(uuid)       from public, anon, authenticated;
revoke all on function public._gift_sync_group()        from public, anon, authenticated;

revoke all on function public.lookup_gift_recipient(text) from public, anon;
grant execute on function public.lookup_gift_recipient(text) to authenticated;

revoke all on function public.create_paid_gift_order(
  uuid, text, jsonb, uuid, text, text, text, text) from public, anon;
grant execute on function public.create_paid_gift_order(
  uuid, text, jsonb, uuid, text, text, text, text) to authenticated;
