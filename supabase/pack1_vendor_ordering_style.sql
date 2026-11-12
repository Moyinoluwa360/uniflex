-- =====================================================================
-- Pack 1 / Part 3 — vendor ordering styles: "pack_based" | "fixed_menu"
-- (2026-11-12). See docs/vendor-ordering-styles.md.
--
-- Idempotent; safe to re-run. Business rules unchanged: the two checkout
-- functions below are the exact live definitions (pulled 2026-11-12) with ONE
-- added `perform public._check_leg_style(...)` line each.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. The column (back-fills every existing vendor as pack_based)
-- ---------------------------------------------------------------------
alter table public.vendors
  add column if not exists ordering_style text not null default 'pack_based';

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'vendors_ordering_style_check'
                    and conrelid = 'public.vendors'::regclass) then
    alter table public.vendors
      add constraint vendors_ordering_style_check
      check (ordering_style in ('pack_based', 'fixed_menu'));
  end if;
end $$;

comment on column public.vendors.ordering_style is
  'pack_based (packs + spoons, default) | fixed_menu (fixed priced meals, quantities only). Admin-only; not changeable while the vendor has active orders.';

-- Max of one item in a fixed-menu leg (owner decision 2026-11-12). The app
-- mirrors it in kFixedMenuMaxQty.
create or replace function public._fixed_menu_max_qty()
returns int language sql immutable as $$ select 20 $$;

-- ---------------------------------------------------------------------
-- 2. Who may set / change it
-- ---------------------------------------------------------------------
create or replace function public._guard_vendor_ordering_style()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.ordering_style is distinct from 'pack_based'
       and auth.uid() is not null and not public.is_super_admin() then
      raise exception 'NOT_ALLOWED';
    end if;
    return new;
  end if;

  if new.ordering_style is distinct from old.ordering_style then
    if auth.uid() is not null and not public.is_super_admin() then
      raise exception 'NOT_ALLOWED';
    end if;
    if exists (select 1 from public.orders o
                where o.vendor_id = new.id
                  and o.status not in ('completed', 'cancelled')) then
      raise exception 'VENDOR_HAS_ACTIVE_ORDERS';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists vendors_ordering_style_guard on public.vendors;
create trigger vendors_ordering_style_guard
  before insert or update of ordering_style on public.vendors
  for each row execute function public._guard_vendor_ordering_style();

-- ---------------------------------------------------------------------
-- 3. Checkout rule per leg (called by both checkout functions)
-- ---------------------------------------------------------------------
create or replace function public._check_leg_style(
  p_vendor_id uuid,
  p_declared  text,
  p_packs     jsonb,
  p_items     jsonb
) returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_style text;
begin
  select ordering_style into v_style from public.vendors where id = p_vendor_id;
  if v_style is null then raise exception 'VENDOR_NOT_FOUND'; end if;

  -- A cart built for the other style (vendor switched since) is refused.
  if p_declared is not null and p_declared <> v_style then
    raise exception 'VENDOR_STYLE_CHANGED';
  end if;

  if v_style = 'fixed_menu' then
    if coalesce(jsonb_typeof(p_packs), 'null') = 'array'
       and jsonb_array_length(p_packs) > 0 then
      raise exception 'PACKS_NOT_ALLOWED';
    end if;
    if exists (
      select 1
        from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) it
       group by it ->> 'product_id'
      having sum(coalesce((it ->> 'quantity')::int, 0)) > public._fixed_menu_max_qty()
    ) then
      raise exception 'QUANTITY_TOO_HIGH';
    end if;
  end if;
end;
$$;

revoke all on function public._check_leg_style(uuid, text, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public._guard_vendor_ordering_style() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Belt and braces: no pack rows for a fixed-menu vendor's order
-- ---------------------------------------------------------------------
create or replace function public._order_packs_style_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.orders o
               join public.vendors v on v.id = o.vendor_id
              where o.id = new.order_id and v.ordering_style = 'fixed_menu') then
    raise exception 'PACKS_NOT_ALLOWED';
  end if;
  return new;
end;
$$;
revoke all on function public._order_packs_style_guard() from public, anon, authenticated;

drop trigger if exists order_packs_style_guard on public.order_packs;
create trigger order_packs_style_guard
  before insert on public.order_packs
  for each row execute function public._order_packs_style_guard();

-- ---------------------------------------------------------------------
-- 5. Fixed-menu menu items: validated, stored as plain items
-- ---------------------------------------------------------------------
create or replace function public._fixed_menu_product_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.vendors v
              where v.id = new.vendor_id and v.ordering_style = 'fixed_menu') then
    if nullif(trim(coalesce(new.name, '')), '') is null then
      raise exception 'NAME_REQUIRED';
    end if;
    if nullif(trim(coalesce(new.category, '')), '') is null
       or char_length(trim(new.category)) > 40 then
      raise exception 'CATEGORY_REQUIRED';
    end if;
    if new.base_price is null or new.base_price <= 0 or new.base_price > 500000 then
      raise exception 'INVALID_PRICE';
    end if;
    new.name            := trim(new.name);
    new.category        := trim(new.category);
    new.requires_pack   := false;
    new.section         := 'food';
    new.food_subsection := 'meal';
  end if;
  return new;
end;
$$;
revoke all on function public._fixed_menu_product_guard() from public, anon, authenticated;

drop trigger if exists products_fixed_menu_guard on public.products;
create trigger products_fixed_menu_guard
  before insert or update on public.products
  for each row execute function public._fixed_menu_product_guard();

-- ---------------------------------------------------------------------
-- 6. The two checkout functions (live definitions + one line each)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_paid_delivery_order(p_idempotency_key uuid, p_pin text, p_legs jsonb, p_delivery_location_id uuid, p_location_details text DEFAULT NULL::text, p_student_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_student      uuid := auth.uid();
  v_existing     jsonb;
  v_pin_status   text;
  v_loc          record;
  v_vendor       record;
  v_product      record;
  v_service      numeric(10,2);
  v_capacity     int;
  v_leg          jsonb;
  v_item         jsonb;
  v_pack         jsonb;
  v_pack_item    jsonb;
  v_prepared     jsonb := '[]'::jsonb;
  v_items_out    jsonb;
  v_packs_out    jsonb;
  v_pack_items   jsonb;
  v_vendor_seen  uuid[] := '{}';
  v_qty          int;
  v_spoons       int;
  v_leg_packs    int;
  v_leg_fee      numeric(10,2);
  v_leg_sub      numeric(10,2);
  v_leg_pack_fee numeric(10,2);
  v_fee_total    numeric(10,2) := 0;
  v_total        numeric(10,2);
  v_balance      numeric;
  v_new_balance  numeric;
  v_group_id     uuid;
  v_order_id     uuid;
  v_order_ids    uuid[] := '{}';
  v_idx          int;
  v_details      text := nullif(trim(coalesce(p_location_details, '')), '');
  v_note         text := nullif(trim(coalesce(p_student_note, '')), '');
  v_result       jsonb;
begin
  if v_student is null then raise exception 'Unauthorized'; end if;
  if p_idempotency_key is null then raise exception 'IDEMPOTENCY_KEY_REQUIRED'; end if;

  -- Serialise concurrent retries of the same key.
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));

  select result into v_existing
    from public.order_payment_attempts
   where idempotency_key = p_idempotency_key and student_id = v_student;
  if found then
    return v_existing || jsonb_build_object('replayed', true);
  end if;
  if exists (select 1 from public.order_payment_attempts
              where idempotency_key = p_idempotency_key) then
    raise exception 'IDEMPOTENCY_KEY_IN_USE';
  end if;

  -- PIN (returned, not raised — see header comment).
  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status <> 'ok' then
    return jsonb_build_object('error', case v_pin_status
      when 'locked'  then 'PIN_LOCKED'
      when 'not_set' then 'PIN_NOT_SET'
      else 'INVALID_PIN' end);
  end if;

  -- ── Validate + compute everything (no writes yet) ──────────────────
  if p_legs is null or jsonb_typeof(p_legs) <> 'array'
     or jsonb_array_length(p_legs) = 0 then
    raise exception 'EMPTY_ORDER';
  end if;
  if jsonb_array_length(p_legs) > 10 then
    raise exception 'TOO_MANY_VENDORS';
  end if;
  if v_details is null then raise exception 'LOCATION_DETAILS_REQUIRED'; end if;
  if char_length(v_details) > 300 or char_length(coalesce(v_note, '')) > 500 then
    raise exception 'TEXT_TOO_LONG';
  end if;

  select id, name, price into v_loc
    from public.delivery_locations
   where id = p_delivery_location_id and is_active = true;
  if not found then raise exception 'LOCATION_NOT_FOUND'; end if;

  v_service := public._service_charge();

  select coalesce((select value::numeric::int from public.delivery_settings
                    where key = 'pack_meal_capacity'), 8)
    into v_capacity;

  for v_leg in select * from jsonb_array_elements(p_legs)
  loop
    select id, name, pack_price,
           (is_featured and badge_label = 'Major') as is_uniflex
      into v_vendor
      from public.vendors
     where id = (v_leg ->> 'vendor_id')::uuid
       and is_active = true and deleted_at is null;
    if not found then raise exception 'VENDOR_NOT_FOUND'; end if;
    if v_vendor.id = any (v_vendor_seen) then raise exception 'DUPLICATE_VENDOR'; end if;
    v_vendor_seen := v_vendor_seen || v_vendor.id;

    -- Pack 1 / Part 3: ordering-style rules (fixed menu = no packs, max 20
    -- of an item; a cart built for the other style is refused).
    perform public._check_leg_style(v_vendor.id, v_leg ->> 'ordering_style',
                                    v_leg -> 'packs', v_leg -> 'items');

    -- Items: price comes from the products table, never from the client.
    v_items_out := '[]'::jsonb;
    v_leg_sub   := 0;
    if coalesce(jsonb_typeof(v_leg -> 'items'), '') <> 'array'
       or jsonb_array_length(v_leg -> 'items') = 0 then
      raise exception 'EMPTY_ORDER';
    end if;
    for v_item in select * from jsonb_array_elements(v_leg -> 'items')
    loop
      v_qty := (v_item ->> 'quantity')::int;
      if v_qty is null or v_qty < 1 or v_qty > 99 then
        raise exception 'INVALID_QUANTITY';
      end if;
      select id, name, base_price, is_available, deleted_at
        into v_product
        from public.products
       where id = (v_item ->> 'product_id')::uuid
         and vendor_id = v_vendor.id;
      if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
      if not v_product.is_available or v_product.deleted_at is not null then
        raise exception 'PRODUCT_UNAVAILABLE';
      end if;
      v_leg_sub := v_leg_sub + v_product.base_price * v_qty;
      v_items_out := v_items_out || jsonb_build_object(
        'product_id', v_product.id, 'product_name', v_product.name,
        'quantity', v_qty, 'unit_price', v_product.base_price);
    end loop;

    -- Packs: contents must be this vendor's products that are in the
    -- order, never more of a product than was ordered, and within the
    -- meal-spoon capacity.
    v_packs_out := '[]'::jsonb;
    v_leg_packs := 0;
    for v_pack in select * from jsonb_array_elements(
                    coalesce(v_leg -> 'packs', '[]'::jsonb))
    loop
      v_pack_items := '[]'::jsonb;
      v_spoons := 0;
      for v_pack_item in select * from jsonb_array_elements(
                           coalesce(v_pack -> 'items', '[]'::jsonb))
      loop
        v_qty := (v_pack_item ->> 'quantity')::int;
        if v_qty is null or v_qty < 1 or v_qty > 99 then
          raise exception 'INVALID_QUANTITY';
        end if;
        select id, name, section, food_subsection into v_product
          from public.products
         where id = (v_pack_item ->> 'product_id')::uuid
           and vendor_id = v_vendor.id;
        if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
        if v_product.section = 'food' and v_product.food_subsection = 'meal' then
          v_spoons := v_spoons + v_qty;
        end if;
        v_pack_items := v_pack_items || jsonb_build_object(
          'product_id', v_product.id, 'product_name', v_product.name,
          'quantity', v_qty);
      end loop;
      if v_spoons > v_capacity then raise exception 'PACK_OVER_CAPACITY'; end if;
      v_packs_out := v_packs_out || jsonb_build_object('items', v_pack_items);
      v_leg_packs := v_leg_packs + 1;
    end loop;

    -- No product may appear in packs more often than it was ordered.
    if exists (
      select 1
        from (select (pit ->> 'product_id') as pid, sum((pit ->> 'quantity')::int) as q
                from jsonb_array_elements(v_packs_out) pk,
                     jsonb_array_elements(pk -> 'items') pit
               group by 1) packed
        left join (select (it ->> 'product_id') as pid, sum((it ->> 'quantity')::int) as q
                     from jsonb_array_elements(v_items_out) it
                    group by 1) ordered using (pid)
       where packed.q > coalesce(ordered.q, 0)
    ) then
      raise exception 'PACK_MISMATCH';
    end if;

    v_leg_pack_fee := v_leg_packs * coalesce(v_vendor.pack_price, 0);
    v_leg_fee      := v_loc.price * public._pack_brackets(v_leg_packs);
    v_fee_total    := v_fee_total + v_leg_fee;

    v_prepared := v_prepared || jsonb_build_object(
      'vendor_id',     v_vendor.id,
      'source',        case when v_vendor.is_uniflex then 'uniflex' else 'partner' end,
      'items',         v_items_out,
      'packs',         v_packs_out,
      'pack_count',    v_leg_packs,
      'pack_fee',      v_leg_pack_fee,
      'subtotal',      v_leg_sub,
      'delivery_fee',  v_leg_fee);
  end loop;

  v_total := v_fee_total + v_service;

  -- ── Wallet ─────────────────────────────────────────────────────────
  select balance into v_balance from public.wallets
   where user_id = v_student for update;
  if not found then raise exception 'WALLET_NOT_FOUND'; end if;
  if v_balance < v_total then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.wallets set balance = balance - v_total
   where user_id = v_student returning balance into v_new_balance;

  insert into public.wallet_transactions
    (user_id, type, amount, source, balance_after)
  values
    (v_student, 'debit', v_total, 'commitment_fee', v_new_balance);

  -- ── Create the group (already paid → enters the rider pool) ────────
  insert into public.delivery_groups
    (student_id, delivery_type, delivery_location, student_note,
     commitment_fee_total, service_charge, status,
     delivery_location_id, location_details)
  values
    (v_student, 'delivery', v_loc.name, v_note,
     v_fee_total, v_service, 'commitment_paid',
     v_loc.id, v_details)
  returning id into v_group_id;

  for v_leg in select * from jsonb_array_elements(v_prepared)
  loop
    insert into public.orders
      (student_id, vendor_id, source, type, status, delivery_type,
       delivery_location, total_amount, estimated_time,
       pack_count, pack_fee, notes, delivery_group_id,
       commitment_fee_paid, commitment_fee_amount,
       delivery_location_id, location_details)
    values
      (v_student,
       (v_leg ->> 'vendor_id')::uuid,
       v_leg ->> 'source',
       'food', 'placed', 'delivery',
       v_loc.name,
       (v_leg ->> 'subtotal')::numeric + (v_leg ->> 'pack_fee')::numeric,
       '20–30 min',
       (v_leg ->> 'pack_count')::int,
       (v_leg ->> 'pack_fee')::numeric,
       v_note,
       v_group_id,
       true, (v_leg ->> 'delivery_fee')::numeric,
       v_loc.id, v_details)
    returning id into v_order_id;
    v_order_ids := v_order_ids || v_order_id;

    for v_item in select * from jsonb_array_elements(v_leg -> 'items')
    loop
      insert into public.order_items
        (order_id, product_id, product_name, quantity, unit_price, selected_options)
      values
        (v_order_id, (v_item ->> 'product_id')::uuid, v_item ->> 'product_name',
         (v_item ->> 'quantity')::int, (v_item ->> 'unit_price')::numeric,
         '[]'::jsonb);
    end loop;

    v_idx := 0;
    for v_pack in select * from jsonb_array_elements(v_leg -> 'packs')
    loop
      insert into public.order_packs (order_id, pack_index, items)
      values (v_order_id, v_idx, v_pack -> 'items');
      v_idx := v_idx + 1;
    end loop;
  end loop;

  v_result := jsonb_build_object(
    'kind',               'delivery',
    'order_id',           v_group_id,
    'group_id',           v_group_id,
    'order_ids',          to_jsonb(v_order_ids),
    'delivery_fee_total', v_fee_total,
    'service_charge',     v_service,
    'total_charged',      v_total,
    'balance_after',      v_new_balance);

  insert into public.order_payment_attempts (idempotency_key, student_id, kind, result)
  values (p_idempotency_key, v_student, 'delivery', v_result);

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_paid_pickup_order(p_idempotency_key uuid, p_pin text, p_vendor_id uuid, p_items jsonb, p_packs jsonb DEFAULT '[]'::jsonb, p_scheduled_for timestamp with time zone DEFAULT NULL::timestamp with time zone, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_student      uuid := auth.uid();
  v_existing     jsonb;
  v_pin_status   text;
  v_vendor       record;
  v_product      record;
  v_capacity     int;
  v_item         jsonb;
  v_pack         jsonb;
  v_pack_item    jsonb;
  v_items_out    jsonb := '[]'::jsonb;
  v_packs_out    jsonb := '[]'::jsonb;
  v_pack_items   jsonb;
  v_qty          int;
  v_spoons       int;
  v_subtotal     numeric(10,2) := 0;
  v_pack_count   int := 0;
  v_pack_fee     numeric(10,2);
  v_total        numeric(10,2);
  v_balance      numeric;
  v_new_balance  numeric;
  v_order_id     uuid;
  v_idx          int := 0;
  v_note         text := nullif(trim(coalesce(p_notes, '')), '');
  v_plan_id      uuid;
  v_plan_period  text;
  v_plan_budget  numeric;
  v_plan_spent   numeric;
  v_period_start timestamptz;
  v_period_end   timestamptz;
  v_new_spent    numeric;
  v_plan_over    boolean := false;
  v_result       jsonb;
begin
  if v_student is null then raise exception 'Unauthorized'; end if;
  if p_idempotency_key is null then raise exception 'IDEMPOTENCY_KEY_REQUIRED'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));

  select result into v_existing
    from public.order_payment_attempts
   where idempotency_key = p_idempotency_key and student_id = v_student;
  if found then
    return v_existing || jsonb_build_object('replayed', true);
  end if;
  if exists (select 1 from public.order_payment_attempts
              where idempotency_key = p_idempotency_key) then
    raise exception 'IDEMPOTENCY_KEY_IN_USE';
  end if;

  v_pin_status := public._check_transaction_pin(p_pin);
  if v_pin_status <> 'ok' then
    return jsonb_build_object('error', case v_pin_status
      when 'locked'  then 'PIN_LOCKED'
      when 'not_set' then 'PIN_NOT_SET'
      else 'INVALID_PIN' end);
  end if;

  if p_scheduled_for is not null and p_scheduled_for <= now() then
    raise exception 'SCHEDULE_IN_PAST';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'EMPTY_ORDER';
  end if;
  if char_length(coalesce(v_note, '')) > 500 then raise exception 'TEXT_TOO_LONG'; end if;

  select id, pack_price, (is_featured and badge_label = 'Major') as is_uniflex
    into v_vendor
    from public.vendors
   where id = p_vendor_id and is_active = true and deleted_at is null;
  if not found then raise exception 'VENDOR_NOT_FOUND'; end if;
  if not v_vendor.is_uniflex then raise exception 'PICKUP_UNIFLEX_ONLY'; end if;

  -- Pack 1 / Part 3: ordering-style rules (see _check_leg_style).
  perform public._check_leg_style(v_vendor.id, null, p_packs, p_items);

  select coalesce((select value::numeric::int from public.delivery_settings
                    where key = 'pack_meal_capacity'), 8)
    into v_capacity;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item ->> 'quantity')::int;
    if v_qty is null or v_qty < 1 or v_qty > 99 then
      raise exception 'INVALID_QUANTITY';
    end if;
    select id, name, base_price, is_available, deleted_at into v_product
      from public.products
     where id = (v_item ->> 'product_id')::uuid and vendor_id = v_vendor.id;
    if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
    if not v_product.is_available or v_product.deleted_at is not null then
      raise exception 'PRODUCT_UNAVAILABLE';
    end if;
    v_subtotal := v_subtotal + v_product.base_price * v_qty;
    v_items_out := v_items_out || jsonb_build_object(
      'product_id', v_product.id, 'product_name', v_product.name,
      'quantity', v_qty, 'unit_price', v_product.base_price);
  end loop;

  for v_pack in select * from jsonb_array_elements(
                  coalesce(p_packs, '[]'::jsonb))
  loop
    v_pack_items := '[]'::jsonb;
    v_spoons := 0;
    for v_pack_item in select * from jsonb_array_elements(
                         coalesce(v_pack -> 'items', '[]'::jsonb))
    loop
      v_qty := (v_pack_item ->> 'quantity')::int;
      if v_qty is null or v_qty < 1 or v_qty > 99 then
        raise exception 'INVALID_QUANTITY';
      end if;
      select id, name, section, food_subsection into v_product
        from public.products
       where id = (v_pack_item ->> 'product_id')::uuid and vendor_id = v_vendor.id;
      if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
      if v_product.section = 'food' and v_product.food_subsection = 'meal' then
        v_spoons := v_spoons + v_qty;
      end if;
      v_pack_items := v_pack_items || jsonb_build_object(
        'product_id', v_product.id, 'product_name', v_product.name,
        'quantity', v_qty);
    end loop;
    if v_spoons > v_capacity then raise exception 'PACK_OVER_CAPACITY'; end if;
    v_packs_out := v_packs_out || jsonb_build_object('items', v_pack_items);
    v_pack_count := v_pack_count + 1;
  end loop;

  if exists (
    select 1
      from (select (pit ->> 'product_id') as pid, sum((pit ->> 'quantity')::int) as q
              from jsonb_array_elements(v_packs_out) pk,
                   jsonb_array_elements(pk -> 'items') pit
             group by 1) packed
      left join (select (it ->> 'product_id') as pid, sum((it ->> 'quantity')::int) as q
                   from jsonb_array_elements(v_items_out) it
                  group by 1) ordered using (pid)
     where packed.q > coalesce(ordered.q, 0)
  ) then
    raise exception 'PACK_MISMATCH';
  end if;

  v_pack_fee := v_pack_count * coalesce(v_vendor.pack_price, 0);
  v_total    := v_subtotal + v_pack_fee;     -- pickup: no delivery fee, no service charge

  select balance into v_balance from public.wallets
   where user_id = v_student for update;
  if not found then raise exception 'WALLET_NOT_FOUND'; end if;
  if v_balance < v_total then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.wallets set balance = balance - v_total
   where user_id = v_student returning balance into v_new_balance;

  insert into public.orders
    (student_id, vendor_id, source, type, status, delivery_type,
     total_amount, estimated_time, scheduled_for,
     pack_count, pack_fee, notes)
  values
    (v_student, v_vendor.id, 'uniflex', 'food', 'placed', 'pickup',
     v_total,
     case when p_scheduled_for is not null then 'Scheduled' else '20–30 min' end,
     p_scheduled_for, v_pack_count, v_pack_fee, v_note)
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(v_items_out)
  loop
    insert into public.order_items
      (order_id, product_id, product_name, quantity, unit_price, selected_options)
    values
      (v_order_id, (v_item ->> 'product_id')::uuid, v_item ->> 'product_name',
       (v_item ->> 'quantity')::int, (v_item ->> 'unit_price')::numeric,
       '[]'::jsonb);
  end loop;

  for v_pack in select * from jsonb_array_elements(v_packs_out)
  loop
    insert into public.order_packs (order_id, pack_index, items)
    values (v_order_id, v_idx, v_pack -> 'items');
    v_idx := v_idx + 1;
  end loop;

  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_student, 'debit', v_total, 'order_payment', v_order_id, v_new_balance);

  -- Saving plan (lazy period reset) — unchanged behaviour.
  select id, period, budget, spent, period_start
    into v_plan_id, v_plan_period, v_plan_budget, v_plan_spent, v_period_start
    from public.saving_plans
   where user_id = v_student and is_active
   limit 1;
  if v_plan_id is not null then
    v_period_end := case v_plan_period
      when 'daily'  then v_period_start + interval '1 day'
      when 'weekly' then v_period_start + interval '7 days'
      else               v_period_start + interval '1 month'
    end;
    if now() >= v_period_end then
      v_period_start := date_trunc('day', now());
      v_new_spent    := v_total;
    else
      v_new_spent    := v_plan_spent + v_total;
    end if;
    update public.saving_plans
       set spent = v_new_spent, period_start = v_period_start, updated_at = now()
     where id = v_plan_id;
    v_plan_over := v_new_spent > v_plan_budget;
  end if;

  v_result := jsonb_build_object(
    'kind',             'pickup',
    'order_id',         v_order_id,
    'service_charge',   0,
    'total_charged',    v_total,
    'balance_after',    v_new_balance,
    'plan_over_budget', v_plan_over);

  insert into public.order_payment_attempts (idempotency_key, student_id, kind, result)
  values (p_idempotency_key, v_student, 'pickup', v_result);

  return v_result;
end;
$function$;
