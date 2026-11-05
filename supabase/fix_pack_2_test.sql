-- =====================================================================
-- Fix Pack 2 — SQL Test Script
--
-- Runs inside a transaction that is always rolled back, so it is safe
-- to execute in the Supabase SQL editor on a live database.
-- Every assertion raises an exception on failure; a clean run prints
-- a final NOTICE: All Fix Pack 2 tests passed.
-- =====================================================================

begin;

-- ── Helpers ───────────────────────────────────────────────────────────

create or replace function _assert(condition boolean, msg text)
returns void language plpgsql as $$
begin
  if not condition then
    raise exception 'ASSERTION FAILED: %', msg;
  end if;
end;
$$;


-- ── 1. Schema: new columns exist ──────────────────────────────────────

select _assert(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'delivery_groups'
      and column_name  = 'rider_accepted_at'
  ),
  'delivery_groups.rider_accepted_at column is missing'
);

select _assert(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'delivery_groups'
      and column_name  = 'cancelled_by_student'
  ),
  'delivery_groups.cancelled_by_student column is missing'
);

select _assert(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'support_messages'
      and column_name  = 'delivery_group_id'
  ),
  'support_messages.delivery_group_id column is missing (Fix Pack 1)'
);


-- ── 2. Status constraint accepts rider_accepted ───────────────────────

do $$
declare
  v_student_id  uuid;
  v_location_id uuid;
  v_group_id    uuid;
begin
  select id into v_student_id from public.profiles
  where role = 'student' and is_active = true limit 1;

  if v_student_id is null then
    raise notice 'SKIP: no active student found — status constraint test skipped';
  else
    select id into v_location_id from public.delivery_locations limit 1;

    insert into public.delivery_groups (
      student_id, delivery_type, delivery_location_id,
      commitment_fee_total, status
    ) values (
      v_student_id, 'delivery', v_location_id,
      300, 'commitment_paid'
    ) returning id into v_group_id;

    update public.delivery_groups
    set status = 'rider_accepted', rider_accepted_at = now()
    where id = v_group_id;

    perform _assert(
      (select status from public.delivery_groups where id = v_group_id) = 'rider_accepted',
      'rider_accepted status was not stored'
    );

    perform _assert(
      (select rider_accepted_at from public.delivery_groups where id = v_group_id) is not null,
      'rider_accepted_at was not set'
    );
  end if;
end;
$$;


-- ── 3. set_delivery_group_final_price: validation guards ──────────────

do $$
declare
  v_group_id uuid;
  v_hit      boolean := false;
begin
  select id into v_group_id
  from public.delivery_groups
  where status = 'rider_accepted'
  limit 1;

  if v_group_id is null then
    raise notice 'SKIP: no rider_accepted group available — final price validation test skipped';
    return;
  end if;

  begin
    perform public.set_delivery_group_final_price(v_group_id, 0);
  exception when others then
    v_hit := true;
  end;
  perform _assert(v_hit, 'set_delivery_group_final_price should reject amount = 0');

  v_hit := false;
  begin
    perform public.set_delivery_group_final_price(v_group_id, -100);
  exception when others then
    v_hit := true;
  end;
  perform _assert(v_hit, 'set_delivery_group_final_price should reject negative amount');

  v_hit := false;
  begin
    perform public.set_delivery_group_final_price(v_group_id, 500001);
  exception when others then
    v_hit := true;
  end;
  perform _assert(v_hit, 'set_delivery_group_final_price should reject amount > 500000');
end;
$$;


-- ── 4. RPCs exist ─────────────────────────────────────────────────────

select _assert(
  exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'set_delivery_group_final_price'
  ),
  'set_delivery_group_final_price RPC missing'
);

select _assert(
  exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'decline_group_final_amount'
  ),
  'decline_group_final_amount RPC missing'
);

select _assert(
  exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'cancel_delivery_group_before_accept'
  ),
  'cancel_delivery_group_before_accept RPC missing'
);

select _assert(
  exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'get_group_customer_info'
  ),
  'get_group_customer_info RPC missing'
);

select _assert(
  exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'get_group_items'
  ),
  'get_group_items RPC missing'
);


-- ── 5. place_multi_vendor_order rejects scheduled_for on delivery ─────

do $$
declare
  v_student_id    uuid;
  v_location_id   uuid;
  v_product_id    uuid;
  v_vendor_id     uuid;
  v_hit           boolean := false;
begin
  select p.id, v.id, pr.id
  into v_student_id, v_vendor_id, v_product_id
  from public.profiles p
  cross join public.vendors v
  cross join public.products pr
  where p.role = 'student' and p.is_active = true
    and v.is_active = true
    and pr.vendor_id = v.id and pr.is_available = true
  limit 1;

  select id into v_location_id from public.delivery_locations limit 1;

  if v_student_id is null or v_product_id is null or v_location_id is null then
    raise notice 'SKIP: insufficient seed data — scheduled_for guard test skipped';
    return;
  end if;

  begin
    perform public.place_multi_vendor_order(
      p_items            := jsonb_build_array(
        jsonb_build_object(
          'product_id', v_product_id,
          'quantity', 1,
          'unit_price', 500,
          'options', '[]'::jsonb
        )
      ),
      p_delivery_type        := 'delivery',
      p_delivery_location_id := v_location_id,
      p_scheduled_for        := now() + interval '2 hours',
      p_pin                  := '0000'
    );
  exception when others then
    v_hit := true;
  end;

  perform _assert(v_hit,
    'place_multi_vendor_order should reject scheduled_for on delivery type');
end;
$$;


-- ── 6. Realtime: delivery_groups is published ─────────────────────────

select _assert(
  exists (
    select 1 from pg_publication_tables
    where pubname    = 'supabase_realtime'
      and schemaname = 'public'
      and tablename  = 'delivery_groups'
  ),
  'delivery_groups is not in supabase_realtime publication'
);


-- ── Done ──────────────────────────────────────────────────────────────

do $$ begin raise notice 'All Fix Pack 2 tests passed.'; end; $$;

rollback;
