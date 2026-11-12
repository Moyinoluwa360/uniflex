# Vendor ordering styles (Pack 1 / Part 3)

Two ways a vendor can take food orders:

| Style (`vendors.ordering_style`) | Label | What the student does |
|---|---|---|
| `pack_based` (default, every existing vendor) | Pack-based | Customers build packs: how many packs, spoons and toppings |
| `fixed_menu` | Fixed menu | Every meal is fixed and priced as listed; customers just choose quantities |

## 1. What existed before this pack (read from code + the live database, 2026-11-12)

**Data**
- `vendors`: name, description, image, location, contact, `pack_price`,
  campus/hostel delivery fees, `is_featured` + `badge_label = 'Major'` (= Uniflex),
  `is_active`, `deleted_at`. RLS: everyone signed in reads non-deleted
  vendors; only `is_super_admin()` inserts / updates / deletes.
- `products`: `vendor_id`, name, description, free-text `category`,
  `base_price` (numeric, **naira**, not kobo — the whole app stores naira
  `numeric(10,2)`), `is_available`, `requires_pack`, `section`
  (food | drinks | others, checked), `food_subsection` (meal | protein_topping,
  required for food), `deleted_at`. Students only see available, non-deleted
  items (RLS), so "unavailable" items are simply not listed to students.
- Packs: `delivery_settings.pack_meal_capacity` (8 spoons), a pack = a map
  productId → quantity; meals count toward capacity, proteins/toppings don't.
- Orders: `delivery_groups` (one per checkout) → `orders` (one per vendor leg,
  `pack_count`, `pack_fee`, `total_amount`) → `order_items` (**snapshot**:
  `product_name`, `unit_price`, `quantity`) and `order_packs` (per-pack
  contents jsonb + `price`).

**Pricing (server only)** — `create_paid_delivery_order(p_legs …)` (also used by
`create_paid_gift_order`) and `create_paid_pickup_order` (Uniflex only). The
client sends only `{vendor_id, items:[{product_id, quantity}], packs:[…]}`. The
server reads prices from `products`, rejects unknown / unavailable / other-
vendor items and quantities outside 1–99, checks pack capacity and that packs
never hold more than was ordered, computes pack fee = packs × vendor pack price,
delivery fee = location price × brackets(packs) (0 packs = 1 bracket) and the
service charge, debits the wallet and writes everything in one transaction.
**Packs were already optional**: a leg with items and no packs is valid.

**Client**
- Cart: `cartProvider` (SharedPreferences), groups per vendor with a
  serialised `Vendor` snapshot, items, `packCount`, `packFee`, `packContents`.
- Student vendor page `CatalogScreen`: "Food" → an "Order Food (Packs)" row →
  `PackBuilderScreen`; Drinks and Others as accordions with inline add/stepper.
- Cart UIs: `CartScreen` (Your Cart) and Orders → Cart tab: plain item rows
  with steppers; the pack line only shows when `packCount > 0`.
- Order display: every role reads `get_order_breakdown` →
  `_breakdown_leg` → `OrderBreakdownView` (packs as dropdowns, then plain
  Items / Drinks / Others lists, `2×` + name at 16 px, names wrap). An order
  with no packs already shows a plain "Items" list with no pack headings.
- Admin: `VendorFormScreen` (create/edit vendor), `VendorMenuManager` (four
  sections Meals / Proteins / Drinks / Others, each with "+ Add"),
  `ProductFormScreen`.

## 2. What this pack adds

**Database** (`supabase/pack1_vendor_ordering_style.sql`)
- `vendors.ordering_style text not null default 'pack_based'` + check
  (`pack_based`, `fixed_menu`). Adding the column back-fills every existing
  vendor as `pack_based`; nothing else about them changes.
- Guard trigger: only a super admin (or the service role) may set a non-default
  style on insert or change it on update, and a change is refused
  (`VENDOR_HAS_ACTIVE_ORDERS`) while the vendor has an order that is not
  completed or cancelled. Reading it follows the existing vendor read policy.
- `_check_leg_style(vendor, declared_style, packs, items)`, called by both
  checkout functions right after the vendor is loaded:
  - the leg's declared style (sent by new app builds from the cart snapshot)
    must equal the vendor's current style → else `VENDOR_STYLE_CHANGED`
    (a cart built before an admin switched the style can't be ordered);
  - fixed-menu legs: no packs (`PACKS_NOT_ALLOWED`), and at most 20 of one
    item (`QUANTITY_TOO_HIGH`, summed per product).
  - pack-based legs: unchanged.
- Belt and braces: `order_packs` rows can't be inserted for a fixed-menu
  vendor; fixed-menu products must have a name, a category and a price
  greater than 0 and at most ₦500,000, and are stored as plain items
  (`requires_pack = false`, section food / meal so every existing display shows
  them under "Items").

Prices for fixed-menu vendors are therefore exactly unit price × quantity from
`products`, no pack fee, no spoon logic; delivery fee = 1 bracket per vendor
(same as a drinks-only leg today); service charge, payment-first, delivery fee
= commitment fee, cancellation and the rider 3-job limit are untouched.

**Admin** — vendor form gets an "Ordering style" segmented control (Pack-based |
Fixed menu) with one helper line; Pack price only shows for pack-based. A
fixed-menu vendor's menu manager lists items grouped by **category** with one
"+ Add item"; the item form asks for name, category, description, price,
photo, availability (no section / meal / protein / pack fields).

**Student** — a fixed-menu vendor page has no "Order Food (Packs)" row: each
category is a dropdown (same accordion as Drinks/Others) with name,
description, price, an outlined green `+` that becomes `− 1 +` (0 removes,
max 20). Pack-based vendors are unchanged. Cart, checkout, order cards,
tracking, rider and admin views reuse the existing code paths, which already
handle a vendor with no packs.

**Not changed (owner decisions, 2026-11-12):** the rider still confirms the food
price exactly as today; style is editable by admin only and blocked while
orders are active; max 20 per item; labels "Pack-based" / "Fixed menu".
