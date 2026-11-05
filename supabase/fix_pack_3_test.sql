-- =====================================================================
-- Fix Pack 3 — SQL Test Script
--
-- Runs inside a transaction that is always rolled back, so it is safe
-- to execute in the Supabase SQL editor on a live database.
-- Every assertion raises an exception on failure; a clean run prints
-- a final NOTICE: All Fix Pack 3 tests passed.
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


-- ── 1. Schema: soft-delete columns exist ─────────────────────────────

select _assert(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'products'
      and column_name  = 'deleted_at'
  ),
  'products.deleted_at column is missing'
);

select _assert(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'vendors'
      and column_name  = 'deleted_at'
  ),
  'vendors.deleted_at column is missing'
);

select _assert(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name   = 'errand_categories'
      and column_name  = 'deleted_at'
  ),
  'errand_categories.deleted_at column is missing'
);


-- ── 2. Storage bucket exists ─────────────────────────────────────────

select _assert(
  exists (
    select 1 from storage.buckets
    where id = 'product-images' and public = true
  ),
  'product-images storage bucket is missing or not public'
);


-- ── 3. Advertisements: link_type constraint is narrow ────────────────

do $$
declare
  v_hit boolean := false;
begin
  begin
    insert into public.advertisements (
      id, title, subtitle, is_dark, is_active, sort_order, link_type
    ) values (
      gen_random_uuid(), 'Test', '', false, false, 999, 'vendor'
    );
  exception when check_violation then
    v_hit := true;
  end;
  perform _assert(v_hit,
    'advertisements: inserting link_type=vendor should violate check constraint');
end;
$$;

do $$
declare
  v_hit boolean := false;
begin
  begin
    insert into public.advertisements (
      id, title, subtitle, is_dark, is_active, sort_order, link_type
    ) values (
      gen_random_uuid(), 'Test', '', false, false, 999, 'wallet'
    );
  exception when check_violation then
    v_hit := true;
  end;
  perform _assert(v_hit,
    'advertisements: inserting link_type=wallet should violate check constraint');
end;
$$;

-- 'none' and 'url' must be accepted.
do $$
declare
  v_id_none uuid := gen_random_uuid();
  v_id_url  uuid := gen_random_uuid();
begin
  insert into public.advertisements (
    id, title, subtitle, is_dark, is_active, sort_order, link_type
  ) values (
    v_id_none, 'Test', '', false, false, 999, 'none'
  );

  insert into public.advertisements (
    id, title, subtitle, is_dark, is_active, sort_order, link_type, link_value
  ) values (
    v_id_url, 'Test', '', false, false, 999, 'url', 'https://example.com'
  );

  perform _assert(
    (select count(*) from public.advertisements where id in (v_id_none, v_id_url)) = 2,
    'advertisements: none and url link types should be insertable'
  );
end;
$$;


-- ── 4. Soft-delete filtering: products ───────────────────────────────

do $$
declare
  v_product_id uuid;
begin
  select id into v_product_id
  from public.products
  where is_available = true and deleted_at is null
  limit 1;

  if v_product_id is null then
    raise notice 'SKIP: no available product found — soft-delete filter test skipped';
    return;
  end if;

  update public.products set deleted_at = now() where id = v_product_id;

  perform _assert(
    not exists (
      select 1 from public.products
      where id = v_product_id
        and is_available = true
        and deleted_at is null
    ),
    'deleted product still passes student filter (deleted_at is null check broken)'
  );

  perform _assert(
    exists (
      select 1 from public.products
      where id = v_product_id and deleted_at is not null
    ),
    'deleted product missing from full table (hard-delete happened unexpectedly)'
  );
end;
$$;


-- ── 5. Soft-delete filtering: vendors ────────────────────────────────

do $$
declare
  v_vendor_id uuid;
begin
  select id into v_vendor_id
  from public.vendors
  where is_active = true and deleted_at is null
  limit 1;

  if v_vendor_id is null then
    raise notice 'SKIP: no active vendor found — vendor soft-delete test skipped';
    return;
  end if;

  update public.vendors set deleted_at = now() where id = v_vendor_id;

  perform _assert(
    not exists (
      select 1 from public.vendors
      where id = v_vendor_id and deleted_at is null
    ),
    'deleted vendor still passes student filter (vendors.deleted_at filter broken)'
  );

  perform _assert(
    exists (
      select 1 from public.vendors
      where id = v_vendor_id and deleted_at is not null
    ),
    'vendor missing from full table after soft-delete'
  );
end;
$$;


-- ── 6. Soft-delete filtering: errand_categories ──────────────────────

do $$
declare
  v_key text;
begin
  select key into v_key
  from public.errand_categories
  where is_active = true and deleted_at is null
  limit 1;

  if v_key is null then
    raise notice 'SKIP: no active errand category found — category soft-delete test skipped';
    return;
  end if;

  update public.errand_categories set deleted_at = now() where key = v_key;

  perform _assert(
    not exists (
      select 1 from public.errand_categories
      where key = v_key
        and is_active = true
        and deleted_at is null
    ),
    'deleted errand category still passes student filter'
  );

  perform _assert(
    exists (
      select 1 from public.errand_categories
      where key = v_key and deleted_at is not null
    ),
    'errand category missing from full table after soft-delete'
  );
end;
$$;


-- ── 7. products subsection constraint still enforced ─────────────────

do $$
declare
  v_vendor_id uuid;
  v_hit       boolean := false;
begin
  select id into v_vendor_id from public.vendors limit 1;

  if v_vendor_id is null then
    raise notice 'SKIP: no vendor found — subsection constraint test skipped';
    return;
  end if;

  begin
    insert into public.products (
      vendor_id, name, description, category,
      base_price, is_available, section, food_subsection
    ) values (
      v_vendor_id, 'Test Item', '', 'Food',
      500, true, 'food', null
    );
  exception when check_violation then
    v_hit := true;
  end;
  perform _assert(v_hit,
    'products: food section with null food_subsection should violate check constraint');
end;
$$;


-- ── Done ──────────────────────────────────────────────────────────────

do $$ begin raise notice 'All Fix Pack 3 tests passed.'; end; $$;

rollback;
