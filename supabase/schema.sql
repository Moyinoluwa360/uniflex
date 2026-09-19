-- Uniflex — Phase 1 schema (Onboarding & Auth)
--
-- This is not applied automatically — there is no service-role / DB
-- password wired into this repo or its tooling, only the anon key in
-- .env. Run this once, by hand, in the Supabase project's SQL editor
-- (Dashboard → SQL Editor → New query → paste → Run) before testing
-- Phase 1 sign-up/login against a real backend.
--
-- Before running this: in Dashboard → Authentication → Providers → Email,
-- turn OFF "Confirm email". Uniflex verifies the account via Termii phone
-- OTP (see VerifyPhoneScreen) instead of Supabase's email-link
-- confirmation — leaving email confirmation on would leave the account
-- unable to sign in until an email link is also clicked, which this app
-- never sends.

-- ---------------------------------------------------------------------
-- profiles — one row per auth.users row, for every role.
-- Student rows are created by the app during onboarding (see the
-- complete_student_onboarding() function below). Rider/Admin rows are
-- created by hand (see "Seeding a test Rider/Admin account" below) —
-- there is no app path that inserts a profile with role 'rider' or
-- 'admin'.
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role text not null default 'student' check (role in ('student', 'rider', 'admin')),
  email text,
  phone text,
  phone_verified_at timestamptz,
  nickname text unique,
  full_name text,
  matric_number text unique,
  school text default 'Redeemer''s University',
  date_of_birth date,
  referral_code text unique,
  referred_by_code text,
  onboarding_complete boolean not null default false,
  created_at timestamptz not null default now()
);

comment on table public.profiles is
  'One row per account, every role. Student rows are written by complete_student_onboarding(); rider/admin rows are seeded by hand (invite-only, no self-signup).';

-- ---------------------------------------------------------------------
-- wallets — created automatically for a student the moment onboarding
-- completes. Staff (rider/admin) do not get a wallet in this phase.
-- ---------------------------------------------------------------------
create table if not exists public.wallets (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  balance numeric(12, 2) not null default 0,
  -- STUB: not a real Paystack Dedicated Virtual Account. Replaced when
  -- the Payments phase wires up Paystack; format is a local placeholder
  -- reference only, never present it to a user as a real bank account.
  virtual_account_number text not null,
  tier text not null default 'Bronze' check (tier in ('Bronze', 'Silver', 'Gold', 'Platinum')),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- referrals — placeholder relationship only. No reward/credit logic
-- yet; that (plus the leaderboard) is a later phase.
-- ---------------------------------------------------------------------
create table if not exists public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_id uuid not null references public.profiles (id) on delete cascade,
  referred_id uuid not null unique references public.profiles (id) on delete cascade,
  referral_code_used text not null,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.referrals enable row level security;

create policy "profiles: read own row" on public.profiles
  for select using (auth.uid() = id);

create policy "profiles: update own row" on public.profiles
  for update using (auth.uid() = id);

-- No direct insert policy for profiles — rows are written through
-- complete_student_onboarding() (SECURITY DEFINER, below), never by a
-- raw client insert. Rider/Admin rows are inserted by a project admin
-- from the Supabase Studio table editor, which uses the service role
-- and bypasses RLS entirely.

create policy "wallets: read own row" on public.wallets
  for select using (auth.uid() = user_id);

create policy "referrals: read rows referencing me" on public.referrals
  for select using (auth.uid() = referrer_id or auth.uid() = referred_id);

-- ---------------------------------------------------------------------
-- RPCs used by the app instead of raw table access, so uniqueness
-- checks and the multi-table onboarding write happen atomically /
-- server-side rather than as several separate round trips a client
-- could partially fail in the middle of.
-- ---------------------------------------------------------------------

-- Availability checks (Step Two, live validation as the user types).
create or replace function public.is_nickname_available(p_nickname text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.profiles where lower(nickname) = lower(p_nickname)
  );
$$;

create or replace function public.is_matric_number_available(p_matric_number text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.profiles where lower(matric_number) = lower(p_matric_number)
  );
$$;

create or replace function public.is_referral_code_valid(p_code text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where referral_code = upper(trim(p_code))
  );
$$;

-- Step Two submit. Runs as the signed-in user (auth.uid()) and does the
-- whole "profile + wallet + own referral code + referral relationship"
-- write as one transaction: either the student ends up with all four,
-- or (on any error, e.g. a uniqueness race) none of them.
create or replace function public.complete_student_onboarding(
  p_nickname text,
  p_full_name text,
  p_matric_number text,
  p_school text,
  p_date_of_birth date,
  p_referral_code_used text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_new_code text;
  v_referrer_id uuid;
  v_profile public.profiles;
begin
  if v_user_id is null then
    raise exception 'Not signed in';
  end if;

  if p_referral_code_used is not null and length(trim(p_referral_code_used)) > 0 then
    select id into v_referrer_id
      from public.profiles
      where referral_code = upper(trim(p_referral_code_used));

    if v_referrer_id is null then
      raise exception 'Referral code % not found', p_referral_code_used;
    end if;
  end if;

  -- Generate this student's own shareable referral code, retrying on the
  -- rare collision rather than trusting one random draw to be unique.
  loop
    v_new_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from public.profiles where referral_code = v_new_code);
  end loop;

  update public.profiles set
    role = 'student',
    nickname = p_nickname,
    full_name = p_full_name,
    matric_number = p_matric_number,
    school = p_school,
    date_of_birth = p_date_of_birth,
    referral_code = v_new_code,
    referred_by_code = case when v_referrer_id is not null then upper(trim(p_referral_code_used)) else null end,
    onboarding_complete = true
  where id = v_user_id
  returning * into v_profile;

  if not found then
    raise exception 'No profile row for %; Step One (create account) must run first', v_user_id;
  end if;

  insert into public.wallets (user_id, balance, virtual_account_number, tier)
  values (
    v_user_id,
    0,
    -- STUB placeholder VAN — see comment on public.wallets above.
    'UFX-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
    'Bronze'
  )
  on conflict (user_id) do nothing;

  if v_referrer_id is not null then
    insert into public.referrals (referrer_id, referred_id, referral_code_used)
    values (v_referrer_id, v_user_id, upper(trim(p_referral_code_used)))
    on conflict (referred_id) do nothing;
  end if;

  return v_profile;
end;
$$;

grant execute on function public.is_nickname_available(text) to authenticated;
grant execute on function public.is_matric_number_available(text) to authenticated;
grant execute on function public.is_referral_code_valid(text) to authenticated;
grant execute on function public.complete_student_onboarding(text, text, text, text, date, text) to authenticated;

-- ---------------------------------------------------------------------
-- Step One (Create Account) support: the app inserts a bare profiles
-- row itself right after Supabase Auth user creation succeeds (role
-- defaults to 'student', onboarding_complete defaults to false) so that
-- phone/phone_verified_at have somewhere to land before Step Two runs.
-- That insert is a plain authenticated insert restricted to the caller's
-- own id/row.
-- ---------------------------------------------------------------------
create policy "profiles: insert own row" on public.profiles
  for insert with check (auth.uid() = id);

-- ---------------------------------------------------------------------
-- Seeding a test Rider/Admin account (manual, invite-only — there is no
-- app UI that can do this)
-- ---------------------------------------------------------------------
-- 1. Dashboard → Authentication → Users → Add user → set an email +
--    password by hand (this is exactly how a real staff invite would be
--    provisioned later, just done manually for now). Copy the new
--    user's UUID.
-- 2. Table editor → profiles → Insert row:
--      id                  = the UUID from step 1
--      role                = 'rider'  (or 'admin')
--      email               = the same email
--      full_name           = whatever test name you like
--      onboarding_complete = true
--    Leave nickname/matric_number/school/date_of_birth/referral_code
--    null — those are student-only fields.
-- 3. That account can now log in from the app's normal Login screen and
--    will land on RiderShell / AdminShell. No wallet row is created for
--    staff in this phase.


-- =====================================================================
-- PHASE 2 — Home & Core Ordering Flow
-- =====================================================================
-- Append these statements after the Phase 1 block in the same SQL
-- editor run, or run them separately if Phase 1 is already applied.
-- =====================================================================

-- ---------------------------------------------------------------------
-- vendors — the vendors whose menus appear in the Student app.
-- Uniflex is the primary (is_featured true, badge_label 'Major');
-- all others are partner vendors. Partner vendor management (editing
-- menus, toggling active status) is an Admin-phase feature — for now
-- rows are seeded directly below.
-- ---------------------------------------------------------------------
create table if not exists public.vendors (
  id          uuid    primary key default gen_random_uuid(),
  name        text    not null,
  description text    not null default '',
  is_featured boolean not null default false,
  badge_label text,                           -- 'Major' | 'Partner' | null
  image_url   text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- products — items on a vendor's menu.
-- ---------------------------------------------------------------------
create table if not exists public.products (
  id           uuid    primary key default gen_random_uuid(),
  vendor_id    uuid    not null references public.vendors (id) on delete cascade,
  name         text    not null,
  description  text    not null default '',
  category     text    not null,   -- 'Protein Meals' | 'Sides' | 'Snacks' | 'Drinks'
  base_price   numeric(10, 2) not null,
  image_url    text,
  is_available boolean not null default true,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- product_options — configurable add-ons per product.
-- option_group: 'protein' (radio, choose one), 'extra' (checkbox,
-- choose many), 'drink' (not used here — drinks are separate products
-- picked in the customization flow).
-- ---------------------------------------------------------------------
create table if not exists public.product_options (
  id           uuid primary key default gen_random_uuid(),
  product_id   uuid not null references public.products (id) on delete cascade,
  option_group text not null,   -- 'protein' | 'extra'
  name         text not null,
  price_delta  numeric(10, 2) not null default 0
);

-- ---------------------------------------------------------------------
-- orders — one row per order, covering both food-delivery orders
-- (type 'food') and on-demand errand requests (type 'around').
-- source distinguishes Uniflex-fulfilled vs partner-vendor orders.
-- ---------------------------------------------------------------------
create table if not exists public.orders (
  id                uuid    primary key default gen_random_uuid(),
  student_id        uuid    not null references public.profiles (id) on delete cascade,
  vendor_id         uuid    references public.vendors (id),
  source            text    not null default 'uniflex'
                            check (source in ('uniflex', 'partner')),
  type              text    not null default 'food'
                            check (type in ('food', 'around')),
  status            text    not null default 'placed'
                            check (status in (
                              'placed', 'preparing', 'ready',
                              'out_for_delivery', 'ready_for_pickup',
                              'completed', 'cancelled'
                            )),
  delivery_type     text    check (delivery_type in ('pickup', 'delivery')),
  delivery_location text,
  total_amount      numeric(10, 2) not null default 0,
  estimated_time    text,
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- Keep updated_at current automatically.
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

create trigger orders_updated_at
  before update on public.orders
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
-- order_items — line items for food orders. Around requests store their
-- details in around_requests instead.
-- ---------------------------------------------------------------------
create table if not exists public.order_items (
  id               uuid    primary key default gen_random_uuid(),
  order_id         uuid    not null references public.orders (id) on delete cascade,
  product_id       uuid    references public.products (id),
  product_name     text    not null,
  quantity         int     not null default 1 check (quantity > 0),
  unit_price       numeric(10, 2) not null,
  -- [{\"group\": \"protein\", \"name\": \"Chicken\", \"price_delta\": 0}, ...]
  selected_options jsonb   not null default '[]'::jsonb
);

-- ---------------------------------------------------------------------
-- around_requests — details for type='around' orders. Linked 1-to-1
-- to an orders row via order_id; the orders row carries status/amounts.
-- ---------------------------------------------------------------------
create table if not exists public.around_requests (
  id               uuid  primary key default gen_random_uuid(),
  order_id         uuid  not null unique references public.orders (id) on delete cascade,
  category         text  not null
                         check (category in (
                           'errand', 'laundry', 'hostel',
                           'vendor_fetch', 'peer_courier'
                         )),
  pickup_location  text  not null,
  dropoff_location text  not null,
  item_description text  not null,
  estimated_fee    numeric(10, 2) not null default 500
);

-- ---------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------
alter table public.vendors         enable row level security;
alter table public.products        enable row level security;
alter table public.product_options enable row level security;
alter table public.orders          enable row level security;
alter table public.order_items     enable row level security;
alter table public.around_requests enable row level security;

-- Vendors, products, and options are public catalog data — any
-- authenticated user can read them.
create policy "vendors: authenticated read"
  on public.vendors for select to authenticated using (true);

create policy "products: authenticated read"
  on public.products for select to authenticated using (true);

create policy "product_options: authenticated read"
  on public.product_options for select to authenticated using (true);

-- Orders belong to the student who placed them.
create policy "orders: insert own"
  on public.orders for insert
  with check (auth.uid() = student_id);

create policy "orders: read own"
  on public.orders for select
  using (auth.uid() = student_id);

create policy "orders: update own"
  on public.orders for update
  using (auth.uid() = student_id);

-- Order items are readable/insertable by the order's owner.
create policy "order_items: insert own"
  on public.order_items for insert
  with check (
    exists (
      select 1 from public.orders
      where id = order_id and student_id = auth.uid()
    )
  );

create policy "order_items: read own"
  on public.order_items for select
  using (
    exists (
      select 1 from public.orders
      where id = order_id and student_id = auth.uid()
    )
  );

-- Around requests follow the same pattern.
create policy "around_requests: insert own"
  on public.around_requests for insert
  with check (
    exists (
      select 1 from public.orders
      where id = order_id and student_id = auth.uid()
    )
  );

create policy "around_requests: read own"
  on public.around_requests for select
  using (
    exists (
      select 1 from public.orders
      where id = order_id and student_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------
-- Seed data — vendors
-- Fixed UUIDs so the Flutter app can reference Uniflex by a known ID
-- constant if needed, and so re-running this file is idempotent via
-- ON CONFLICT.
-- ---------------------------------------------------------------------
insert into public.vendors (id, name, description, is_featured, badge_label, is_active)
values
  ('00000000-0000-0000-0000-000000000001',
   'Uniflex',
   'Your campus food hub — protein meals, sides, snacks, drinks, and more. Ordered here, delivered or picked up on campus.',
   true, 'Major', true),

  ('00000000-0000-0000-0000-000000000002',
   'Mama Tee Kitchen',
   'Home-cooked Nigerian meals. Fresh pots every day.',
   false, 'Partner', true),

  ('00000000-0000-0000-0000-000000000003',
   'QuickBite Grill',
   'Grilled street food, suya, and sharwarma — fast and hot.',
   false, 'Partner', true),

  ('00000000-0000-0000-0000-000000000004',
   'Campus Smoothies',
   'Cold-pressed smoothies, fresh juices, and milkshakes.',
   false, 'Partner', true)

on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Seed data — Uniflex products
-- ---------------------------------------------------------------------
-- Protein Meals
insert into public.products (vendor_id, name, description, category, base_price)
values
  ('00000000-0000-0000-0000-000000000001',
   'Jollof Rice + Protein',
   'Classic smoky Nigerian jollof rice served with your choice of protein.',
   'Protein Meals', 1200),

  ('00000000-0000-0000-0000-000000000001',
   'Fried Rice + Protein',
   'Vegetable fried rice with carrot, green beans, and sweet corn, served with your choice of protein.',
   'Protein Meals', 1300),

  ('00000000-0000-0000-0000-000000000001',
   'White Rice + Stew + Protein',
   'Parboiled white rice with rich tomato-pepper stew and your choice of protein.',
   'Protein Meals', 1100),

  ('00000000-0000-0000-0000-000000000001',
   'Spaghetti + Protein',
   'Spaghetti in a tomato-based sauce with your choice of protein.',
   'Protein Meals', 1200),

  ('00000000-0000-0000-0000-000000000001',
   'Ofada Rice + Ayamase',
   'Local ofada rice with spicy green ayamase (ofada) stew. Add protein for extra.',
   'Protein Meals', 1400)
on conflict do nothing;

-- Sides
insert into public.products (vendor_id, name, description, category, base_price)
values
  ('00000000-0000-0000-0000-000000000001',
   'Moi Moi',
   'Steamed bean pudding, made fresh daily.',
   'Sides', 400),

  ('00000000-0000-0000-0000-000000000001',
   'Coleslaw',
   'Creamy cabbage and carrot coleslaw.',
   'Sides', 300),

  ('00000000-0000-0000-0000-000000000001',
   'Fried Plantain (Dodo)',
   'Sweet ripe plantain, fried to caramelised perfection.',
   'Sides', 350)
on conflict do nothing;

-- Snacks
insert into public.products (vendor_id, name, description, category, base_price)
values
  ('00000000-0000-0000-0000-000000000001',
   'Chin Chin',
   'Crunchy fried dough snack. A bag per order.',
   'Snacks', 300),

  ('00000000-0000-0000-0000-000000000001',
   'Puff Puff',
   'Soft, deep-fried dough balls. 5 pieces per order.',
   'Snacks', 300),

  ('00000000-0000-0000-0000-000000000001',
   'Meat Pie',
   'Flaky shortcrust pastry filled with spiced minced meat and vegetables.',
   'Snacks', 500)
on conflict do nothing;

-- Drinks
insert into public.products (vendor_id, name, description, category, base_price)
values
  ('00000000-0000-0000-0000-000000000001',
   'Zobo Drink',
   'Chilled hibiscus-flower drink, lightly sweetened. 35cl bottle.',
   'Drinks', 300),

  ('00000000-0000-0000-0000-000000000001',
   'Chapman',
   'Classic Nigerian Chapman mocktail — Fanta, Sprite, grenadine, cucumber, fruit.',
   'Drinks', 500),

  ('00000000-0000-0000-0000-000000000001',
   'Kunu Drink',
   'Chilled fermented millet drink. 35cl.',
   'Drinks', 300),

  ('00000000-0000-0000-0000-000000000001',
   'Bottled Water',
   '75cl table water.',
   'Drinks', 200)
on conflict do nothing;

-- ---------------------------------------------------------------------
-- Seed data — protein options for Uniflex's Protein Meal products.
-- We insert options referencing product names via a subquery so the
-- seed stays idempotent regardless of the generated product UUIDs.
-- ---------------------------------------------------------------------
insert into public.product_options (product_id, option_group, name, price_delta)
select p.id, 'protein', o.name, o.price_delta
from public.products p
cross join (values
  ('Chicken',      0::numeric),
  ('Beef',        50::numeric),
  ('Fish',       100::numeric),
  ('Turkey',     150::numeric),
  ('Egg',        -100::numeric),
  ('Mixed (x2)', 200::numeric)
) as o(name, price_delta)
where p.vendor_id = '00000000-0000-0000-0000-000000000001'
  and p.category = 'Protein Meals'
on conflict do nothing;

-- Extra sides available as add-ons for any Uniflex protein meal.
insert into public.product_options (product_id, option_group, name, price_delta)
select p.id, 'extra', o.name, o.price_delta
from public.products p
cross join (values
  ('Extra Stew',        100::numeric),
  ('Fried Plantain',    200::numeric),
  ('Coleslaw',          150::numeric),
  ('Moi Moi',           200::numeric)
) as o(name, price_delta)
where p.vendor_id = '00000000-0000-0000-0000-000000000001'
  and p.category = 'Protein Meals'
on conflict do nothing;

-- ---------------------------------------------------------------------
-- Seed data — partner vendor products (lightweight, 3 items each)
-- ---------------------------------------------------------------------
-- Mama Tee Kitchen
insert into public.products (vendor_id, name, description, category, base_price)
values
  ('00000000-0000-0000-0000-000000000002', 'Egusi Soup + Eba',    'Fresh egusi soup with stockfish and assorted meat, served with eba.',     'Main', 1500),
  ('00000000-0000-0000-0000-000000000002', 'Banga Soup + Starch', 'Delta-style palm-nut banga soup with periwinkle and starch.',             'Main', 1600),
  ('00000000-0000-0000-0000-000000000002', 'Amala + Ewedu',       'Yam flour amala with ewedu soup, gbegiri, and assorted stewed meat.',     'Main', 1400)
on conflict do nothing;

-- QuickBite Grill
insert into public.products (vendor_id, name, description, category, base_price)
values
  ('00000000-0000-0000-0000-000000000003', 'Chicken Suya',    'Spicy skewered grilled chicken suya with fresh tomato and onion.', 'Grills', 1200),
  ('00000000-0000-0000-0000-000000000003', 'Beef Suya',       'Classic spiced beef suya, smoky off the grill. Per stick.',       'Grills',  800),
  ('00000000-0000-0000-0000-000000000003', 'Sharwarma Wrap',  'Grilled chicken, veggies, and garlic sauce in a flour wrap.',     'Grills', 1800)
on conflict do nothing;

-- Campus Smoothies
insert into public.products (vendor_id, name, description, category, base_price)
values
  ('00000000-0000-0000-0000-000000000004', 'Green Boost Smoothie', 'Spinach, banana, pineapple, ginger, and almond milk blend. 35cl.', 'Smoothies', 1200),
  ('00000000-0000-0000-0000-000000000004', 'Berry Blast Smoothie', 'Mixed berry, yogurt, and honey. 35cl.',                            'Smoothies', 1100),
  ('00000000-0000-0000-0000-000000000004', 'Fresh Pineapple Juice','Cold-pressed 100% pineapple juice. 35cl.',                         'Juices',     800)
on conflict do nothing;


-- =====================================================================
-- PHASE 3 — Wallet & Payments
-- =====================================================================
-- Append these statements after the Phase 2 block, or run them separately
-- if Phase 2 is already applied. All Paystack interactions use test/sandbox
-- keys only — no live transactions are processed in this phase.
-- =====================================================================

-- ---------------------------------------------------------------------
-- wallet_transactions — every credit and debit against a student wallet.
-- Writes come exclusively from SECURITY DEFINER RPCs (never direct
-- client inserts) so the balance_after field stays consistent.
-- ---------------------------------------------------------------------
create table if not exists public.wallet_transactions (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null references public.profiles (id) on delete cascade,
  -- 'credit' = money in (top-up, refund)
  -- 'debit'  = money out (order payment)
  type         text        not null check (type in ('credit', 'debit')),
  amount       numeric(12, 2) not null check (amount > 0),
  -- source distinguishes why the transaction happened
  source       text        not null
                           check (source in ('topup', 'order_payment', 'refund')),
  -- non-null for debit transactions linked to a placed order
  order_id     uuid        references public.orders (id) on delete set null,
  -- Paystack reference — populated for top-up credits
  reference    text,
  -- denormalised running balance after this transaction was applied;
  -- computed inside the RPC, never by the client.
  balance_after numeric(12, 2) not null,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- saving_plans — each student has at most one active plan at a time
-- (unique on user_id). The plan tracks spending against a self-set
-- budget for the current period. The period counter resets lazily the
-- next time an order is placed after the period boundary passes.
-- ---------------------------------------------------------------------
create table if not exists public.saving_plans (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null unique references public.profiles (id) on delete cascade,
  period       text        not null check (period in ('daily', 'weekly', 'monthly')),
  budget       numeric(12, 2) not null check (budget > 0),
  spent        numeric(12, 2) not null default 0 check (spent >= 0),
  -- UTC anchor: start of the current period (day/week/month boundary)
  period_start timestamptz not null default date_trunc('day', now() at time zone 'utc'),
  is_active    boolean     not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create trigger saving_plans_updated_at
  before update on public.saving_plans
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------
alter table public.wallet_transactions enable row level security;
alter table public.saving_plans enable row level security;

-- Transactions are written by SECURITY DEFINER RPCs; clients only read.
create policy "wallet_transactions: read own"
  on public.wallet_transactions for select
  using (auth.uid() = user_id);

-- Saving plans are managed directly by the client (upsert / delete).
create policy "saving_plans: read own"
  on public.saving_plans for select
  using (auth.uid() = user_id);

create policy "saving_plans: insert own"
  on public.saving_plans for insert
  with check (auth.uid() = user_id);

create policy "saving_plans: update own"
  on public.saving_plans for update
  using (auth.uid() = user_id);

create policy "saving_plans: delete own"
  on public.saving_plans for delete
  using (auth.uid() = user_id);

-- Allow clients to update their own wallet (needed for webview callback path).
-- Balance updates are done only through SECURITY DEFINER RPCs below, but
-- the SELECT policy alone would block the balance re-read after the RPC
-- returns; the existing "wallets: read own" policy covers that.
-- No INSERT/UPDATE policy is added here — all mutations go through RPCs.

-- ---------------------------------------------------------------------
-- RPC: credit_wallet
-- Called ONLY from the verify-paystack-payment Edge Function using the
-- service-role key. Never granted to 'authenticated'.
-- Atomically increments the balance and records a credit transaction.
-- Raises DUPLICATE_REFERENCE if the Paystack reference has already been
-- processed (idempotency guard).
-- ---------------------------------------------------------------------
create or replace function public.credit_wallet(
  p_user_id   uuid,
  p_amount    numeric,
  p_reference text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_balance numeric;
begin
  -- Idempotency: reject duplicate Paystack references
  if exists (
    select 1 from public.wallet_transactions
    where reference = p_reference and type = 'credit'
  ) then
    raise exception 'DUPLICATE_REFERENCE';
  end if;

  -- Atomic increment; raises implicit NOT NULL / FK errors if wallet missing
  update public.wallets
    set balance = balance + p_amount
  where user_id = p_user_id
  returning balance into v_new_balance;

  if not found then
    raise exception 'WALLET_NOT_FOUND';
  end if;

  insert into public.wallet_transactions
    (user_id, type, amount, source, reference, balance_after)
  values
    (p_user_id, 'credit', p_amount, 'topup', p_reference, v_new_balance);

  return jsonb_build_object('balance', v_new_balance);
end;
$$;

-- Only the Edge Function (running with the service-role key) may call this.
-- Authenticated clients are explicitly denied.
grant execute on function public.credit_wallet(uuid, numeric, text)
  to service_role;

-- ---------------------------------------------------------------------
-- RPC: place_food_order_with_payment
-- Called by the Flutter client (authenticated). Atomically:
--   1. Row-locks the wallet to prevent concurrent double-spend
--   2. Checks and deducts the balance
--   3. Creates the orders + order_items rows
--   4. Records a debit wallet_transaction
--   5. Updates the active saving plan (lazy period reset)
-- Returns a JSONB payload with order_id, balance_after, and saving-plan
-- flags so the client can show appropriate feedback in one round trip.
-- Raises INSUFFICIENT_BALANCE if the wallet cannot cover the total.
-- ---------------------------------------------------------------------
create or replace function public.place_food_order_with_payment(
  p_vendor_id          uuid,
  p_source             text,
  p_delivery_type      text,
  p_delivery_location  text,
  p_total_amount       numeric,
  p_estimated_time     text,
  p_line_items         jsonb   -- [{product_id, product_name, quantity, unit_price, selected_options}]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id   uuid        := auth.uid();
  v_balance      numeric;
  v_new_balance  numeric;
  v_order_id     uuid;
  v_plan_id      uuid;
  v_plan_period  text;
  v_plan_budget  numeric;
  v_plan_spent   numeric;
  v_period_start timestamptz;
  v_period_end   timestamptz;
  v_new_spent    numeric;
  v_period_reset boolean     := false;
  v_plan_over    boolean     := false;
begin
  if v_student_id is null then
    raise exception 'Not authenticated';
  end if;

  -- Lock the wallet row (prevents concurrent double-spend)
  select balance into v_balance
    from public.wallets
   where user_id = v_student_id
  for update;

  if not found then
    raise exception 'WALLET_NOT_FOUND';
  end if;

  if v_balance < p_total_amount then
    raise exception 'INSUFFICIENT_BALANCE';
  end if;

  -- Debit
  update public.wallets
    set balance = balance - p_total_amount
  where user_id = v_student_id
  returning balance into v_new_balance;

  -- Create the order
  insert into public.orders
    (student_id, vendor_id, source, type, status,
     delivery_type, delivery_location, total_amount, estimated_time)
  values
    (v_student_id, p_vendor_id, p_source, 'food', 'placed',
     p_delivery_type, p_delivery_location, p_total_amount, p_estimated_time)
  returning id into v_order_id;

  -- Insert line items from JSONB
  insert into public.order_items
    (order_id, product_id, product_name, quantity, unit_price, selected_options)
  select
    v_order_id,
    (item->>'product_id')::uuid,
    item->>'product_name',
    (item->>'quantity')::int,
    (item->>'unit_price')::numeric,
    coalesce((item->'selected_options')::jsonb, '[]'::jsonb)
  from jsonb_array_elements(p_line_items) as item;

  -- Record the debit transaction
  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_student_id, 'debit', p_total_amount, 'order_payment', v_order_id, v_new_balance);

  -- ── Saving plan accounting (best-effort, never blocks the order) ────
  select id, period, budget, spent, period_start
    into v_plan_id, v_plan_period, v_plan_budget, v_plan_spent, v_period_start
    from public.saving_plans
   where user_id = v_student_id and is_active = true
  for update;

  if found then
    v_period_end := case v_plan_period
      when 'daily'   then v_period_start + interval '1 day'
      when 'weekly'  then v_period_start + interval '7 days'
      when 'monthly' then v_period_start + interval '1 month'
      else                v_period_start + interval '1 day'
    end;

    if now() at time zone 'utc' >= v_period_end then
      -- New period: reset spent counter
      v_period_reset := true;
      v_new_spent    := p_total_amount;
      update public.saving_plans
        set spent        = p_total_amount,
            period_start = date_trunc(
              case v_plan_period
                when 'daily'   then 'day'
                when 'weekly'  then 'week'
                when 'monthly' then 'month'
                else                'day'
              end,
              now() at time zone 'utc'
            ),
            updated_at   = now()
      where id = v_plan_id;
    else
      v_new_spent := v_plan_spent + p_total_amount;
      update public.saving_plans
        set spent      = v_new_spent,
            updated_at = now()
      where id = v_plan_id;
    end if;

    v_plan_over := v_new_spent > v_plan_budget;
  end if;

  return jsonb_build_object(
    'order_id',           v_order_id,
    'balance_after',      v_new_balance,
    'plan_over_budget',   v_plan_over,
    'plan_period_reset',  v_period_reset
  );
end;
$$;

grant execute on function public.place_food_order_with_payment(
  uuid, text, text, text, numeric, text, jsonb
) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: place_around_with_payment
-- Same guarantees as place_food_order_with_payment but for type='around'
-- requests. No line items — the details live in around_requests instead.
-- ---------------------------------------------------------------------
create or replace function public.place_around_with_payment(
  p_category          text,
  p_pickup_location   text,
  p_dropoff_location  text,
  p_item_description  text,
  p_total_amount      numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id   uuid    := auth.uid();
  v_balance      numeric;
  v_new_balance  numeric;
  v_order_id     uuid;
  v_plan_id      uuid;
  v_plan_period  text;
  v_plan_budget  numeric;
  v_plan_spent   numeric;
  v_period_start timestamptz;
  v_period_end   timestamptz;
  v_new_spent    numeric;
  v_plan_over    boolean := false;
begin
  if v_student_id is null then
    raise exception 'Not authenticated';
  end if;

  select balance into v_balance
    from public.wallets
   where user_id = v_student_id
  for update;

  if not found then
    raise exception 'WALLET_NOT_FOUND';
  end if;

  if v_balance < p_total_amount then
    raise exception 'INSUFFICIENT_BALANCE';
  end if;

  update public.wallets
    set balance = balance - p_total_amount
  where user_id = v_student_id
  returning balance into v_new_balance;

  insert into public.orders
    (student_id, source, type, status, delivery_type, total_amount, estimated_time)
  values
    (v_student_id, 'uniflex', 'around', 'placed', 'delivery',
     p_total_amount, '15–25 min')
  returning id into v_order_id;

  insert into public.around_requests
    (order_id, category, pickup_location, dropoff_location,
     item_description, estimated_fee)
  values
    (v_order_id, p_category, p_pickup_location, p_dropoff_location,
     p_item_description, p_total_amount);

  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_student_id, 'debit', p_total_amount, 'order_payment', v_order_id, v_new_balance);

  -- ── Saving plan accounting ───────────────────────────────────────────
  select id, period, budget, spent, period_start
    into v_plan_id, v_plan_period, v_plan_budget, v_plan_spent, v_period_start
    from public.saving_plans
   where user_id = v_student_id and is_active = true
  for update;

  if found then
    v_period_end := case v_plan_period
      when 'daily'   then v_period_start + interval '1 day'
      when 'weekly'  then v_period_start + interval '7 days'
      when 'monthly' then v_period_start + interval '1 month'
      else                v_period_start + interval '1 day'
    end;

    if now() at time zone 'utc' >= v_period_end then
      v_new_spent := p_total_amount;
      update public.saving_plans
        set spent        = p_total_amount,
            period_start = date_trunc(
              case v_plan_period
                when 'daily'   then 'day'
                when 'weekly'  then 'week'
                when 'monthly' then 'month'
                else                'day'
              end,
              now() at time zone 'utc'
            ),
            updated_at   = now()
      where id = v_plan_id;
    else
      v_new_spent := v_plan_spent + p_total_amount;
      update public.saving_plans
        set spent      = v_new_spent,
            updated_at = now()
      where id = v_plan_id;
    end if;

    v_plan_over := v_new_spent > v_plan_budget;
  end if;

  return jsonb_build_object(
    'order_id',         v_order_id,
    'balance_after',    v_new_balance,
    'plan_over_budget', v_plan_over
  );
end;
$$;

grant execute on function public.place_around_with_payment(
  text, text, text, text, numeric
) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: get_wallet_info
-- Returns balance + virtual account number + tier in one call.
-- Safer than a raw SELECT because it gives a single point to add
-- access logging or transform the VAN display format later.
-- ---------------------------------------------------------------------
create or replace function public.get_wallet_info()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'balance',                balance,
    'virtual_account_number', virtual_account_number,
    'tier',                   tier
  )
  from public.wallets
  where user_id = auth.uid();
$$;

grant execute on function public.get_wallet_info() to authenticated;


-- =====================================================================
-- PHASE 4 — Admin & Kitchen Module
-- =====================================================================
-- Append these after the Phase 3 block, or run separately if Phase 3 is
-- already applied.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Schema additions
-- ---------------------------------------------------------------------

-- admin_tier distinguishes super_admin from kitchen_staff within the
-- 'admin' role. NULL is treated as super_admin by the app for backwards
-- compatibility with any seeded admin rows that predate this column.
-- Non-admin rows (student, rider) will have NULL here — the column is
-- only meaningful when profiles.role = 'admin'.
alter table public.profiles
  add column if not exists admin_tier text
    check (admin_tier in ('super_admin', 'kitchen_staff'));

-- location and contact for partner vendors — used in the admin vendor
-- management screens. Both are optional (NULL = not specified).
alter table public.vendors
  add column if not exists location text;

alter table public.vendors
  add column if not exists contact text;

-- ---------------------------------------------------------------------
-- Helper: is the signed-in user an admin?
-- Centralised here so all Phase 4 RLS policies and RPCs call one place.
-- ---------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

grant execute on function public.is_admin() to authenticated;

-- ---------------------------------------------------------------------
-- Admin RLS — vendors
-- The existing "vendors: authenticated read" policy already lets any
-- authenticated user read all vendor rows (students need this for the
-- catalog). Admin needs write access for management.
-- ---------------------------------------------------------------------
create policy "vendors: admin insert"
  on public.vendors for insert to authenticated
  with check (public.is_admin());

create policy "vendors: admin update"
  on public.vendors for update to authenticated
  using (public.is_admin());

create policy "vendors: admin delete"
  on public.vendors for delete to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- Admin RLS — products
-- The existing "products: authenticated read" policy already covers
-- reads. Admin needs full write access for menu management.
-- ---------------------------------------------------------------------
create policy "products: admin insert"
  on public.products for insert to authenticated
  with check (public.is_admin());

create policy "products: admin update"
  on public.products for update to authenticated
  using (public.is_admin());

create policy "products: admin delete"
  on public.products for delete to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- Admin RLS — product_options
-- ---------------------------------------------------------------------
create policy "product_options: admin insert"
  on public.product_options for insert to authenticated
  with check (public.is_admin());

create policy "product_options: admin update"
  on public.product_options for update to authenticated
  using (public.is_admin());

create policy "product_options: admin delete"
  on public.product_options for delete to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- Admin RLS — orders
-- The existing "orders: read own" policy lets students read their own.
-- Multiple SELECT policies OR together in Postgres RLS, so adding an
-- admin policy doesn't break the student policy.
-- ---------------------------------------------------------------------
create policy "orders: admin read all"
  on public.orders for select to authenticated
  using (public.is_admin());

-- Admin can update any order (for status transitions in the kitchen queue).
-- The existing "orders: update own" policy still lets students update
-- their own orders (currently unused in the app, but kept for future use).
create policy "orders: admin update"
  on public.orders for update to authenticated
  using (public.is_admin());

-- Admin needs to read order_items for kitchen queue detail view.
create policy "order_items: admin read all"
  on public.order_items for select to authenticated
  using (public.is_admin());

-- Admin can read around_requests (for kitchen queue detail view).
create policy "around_requests: admin read all"
  on public.around_requests for select to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- Supabase Realtime — enable for orders table so the kitchen queue
-- StreamProvider receives live updates without polling.
--
-- Run this once. If the table is already in the publication, the DO
-- block is a no-op so re-running this script is safe.
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- RPC: update_order_status
-- Called by admin (kitchen staff or super_admin) to advance an order
-- through the kitchen stages. Validates the caller is an admin, then
-- updates the status column.
-- ---------------------------------------------------------------------
create or replace function public.update_order_status(
  p_order_id   uuid,
  p_new_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (select public.is_admin()) then
    raise exception 'Unauthorized';
  end if;

  if p_new_status not in (
    'placed', 'preparing', 'ready',
    'out_for_delivery', 'ready_for_pickup',
    'completed', 'cancelled'
  ) then
    raise exception 'Invalid status: %', p_new_status;
  end if;

  update public.orders
    set status = p_new_status
  where id = p_order_id;

  if not found then
    raise exception 'Order not found: %', p_order_id;
  end if;
end;
$$;

grant execute on function public.update_order_status(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: get_dashboard_stats
-- Returns a single JSONB object with today's order metrics for the
-- admin dashboard. Only callable by admin accounts.
-- ---------------------------------------------------------------------
create or replace function public.get_dashboard_stats()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today_start timestamptz := date_trunc('day', now() at time zone 'utc');
  v_stats       jsonb;
begin
  if not (select public.is_admin()) then
    raise exception 'Unauthorized';
  end if;

  select jsonb_build_object(
    -- Total orders placed today across all sources
    'today_orders_total',
    count(*) filter (where created_at >= v_today_start),
    -- Revenue from non-cancelled orders today (Uniflex-source only)
    'today_revenue',
    coalesce(sum(total_amount) filter (
      where source = 'uniflex'
        and status not in ('cancelled')
        and created_at >= v_today_start
    ), 0),
    -- Uniflex orders currently in active kitchen stages
    'pending_count',
    count(*) filter (
      where source = 'uniflex'
        and status in ('placed', 'preparing')
    ),
    -- Status breakdown for Uniflex orders only (kitchen-relevant)
    'by_status', jsonb_build_object(
      'placed',    count(*) filter (where source = 'uniflex' and status = 'placed'),
      'preparing', count(*) filter (where source = 'uniflex' and status = 'preparing'),
      'ready',     count(*) filter (where source = 'uniflex' and status = 'ready'),
      'completed', count(*) filter (
        where source = 'uniflex'
          and status = 'completed'
          and created_at >= v_today_start
      )
    )
  )
  into v_stats
  from public.orders;

  return v_stats;
end;
$$;

grant execute on function public.get_dashboard_stats() to authenticated;

-- ---------------------------------------------------------------------
-- Supabase Storage — product-images bucket
-- The bucket itself must be created from the Supabase dashboard:
--   Storage → New bucket → Name: product-images → Public: true
-- Then add these storage policies so admins can upload/delete and
-- authenticated users can read.
--
-- Run in the SQL editor after creating the bucket:
-- ---------------------------------------------------------------------
-- insert into storage.buckets (id, name, public)
--   values ('product-images', 'product-images', true)
--   on conflict (id) do nothing;
--
-- create policy "product-images: admin upload"
--   on storage.objects for insert to authenticated
--   with check (
--     bucket_id = 'product-images' and public.is_admin()
--   );
--
-- create policy "product-images: admin update"
--   on storage.objects for update to authenticated
--   using (
--     bucket_id = 'product-images' and public.is_admin()
--   );
--
-- create policy "product-images: admin delete"
--   on storage.objects for delete to authenticated
--   using (
--     bucket_id = 'product-images' and public.is_admin()
--   );
--
-- create policy "product-images: authenticated read"
--   on storage.objects for select to authenticated
--   using (bucket_id = 'product-images');
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- Seeding — update Uniflex vendor with admin_tier note in comments
-- No data migration needed for existing admin rows; NULL admin_tier
-- is treated as 'super_admin' by the app. To create a kitchen_staff
-- account:
--   1. Create the auth user as in Phase 1 instructions.
--   2. Table editor → profiles → Insert row:
--        role       = 'admin'
--        admin_tier = 'kitchen_staff'
--        email      = …
--        full_name  = …
--        onboarding_complete = true
-- ---------------------------------------------------------------------

-- =====================================================================
-- Phase 5 — Rider Shell
-- Apply in the Supabase SQL editor AFTER Phase 4 has been run.
-- =====================================================================

-- ── Profiles: rider online/offline toggle ────────────────────────────
alter table public.profiles
  add column if not exists rider_is_online boolean not null default false;

-- ── Orders: rider assignment fields ──────────────────────────────────
alter table public.orders
  add column if not exists rider_id uuid references public.profiles (id) on delete set null,
  add column if not exists delivery_pin text,
  add column if not exists delivery_stage text
    check (delivery_stage in ('accepted', 'picked_up'));

-- ── delivery_records — written at delivery completion ─────────────────
create table if not exists public.delivery_records (
  id               uuid primary key default gen_random_uuid(),
  order_id         uuid not null unique references public.orders (id) on delete cascade,
  rider_id         uuid not null references public.profiles (id) on delete cascade,
  completed_at     timestamptz not null default now(),
  duration_seconds int,   -- seconds from accept → complete
  distance_meters  int,   -- straight-line estimate (optional)
  rating           smallint check (rating between 1 and 5)
);

comment on table public.delivery_records is
  'One row per completed delivery, written by verify_delivery(). '
  'Used for rider history and future rating features.';

-- ── generate_delivery_pin trigger ─────────────────────────────────────
-- Fires on ORDER INSERT. Sets a 4-char alphanumeric PIN for all
-- delivery-type orders (food delivery + around). Pickup orders remain
-- null (no PIN needed — student collects in person).
create or replace function public._generate_delivery_pin()
returns trigger language plpgsql security definer as $$
declare
  v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- 32 unambiguous chars
  v_pin   text := '';
  v_bytes bytea;
begin
  if new.delivery_type = 'delivery' then
    v_bytes := gen_random_bytes(4);
    for i in 0..3 loop
      v_pin := v_pin || substr(v_chars, (get_byte(v_bytes, i) % 32) + 1, 1);
    end loop;
    new.delivery_pin := v_pin;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_generate_delivery_pin on public.orders;
create trigger trg_generate_delivery_pin
  before insert on public.orders
  for each row execute function public._generate_delivery_pin();

-- ── is_rider() helper (mirrors is_admin() from Phase 4) ──────────────
create or replace function public.is_rider()
returns boolean language sql security definer stable as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'rider'
  );
$$;

grant execute on function public.is_rider() to authenticated;

-- ── RLS: delivery_records ─────────────────────────────────────────────
alter table public.delivery_records enable row level security;

drop policy if exists "delivery_records: rider read own" on public.delivery_records;
create policy "delivery_records: rider read own"
  on public.delivery_records for select to authenticated
  using (rider_id = auth.uid() and public.is_rider());

drop policy if exists "delivery_records: admin read all" on public.delivery_records;
create policy "delivery_records: admin read all"
  on public.delivery_records for select to authenticated
  using (public.is_admin());

-- ── RLS: orders — rider SELECT policies ──────────────────────────────
-- Riders see unassigned pool-eligible orders (the job pool) …
drop policy if exists "orders: rider read pool" on public.orders;
create policy "orders: rider read pool"
  on public.orders for select to authenticated
  using (
    public.is_rider()
    and rider_id is null
    and (
      (source = 'uniflex' and status = 'ready'  and delivery_type = 'delivery')
      or (source = 'partner' and status = 'placed' and delivery_type = 'delivery')
      or (type   = 'around' and status = 'placed')
    )
  );

-- … and their own currently/previously assigned orders.
drop policy if exists "orders: rider read own assigned" on public.orders;
create policy "orders: rider read own assigned"
  on public.orders for select to authenticated
  using (public.is_rider() and rider_id = auth.uid());

-- ── RLS: around_requests — rider SELECT ──────────────────────────────
-- Riders need pickup_location for pool cards and active deliveries.
drop policy if exists "around_requests: rider read pool or assigned" on public.around_requests;
create policy "around_requests: rider read pool or assigned"
  on public.around_requests for select to authenticated
  using (
    public.is_rider()
    and exists (
      select 1 from public.orders o
      where o.id = around_requests.order_id
        and (o.rider_id is null or o.rider_id = auth.uid())
    )
  );

-- ── accept_order RPC ─────────────────────────────────────────────────
-- Pull-model: first rider to call this wins. FOR UPDATE prevents races.
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
  for update nowait;   -- raise immediately if another session holds the lock

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.rider_id is not null then
    raise exception 'Order already taken';
  end if;

  if not (
    (v_order.source = 'uniflex' and v_order.status = 'ready'  and v_order.delivery_type = 'delivery')
    or (v_order.source = 'partner' and v_order.status = 'placed' and v_order.delivery_type = 'delivery')
    or (v_order.type  = 'around' and v_order.status = 'placed')
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

-- ── confirm_pickup RPC ────────────────────────────────────────────────
create or replace function public.confirm_pickup(p_order_id uuid)
returns void language plpgsql security definer as $$
begin
  if not public.is_rider() then
    raise exception 'Unauthorized';
  end if;

  update public.orders
  set delivery_stage = 'picked_up'
  where id = p_order_id
    and rider_id = auth.uid()
    and delivery_stage = 'accepted';

  if not found then
    raise exception 'Order not found or not in accepted stage';
  end if;
end;
$$;

grant execute on function public.confirm_pickup(uuid) to authenticated;

-- ── verify_delivery RPC ───────────────────────────────────────────────
-- Validates the student's PIN, marks the order completed, and writes
-- a delivery_record. No path to completion without the correct PIN.
create or replace function public.verify_delivery(
  p_order_id uuid,
  p_pin      text
) returns void language plpgsql security definer as $$
declare
  v_order public.orders%rowtype;
begin
  if not public.is_rider() then
    raise exception 'Unauthorized';
  end if;

  select * into v_order from public.orders
  where id = p_order_id and rider_id = auth.uid();

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.delivery_stage != 'picked_up' then
    raise exception 'Confirm pickup before verifying delivery';
  end if;

  if upper(trim(p_pin)) != upper(v_order.delivery_pin) then
    raise exception 'Incorrect delivery PIN';
  end if;

  update public.orders
  set status = 'completed', delivery_stage = null
  where id = p_order_id;

  insert into public.delivery_records (order_id, rider_id, completed_at)
  values (p_order_id, auth.uid(), now())
  on conflict (order_id) do nothing;
end;
$$;

grant execute on function public.verify_delivery(uuid, text) to authenticated;

-- ── get_customer_info RPC ─────────────────────────────────────────────
-- Returns name + phone ONLY to the assigned rider (privacy guard).
create or replace function public.get_customer_info(p_order_id uuid)
returns json language plpgsql security definer as $$
declare
  v_order   public.orders%rowtype;
  v_profile public.profiles%rowtype;
begin
  if not public.is_rider() then
    raise exception 'Unauthorized';
  end if;

  select * into v_order from public.orders
  where id = p_order_id and rider_id = auth.uid();

  if not found then
    raise exception 'Order not assigned to this rider';
  end if;

  select * into v_profile from public.profiles
  where id = v_order.student_id;

  return json_build_object(
    'full_name', v_profile.full_name,
    'phone',     v_profile.phone
  );
end;
$$;

grant execute on function public.get_customer_info(uuid) to authenticated;

-- ── get_rider_stats RPC ───────────────────────────────────────────────
create or replace function public.get_rider_stats()
returns json language plpgsql security definer as $$
declare
  v_stats json;
begin
  if not public.is_rider() then
    raise exception 'Unauthorized';
  end if;

  select json_build_object(
    'today_completed',
      count(*) filter (where completed_at::date = current_date),
    'total_completed',
      count(*),
    'is_online',
      (select rider_is_online from public.profiles where id = auth.uid())
  )
  into v_stats
  from public.delivery_records
  where rider_id = auth.uid();

  return v_stats;
end;
$$;

grant execute on function public.get_rider_stats() to authenticated;

-- ── toggle_rider_online RPC ───────────────────────────────────────────
create or replace function public.toggle_rider_online(p_online boolean)
returns void language plpgsql security definer as $$
begin
  if not public.is_rider() then
    raise exception 'Unauthorized';
  end if;

  update public.profiles
  set rider_is_online = p_online
  where id = auth.uid();
end;
$$;

grant execute on function public.toggle_rider_online(boolean) to authenticated;

-- ── Supabase Realtime — keep orders in publication ────────────────────
-- (Idempotent; safe to run even if Phase 4 already added the table.)
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname    = 'supabase_realtime'
      and schemaname = 'public'
      and tablename  = 'orders'
  ) then
    execute 'alter publication supabase_realtime add table public.orders';
  end if;
end;
$$;

-- ── Seeding — rider account ───────────────────────────────────────────
-- To create a test rider account:
--   1. Create the auth user (Dashboard → Auth → Users → Add user).
--   2. Table editor → profiles → Insert row:
--        role                = 'rider'
--        email               = …
--        full_name           = …
--        onboarding_complete = true
--        rider_is_online     = false

-- =====================================================================
-- Phase 6 — Profile & Loyalty, Referral System, Gifting, Group
--            Checkout, Bulk Delivery, Birthday Rewards, Smart Pre-Order,
--            Extended Delivery Types, Push Notifications, Admin Scheduling
-- =====================================================================

-- ─── 1. Extend profiles ──────────────────────────────────────────────
alter table public.profiles
  add column if not exists reward_points     int          not null default 0,
  add column if not exists membership_tier   text         not null default 'Bronze'
    check (membership_tier in ('Bronze','Silver','Gold','Platinum')),
  add column if not exists lifetime_spending numeric(12,2) not null default 0,
  add column if not exists total_orders      int          not null default 0,
  add column if not exists referral_count    int          not null default 0,
  add column if not exists fcm_token         text;

-- ─── 2. Extend orders ────────────────────────────────────────────────
alter table public.orders
  add column if not exists scheduled_for     timestamptz,
  add column if not exists is_bulk           boolean      not null default false,
  add column if not exists bulk_discount_pct numeric(5,2) not null default 0,
  add column if not exists group_order_id    uuid;

-- Extend delivery_type to include campus + hostel options
alter table public.orders
  drop constraint if exists orders_delivery_type_check;

alter table public.orders
  add constraint orders_delivery_type_check
  check (delivery_type in ('pickup','delivery','campus_delivery','hostel_delivery'));

-- ─── 3. New tables ───────────────────────────────────────────────────

-- group_orders — a shared basket session opened by one student
create table if not exists public.group_orders (
  id                 uuid primary key default gen_random_uuid(),
  creator_id         uuid not null references public.profiles (id) on delete cascade,
  vendor_id          uuid not null references public.vendors  (id) on delete cascade,
  status             text not null default 'open'
    check (status in ('open','checked_out','cancelled')),
  delivery_type      text,
  delivery_location  text,
  bulk_discount_pct  numeric(5,2) not null default 0,
  created_at         timestamptz not null default now()
);

-- group_order_members — one row per participant (including creator)
create table if not exists public.group_order_members (
  id              uuid primary key default gen_random_uuid(),
  group_order_id  uuid not null references public.group_orders (id) on delete cascade,
  student_id      uuid not null references public.profiles    (id) on delete cascade,
  order_id        uuid references public.orders (id) on delete set null,
  paid            boolean not null default false,
  joined_at       timestamptz not null default now(),
  unique (group_order_id, student_id)
);

-- gifts — food sent to another student by matric number
create table if not exists public.gifts (
  id            uuid primary key default gen_random_uuid(),
  sender_id     uuid not null references public.profiles (id) on delete cascade,
  recipient_id  uuid not null references public.profiles (id) on delete cascade,
  order_id      uuid references public.orders (id) on delete set null,
  message       text,
  created_at    timestamptz not null default now()
);

-- referral_credits — audit trail for ₦500 referral bonuses
create table if not exists public.referral_credits (
  id             uuid primary key default gen_random_uuid(),
  referrer_id    uuid not null references public.profiles (id) on delete cascade,
  referred_id    uuid not null references public.profiles (id) on delete cascade,
  credit_amount  numeric(12,2) not null,
  credited_at    timestamptz not null default now()
);

-- achievements — catalogue of all possible badges (seeded below)
create table if not exists public.achievements (
  id          uuid primary key default gen_random_uuid(),
  code        text unique not null,
  name        text not null,
  description text not null,
  icon_name   text not null,
  created_at  timestamptz not null default now()
);

-- user_achievements — badges earned by a student
create table if not exists public.user_achievements (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles    (id) on delete cascade,
  achievement_id  uuid not null references public.achievements(id) on delete cascade,
  earned_at       timestamptz not null default now(),
  unique (user_id, achievement_id)
);

-- ─── 4. Row Level Security ───────────────────────────────────────────
alter table public.group_orders        enable row level security;
alter table public.group_order_members enable row level security;
alter table public.gifts               enable row level security;
alter table public.referral_credits    enable row level security;
alter table public.achievements        enable row level security;
alter table public.user_achievements   enable row level security;

-- group_orders: creator + members can read; creator can update
create policy "group_orders: members read"
  on public.group_orders for select
  using (
    auth.uid() = creator_id
    or exists (
      select 1 from public.group_order_members
      where group_order_id = group_orders.id and student_id = auth.uid()
    )
  );

create policy "group_orders: creator update"
  on public.group_orders for update
  using (auth.uid() = creator_id);

-- group_order_members: anyone in the group can see all members
create policy "group_order_members: co-members read"
  on public.group_order_members for select
  using (
    exists (
      select 1 from public.group_order_members gom2
      where gom2.group_order_id = group_order_members.group_order_id
        and gom2.student_id = auth.uid()
    )
  );

-- gifts: sent or received
create policy "gifts: own records"
  on public.gifts for select
  using (sender_id = auth.uid() or recipient_id = auth.uid());

-- referral_credits: referrer only
create policy "referral_credits: own records"
  on public.referral_credits for select
  using (referrer_id = auth.uid());

-- achievements: public read (catalogue)
create policy "achievements: public read"
  on public.achievements for select
  using (true);

-- user_achievements: own records
create policy "user_achievements: own records"
  on public.user_achievements for select
  using (user_id = auth.uid());

-- ─── 5. Trigger: update stats + tier on order placed ────────────────
create or replace function public._after_order_placed()
returns trigger language plpgsql security definer as $$
declare
  v_new_spending  numeric;
  v_new_tier      text;
  v_new_orders    int;
begin
  -- Only count food/around orders (group member orders already counted)
  if new.type not in ('food','around') then
    return new;
  end if;

  update public.profiles
  set
    total_orders      = total_orders + 1,
    lifetime_spending = lifetime_spending + new.total_amount,
    -- 1 point per ₦100 spent (floor)
    reward_points     = reward_points + floor(new.total_amount / 100)::int
  where id = new.student_id
  returning lifetime_spending, total_orders
    into v_new_spending, v_new_orders;

  -- Recalculate membership tier
  v_new_tier := case
    when v_new_spending >= 50000 then 'Platinum'
    when v_new_spending >= 20000 then 'Gold'
    when v_new_spending >= 5000  then 'Silver'
    else                              'Bronze'
  end;

  update public.profiles
    set membership_tier = v_new_tier
  where id = new.student_id and membership_tier <> v_new_tier;

  -- Award tier achievement badges
  if v_new_tier = 'Silver' then
    insert into public.user_achievements (user_id, achievement_id)
    select new.student_id, id from public.achievements where code = 'silver_tier'
    on conflict (user_id, achievement_id) do nothing;
  elsif v_new_tier = 'Gold' then
    insert into public.user_achievements (user_id, achievement_id)
    select new.student_id, id from public.achievements where code = 'gold_tier'
    on conflict (user_id, achievement_id) do nothing;
  elsif v_new_tier = 'Platinum' then
    insert into public.user_achievements (user_id, achievement_id)
    select new.student_id, id from public.achievements where code = 'platinum_tier'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  -- first_order badge
  if v_new_orders = 1 then
    insert into public.user_achievements (user_id, achievement_id)
    select new.student_id, id from public.achievements where code = 'first_order'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  -- ten_orders badge
  if v_new_orders = 10 then
    insert into public.user_achievements (user_id, achievement_id)
    select new.student_id, id from public.achievements where code = 'ten_orders'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  -- fifty_orders badge
  if v_new_orders = 50 then
    insert into public.user_achievements (user_id, achievement_id)
    select new.student_id, id from public.achievements where code = 'fifty_orders'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists after_order_placed on public.orders;
create trigger after_order_placed
  after insert on public.orders
  for each row execute function public._after_order_placed();

-- ─── 6. Trigger: credit referrer on first completed order ────────────
create or replace function public._after_order_completed()
returns trigger language plpgsql security definer as $$
declare
  v_referrer_id      uuid;
  v_completed_count  bigint;
  v_credit           numeric := 500; -- ₦500 referral bonus
begin
  -- Only fires on status transition → 'completed'
  if new.status <> 'completed' or old.status = 'completed' then
    return new;
  end if;

  -- Is this student referred by someone?
  select referrer_id into v_referrer_id
    from public.referrals
   where referred_id = new.student_id;

  if v_referrer_id is null then return new; end if;

  -- Only on FIRST completed order
  select count(*) into v_completed_count
    from public.orders
   where student_id = new.student_id
     and status = 'completed'
     and id <> new.id;

  if v_completed_count > 0 then return new; end if;

  -- Already credited?
  if exists (
    select 1 from public.referral_credits
    where referrer_id = v_referrer_id and referred_id = new.student_id
  ) then return new; end if;

  -- Credit referrer's wallet
  update public.wallets
    set balance = balance + v_credit
  where user_id = v_referrer_id;

  insert into public.wallet_transactions
    (user_id, type, amount, source, balance_after)
  select v_referrer_id, 'credit', v_credit, 'referral_bonus', balance
    from public.wallets where user_id = v_referrer_id;

  -- Bump referrer stats + award badge
  update public.profiles
    set reward_points  = reward_points  + 50,
        referral_count = referral_count + 1
  where id = v_referrer_id;

  insert into public.user_achievements (user_id, achievement_id)
  select v_referrer_id, id from public.achievements where code = 'first_referral'
  on conflict (user_id, achievement_id) do nothing;

  -- Audit row
  insert into public.referral_credits
    (referrer_id, referred_id, credit_amount)
  values (v_referrer_id, new.student_id, v_credit);

  return new;
end;
$$;

drop trigger if exists after_order_completed on public.orders;
create trigger after_order_completed
  after update on public.orders
  for each row execute function public._after_order_completed();

-- ─── 7. RPCs ─────────────────────────────────────────────────────────

-- get_student_stats
create or replace function public.get_student_stats()
returns json language plpgsql security definer as $$
declare
  v_uid  uuid := auth.uid();
  v_out  json;
begin
  select json_build_object(
    'total_orders',      coalesce(p.total_orders,      0),
    'reward_points',     coalesce(p.reward_points,     0),
    'membership_tier',   coalesce(p.membership_tier,   'Bronze'),
    'lifetime_spending', coalesce(p.lifetime_spending, 0),
    'referral_count',    coalesce(p.referral_count,    0)
  ) into v_out
  from public.profiles p
  where p.id = v_uid;
  return v_out;
end;
$$;

grant execute on function public.get_student_stats() to authenticated;

-- get_referral_leaderboard — top 10 by referral_count
create or replace function public.get_referral_leaderboard()
returns json language plpgsql security definer as $$
declare v_rows json; begin
  select json_agg(row_to_json(r)) into v_rows
  from (
    select
      coalesce(nickname, split_part(full_name,' ',1)) as display_name,
      referral_count,
      rank() over (order by referral_count desc) as rank
    from public.profiles
    where role = 'student' and referral_count > 0
    order by referral_count desc
    limit 10
  ) r;
  return coalesce(v_rows, '[]'::json);
end;
$$;

grant execute on function public.get_referral_leaderboard() to authenticated;

-- store_fcm_token — called on app startup after Firebase initializes
create or replace function public.store_fcm_token(p_token text)
returns void language plpgsql security definer as $$
begin
  update public.profiles set fcm_token = p_token where id = auth.uid();
end;
$$;

grant execute on function public.store_fcm_token(text) to authenticated;

-- get_user_achievements
create or replace function public.get_user_achievements()
returns json language plpgsql security definer as $$
declare v_rows json; begin
  select json_agg(row_to_json(r)) into v_rows
  from (
    select
      a.code, a.name, a.description, a.icon_name,
      ua.earned_at
    from public.user_achievements ua
    join public.achievements a on a.id = ua.achievement_id
    where ua.user_id = auth.uid()
    order by ua.earned_at desc
  ) r;
  return coalesce(v_rows, '[]'::json);
end;
$$;

grant execute on function public.get_user_achievements() to authenticated;

-- send_gift — places an order under recipient's account, charged to sender
create or replace function public.send_gift(
  p_recipient_matric  text,
  p_vendor_id         uuid,
  p_line_items        jsonb,
  p_total_amount      numeric,
  p_message           text    default null,
  p_delivery_type     text    default 'pickup',
  p_delivery_location text    default null
)
returns jsonb language plpgsql security definer as $$
declare
  v_sender_id    uuid := auth.uid();
  v_recipient_id uuid;
  v_order_id     uuid;
  v_balance      numeric;
  v_new_balance  numeric;
  v_gift_id      uuid;
  v_is_uniflex   boolean;
  v_source       text;
begin
  -- Resolve recipient by matric
  select id into v_recipient_id
    from public.profiles
   where matric_number = p_recipient_matric and role = 'student';
  if not found then raise exception 'RECIPIENT_NOT_FOUND'; end if;
  if v_recipient_id = v_sender_id then raise exception 'CANNOT_GIFT_SELF'; end if;

  -- Charge sender's wallet
  select balance into v_balance
    from public.wallets where user_id = v_sender_id for update;
  if not found then raise exception 'WALLET_NOT_FOUND'; end if;
  if v_balance < p_total_amount then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.wallets set balance = balance - p_total_amount
    where user_id = v_sender_id returning balance into v_new_balance;

  -- Determine source from vendor is_featured + badge_label
  select (is_featured and badge_label = 'Major') into v_is_uniflex
    from public.vendors where id = p_vendor_id;
  v_source := case when v_is_uniflex then 'uniflex' else 'partner' end;

  -- Place order under recipient
  insert into public.orders
    (student_id, vendor_id, source, type, status,
     delivery_type, delivery_location, total_amount, estimated_time)
  values
    (v_recipient_id, p_vendor_id, v_source, 'food', 'placed',
     p_delivery_type, p_delivery_location, p_total_amount, '20–30 min')
  returning id into v_order_id;

  -- Line items
  insert into public.order_items
    (order_id, product_id, product_name, quantity, unit_price, selected_options)
  select
    v_order_id,
    (item->>'product_id')::uuid,
    item->>'product_name',
    (item->>'quantity')::int,
    (item->>'unit_price')::numeric,
    coalesce((item->'selected_options')::jsonb, '[]'::jsonb)
  from jsonb_array_elements(p_line_items) as item;

  -- Wallet transaction (sender pays)
  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_sender_id, 'debit', p_total_amount, 'gift_payment', v_order_id, v_new_balance);

  -- Gift record
  insert into public.gifts (sender_id, recipient_id, order_id, message)
  values (v_sender_id, v_recipient_id, v_order_id, p_message)
  returning id into v_gift_id;

  -- Gifter badge
  insert into public.user_achievements (user_id, achievement_id)
  select v_sender_id, id from public.achievements where code = 'gifter'
  on conflict (user_id, achievement_id) do nothing;

  return jsonb_build_object(
    'gift_id',            v_gift_id,
    'order_id',           v_order_id,
    'recipient_nickname', (select coalesce(nickname, full_name)
                            from public.profiles where id = v_recipient_id)
  );
end;
$$;

grant execute on function public.send_gift(text, uuid, jsonb, numeric, text, text, text) to authenticated;

-- get_gifts — sent and received gifts for current user
create or replace function public.get_gifts()
returns json language plpgsql security definer as $$
declare
  v_uid uuid := auth.uid();
  v_rows json;
begin
  select json_agg(row_to_json(g)) into v_rows
  from (
    select
      gi.id,
      gi.created_at,
      gi.message,
      gi.order_id,
      case when gi.sender_id = v_uid then 'sent' else 'received' end as direction,
      coalesce(sp.nickname, sp.full_name) as sender_name,
      coalesce(rp.nickname, rp.full_name) as recipient_name,
      o.total_amount,
      o.status as order_status
    from public.gifts gi
    join public.profiles sp on sp.id = gi.sender_id
    join public.profiles rp on rp.id = gi.recipient_id
    left join public.orders o on o.id = gi.order_id
    where gi.sender_id = v_uid or gi.recipient_id = v_uid
    order by gi.created_at desc
  ) g;
  return coalesce(v_rows, '[]'::json);
end;
$$;

grant execute on function public.get_gifts() to authenticated;

-- create_group_order — open a group session
create or replace function public.create_group_order(
  p_vendor_id      uuid,
  p_bulk_discount  numeric default 0
)
returns uuid language plpgsql security definer as $$
declare
  v_uid      uuid := auth.uid();
  v_group_id uuid;
begin
  insert into public.group_orders (creator_id, vendor_id, bulk_discount_pct)
  values (v_uid, p_vendor_id, p_bulk_discount)
  returning id into v_group_id;

  insert into public.group_order_members (group_order_id, student_id)
  values (v_group_id, v_uid);

  return v_group_id;
end;
$$;

grant execute on function public.create_group_order(uuid, numeric) to authenticated;

-- join_group_order
create or replace function public.join_group_order(p_group_id uuid)
returns void language plpgsql security definer as $$
declare
  v_status text;
begin
  select status into v_status from public.group_orders where id = p_group_id;
  if not found then raise exception 'GROUP_NOT_FOUND'; end if;
  if v_status <> 'open' then raise exception 'GROUP_CLOSED'; end if;

  insert into public.group_order_members (group_order_id, student_id)
  values (p_group_id, auth.uid())
  on conflict (group_order_id, student_id) do nothing;
end;
$$;

grant execute on function public.join_group_order(uuid) to authenticated;

-- checkout_group_order — each member checks out their own portion
create or replace function public.checkout_group_order(
  p_group_id          uuid,
  p_line_items        jsonb,
  p_my_total          numeric,
  p_delivery_type     text default 'pickup',
  p_delivery_location text default null
)
returns jsonb language plpgsql security definer as $$
declare
  v_uid          uuid := auth.uid();
  v_group        public.group_orders;
  v_balance      numeric;
  v_new_balance  numeric;
  v_order_id     uuid;
  v_is_uniflex   boolean;
  v_source       text;
begin
  select * into v_group from public.group_orders where id = p_group_id;
  if not found then raise exception 'GROUP_NOT_FOUND'; end if;
  if v_group.status = 'cancelled' then raise exception 'GROUP_CANCELLED'; end if;

  if not exists (
    select 1 from public.group_order_members
    where group_order_id = p_group_id and student_id = v_uid
  ) then raise exception 'NOT_A_MEMBER'; end if;

  if exists (
    select 1 from public.group_order_members
    where group_order_id = p_group_id and student_id = v_uid and paid = true
  ) then raise exception 'ALREADY_CHECKED_OUT'; end if;

  select balance into v_balance from public.wallets
  where user_id = v_uid for update;
  if not found then raise exception 'WALLET_NOT_FOUND'; end if;
  if v_balance < p_my_total then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.wallets set balance = balance - p_my_total
  where user_id = v_uid returning balance into v_new_balance;

  select (is_featured and badge_label = 'Major') into v_is_uniflex
    from public.vendors where id = v_group.vendor_id;
  v_source := case when v_is_uniflex then 'uniflex' else 'partner' end;

  insert into public.orders
    (student_id, vendor_id, source, type, status, delivery_type,
     delivery_location, total_amount, estimated_time,
     group_order_id, bulk_discount_pct)
  values
    (v_uid, v_group.vendor_id, v_source, 'food', 'placed',
     coalesce(p_delivery_type, v_group.delivery_type),
     coalesce(p_delivery_location, v_group.delivery_location),
     p_my_total, '20–30 min', p_group_id, v_group.bulk_discount_pct)
  returning id into v_order_id;

  insert into public.order_items
    (order_id, product_id, product_name, quantity, unit_price, selected_options)
  select
    v_order_id,
    (item->>'product_id')::uuid,
    item->>'product_name',
    (item->>'quantity')::int,
    (item->>'unit_price')::numeric,
    coalesce((item->'selected_options')::jsonb, '[]'::jsonb)
  from jsonb_array_elements(p_line_items) as item;

  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_uid, 'debit', p_my_total, 'group_order_payment', v_order_id, v_new_balance);

  update public.group_order_members
    set order_id = v_order_id, paid = true
  where group_order_id = p_group_id and student_id = v_uid;

  return jsonb_build_object('order_id', v_order_id);
end;
$$;

grant execute on function public.checkout_group_order(uuid, jsonb, numeric, text, text) to authenticated;

-- process_birthday_rewards — called by pg_cron daily at midnight UTC
create or replace function public.process_birthday_rewards()
returns void language plpgsql security definer as $$
declare rec record; v_credit numeric; begin
  for rec in
    select p.id, p.membership_tier
    from   public.profiles p
    join   public.wallets  w on w.user_id = p.id
    where  p.role = 'student'
      and  p.membership_tier in ('Silver','Gold','Platinum')
      and  date_part('month', p.date_of_birth) = date_part('month', current_date)
      and  date_part('day',   p.date_of_birth) = date_part('day',   current_date)
  loop
    v_credit := case rec.membership_tier
      when 'Silver'   then 500
      when 'Gold'     then 1000
      when 'Platinum' then 2000
      else 0
    end;

    if v_credit > 0 then
      update public.wallets set balance = balance + v_credit where user_id = rec.id;
      insert into public.wallet_transactions
        (user_id, type, amount, source, balance_after)
      select rec.id, 'credit', v_credit, 'birthday_reward', balance
        from public.wallets where user_id = rec.id;

      insert into public.user_achievements (user_id, achievement_id)
      select rec.id, id from public.achievements where code = 'birthday_bonus'
      on conflict (user_id, achievement_id) do nothing;
    end if;
  end loop;
end;
$$;

grant execute on function public.process_birthday_rewards() to authenticated;
grant execute on function public.process_birthday_rewards() to postgres;

-- ─── 8. Extend place_food_order_with_payment (backward-compatible) ───
-- Adds optional p_scheduled_for, p_is_bulk, p_bulk_discount_pct.
-- Old calls (7 params) still resolve because PostgreSQL matches on name.
create or replace function public.place_food_order_with_payment(
  p_vendor_id          uuid,
  p_source             text,
  p_delivery_type      text,
  p_delivery_location  text,
  p_total_amount       numeric,
  p_estimated_time     text,
  p_line_items         jsonb,
  p_scheduled_for      timestamptz default null,
  p_is_bulk            boolean     default false,
  p_bulk_discount_pct  numeric     default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id   uuid        := auth.uid();
  v_balance      numeric;
  v_new_balance  numeric;
  v_order_id     uuid;
  v_plan_id      uuid;
  v_plan_period  text;
  v_plan_budget  numeric;
  v_plan_spent   numeric;
  v_period_start timestamptz;
  v_period_end   timestamptz;
  v_new_spent    numeric;
  v_period_reset boolean     := false;
  v_plan_over    boolean     := false;
begin
  if v_student_id is null then raise exception 'Not authenticated'; end if;

  select balance into v_balance from public.wallets
   where user_id = v_student_id for update;
  if not found then raise exception 'WALLET_NOT_FOUND'; end if;
  if v_balance < p_total_amount then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.wallets set balance = balance - p_total_amount
   where user_id = v_student_id returning balance into v_new_balance;

  insert into public.orders
    (student_id, vendor_id, source, type, status,
     delivery_type, delivery_location, total_amount, estimated_time,
     scheduled_for, is_bulk, bulk_discount_pct)
  values
    (v_student_id, p_vendor_id, p_source, 'food', 'placed',
     p_delivery_type, p_delivery_location, p_total_amount, p_estimated_time,
     p_scheduled_for, p_is_bulk, p_bulk_discount_pct)
  returning id into v_order_id;

  insert into public.order_items
    (order_id, product_id, product_name, quantity, unit_price, selected_options)
  select
    v_order_id,
    (item->>'product_id')::uuid,
    item->>'product_name',
    (item->>'quantity')::int,
    (item->>'unit_price')::numeric,
    coalesce((item->'selected_options')::jsonb, '[]'::jsonb)
  from jsonb_array_elements(p_line_items) as item;

  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_student_id, 'debit', p_total_amount, 'order_payment', v_order_id, v_new_balance);

  -- Saving plan accounting (best-effort)
  select id, period, budget, spent, period_start
    into v_plan_id, v_plan_period, v_plan_budget, v_plan_spent, v_period_start
    from public.saving_plans
   where user_id = v_student_id and is_active = true for update;

  if found then
    v_period_end := case v_plan_period
      when 'daily'   then v_period_start + interval '1 day'
      when 'weekly'  then v_period_start + interval '7 days'
      when 'monthly' then v_period_start + interval '1 month'
      else                v_period_start + interval '1 day'
    end;
    if now() at time zone 'utc' >= v_period_end then
      v_period_reset := true;
      v_new_spent    := p_total_amount;
      update public.saving_plans
        set spent        = p_total_amount,
            period_start = date_trunc(
              case v_plan_period
                when 'daily'   then 'day'
                when 'weekly'  then 'week'
                when 'monthly' then 'month'
                else 'day' end,
              now() at time zone 'utc'),
            updated_at   = now()
      where id = v_plan_id;
    else
      v_new_spent := v_plan_spent + p_total_amount;
      update public.saving_plans set spent = v_new_spent, updated_at = now()
       where id = v_plan_id;
    end if;
    v_plan_over := v_new_spent > v_plan_budget;
  end if;

  return jsonb_build_object(
    'order_id',          v_order_id,
    'balance_after',     v_new_balance,
    'plan_over_budget',  v_plan_over,
    'plan_period_reset', v_period_reset
  );
end;
$$;

grant execute on function public.place_food_order_with_payment(
  uuid, text, text, text, numeric, text, jsonb, timestamptz, boolean, numeric
) to authenticated;

-- ─── 9. Seed achievements catalogue ──────────────────────────────────
insert into public.achievements (code, name, description, icon_name) values
  ('first_order',    'First Bite',         'Placed your first order',            'restaurant'),
  ('ten_orders',     'Regular',            'Placed 10 orders',                   'repeat'),
  ('fifty_orders',   'Super Regular',      'Placed 50 orders',                   'star'),
  ('first_referral', 'Connector',          'Referred your first friend',         'people'),
  ('ten_referrals',  'Ambassador',         'Referred 10 friends',                'emoji_events'),
  ('gifter',         'Gifter',             'Sent your first food gift',          'card_giftcard'),
  ('silver_tier',    'Silver Member',      'Reached Silver membership tier',     'workspace_premium'),
  ('gold_tier',      'Gold Member',        'Reached Gold membership tier',       'military_tech'),
  ('platinum_tier',  'Platinum Member',    'Reached Platinum membership tier',   'diamond'),
  ('birthday_bonus', 'Birthday Blessings', 'Received your first birthday reward','cake')
on conflict (code) do nothing;

-- ─── 10. pg_cron — birthday rewards (requires pg_cron extension) ─────
-- Enable pg_cron in Supabase Dashboard → Extensions, then run:
--
--   select cron.schedule(
--     'birthday-rewards-daily',
--     '0 0 * * *',
--     $$select public.process_birthday_rewards()$$
--   );
--
-- (Commented out so this file is safe to run in one shot.)

-- ─── 11. Realtime — publish new tables ───────────────────────────────
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'group_orders'
  ) then
    execute 'alter publication supabase_realtime add table public.group_orders';
  end if;
end;
$$;


-- =====================================================================
-- PHASE 7 — Post-Stage-1-testing corrections (2026-09-15)
-- ---------------------------------------------------------------------
-- Five bugs found by the Stage-1 integration test suite, folded in here
-- so a fresh top-to-bottom run of this file produces the corrected
-- schema. Every block is idempotent. (Each was first applied to the live
-- database via a standalone fix file; those are now consolidated here.)
-- =====================================================================

-- ── Fix 1: profiles role/admin_tier tampering ────────────────────────
-- A signed-in student could PATCH/INSERT their own profiles row to
-- role='admin'/'rider'. Self-insert is now forced to a student row, and a
-- trigger locks role/admin_tier to service-role changes only.
drop policy if exists "profiles: insert own row" on public.profiles;
create policy "profiles: insert own row" on public.profiles
  for insert to authenticated
  with check (auth.uid() = id and role = 'student' and admin_tier is null);

create or replace function public.guard_profile_privileged_columns()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_jwt_role text := coalesce(
    (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'role'), '');
begin
  if (new.role is distinct from old.role)
     or (new.admin_tier is distinct from old.admin_tier) then
    if v_jwt_role <> 'service_role' then
      raise exception
        'role/admin_tier can only be changed by an administrator (attempted by %)',
        coalesce(v_jwt_role, 'unknown');
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_guard_profile_privileged_columns on public.profiles;
create trigger trg_guard_profile_privileged_columns
  before update on public.profiles
  for each row execute function public.guard_profile_privileged_columns();

-- ── Fix 2: ambiguous place_food_order_with_payment 7-arg overload ─────
-- The 7-arg + 10-arg overloads made 7-arg calls ambiguous (HTTP 300),
-- breaking normal orders. Keep only the 10-arg (defaulted) version.
drop function if exists public.place_food_order_with_payment(
  uuid, text, text, text, numeric, text, jsonb);

-- ── Fix 3: kitchen_staff must not reach super_admin-only surfaces ─────
-- is_admin() ignored admin_tier. Add is_super_admin() and use it for
-- catalog writes + dashboard financials. is_admin() still gates the
-- shared surfaces kitchen_staff needs (orders read/update queue).
create or replace function public.is_super_admin()
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
      and (admin_tier is null or admin_tier = 'super_admin'));
$$;
grant execute on function public.is_super_admin() to authenticated;

drop policy if exists "vendors: admin insert" on public.vendors;
create policy "vendors: admin insert" on public.vendors
  for insert to authenticated with check (public.is_super_admin());
drop policy if exists "vendors: admin update" on public.vendors;
create policy "vendors: admin update" on public.vendors
  for update to authenticated using (public.is_super_admin());
drop policy if exists "vendors: admin delete" on public.vendors;
create policy "vendors: admin delete" on public.vendors
  for delete to authenticated using (public.is_super_admin());

drop policy if exists "products: admin insert" on public.products;
create policy "products: admin insert" on public.products
  for insert to authenticated with check (public.is_super_admin());
drop policy if exists "products: admin update" on public.products;
create policy "products: admin update" on public.products
  for update to authenticated using (public.is_super_admin());
drop policy if exists "products: admin delete" on public.products;
create policy "products: admin delete" on public.products
  for delete to authenticated using (public.is_super_admin());

drop policy if exists "product_options: admin insert" on public.product_options;
create policy "product_options: admin insert" on public.product_options
  for insert to authenticated with check (public.is_super_admin());
drop policy if exists "product_options: admin update" on public.product_options;
create policy "product_options: admin update" on public.product_options
  for update to authenticated using (public.is_super_admin());
drop policy if exists "product_options: admin delete" on public.product_options;
create policy "product_options: admin delete" on public.product_options
  for delete to authenticated using (public.is_super_admin());

create or replace function public.get_dashboard_stats()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_today_start timestamptz := date_trunc('day', now() at time zone 'utc');
  v_stats       jsonb;
begin
  if not (select public.is_super_admin()) then
    raise exception 'Unauthorized';
  end if;
  select jsonb_build_object(
    'today_orders_total', count(*) filter (where created_at >= v_today_start),
    'today_revenue', coalesce(sum(total_amount) filter (
      where source = 'uniflex' and status not in ('cancelled') and created_at >= v_today_start), 0),
    'pending_count', count(*) filter (
      where source = 'uniflex' and status in ('placed', 'preparing')),
    'by_status', jsonb_build_object(
      'placed',    count(*) filter (where source = 'uniflex' and status = 'placed'),
      'preparing', count(*) filter (where source = 'uniflex' and status = 'preparing'),
      'ready',     count(*) filter (where source = 'uniflex' and status = 'ready'),
      'completed', count(*) filter (where source = 'uniflex' and status = 'completed' and created_at >= v_today_start)))
  into v_stats from public.orders;
  return v_stats;
end;
$$;
grant execute on function public.get_dashboard_stats() to authenticated;

-- ── Fix 4: delivery PIN trigger couldn't see pgcrypto ────────────────
-- gen_random_bytes lives in the extensions schema; add it to search_path
-- so delivery-type order inserts stop failing (SQLSTATE 42883).
create extension if not exists pgcrypto with schema extensions;
create or replace function public._generate_delivery_pin()
returns trigger language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_pin   text := '';
  v_bytes bytea;
begin
  if new.delivery_type = 'delivery' then
    v_bytes := gen_random_bytes(4);
    for i in 0..3 loop
      v_pin := v_pin || substr(v_chars, (get_byte(v_bytes, i) % 32) + 1, 1);
    end loop;
    new.delivery_pin := v_pin;
  end if;
  return new;
end;
$$;

-- ── Fix 5: wallet_transactions.source CHECK too narrow ───────────────
-- Referral/gift/birthday/group-checkout inserts used source values the
-- original CHECK rejected (SQLSTATE 23514). Widen it.
alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_source_check;
alter table public.wallet_transactions
  add constraint wallet_transactions_source_check
  check (source in ('topup','order_payment','refund','referral_bonus',
                    'gift_payment','birthday_reward','group_order_payment'));

-- ============================================================================
-- PHASE 8 — Post-Stage-2-testing correction (bug #7)
-- Campus/Hostel food-delivery orders were invisible to riders + got no PIN.
-- delivery_type was extended to 'campus_delivery'/'hostel_delivery' (see the
-- orders_delivery_type_check migration above), but the PIN trigger, the rider
-- job-pool RLS policy, and accept_order() still matched delivery_type =
-- 'delivery' EXACTLY. The student food-order path only ever sends
-- 'pickup'/'campus_delivery'/'hostel_delivery' (never plain 'delivery'), so no
-- real student food delivery could reach a rider. Treat all delivery variants
-- alike. Idempotent (mirrors supabase/security_fix_campus_hostel_delivery.sql).
-- ============================================================================

-- 1. Delivery PIN trigger — cover every delivery-type variant.
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

-- =====================================================================
-- POST-TESTING FIXES & CHANGES — first on-device Android QA pass
-- =====================================================================
-- Everything below is new as of the post-testing pass (see CHANGELOG.md
-- "Post-testing fixes & changes"). Run this once, appended after
-- everything above it. It is additive only — no destructive drops.
-- =====================================================================

-- pgcrypto — needed for crypt()/gen_salt() used by the transaction PIN
-- (Section 6). Supabase projects ship this extension; this just makes
-- sure it's enabled.
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Section 6 — Order confirmation PIN
-- ---------------------------------------------------------------------
-- transaction_pins — one row per student who has set a 4-digit
-- transaction PIN. Mirrors the wallet_transactions pattern: no direct
-- client SELECT/INSERT/UPDATE policy at all — every read/write goes
-- through the SECURITY DEFINER RPCs below, keyed off auth.uid(), so a
-- client can never read another user's hash or set a PIN for someone
-- else.
create table if not exists public.transaction_pins (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  pin_hash   text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.transaction_pins enable row level security;

create or replace function public.set_transaction_pin(p_pin text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;
  if p_pin !~ '^[0-9]{4}$' then
    raise exception 'PIN must be exactly 4 digits';
  end if;

  insert into public.transaction_pins (user_id, pin_hash, updated_at)
  values (v_user_id, crypt(p_pin, gen_salt('bf')), now())
  on conflict (user_id) do update
    set pin_hash = excluded.pin_hash, updated_at = now();
end;
$$;

grant execute on function public.set_transaction_pin(text) to authenticated;

-- Lets the client ask "does this student have a PIN yet?" without ever
-- exposing the hash itself.
create or replace function public.has_transaction_pin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.transaction_pins where user_id = auth.uid()
  );
$$;

grant execute on function public.has_transaction_pin() to authenticated;

create or replace function public.verify_transaction_pin(p_pin text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hash text;
begin
  select pin_hash into v_hash
    from public.transaction_pins
   where user_id = auth.uid();

  if v_hash is null then
    return false;
  end if;

  return crypt(p_pin, v_hash) = v_hash;
end;
$$;

grant execute on function public.verify_transaction_pin(text) to authenticated;

-- ---------------------------------------------------------------------
-- Section 7 — Admin rider management (add / remove / activate)
-- ---------------------------------------------------------------------
-- is_active gates sign-in for ANY profile (defaults true, so students
-- and existing admins/riders are unaffected). Only the rider management
-- screen exposes a UI to flip it — "remove" and "deactivate" are both
-- implemented as is_active = false so a rider's account and delivery
-- history (delivery_records, past orders) are never deleted, only their
-- ability to sign in and appear in the active roster.
alter table public.profiles add column if not exists is_active boolean not null default true;

create or replace function public.admin_list_riders()
returns table (
  id              uuid,
  full_name       text,
  email           text,
  phone           text,
  is_active       boolean,
  rider_is_online boolean,
  created_at      timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.full_name, p.email, p.phone, p.is_active, p.rider_is_online, p.created_at
  from public.profiles p
  where p.role = 'rider' and public.is_admin()
  order by p.created_at desc;
$$;

grant execute on function public.admin_list_riders() to authenticated;

create or replace function public.admin_set_rider_active(p_rider_id uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Unauthorized';
  end if;

  update public.profiles
    set is_active = p_active
  where id = p_rider_id and role = 'rider';

  if not found then
    raise exception 'Rider not found';
  end if;
end;
$$;

grant execute on function public.admin_set_rider_active(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- Section 9 — Admin-configurable Around categories
-- ---------------------------------------------------------------------
create table if not exists public.around_categories (
  id          uuid primary key default gen_random_uuid(),
  key         text unique not null,
  title       text not null,
  subtitle    text not null default '',
  description text not null default '',
  icon_name   text not null default 'explore',
  flat_fee    numeric(10, 2) not null default 500,
  is_active   boolean not null default true,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);

alter table public.around_categories enable row level security;

drop policy if exists "around_categories: authenticated read active" on public.around_categories;
create policy "around_categories: authenticated read active"
  on public.around_categories for select to authenticated
  using (is_active or public.is_admin());

drop policy if exists "around_categories: admin insert" on public.around_categories;
create policy "around_categories: admin insert"
  on public.around_categories for insert to authenticated
  with check (public.is_admin());

drop policy if exists "around_categories: admin update" on public.around_categories;
create policy "around_categories: admin update"
  on public.around_categories for update to authenticated
  using (public.is_admin());

drop policy if exists "around_categories: admin delete" on public.around_categories;
create policy "around_categories: admin delete"
  on public.around_categories for delete to authenticated
  using (public.is_admin());

-- Seed the 5 categories that used to be hardcoded in the Dart enum, so
-- the Student-facing Around flow keeps working unchanged the moment
-- this migrates to reading from this table.
insert into public.around_categories (key, title, subtitle, description, icon_name, flat_fee, sort_order)
values
  ('errand', 'General Errand', 'Post a task, get a runner',
   'Free-text description of any item or task you need fetched on or near campus.',
   'assignment', 500, 0),
  ('laundry', 'Laundry Pickup & Dropoff', 'Pickup & drop at the point',
   'Rider picks up your laundry bag and drops it at the laundry point — or picks it up when ready. No washing service included.',
   'laundry', 600, 1),
  ('hostel', 'Hostel Transfer', 'Between hostels',
   'Move items between hostels or any two campus points.',
   'home', 400, 2),
  ('vendor_fetch', 'Nearby Shop Fetch', 'Fetch from any shop',
   'Fetch an item from any nearby off-catalog shop or vendor.',
   'storefront', 500, 3),
  ('peer_courier', 'Peer Courier', 'Student to student',
   'Point-to-point delivery from you to another student, or vice versa.',
   'send', 400, 4)
on conflict (key) do nothing;

-- around_requests.category used to be a hardcoded CHECK against the 5
-- values above; it's now a foreign key into around_categories so admin
-- can add/edit/remove categories without a schema change.
alter table public.around_requests drop constraint if exists around_requests_category_check;
alter table public.around_requests drop constraint if exists around_requests_category_fkey;
alter table public.around_requests
  add constraint around_requests_category_fkey
  foreign key (category) references public.around_categories (key);

-- Anonymous rider-availability signal for the Around tab (Section 10) —
-- returns whether ANY rider is currently online, with no names or
-- per-rider status ever leaving the server.
create or replace function public.any_riders_available()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where role = 'rider' and rider_is_online = true and is_active = true
  );
$$;

grant execute on function public.any_riders_available() to authenticated;

-- ---------------------------------------------------------------------
-- Section 11 — Catalog & ordering flow rework (independent items + packs)
-- ---------------------------------------------------------------------
-- Every product is now its own orderable catalog item (no more
-- protein/extra options bolted onto a "meal" — product_options stays in
-- the schema for backward compatibility but the new catalog UI no
-- longer drives a combo-builder from it).
alter table public.products add column if not exists requires_pack boolean not null default false;

-- Pack price is per-vendor (Uniflex and each partner vendor set their
-- own), not a single global value.
alter table public.vendors add column if not exists pack_price numeric(10, 2) not null default 200;

alter table public.orders add column if not exists pack_count int not null default 0;
alter table public.orders add column if not exists pack_fee   numeric(10, 2) not null default 0;

-- order_packs — one row per pack the student built at checkout, so
-- Kitchen/Admin can see exactly what goes in each pack, not just a
-- total count.
create table if not exists public.order_packs (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null references public.orders (id) on delete cascade,
  pack_index int  not null,
  -- [{product_id, product_name, quantity}, ...]
  items      jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.order_packs enable row level security;

drop policy if exists "order_packs: read own via order" on public.order_packs;
create policy "order_packs: read own via order"
  on public.order_packs for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_packs.order_id and o.student_id = auth.uid()
    )
  );

drop policy if exists "order_packs: admin read all" on public.order_packs;
create policy "order_packs: admin read all"
  on public.order_packs for select to authenticated
  using (public.is_admin());
-- No client insert policy — order_packs rows are written exclusively by
-- place_food_order_with_payment() below.

-- place_food_order_with_payment — extended with the transaction PIN gate
-- (Section 6) and pack fields (Section 11). Postgres treats a longer
-- parameter list as a new overload rather than replacing the Phase 6
-- version in place (same append-only pattern already used for
-- p_scheduled_for/p_is_bulk/p_bulk_discount_pct) — existing callers are
-- unaffected, and the Flutter client always calls with the full current
-- set of named params, so it always resolves to this version.
create or replace function public.place_food_order_with_payment(
  p_vendor_id       uuid,
  p_source          text,
  p_delivery_type   text,
  p_delivery_location text,
  p_total_amount    numeric,
  p_estimated_time  text,
  p_line_items      jsonb,
  p_scheduled_for   timestamptz default null,
  p_is_bulk         boolean default false,
  p_bulk_discount_pct numeric default 0,
  p_pin             text default null,
  p_pack_fee        numeric default 0,
  p_packs           jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id   uuid := auth.uid();
  v_balance      numeric;
  v_new_balance  numeric;
  v_order_id     uuid;
  v_item         jsonb;
  v_plan_id      uuid;
  v_plan_period  text;
  v_plan_budget  numeric;
  v_plan_spent   numeric;
  v_period_start timestamptz;
  v_period_end   timestamptz;
  v_new_spent    numeric;
  v_plan_over    boolean := false;
  v_pack         jsonb;
  v_pack_idx     int := 0;
begin
  if v_student_id is null then
    raise exception 'Not authenticated';
  end if;

  if not public.verify_transaction_pin(p_pin) then
    raise exception 'INVALID_PIN';
  end if;

  select balance into v_balance
    from public.wallets
   where user_id = v_student_id
  for update;

  if not found then
    raise exception 'WALLET_NOT_FOUND';
  end if;

  if v_balance < p_total_amount then
    raise exception 'INSUFFICIENT_BALANCE';
  end if;

  update public.wallets
    set balance = balance - p_total_amount
  where user_id = v_student_id
  returning balance into v_new_balance;

  insert into public.orders
    (student_id, vendor_id, source, type, status, delivery_type,
     delivery_location, total_amount, estimated_time, scheduled_for,
     is_bulk, bulk_discount_pct, pack_count, pack_fee)
  values
    (v_student_id, p_vendor_id, p_source, 'food', 'placed', p_delivery_type,
     p_delivery_location, p_total_amount, p_estimated_time, p_scheduled_for,
     p_is_bulk, p_bulk_discount_pct, jsonb_array_length(p_packs), p_pack_fee)
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_line_items)
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

  for v_pack in select * from jsonb_array_elements(p_packs)
  loop
    insert into public.order_packs (order_id, pack_index, items)
    values (v_order_id, v_pack_idx, coalesce(v_pack -> 'items', '[]'::jsonb));
    v_pack_idx := v_pack_idx + 1;
  end loop;

  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_student_id, 'debit', p_total_amount, 'order_payment', v_order_id, v_new_balance);

  -- Lazily update the active saving plan's spent counter, resetting it
  -- if the current period boundary has passed (unchanged from Phase 3).
  select id, period, budget, spent, period_start
    into v_plan_id, v_plan_period, v_plan_budget, v_plan_spent, v_period_start
  from public.saving_plans
  where user_id = v_student_id and is_active
  limit 1;

  if v_plan_id is not null then
    v_period_end := case v_plan_period
      when 'daily' then v_period_start + interval '1 day'
      when 'weekly' then v_period_start + interval '7 days'
      else v_period_start + interval '1 month'
    end;

    if now() >= v_period_end then
      v_period_start := date_trunc('day', now());
      v_new_spent := p_total_amount;
    else
      v_new_spent := v_plan_spent + p_total_amount;
    end if;

    update public.saving_plans
      set spent = v_new_spent, period_start = v_period_start, updated_at = now()
    where id = v_plan_id;

    v_plan_over := v_new_spent > v_plan_budget;
  end if;

  return jsonb_build_object(
    'order_id', v_order_id,
    'balance_after', v_new_balance,
    'plan_over_budget', v_plan_over,
    'plan_period_reset', false
  );
end;
$$;

grant execute on function public.place_food_order_with_payment(
  uuid, text, text, text, numeric, text, jsonb, timestamptz, boolean, numeric, text, numeric, jsonb
) to authenticated;

-- place_around_with_payment — extended with the transaction PIN gate.
create or replace function public.place_around_with_payment(
  p_category          text,
  p_pickup_location   text,
  p_dropoff_location  text,
  p_item_description  text,
  p_total_amount      numeric,
  p_pin               text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id   uuid    := auth.uid();
  v_balance      numeric;
  v_new_balance  numeric;
  v_order_id     uuid;
  v_plan_id      uuid;
  v_plan_period  text;
  v_plan_budget  numeric;
  v_plan_spent   numeric;
  v_period_start timestamptz;
  v_period_end   timestamptz;
  v_new_spent    numeric;
  v_plan_over    boolean := false;
begin
  if v_student_id is null then
    raise exception 'Not authenticated';
  end if;

  if not public.verify_transaction_pin(p_pin) then
    raise exception 'INVALID_PIN';
  end if;

  select balance into v_balance
    from public.wallets
   where user_id = v_student_id
  for update;

  if not found then
    raise exception 'WALLET_NOT_FOUND';
  end if;

  if v_balance < p_total_amount then
    raise exception 'INSUFFICIENT_BALANCE';
  end if;

  update public.wallets
    set balance = balance - p_total_amount
  where user_id = v_student_id
  returning balance into v_new_balance;

  insert into public.orders
    (student_id, source, type, status, delivery_type, total_amount, estimated_time)
  values
    (v_student_id, 'uniflex', 'around', 'placed', 'delivery',
     p_total_amount, '15–25 min')
  returning id into v_order_id;

  insert into public.around_requests
    (order_id, category, pickup_location, dropoff_location,
     item_description, estimated_fee)
  values
    (v_order_id, p_category, p_pickup_location, p_dropoff_location,
     p_item_description, p_total_amount);

  insert into public.wallet_transactions
    (user_id, type, amount, source, order_id, balance_after)
  values
    (v_student_id, 'debit', p_total_amount, 'order_payment', v_order_id, v_new_balance);

  select id, period, budget, spent, period_start
    into v_plan_id, v_plan_period, v_plan_budget, v_plan_spent, v_period_start
  from public.saving_plans
  where user_id = v_student_id and is_active
  limit 1;

  if v_plan_id is not null then
    v_period_end := case v_plan_period
      when 'daily' then v_period_start + interval '1 day'
      when 'weekly' then v_period_start + interval '7 days'
      else v_period_start + interval '1 month'
    end;

    if now() >= v_period_end then
      v_period_start := date_trunc('day', now());
      v_new_spent := p_total_amount;
    else
      v_new_spent := v_plan_spent + p_total_amount;
    end if;

    update public.saving_plans
      set spent = v_new_spent, period_start = v_period_start, updated_at = now()
    where id = v_plan_id;

    v_plan_over := v_new_spent > v_plan_budget;
  end if;

  return jsonb_build_object(
    'order_id', v_order_id,
    'balance_after', v_new_balance,
    'plan_over_budget', v_plan_over,
    'plan_period_reset', false
  );
end;
$$;

grant execute on function public.place_around_with_payment(
  text, text, text, text, numeric, text
) to authenticated;

-- ---------------------------------------------------------------------
-- Section 12 — Order status sync (single source of truth)
-- ---------------------------------------------------------------------
-- Marks the moment Admin/Kitchen explicitly hands a Uniflex delivery
-- order to the rider pool — see transfer_order_to_rider() below. Pool
-- eligibility for Uniflex-source delivery orders now requires this to
-- be set, not just status = 'ready', so there is one explicit,
-- auditable action instead of an implicit status side-effect.
alter table public.orders add column if not exists transferred_to_rider_at timestamptz;

drop policy if exists "orders: rider read pool" on public.orders;
create policy "orders: rider read pool"
  on public.orders for select to authenticated
  using (
    public.is_rider()
    and rider_id is null
    and (
      (source = 'uniflex' and status = 'ready' and transferred_to_rider_at is not null
         and delivery_type in ('delivery', 'campus_delivery', 'hostel_delivery'))
      or (source = 'partner' and status = 'placed'
         and delivery_type in ('delivery', 'campus_delivery', 'hostel_delivery'))
      or (type = 'around' and status = 'placed')
    )
  );

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
       and v_order.transferred_to_rider_at is not null
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

-- transfer_order_to_rider — the "Transfer to Rider" action from the
-- Kitchen Queue (Section 12). Only Admin/Kitchen Staff can call it, only
-- on a Uniflex food delivery order that is already Ready and has no
-- rider yet.
create or replace function public.transfer_order_to_rider(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Unauthorized';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.source <> 'uniflex' or v_order.type <> 'food' then
    raise exception 'Only Uniflex food orders can be transferred to a rider here';
  end if;

  if v_order.delivery_type not in ('delivery', 'campus_delivery', 'hostel_delivery') then
    raise exception 'Order is not a delivery order';
  end if;

  if v_order.status <> 'ready' then
    raise exception 'Order must be marked Ready before it can be transferred to a rider';
  end if;

  if v_order.rider_id is not null then
    raise exception 'Order already has a rider assigned';
  end if;

  update public.orders
    set transferred_to_rider_at = now()
  where id = p_order_id;
end;
$$;

grant execute on function public.transfer_order_to_rider(uuid) to authenticated;

-- update_order_status — hardened so the only path to 'out_for_delivery'
-- or 'completed' on a delivery order (food delivery or around) is the
-- rider workflow (accept_order / verify_delivery), which enforces the
-- PIN gate. This is what makes "must not show as completed anywhere
-- until the PIN is confirmed" actually true at the data layer instead
-- of relying on every screen to agree not to call the wrong RPC.
create or replace function public.update_order_status(
  p_order_id   uuid,
  p_new_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if not (select public.is_admin()) then
    raise exception 'Unauthorized';
  end if;

  if p_new_status not in (
    'placed', 'preparing', 'ready',
    'out_for_delivery', 'ready_for_pickup',
    'completed', 'cancelled'
  ) then
    raise exception 'Invalid status: %', p_new_status;
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if not found then
    raise exception 'Order not found: %', p_order_id;
  end if;

  if (
       v_order.type = 'around'
       or (v_order.type = 'food' and v_order.delivery_type in ('delivery', 'campus_delivery', 'hostel_delivery'))
     )
     and p_new_status in ('out_for_delivery', 'completed') then
    raise exception 'Delivery orders can only reach that status through the rider workflow';
  end if;

  if v_order.type = 'food' and v_order.delivery_type = 'pickup'
     and p_new_status = 'completed' and v_order.status <> 'ready_for_pickup' then
    raise exception 'Pickup orders must be Ready for Pickup before they can be completed';
  end if;

  update public.orders
    set status = p_new_status
  where id = p_order_id;
end;
$$;

grant execute on function public.update_order_status(uuid, text) to authenticated;

-- get_rider_info — lets the STUDENT see their assigned rider's name and
-- phone once one is accepted (mirrors get_customer_info, which already
-- does the reverse for the rider). Only the order's own student can call
-- it, and only once a rider is actually assigned.
create or replace function public.get_rider_info(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider_id   uuid;
  v_student_id uuid;
  v_result     jsonb;
begin
  select rider_id, student_id into v_rider_id, v_student_id
    from public.orders where id = p_order_id;

  if v_student_id is null or v_student_id <> auth.uid() then
    raise exception 'Unauthorized';
  end if;

  if v_rider_id is null then
    return null;
  end if;

  select jsonb_build_object('full_name', full_name, 'phone', phone)
    into v_result
  from public.profiles where id = v_rider_id;

  return v_result;
end;
$$;

grant execute on function public.get_rider_info(uuid) to authenticated;
