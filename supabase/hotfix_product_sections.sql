-- ==========================================================================
-- ROUND 7 — Complete SQL (with hotfix applied)
-- ==========================================================================
-- Paste this entire block into the Supabase SQL Editor and run once.
-- Everything is idempotent — safe to re-run.
--
-- HOTFIX: The original Round 7 SQL added the products_subsection_only_for_food
-- CHECK constraint BEFORE backfilling existing rows, causing a check_violation
-- that rolled back the entire transaction. This file puts the backfill FIRST,
-- then the constraint.
-- ==========================================================================


-- ─────────────────────────────────────────────────────────────────────
-- 7-A. delivery_settings — admin-editable delivery fees
-- ─────────────────────────────────────────────────────────────────────
create table if not exists public.delivery_settings (
  key   text primary key,
  value numeric(10,2) not null
);
alter table public.delivery_settings enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'delivery_settings_read' and tablename = 'delivery_settings') then
    create policy delivery_settings_read on public.delivery_settings
      for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where policyname = 'delivery_settings_admin_write' and tablename = 'delivery_settings') then
    create policy delivery_settings_admin_write on public.delivery_settings
      for all to authenticated using (public.is_admin())
      with check (public.is_admin());
  end if;
end $$;

insert into public.delivery_settings (key, value) values
  ('campus_delivery_fee', 200),
  ('hostel_delivery_fee', 300)
on conflict (key) do nothing;

create or replace function public._delivery_fee_from_settings(p_delivery_type text)
returns numeric(10,2)
language sql stable
security definer
set search_path = public
as $$
  select coalesce(
    (select value from public.delivery_settings
     where key = case p_delivery_type
       when 'campus_delivery' then 'campus_delivery_fee'
       when 'hostel_delivery' then 'hostel_delivery_fee'
       else null
     end),
    0
  );
$$;


-- ─────────────────────────────────────────────────────────────────────
-- 7-B. Product section / food_subsection fields
-- ─────────────────────────────────────────────────────────────────────
alter table public.products
  add column if not exists section text not null default 'food'
    check (section in ('food', 'drinks', 'others')),
  add column if not exists food_subsection text
    check (food_subsection is null or food_subsection in ('meal', 'protein_topping'));

insert into public.delivery_settings (key, value) values
  ('pack_meal_capacity', 8)
on conflict (key) do nothing;


-- ─────────────────────────────────────────────────────────────────────
-- 7-B2. Backfill FIRST, then add the cross-column constraint.
-- ─────────────────────────────────────────────────────────────────────
update public.products set section = 'food', food_subsection = 'meal'
where lower(category) in ('meals', 'protein meals', 'main', 'sides', 'snacks', 'grills')
  and section = 'food' and food_subsection is null;

update public.products set section = 'food', food_subsection = 'protein_topping'
where lower(category) in ('proteins', 'protein', 'toppings')
  and food_subsection is null;

update public.products set section = 'drinks', food_subsection = null
where lower(category) in ('drinks', 'smoothies', 'juices')
  and section = 'food';

update public.products set section = 'others', food_subsection = null
where lower(category) in ('others', 'shawarma', 'snacks & pastries', 'bread', 'pastries')
  and section = 'food'
  and food_subsection is null
  and lower(category) not in ('meals', 'protein meals', 'main', 'sides', 'grills');

-- Catch-all: any remaining food-section product without a subsection → meal
update public.products set food_subsection = 'meal'
where section = 'food' and food_subsection is null;

-- NOW add the cross-column constraint (all rows satisfy it).
do $$ begin
  alter table public.products
    add constraint products_subsection_only_for_food
    check (section <> 'food' or food_subsection is not null);
exception when duplicate_object then null;
end $$;


-- ─────────────────────────────────────────────────────────────────────
-- 7-C. delivery_groups — parent record for multi-vendor checkouts
-- ─────────────────────────────────────────────────────────────────────
create table if not exists public.delivery_groups (
  id                     uuid primary key default gen_random_uuid(),
  student_id             uuid not null references public.profiles (id) on delete cascade,
  delivery_type          text not null check (delivery_type in ('pickup', 'campus_delivery', 'hostel_delivery')),
  delivery_location      text,
  student_note           text,
  commitment_fee_total   numeric(10,2) not null default 0,
  final_amount           numeric(10,2),
  final_payment_paid     boolean not null default false,
  status                 text not null default 'placed'
    check (status in (
      'placed',
      'commitment_paid',
      'awaiting_final_payment',
      'out_for_delivery',
      'completed',
      'cancelled'
    )),
  rider_id               uuid references public.profiles (id),
  delivery_pin           text,
  delivery_stage         text check (delivery_stage in ('accepted', 'picked_up')),
  scheduled_for          timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

alter table public.delivery_groups enable row level security;

-- Reuse the existing touch_updated_at trigger function.
do $$ begin
  create trigger delivery_groups_updated_at
    before update on public.delivery_groups
    for each row execute function public.touch_updated_at();
exception when duplicate_object then null;
end $$;

create or replace function public._generate_delivery_group_pin()
returns trigger language plpgsql as $$
declare
  v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_pin   text := '';
  i       int;
begin
  if new.delivery_type <> 'pickup' then
    for i in 1..4 loop
      v_pin := v_pin || substr(v_chars, floor(random() * length(v_chars))::int + 1, 1);
    end loop;
    new.delivery_pin := v_pin;
  end if;
  return new;
end;
$$;

do $$ begin
  create trigger delivery_groups_gen_pin
    before insert on public.delivery_groups
    for each row execute function public._generate_delivery_group_pin();
exception when duplicate_object then null;
end $$;

-- Link orders to their delivery group.
alter table public.orders
  add column if not exists delivery_group_id uuid references public.delivery_groups (id);

-- RLS
do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'dg_student_read' and tablename = 'delivery_groups') then
    create policy dg_student_read on public.delivery_groups
      for select to authenticated
      using (student_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where policyname = 'dg_rider_read' and tablename = 'delivery_groups') then
    create policy dg_rider_read on public.delivery_groups
      for select to authenticated
      using (rider_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where policyname = 'dg_admin_read' and tablename = 'delivery_groups') then
    create policy dg_admin_read on public.delivery_groups
      for select to authenticated
      using (public.is_admin());
  end if;
end $$;

do $$ begin
  alter publication supabase_realtime add table public.delivery_groups;
exception when duplicate_object then null;
end $$;


-- ─────────────────────────────────────────────────────────────────────
-- 7-D. Core RPCs
-- ─────────────────────────────────────────────────────────────────────

-- 7-D1. place_multi_vendor_order
create or replace function public.place_multi_vendor_order(
  p_delivery_type     text,
  p_delivery_location text default null,
  p_student_note      text default null,
  p_scheduled_for     timestamptz default null,
  p_legs              jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_student_id  uuid := auth.uid();
  v_group_id    uuid;
  v_fee_per     numeric(10,2);
  v_total_fee   numeric(10,2);
  v_leg         jsonb;
  v_order_id    uuid;
  v_item        jsonb;
  v_pack        jsonb;
  v_pack_idx    int;
  v_leg_count   int;
  v_capacity    int;
begin
  if v_student_id is null then
    raise exception 'Not authenticated';
  end if;

  v_leg_count := jsonb_array_length(p_legs);
  if v_leg_count = 0 then
    raise exception 'No vendor legs provided';
  end if;

  if p_delivery_type = 'pickup' then
    v_fee_per := 0;
  else
    v_fee_per := public._delivery_fee_from_settings(p_delivery_type);
  end if;
  v_total_fee := v_fee_per * v_leg_count;

  select value::int into v_capacity from public.delivery_settings where key = 'pack_meal_capacity';
  if v_capacity is null then v_capacity := 8; end if;

  insert into public.delivery_groups
    (student_id, delivery_type, delivery_location, student_note,
     commitment_fee_total, scheduled_for, status)
  values
    (v_student_id, p_delivery_type, p_delivery_location, p_student_note,
     v_total_fee, p_scheduled_for, 'placed')
  returning id into v_group_id;

  for v_leg in select * from jsonb_array_elements(p_legs)
  loop
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

    insert into public.orders
      (student_id, vendor_id, source, type, status, delivery_type,
       delivery_location, total_amount, estimated_time, scheduled_for,
       pack_count, pack_fee, notes, delivery_group_id)
    values
      (v_student_id,
       (v_leg ->> 'vendor_id')::uuid,
       coalesce(v_leg ->> 'source', 'partner'),
       'food',
       'placed',
       p_delivery_type,
       p_delivery_location,
       coalesce((v_leg ->> 'total_amount')::numeric, 0),
       coalesce(v_leg ->> 'estimated_time', '20–30 min'),
       p_scheduled_for,
       jsonb_array_length(coalesce(v_leg -> 'packs', '[]'::jsonb)),
       coalesce((v_leg ->> 'pack_fee')::numeric, 0),
       p_student_note,
       v_group_id)
    returning id into v_order_id;

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

    v_pack_idx := 0;
    for v_pack in select * from jsonb_array_elements(coalesce(v_leg -> 'packs', '[]'::jsonb))
    loop
      insert into public.order_packs (order_id, pack_index, items)
      values (v_order_id, v_pack_idx, coalesce(v_pack -> 'items', '[]'::jsonb));
      v_pack_idx := v_pack_idx + 1;
    end loop;
  end loop;

  return jsonb_build_object(
    'group_id', v_group_id,
    'commitment_fee_total', v_total_fee,
    'delivery_fee_per_vendor', v_fee_per,
    'vendor_count', v_leg_count
  );
end;
$$;
grant execute on function public.place_multi_vendor_order(text, text, text, timestamptz, jsonb) to authenticated;


-- 7-D2. pay_group_commitment_fee
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
  v_group      public.delivery_groups%rowtype;
  v_wallet     public.wallets%rowtype;
  v_pin_status text;
  v_fee        numeric(10,2);
  v_has_uniflex boolean := false;
begin
  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status = 'not_set' then raise exception 'PIN_NOT_SET'; end if;
  if v_pin_status = 'locked'  then raise exception 'PIN_LOCKED'; end if;
  if v_pin_status = 'invalid' then raise exception 'INVALID_PIN'; end if;

  select * into v_group from public.delivery_groups
  where id = p_group_id for update;
  if not found then raise exception 'Group not found'; end if;
  if v_group.student_id <> v_student_id then raise exception 'Unauthorized'; end if;
  if v_group.status <> 'placed' then raise exception 'Already paid or cancelled'; end if;

  v_fee := v_group.commitment_fee_total;

  if v_fee > 0 then
    select * into v_wallet from public.wallets
    where user_id = v_student_id for update;
    if not found then raise exception 'Wallet not found'; end if;
    if v_wallet.balance < v_fee then raise exception 'INSUFFICIENT_BALANCE'; end if;

    update public.wallets set balance = balance - v_fee
    where user_id = v_student_id;

    insert into public.wallet_transactions
      (user_id, type, amount, source, balance_after)
    values
      (v_student_id, 'debit', v_fee, 'commitment_fee',
       v_wallet.balance - v_fee);
  end if;

  update public.delivery_groups
  set status = 'commitment_paid'
  where id = p_group_id;

  select exists(
    select 1 from public.orders
    where delivery_group_id = p_group_id and source = 'uniflex'
  ) into v_has_uniflex;

  update public.orders
  set status = 'preparing',
      commitment_fee_paid = true,
      commitment_fee_amount = public._delivery_fee_from_settings(v_group.delivery_type)
  where delivery_group_id = p_group_id and source = 'uniflex';

  update public.orders
  set status = 'being_sourced',
      commitment_fee_paid = true,
      commitment_fee_amount = public._delivery_fee_from_settings(v_group.delivery_type)
  where delivery_group_id = p_group_id and source = 'partner';

  return jsonb_build_object(
    'balance_after', case when v_fee > 0 then v_wallet.balance - v_fee else null end,
    'has_uniflex', v_has_uniflex
  );
end;
$$;
grant execute on function public.pay_group_commitment_fee(uuid, text) to authenticated;


-- 7-D3. accept_delivery_group
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
  select * into v_group from public.delivery_groups
  where id = p_group_id for update nowait;

  if not found then raise exception 'Group not found'; end if;
  if v_group.rider_id is not null then raise exception 'Already accepted by another rider'; end if;
  if v_group.status not in ('commitment_paid') then
    raise exception 'Group not available for pickup';
  end if;

  update public.delivery_groups
  set rider_id = v_rider_id,
      delivery_stage = 'accepted'
  where id = p_group_id;

  update public.orders
  set rider_id = v_rider_id,
      delivery_stage = 'accepted'
  where delivery_group_id = p_group_id
    and source = 'partner'
    and status = 'being_sourced';

  update public.orders
  set rider_id = v_rider_id
  where delivery_group_id = p_group_id
    and source = 'uniflex';
end;
$$;
grant execute on function public.accept_delivery_group(uuid) to authenticated;


-- 7-D4. confirm_group_leg_pickup
create or replace function public.confirm_group_leg_pickup(
  p_order_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider_id uuid := auth.uid();
  v_order    public.orders%rowtype;
  v_group    public.delivery_groups%rowtype;
  v_all_picked boolean;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if v_order.rider_id <> v_rider_id then raise exception 'Not your order'; end if;
  if v_order.delivery_group_id is null then raise exception 'Not a group order leg'; end if;

  update public.orders
  set delivery_stage = 'picked_up',
      status = 'out_for_delivery'
  where id = p_order_id;

  select not exists(
    select 1 from public.orders
    where delivery_group_id = v_order.delivery_group_id
      and delivery_stage is distinct from 'picked_up'
      and status not in ('cancelled')
  ) into v_all_picked;

  if v_all_picked then
    update public.delivery_groups
    set delivery_stage = 'picked_up'
    where id = v_order.delivery_group_id;
  end if;
end;
$$;
grant execute on function public.confirm_group_leg_pickup(uuid) to authenticated;


-- 7-D5. pay_group_final_amount
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
  v_student_id  uuid := auth.uid();
  v_group       public.delivery_groups%rowtype;
  v_wallet      public.wallets%rowtype;
  v_pin_status  text;
  v_total       numeric(10,2) := 0;
begin
  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status = 'not_set' then raise exception 'PIN_NOT_SET'; end if;
  if v_pin_status = 'locked'  then raise exception 'PIN_LOCKED'; end if;
  if v_pin_status = 'invalid' then raise exception 'INVALID_PIN'; end if;

  select * into v_group from public.delivery_groups
  where id = p_group_id for update;
  if not found then raise exception 'Group not found'; end if;
  if v_group.student_id <> v_student_id then raise exception 'Unauthorized'; end if;
  if v_group.status <> 'awaiting_final_payment' then
    raise exception 'Group is not awaiting payment';
  end if;

  select coalesce(sum(
    case when final_amount is not null then final_amount else total_amount end
  ), 0) into v_total
  from public.orders
  where delivery_group_id = p_group_id
    and status <> 'cancelled';

  select * into v_wallet from public.wallets
  where user_id = v_student_id for update;
  if not found then raise exception 'Wallet not found'; end if;
  if v_wallet.balance < v_total then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.wallets set balance = balance - v_total
  where user_id = v_student_id;

  insert into public.wallet_transactions
    (user_id, type, amount, source, balance_after)
  values
    (v_student_id, 'debit', v_total, 'order_payment',
     v_wallet.balance - v_total);

  update public.delivery_groups
  set final_amount = v_total,
      final_payment_paid = true,
      status = 'out_for_delivery'
  where id = p_group_id;

  update public.orders
  set final_payment_paid = true,
      final_amount = case when final_amount is not null then final_amount else total_amount end,
      status = 'out_for_delivery'
  where delivery_group_id = p_group_id
    and status <> 'cancelled';

  return jsonb_build_object(
    'balance_after', v_wallet.balance - v_total,
    'total_paid', v_total
  );
end;
$$;
grant execute on function public.pay_group_final_amount(uuid, text) to authenticated;


-- 7-D6. verify_group_delivery
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
  select * into v_group from public.delivery_groups
  where id = p_group_id for update;
  if not found then raise exception 'Group not found'; end if;
  if v_group.rider_id <> v_rider_id then raise exception 'Not your delivery'; end if;
  if v_group.status <> 'out_for_delivery' then
    raise exception 'Group is not out for delivery';
  end if;

  if upper(p_pin) <> upper(v_group.delivery_pin) then
    raise exception 'Incorrect delivery PIN';
  end if;

  update public.delivery_groups
  set status = 'completed',
      delivery_stage = null
  where id = p_group_id;

  update public.orders
  set status = 'completed',
      delivery_stage = null
  where delivery_group_id = p_group_id
    and status <> 'cancelled';

  insert into public.delivery_records (rider_id, order_id)
  select v_rider_id, id from public.orders
  where delivery_group_id = p_group_id
    and status = 'completed';
end;
$$;
grant execute on function public.verify_group_delivery(uuid, text) to authenticated;


-- 7-D7. confirm_group_leg_sourcing
create or replace function public.confirm_group_leg_sourcing(
  p_order_id     uuid,
  p_final_amount numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider_id   uuid := auth.uid();
  v_order      public.orders%rowtype;
  v_all_ready  boolean;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if v_order.rider_id <> v_rider_id then raise exception 'Not your order'; end if;
  if v_order.status <> 'being_sourced' then raise exception 'Order not in sourcing stage'; end if;

  update public.orders
  set final_amount = p_final_amount,
      status = 'awaiting_final_payment'
  where id = p_order_id;

  if v_order.delivery_group_id is not null then
    select not exists(
      select 1 from public.orders
      where delivery_group_id = v_order.delivery_group_id
        and status not in ('awaiting_final_payment', 'ready', 'ready_for_pickup', 'cancelled')
    ) into v_all_ready;

    if v_all_ready then
      update public.delivery_groups
      set status = 'awaiting_final_payment'
      where id = v_order.delivery_group_id;
    end if;
  end if;
end;
$$;
grant execute on function public.confirm_group_leg_sourcing(uuid, numeric) to authenticated;


-- 7-D8. Rider pool query for delivery groups.
do $$ begin
  if not exists (select 1 from pg_policies where policyname = 'dg_pool_read' and tablename = 'delivery_groups') then
    create policy dg_pool_read on public.delivery_groups
      for select to authenticated
      using (
        status = 'commitment_paid'
        and rider_id is null
        and (exists (select 1 from public.profiles where id = auth.uid() and role = 'rider'))
      );
  end if;
end $$;


-- 7-D9. Admin update delivery settings.
create or replace function public.update_delivery_setting(
  p_key   text,
  p_value numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Not an admin';
  end if;
  update public.delivery_settings set value = p_value where key = p_key;
  if not found then
    raise exception 'Setting not found: %', p_key;
  end if;
end;
$$;
grant execute on function public.update_delivery_setting(text, numeric) to authenticated;


-- 7-D10. Get delivery settings (public read).
create or replace function public.get_delivery_settings()
returns jsonb
language sql stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from public.delivery_settings;
$$;
grant execute on function public.get_delivery_settings() to authenticated;


-- 7-D11. Kitchen: when admin marks a Uniflex leg as 'ready', check if
-- the whole group is now ready for final payment.
create or replace function public._check_group_ready_after_kitchen()
returns trigger language plpgsql as $$
declare
  v_group_id uuid;
  v_all_ready boolean;
begin
  if new.delivery_group_id is null then return new; end if;
  if old.status = new.status then return new; end if;
  if new.status not in ('ready', 'ready_for_pickup') then return new; end if;

  v_group_id := new.delivery_group_id;

  select not exists(
    select 1 from public.orders
    where delivery_group_id = v_group_id
      and status not in ('awaiting_final_payment', 'ready', 'ready_for_pickup', 'cancelled')
  ) into v_all_ready;

  if v_all_ready then
    update public.delivery_groups
    set status = 'awaiting_final_payment'
    where id = v_group_id
      and status <> 'awaiting_final_payment';
  end if;

  return new;
end;
$$;

drop trigger if exists check_group_ready on public.orders;
create trigger check_group_ready
  after update on public.orders
  for each row execute function public._check_group_ready_after_kitchen();


-- ==========================================================================
-- Verification query — run after the above to confirm product backfill.
-- ==========================================================================
select
  v.name as vendor,
  p.section,
  p.food_subsection,
  count(*) as product_count
from public.products p
join public.vendors v on v.id = p.vendor_id
where p.is_available = true
group by v.name, p.section, p.food_subsection
order by v.name, p.section, p.food_subsection;
