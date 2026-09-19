-- ============================================================================
-- Security / correctness fix #6 (Stage-2 bug #7)
-- Campus/Hostel food-delivery orders were invisible to riders + got no PIN.
--
-- When delivery_type was extended to add 'campus_delivery' / 'hostel_delivery'
-- (see the orders_delivery_type_check migration), three guards were NOT
-- updated and still matched delivery_type = 'delivery' EXACTLY:
--   1. _generate_delivery_pin() trigger  -> campus/hostel orders got NULL pin
--   2. RLS policy "orders: rider read pool" -> hidden from the rider job pool
--   3. accept_order() eligibility guard     -> rider could not accept
-- The student food-order path only ever sends 'pickup' / 'campus_delivery' /
-- 'hostel_delivery' (never plain 'delivery'), so NO real student food delivery
-- could ever reach a rider.
--
-- Fix: treat campus_delivery + hostel_delivery the same as delivery in all
-- three places. Idempotent — safe to run more than once.
-- ============================================================================

-- 1. Delivery PIN trigger — generate a PIN for every delivery-type variant.
create extension if not exists pgcrypto with schema extensions;
create or replace function public._generate_delivery_pin()
returns trigger language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_pin   text := '';
  v_bytes bytea;
begin
  if new.delivery_type in ('delivery', 'campus_delivery', 'hostel_delivery') then
    v_bytes := gen_random_bytes(4);
    for i in 0..3 loop
      v_pin := v_pin || substr(v_chars, (get_byte(v_bytes, i) % 32) + 1, 1);
    end loop;
    new.delivery_pin := v_pin;
  end if;
  return new;
end;
$$;

-- 2. Rider job-pool RLS policy — include campus/hostel deliveries.
drop policy if exists "orders: rider read pool" on public.orders;
create policy "orders: rider read pool"
  on public.orders for select to authenticated
  using (
    public.is_rider()
    and rider_id is null
    and (
      (source = 'uniflex' and status = 'ready'
         and delivery_type in ('delivery', 'campus_delivery', 'hostel_delivery'))
      or (source = 'partner' and status = 'placed'
         and delivery_type in ('delivery', 'campus_delivery', 'hostel_delivery'))
      or (type = 'around' and status = 'placed')
    )
  );

-- 3. accept_order() eligibility guard — include campus/hostel deliveries.
create or replace function public.accept_order(p_order_id uuid)
returns void language plpgsql security definer as $$
declare
  v_order public.orders%rowtype;
begin
  if not public.is_rider() then
    raise exception 'Unauthorized';
  end if;

  select * into v_order from public.orders
  where id = p_order_id
  for update nowait;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.rider_id is not null then
    raise exception 'Order already taken';
  end if;

  if not (
    (v_order.source = 'uniflex' and v_order.status = 'ready'
       and v_order.delivery_type in ('delivery', 'campus_delivery', 'hostel_delivery'))
    or (v_order.source = 'partner' and v_order.status = 'placed'
       and v_order.delivery_type in ('delivery', 'campus_delivery', 'hostel_delivery'))
    or (v_order.type = 'around' and v_order.status = 'placed')
  ) then
    raise exception 'Order is not eligible for acceptance';
  end if;

  update public.orders
  set
    rider_id       = auth.uid(),
    delivery_stage = 'accepted',
    status         = 'out_for_delivery'
  where id = p_order_id;
end;
$$;

grant execute on function public.accept_order(uuid) to authenticated;
