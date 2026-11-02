-- ==========================================================================
-- Seed test products so every vendor has food (meal + protein/topping),
-- drinks, and others. Idempotent — skips if product already exists.
-- ==========================================================================

-- ── Uniflex (v1) — already has meals, proteins, drinks. Add others. ──

insert into public.products (vendor_id, name, description, category, base_price, requires_pack, section, food_subsection)
select '00000000-0000-0000-0000-000000000001', v.name, v.description, 'Others', v.price, false, 'others', null
from (values
  ('Shawarma Wrap',   'Chicken shawarma with garlic sauce and veggies.', 1500::numeric),
  ('Bread & Butter',  'Sliced bread with butter. Simple and filling.',    300::numeric),
  ('Ice Cream Cup',   'Vanilla ice cream in a cup. 150ml.',              500::numeric)
) as v(name, description, price)
where not exists (
  select 1 from public.products p
  where p.vendor_id = '00000000-0000-0000-0000-000000000001'
    and p.name = v.name
);


-- ── Mama Tee (v2) — only has meals. Add proteins, drinks, others. ────

insert into public.products (vendor_id, name, description, category, base_price, requires_pack, section, food_subsection)
select '00000000-0000-0000-0000-000000000002', v.name, v.description, 'Proteins', v.price, true, 'food', 'protein_topping'
from (values
  ('Assorted Meat',  'Mixed beef, tripe, and cowfoot.',  600::numeric),
  ('Stockfish',      'Dried stockfish, rehydrated.',     500::numeric),
  ('Ponmo (Cowhide)','Soft cowhide, well-seasoned.',     300::numeric)
) as v(name, description, price)
where not exists (
  select 1 from public.products p
  where p.vendor_id = '00000000-0000-0000-0000-000000000002'
    and p.name = v.name
);

insert into public.products (vendor_id, name, description, category, base_price, requires_pack, section, food_subsection)
select '00000000-0000-0000-0000-000000000002', v.name, v.description, 'Drinks', v.price, false, 'drinks', null
from (values
  ('Palm Wine',      'Fresh palm wine, chilled. 35cl.',  400::numeric),
  ('Bottled Water',  '75cl table water.',                200::numeric)
) as v(name, description, price)
where not exists (
  select 1 from public.products p
  where p.vendor_id = '00000000-0000-0000-0000-000000000002'
    and p.name = v.name
);

insert into public.products (vendor_id, name, description, category, base_price, requires_pack, section, food_subsection)
select '00000000-0000-0000-0000-000000000002', v.name, v.description, 'Others', v.price, false, 'others', null
from (values
  ('Moi Moi Wrap',   'Bean pudding wrapped in leaves. Grab and go.', 400::numeric),
  ('Chin Chin Bag',  'Crunchy fried dough snack.',                   300::numeric)
) as v(name, description, price)
where not exists (
  select 1 from public.products p
  where p.vendor_id = '00000000-0000-0000-0000-000000000002'
    and p.name = v.name
);


-- ── QuickBite Grill (v3) — only has grills (meals). Add proteins, drinks, others. ──

insert into public.products (vendor_id, name, description, category, base_price, requires_pack, section, food_subsection)
select '00000000-0000-0000-0000-000000000003', v.name, v.description, 'Proteins', v.price, true, 'food', 'protein_topping'
from (values
  ('Extra Chicken',  'Additional grilled chicken piece.',  500::numeric),
  ('Extra Beef',     'Additional suya beef sticks (x2).',  400::numeric)
) as v(name, description, price)
where not exists (
  select 1 from public.products p
  where p.vendor_id = '00000000-0000-0000-0000-000000000003'
    and p.name = v.name
);

insert into public.products (vendor_id, name, description, category, base_price, requires_pack, section, food_subsection)
select '00000000-0000-0000-0000-000000000003', v.name, v.description, 'Drinks', v.price, false, 'drinks', null
from (values
  ('Chapman',        'Classic Nigerian Chapman mocktail. 50cl.',  600::numeric),
  ('Malt Drink',     'Chilled malt drink. 35cl.',                300::numeric)
) as v(name, description, price)
where not exists (
  select 1 from public.products p
  where p.vendor_id = '00000000-0000-0000-0000-000000000003'
    and p.name = v.name
);

insert into public.products (vendor_id, name, description, category, base_price, requires_pack, section, food_subsection)
select '00000000-0000-0000-0000-000000000003', v.name, v.description, 'Others', v.price, false, 'others', null
from (values
  ('Shawarma Platter','Large shawarma with fries and coleslaw.', 2500::numeric),
  ('Spring Rolls',    'Crispy vegetable spring rolls (4 pcs).',   800::numeric)
) as v(name, description, price)
where not exists (
  select 1 from public.products p
  where p.vendor_id = '00000000-0000-0000-0000-000000000003'
    and p.name = v.name
);


-- ── Campus Smoothies (v4) — only has drinks. Add meals, proteins, others. ──

insert into public.products (vendor_id, name, description, category, base_price, requires_pack, section, food_subsection)
select '00000000-0000-0000-0000-000000000004', v.name, v.description, 'Meals', v.price, true, 'food', 'meal'
from (values
  ('Acai Bowl',       'Blended acai with granola, banana, and honey.',  1500::numeric),
  ('Fruit Salad',     'Mixed fresh fruit bowl. Large.',                  800::numeric)
) as v(name, description, price)
where not exists (
  select 1 from public.products p
  where p.vendor_id = '00000000-0000-0000-0000-000000000004'
    and p.name = v.name
);

insert into public.products (vendor_id, name, description, category, base_price, requires_pack, section, food_subsection)
select '00000000-0000-0000-0000-000000000004', v.name, v.description, 'Proteins', v.price, true, 'food', 'protein_topping'
from (values
  ('Protein Scoop',   'Whey protein add-on to any smoothie.',  300::numeric)
) as v(name, description, price)
where not exists (
  select 1 from public.products p
  where p.vendor_id = '00000000-0000-0000-0000-000000000004'
    and p.name = v.name
);

insert into public.products (vendor_id, name, description, category, base_price, requires_pack, section, food_subsection)
select '00000000-0000-0000-0000-000000000004', v.name, v.description, 'Others', v.price, false, 'others', null
from (values
  ('Energy Bar',      'Oat and nut energy bar.',                400::numeric),
  ('Granola Pack',    'Toasted granola with dried fruit. 200g.', 700::numeric)
) as v(name, description, price)
where not exists (
  select 1 from public.products p
  where p.vendor_id = '00000000-0000-0000-0000-000000000004'
    and p.name = v.name
);


-- ── Verify ──────────────────────────────────────────────────────────────
select
  v.name as vendor,
  p.section,
  p.food_subsection,
  count(*) as items
from public.products p
join public.vendors v on v.id = p.vendor_id
where p.is_available = true
group by v.name, p.section, p.food_subsection
order by v.name, p.section, p.food_subsection;
