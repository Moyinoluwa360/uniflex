-- ==========================================================================
-- Round 8 Migration — run once in Supabase SQL Editor.
-- Idempotent: safe to re-run.
-- ==========================================================================

-- ── 1A. delivery_locations table ─────────────────────────────────────────

create table if not exists public.delivery_locations (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  price       numeric(10,2) not null,
  is_active   boolean not null default true,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);

alter table public.delivery_locations enable row level security;

-- Auth read active rows.
drop policy if exists "delivery_locations: read active" on public.delivery_locations;
create policy "delivery_locations: read active"
  on public.delivery_locations for select to authenticated
  using (is_active = true or public.is_admin());

-- Admin full CRUD.
drop policy if exists "delivery_locations: admin insert" on public.delivery_locations;
create policy "delivery_locations: admin insert"
  on public.delivery_locations for insert to authenticated
  with check (public.is_admin());

drop policy if exists "delivery_locations: admin update" on public.delivery_locations;
create policy "delivery_locations: admin update"
  on public.delivery_locations for update to authenticated
  using (public.is_admin());

drop policy if exists "delivery_locations: admin delete" on public.delivery_locations;
create policy "delivery_locations: admin delete"
  on public.delivery_locations for delete to authenticated
  using (public.is_admin());

-- Realtime.
do $$ begin
  alter publication supabase_realtime add table public.delivery_locations;
exception when duplicate_object then null;
end $$;

-- Seed locations.
insert into public.delivery_locations (name, price, sort_order)
select v.name, v.price, v.sort_order
from (values
  ('Engineering Hostel',    300::numeric, 1),
  ('Queen Esther Hall',     200::numeric, 2),
  ('Prophet Moses Hall',    200::numeric, 3),
  ('Engineering Faculty',   300::numeric, 4),
  ('Law Faculty',           300::numeric, 5),
  ('Main Campus',           300::numeric, 6)
) as v(name, price, sort_order)
where not exists (
  select 1 from public.delivery_locations dl where dl.name = v.name
);

-- ── RPCs for delivery locations ────────────────────────────────────────

create or replace function public.get_delivery_locations()
returns setof public.delivery_locations
language sql stable
security definer
set search_path = public
as $$
  select * from public.delivery_locations
  where is_active = true
  order by sort_order, name;
$$;
grant execute on function public.get_delivery_locations() to authenticated;

create or replace function public.upsert_delivery_location(
  p_id        uuid default null,
  p_name      text default null,
  p_price     numeric default null,
  p_is_active boolean default true,
  p_sort_order int default 0
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.is_admin() then raise exception 'Not an admin'; end if;

  if p_id is not null then
    update public.delivery_locations
    set name = coalesce(p_name, name),
        price = coalesce(p_price, price),
        is_active = p_is_active,
        sort_order = p_sort_order
    where id = p_id
    returning id into v_id;
    if v_id is null then raise exception 'Location not found'; end if;
  else
    insert into public.delivery_locations (name, price, is_active, sort_order)
    values (p_name, p_price, p_is_active, p_sort_order)
    returning id into v_id;
  end if;

  return v_id;
end;
$$;
grant execute on function public.upsert_delivery_location(uuid, text, numeric, boolean, int) to authenticated;

create or replace function public.delete_delivery_location(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Not an admin'; end if;
  delete from public.delivery_locations where id = p_id;
end;
$$;
grant execute on function public.delete_delivery_location(uuid) to authenticated;


-- ── 1B. Add columns to delivery_groups ────────────────────────────────

alter table public.delivery_groups
  add column if not exists delivery_location_id uuid references public.delivery_locations(id);

alter table public.delivery_groups
  add column if not exists location_details text;


-- ── 1C. Add columns to orders for errand drop-off ─────────────────────

alter table public.orders
  add column if not exists delivery_location_id uuid references public.delivery_locations(id);

alter table public.orders
  add column if not exists location_details text;


-- ── 1D. Rename Around → Errand (tables) ──────────────────────────────

-- Rename tables (idempotent via IF EXISTS / catch).
do $$ begin
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'around_categories') then
    alter table public.around_categories rename to errand_categories;
  end if;
exception when others then null;
end $$;

do $$ begin
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'around_requests') then
    alter table public.around_requests rename to errand_requests;
  end if;
exception when others then null;
end $$;

-- Update order type: add 'errand', migrate data, then drop 'around'.
-- Step 1: Drop existing constraint.
alter table public.orders drop constraint if exists orders_type_check;
-- Step 2: Add new constraint allowing both during migration.
alter table public.orders add constraint orders_type_check
  check (type in ('food', 'around', 'errand'));
-- Step 3: Migrate existing rows.
update public.orders set type = 'errand' where type = 'around';
-- Step 4: Drop and re-add with only valid values.
alter table public.orders drop constraint orders_type_check;
alter table public.orders add constraint orders_type_check
  check (type in ('food', 'errand'));


-- ── 1D-2. Rename RLS policies for errand_categories ──────────────────

-- Drop old policies (table may have been renamed, so use new name).
drop policy if exists "around_categories: authenticated read active" on public.errand_categories;
drop policy if exists "around_categories: admin insert" on public.errand_categories;
drop policy if exists "around_categories: admin update" on public.errand_categories;
drop policy if exists "around_categories: admin delete" on public.errand_categories;

-- Create new policies on errand_categories.
create policy "errand_categories: authenticated read active"
  on public.errand_categories for select to authenticated
  using (is_active = true or public.is_admin());

create policy "errand_categories: admin insert"
  on public.errand_categories for insert to authenticated
  with check (public.is_admin());

create policy "errand_categories: admin update"
  on public.errand_categories for update to authenticated
  using (public.is_admin());

create policy "errand_categories: admin delete"
  on public.errand_categories for delete to authenticated
  using (public.is_admin());


-- ── 1D-3. Rename RLS policies for errand_requests ────────────────────

drop policy if exists "around_requests: insert own" on public.errand_requests;
drop policy if exists "around_requests: read own" on public.errand_requests;
drop policy if exists "around_requests: admin read all" on public.errand_requests;
drop policy if exists "around_requests: rider read pool or assigned" on public.errand_requests;

create policy "errand_requests: insert own"
  on public.errand_requests for insert to authenticated
  with check (
    exists (select 1 from public.orders o
            where o.id = errand_requests.order_id and o.student_id = auth.uid())
  );

create policy "errand_requests: read own"
  on public.errand_requests for select to authenticated
  using (
    exists (select 1 from public.orders o
            where o.id = errand_requests.order_id and o.student_id = auth.uid())
  );

create policy "errand_requests: admin read all"
  on public.errand_requests for select to authenticated
  using (public.is_admin());

create policy "errand_requests: rider read pool or assigned"
  on public.errand_requests for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = errand_requests.order_id
        and (
          o.rider_id = auth.uid()
          or (o.rider_id is null and o.status in ('placed', 'being_sourced'))
        )
    )
  );


-- ── 1D-4. Update FK on errand_requests ───────────────────────────────

-- The FK constraint references the old table name internally; rename handles it
-- but re-add to be safe.
alter table public.errand_requests drop constraint if exists around_requests_category_fkey;
do $$ begin
  alter table public.errand_requests
    add constraint errand_requests_category_fkey
    foreign key (category) references public.errand_categories (key);
exception when duplicate_object then null;
end $$;


-- ── 1D-5. Re-seed errand categories (Round 8 defaults: all ₦800) ────

-- Update existing rows to new prices + rename.
update public.errand_categories set flat_fee = 800 where flat_fee < 800;

-- Insert new categories if they don't exist.
insert into public.errand_categories (key, title, subtitle, description, icon_name, flat_fee, sort_order)
select v.key, v.title, v.subtitle, v.description, v.icon_name, v.flat_fee, v.sort_order
from (values
  ('general_errand', 'General Errand', 'Anything you need done', 'A rider handles any general errand for you.', 'assignment', 800::numeric, 1),
  ('buy_and_bring',  'Buy & Bring',    'We buy, we deliver',     'Tell us what to buy and where — rider fetches it.', 'shopping_bag', 800::numeric, 2),
  ('laundry',        'Laundry Pickup/Drop-off', 'Laundry runs', 'Rider picks up or drops off your laundry.', 'laundry', 800::numeric, 3),
  ('item_delivery',  'Item Delivery',  'Send items across campus', 'Send a package or item to someone on campus.', 'send', 800::numeric, 4),
  ('moving_items',   'Moving Items',   'Help moving your stuff',  'Rider helps move items between locations.', 'local_shipping', 800::numeric, 5)
) as v(key, title, subtitle, description, icon_name, flat_fee, sort_order)
where not exists (
  select 1 from public.errand_categories ec where ec.key = v.key
);


-- ── 1D-6. Rename RPCs ───────────────────────────────────────────────

-- place_errand_order (replaces place_around_order).
drop function if exists public.place_around_order(text, text, text, text, numeric, text);
drop function if exists public.place_around_order(text, text, text, text, numeric);

create or replace function public.place_errand_order(
  p_category               text,
  p_pickup_location        text,
  p_dropoff_location       text,
  p_item_description       text,
  p_flat_fee               numeric(10,2),
  p_notes                  text default null,
  p_delivery_location_id   uuid default null,
  p_location_details       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  v_order_id   uuid;
begin
  v_student_id := auth.uid();
  if v_student_id is null then raise exception 'Unauthorized'; end if;

  if not exists (select 1 from public.profiles where id = v_student_id) then
    raise exception 'Profile not found';
  end if;

  insert into public.orders
    (student_id, source, type, status, delivery_type,
     total_amount, estimated_time, notes,
     delivery_location_id, location_details)
  values
    (v_student_id, 'uniflex', 'errand', 'placed', 'delivery',
     p_flat_fee, '15–25 min', p_notes,
     p_delivery_location_id, p_location_details)
  returning id into v_order_id;

  insert into public.errand_requests
    (order_id, category, pickup_location, dropoff_location, item_description)
  values
    (v_order_id, p_category, p_pickup_location, p_dropoff_location, p_item_description);

  return jsonb_build_object('order_id', v_order_id);
end;
$$;
grant execute on function public.place_errand_order(text, text, text, text, numeric, text, uuid, text) to authenticated;

-- place_errand_with_payment (replaces place_around_with_payment if it exists).
-- For now, errands use the staged flow (place then pay commitment fee).
-- Keep backward compat — old place_around_with_payment may still be called.
-- We'll drop it only after the client is updated.


-- ── 1E. Update place_multi_vendor_order for location-based fees ──────

-- Drop old signature.
drop function if exists public.place_multi_vendor_order(text, text, text, timestamptz, jsonb);

create or replace function public.place_multi_vendor_order(
  p_delivery_type          text default 'delivery',
  p_delivery_location      text default null,
  p_student_note           text default null,
  p_scheduled_for          timestamptz default null,
  p_legs                   jsonb default '[]'::jsonb,
  p_delivery_location_id   uuid default null,
  p_location_details       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_student_id  uuid := auth.uid();
  v_group_id    uuid;
  v_location_price numeric(10,2) := 0;
  v_total_fee   numeric(10,2) := 0;
  v_leg         jsonb;
  v_order_id    uuid;
  v_item        jsonb;
  v_pack        jsonb;
  v_pack_idx    int;
  v_leg_count   int;
  v_capacity    int;
  v_leg_packs   int;
  v_leg_fee     numeric(10,2);
begin
  if v_student_id is null then
    raise exception 'Not authenticated';
  end if;

  v_leg_count := jsonb_array_length(p_legs);
  if v_leg_count = 0 then
    raise exception 'No vendor legs provided';
  end if;

  -- Look up delivery fee from location (new) or settings (fallback).
  if p_delivery_type = 'pickup' then
    v_location_price := 0;
  elsif p_delivery_location_id is not null then
    select price into v_location_price
    from public.delivery_locations
    where id = p_delivery_location_id and is_active = true;
    if v_location_price is null then
      raise exception 'Delivery location not found or inactive';
    end if;
  else
    -- Fallback to old settings for backward compat.
    v_location_price := public._delivery_fee_from_settings(p_delivery_type);
  end if;

  -- Calculate per-vendor fees using pack brackets.
  -- Per vendor: location_price * ceil(food_packs / 3). Zero packs = 1x.
  v_total_fee := 0;
  for v_leg in select * from jsonb_array_elements(p_legs)
  loop
    v_leg_packs := jsonb_array_length(coalesce(v_leg -> 'packs', '[]'::jsonb));
    if v_leg_packs <= 0 then
      v_leg_fee := v_location_price;  -- drinks/others only = 1x
    else
      v_leg_fee := v_location_price * ceil(v_leg_packs::numeric / 3);
    end if;
    v_total_fee := v_total_fee + v_leg_fee;
  end loop;

  -- Look up pack capacity.
  select value::int into v_capacity from public.delivery_settings where key = 'pack_meal_capacity';
  if v_capacity is null then v_capacity := 8; end if;

  -- Create the delivery group.
  insert into public.delivery_groups
    (student_id, delivery_type, delivery_location, student_note,
     commitment_fee_total, scheduled_for, status,
     delivery_location_id, location_details)
  values
    (v_student_id, p_delivery_type, p_delivery_location, p_student_note,
     v_total_fee, p_scheduled_for, 'placed',
     p_delivery_location_id, p_location_details)
  returning id into v_group_id;

  -- Create one order (leg) per vendor.
  for v_leg in select * from jsonb_array_elements(p_legs)
  loop
    -- Validate vendor exists.
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

    -- Calculate this vendor's delivery fee.
    v_leg_packs := jsonb_array_length(coalesce(v_leg -> 'packs', '[]'::jsonb));
    if v_leg_packs <= 0 then
      v_leg_fee := v_location_price;
    else
      v_leg_fee := v_location_price * ceil(v_leg_packs::numeric / 3);
    end if;

    insert into public.orders
      (student_id, vendor_id, source, type, status, delivery_type,
       delivery_location, total_amount, estimated_time, scheduled_for,
       pack_count, pack_fee, notes, delivery_group_id,
       commitment_fee_amount, delivery_location_id, location_details)
    values
      (v_student_id,
       (v_leg ->> 'vendor_id')::uuid,
       coalesce(v_leg ->> 'source', 'partner'),
       'food',
       'placed',
       p_delivery_type,
       p_delivery_location,
       coalesce((v_leg ->> 'total_amount')::numeric, 0),
       coalesce(v_leg ->> 'estimated_time', '20-30 min'),
       p_scheduled_for,
       jsonb_array_length(coalesce(v_leg -> 'packs', '[]'::jsonb)),
       coalesce((v_leg ->> 'pack_fee')::numeric, 0),
       p_student_note,
       v_group_id,
       v_leg_fee,
       p_delivery_location_id,
       p_location_details)
    returning id into v_order_id;

    -- Insert line items.
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

    -- Insert packs.
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
    'vendor_count', v_leg_count
  );
end;
$$;
grant execute on function public.place_multi_vendor_order(text, text, text, timestamptz, jsonb, uuid, text) to authenticated;


-- ── 1E-2. Update pay_group_commitment_fee to use per-leg fee ────────

-- The old RPC used _delivery_fee_from_settings for per-leg commitment_fee_amount.
-- Now each leg already has commitment_fee_amount set by place_multi_vendor_order.
-- Update to use that stored value instead.
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
  -- PIN check.
  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status = 'not_set' then raise exception 'PIN_NOT_SET'; end if;
  if v_pin_status = 'locked'  then raise exception 'PIN_LOCKED'; end if;
  if v_pin_status = 'invalid' then raise exception 'INVALID_PIN'; end if;

  -- Lock group.
  select * into v_group from public.delivery_groups
  where id = p_group_id for update;
  if not found then raise exception 'Group not found'; end if;
  if v_group.student_id <> v_student_id then raise exception 'Unauthorized'; end if;
  if v_group.status <> 'placed' then raise exception 'Already paid or cancelled'; end if;

  v_fee := v_group.commitment_fee_total;

  -- Pickup orders have no fee — just advance.
  if v_fee > 0 then
    -- Lock wallet.
    select * into v_wallet from public.wallets
    where user_id = v_student_id for update;
    if not found then raise exception 'Wallet not found'; end if;
    if v_wallet.balance < v_fee then raise exception 'INSUFFICIENT_BALANCE'; end if;

    -- Deduct.
    update public.wallets set balance = balance - v_fee
    where user_id = v_student_id;

    -- Record transaction.
    insert into public.wallet_transactions
      (user_id, type, amount, source, balance_after)
    values
      (v_student_id, 'debit', v_fee, 'commitment_fee',
       v_wallet.balance - v_fee);
  end if;

  -- Advance group.
  update public.delivery_groups
  set status = 'commitment_paid'
  where id = p_group_id;

  -- Check if any leg is Uniflex.
  select exists(
    select 1 from public.orders
    where delivery_group_id = p_group_id and source = 'uniflex'
  ) into v_has_uniflex;

  -- Advance Uniflex legs to 'preparing' (kitchen starts).
  -- commitment_fee_amount was already set by place_multi_vendor_order.
  update public.orders
  set status = 'preparing',
      commitment_fee_paid = true
  where delivery_group_id = p_group_id and source = 'uniflex';

  -- Advance partner legs to 'being_sourced' (rider pool).
  update public.orders
  set status = 'being_sourced',
      commitment_fee_paid = true
  where delivery_group_id = p_group_id and source = 'partner';

  return jsonb_build_object(
    'balance_after', case when v_fee > 0 then v_wallet.balance - v_fee else null end,
    'has_uniflex', v_has_uniflex
  );
end;
$$;
grant execute on function public.pay_group_commitment_fee(uuid, text) to authenticated;


-- ── 1F. Search products RPC ─────────────────────────────────────────

create or replace function public.search_products(p_query text)
returns jsonb
language sql stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb)
  from (
    select
      p.id as product_id,
      p.name as product_name,
      p.description,
      p.base_price,
      p.section,
      p.food_subsection,
      p.image_url,
      v.id as vendor_id,
      v.name as vendor_name,
      v.is_active as vendor_active
    from public.products p
    join public.vendors v on v.id = p.vendor_id
    where p.is_available = true
      and v.is_active = true
      and p.name ilike '%' || p_query || '%'
    order by v.name, p.name
    limit 50
  ) r;
$$;
grant execute on function public.search_products(text) to authenticated;


-- ── Verify ──────────────────────────────────────────────────────────

select 'delivery_locations' as what, count(*) as cnt from public.delivery_locations
union all
select 'errand_categories', count(*) from public.errand_categories
union all
select 'errand orders', count(*) from public.orders where type = 'errand'
union all
select 'around orders (should be 0)', count(*) from public.orders where type = 'around';
