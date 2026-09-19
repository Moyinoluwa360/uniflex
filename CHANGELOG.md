# Changelog

All notable changes to this project are documented here, phase by phase.

## Phase 6 — Profile & Loyalty, Referral, Gifting, Group Checkout, Bulk Delivery, Birthday Rewards, Smart Pre-Order, Extended Delivery, Push Notifications, Admin Scheduling (2026-09-13)

Final phase. Completes the full student experience and admin tools needed
for a live campus deployment.

### Added

- **`supabase/schema.sql` — Phase 6 block**
  - New profile columns: `reward_points`, `membership_tier`, `lifetime_spending`,
    `total_orders`, `referral_count`, `fcm_token`.
  - New order columns: `scheduled_for`, `is_bulk`, `bulk_discount_pct`,
    `group_order_id`.
  - `delivery_type` constraint extended to include `campus_delivery` and
    `hostel_delivery`.
  - New tables: `group_orders`, `group_order_members`, `gifts`,
    `referral_credits`, `achievements`, `user_achievements`.
  - Trigger `_after_order_placed` — fires `AFTER INSERT` on `orders`; bumps
    `total_orders`, `lifetime_spending`, `reward_points`; recalculates
    `membership_tier`; awards tier/milestone badges automatically.
  - Trigger `_after_order_completed` — fires `AFTER UPDATE` on `orders`;
    credits referrer ₦500 + 50 pts on the referred student's first completed
    order; writes to `referral_credits` audit table.
  - RPCs: `get_student_stats`, `get_referral_leaderboard`, `store_fcm_token`,
    `get_user_achievements`, `send_gift`, `get_gifts`, `create_group_order`,
    `join_group_order`, `checkout_group_order`, `process_birthday_rewards`.
  - `place_food_order_with_payment` extended with optional params
    (`p_scheduled_for`, `p_is_bulk`, `p_bulk_discount_pct`) — backward-
    compatible; existing 7-param callers continue to work.
  - Achievements catalogue seeded (10 badges: First Bite, Regular,
    Super Regular, Connector, Ambassador, Gifter, Silver/Gold/Platinum Member,
    Birthday Blessings).
  - pg_cron schedule comment for `process_birthday_rewards` (daily 00:00 UTC).

- **Dart models**
  - `lib/shared/models/profile.dart` — added `rewardPoints`, `membershipTier`,
    `lifetimeSpending`, `totalOrders`, `referralCount`, `fcmToken` fields;
    `tierProgress` and `spendingToNextTier` computed getters.
  - `lib/shared/models/order.dart` — added `scheduledFor`, `isBulk`,
    `bulkDiscountPct`, `groupOrderId` fields; `isForDelivery` now covers
    `campus_delivery` and `hostel_delivery`; `isScheduled` getter.
  - `lib/shared/models/gift.dart` — new model for sent/received food gifts.
  - `lib/shared/models/achievement.dart` — new model for badges catalogue.

- **Packages** (`pubspec.yaml`): `firebase_core`, `firebase_messaging`,
  `flutter_local_notifications`, `share_plus`.

- **Android Firebase config** — `android/build.gradle.kts` (Google Services
  classpath), `android/app/build.gradle.kts` (plugin applied),
  `android/app/google-services.json` (placeholder — replace with real config).

- **`lib/shared/services/notifications/notification_service.dart`** —
  `NotificationService.init()` requests permission, fetches + stores FCM
  token, configures foreground local notifications, handles token refresh.

- **`lib/student/services/student_service.dart`** and
  **`lib/student/services/student_providers.dart`** — wrappers for all Phase 6
  RPCs; providers: `studentStatsProvider`, `referralLeaderboardProvider`,
  `userAchievementsProvider`, `giftsProvider`, `groupMembersProvider`.

- **Student profile** — fully rebuilt `lib/student/profile/student_profile_screen.dart`:
  tier-coloured hero header, wallet balance, Services menu (Membership,
  Referral, Gift, Badges, Scheduled Orders), Account section, More menu
  (Preferences, Log out).

- **Sub-screens**:
  - `membership_card_screen.dart` — card with tier/points/stats, progress bar
    to next tier, perks list, all-tier overview.
  - `referral_screen.dart` — referral code + share sheet (`share_plus`),
    top-10 leaderboard.
  - `gift_screen.dart` — Send Gift tab (matric lookup + message) + History
    tab (sent/received).
  - `badges_screen.dart` — earned badges + locked-badge grid with progress
    counter.
  - `scheduled_orders_student_screen.dart` — upcoming scheduled orders with
    live countdown.
  - `preferences_screen.dart` — Light / Dark / System theme toggle.

- **`lib/student/ordering/checkout_screen.dart`** — 3 fulfillment options
  (Pickup free, Campus Delivery ₦200, Hostel Room Delivery ₦300); optional
  date/time scheduler for pre-orders.

- **Group checkout**:
  - `lib/student/group_checkout/create_group_screen.dart` — creates a session,
    shows shareable group ID.
  - `lib/student/group_checkout/group_checkout_screen.dart` — join by ID
    (`JoinGroupScreen`) and individual member checkout
    (`GroupCheckoutScreen`).

- **`lib/admin/scheduled/admin_scheduled_orders_screen.dart`** — live stream
  of upcoming scheduled orders; each card has a per-second countdown to
  `scheduled_for`; admin can advance status to "Preparing".

- **Admin shell** (`lib/admin/admin_shell.dart`) — added "Scheduled" tab for
  `super_admin`.

- **`lib/admin/services/admin_service.dart`** — `streamScheduledOrders()`.
  **`lib/admin/services/admin_providers.dart`** — `scheduledOrdersProvider`.

- **Kitchen queue** — BULK badge shown on orders with `is_bulk == true`;
  delivery type label now reflects campus/hostel variants.

- **`lib/main.dart`** — Firebase initialisation with try-catch guard (app
  continues gracefully with placeholder `google-services.json`).

- **Edge Functions**:
  - `supabase/functions/send-notification/index.ts` — FCM push via legacy
    HTTP API; requires `FIREBASE_SERVER_KEY` secret.
  - `supabase/functions/birthday-rewards/index.ts` — invokes
    `process_birthday_rewards()` RPC; designed for pg_cron or an external
    daily cron.

### Changed

- `lib/student/ordering/order_repository.dart` — `placeFoodOrder` now accepts
  `scheduledFor`, `isBulk`, `bulkDiscountPct`; delivery fee logic updated for
  three types; passes new optional RPC params.

---

## Phase 5 — Rider Shell (2026-09-13)

Full Rider Shell replacing the Phase 0 placeholder. Riders can toggle
online/offline, browse the live job pool (pull model, first-come-first-
served), work through the full delivery workflow with a mandatory one-time
PIN gate, call customers directly, and review their completed-delivery
history.

### Added

- **`supabase/schema.sql` — Phase 5 block**
  - `rider_is_online` column on `profiles`.
  - `rider_id`, `delivery_pin`, `delivery_stage` columns on `orders`.
  - `delivery_records` table (one row per completed delivery, with optional
    `duration_seconds`, `distance_meters`, and `rating` for future features).
  - `_generate_delivery_pin` trigger — fires `BEFORE INSERT` on `orders`;
    sets a 4-char alphanumeric PIN (unambiguous 32-char alphabet) for every
    `delivery_type = 'delivery'` order.
  - `is_rider()` SECURITY DEFINER helper (mirrors Phase 4's `is_admin()`).
  - RLS policies: rider pool read, rider own-assigned read,
    `delivery_records` own history, `around_requests` pool/assigned read.
  - RPCs: `accept_order` (FOR UPDATE NOWAIT prevents double-accepts),
    `confirm_pickup`, `verify_delivery` (PIN gate + delivery_record write),
    `get_customer_info` (name+phone only, to assigned rider only),
    `get_rider_stats`, `toggle_rider_online`.

- **`lib/shared/models/order.dart`** — `riderId`, `deliveryPin`,
  `deliveryStage` fields; `fromMap` / `copyWith` updated.

- **`lib/rider/`** — full rider module:
  - `pool/pool_order.dart` — enriched model: pickup name/address, type label.
  - `delivery/delivery_record.dart` — history record with `durationLabel`.
  - `services/rider_service.dart` — `RiderService` (stream pool, active
    delivery stream, detail fetch, all delivery actions, history fetch).
  - `services/rider_providers.dart` — `jobPoolProvider`,
    `activeDeliveryProvider`, `riderStatsProvider`,
    `deliveryHistoryProvider`, `activeDeliveryDetailProvider`.
  - `dashboard/rider_dashboard_screen.dart` — online/offline card, daily
    + all-time stats, active delivery banner.
  - `pool/job_pool_screen.dart` — live pool (Supabase Realtime), accept
    with race-condition handling (friendly "already taken" message).
  - `delivery/active_delivery_screen.dart` — accepted → Confirm Pickup →
    picked_up → PIN entry → verify delivery; Google Maps deep-link via
    `url_launcher`; `geolocator` adds current position as route origin;
    customer call button.
  - `history/delivery_history_screen.dart` — past deliveries list.
  - `profile/rider_profile_screen.dart` — real profile data + logout.
  - `rider_shell.dart` — 4 tabs: Home / Jobs / History / Profile.

- **Student screens** — delivery PIN display:
  - `order_confirmation_screen.dart` — `_DeliveryPinCard` shown after
    placing a delivery order; tap to copy.
  - `order_tracking_screen.dart` — `_TrackingPinCard` reminder while
    the order is active; tap to copy.

- **`pubspec.yaml`** — `url_launcher: ^6.3.0`, `geolocator: ^13.0.2`.

- **`android/app/src/main/AndroidManifest.xml`** — `ACCESS_FINE_LOCATION`,
  `ACCESS_COARSE_LOCATION`; `<queries>` for `https` + `tel` schemes.

## Phase 4 — Admin & kitchen module (2026-09-13)

Full Admin Shell replacing the Phase 0 placeholder. Admin/kitchen staff
manage Uniflex's own menu and partner vendors, run the live kitchen queue
with Supabase Realtime, and view a real-time dashboard of today's orders
and revenue. A two-tier permission system (super_admin / kitchen_staff)
restricts kitchen_staff accounts to the queue only, without a separate
login.

### Added

**Supabase schema** (`supabase/schema.sql`) — Phase 4 block appended:
- `admin_tier` column on `profiles` — `'super_admin'` | `'kitchen_staff'`
  | NULL (treated as super_admin). Only meaningful for `role = 'admin'`
  rows.
- `location` and `contact` columns on `vendors` — added for partner
  vendor management (both nullable).
- `is_admin()` helper SECURITY DEFINER function — centralised admin check
  used by all Phase 4 RLS policies and RPCs.
- Admin RLS policies: INSERT/UPDATE/DELETE on `vendors`, `products`, and
  `product_options`; SELECT/UPDATE on `orders` (all orders, not just own);
  SELECT on `order_items` and `around_requests` for admin.
- `ALTER PUBLICATION supabase_realtime ADD TABLE public.orders` (idempotent
  DO block) — required for the kitchen queue StreamProvider.
- `update_order_status(p_order_id, p_new_status)` SECURITY DEFINER RPC —
  advances an order through kitchen stages; validates caller is admin.
- `get_dashboard_stats()` SECURITY DEFINER RPC — returns today's order
  counts by status, pending count, and Uniflex revenue in one call.
- Supabase Storage setup comments for the `product-images` bucket (storage
  policies and bucket creation must be done from the dashboard — see
  schema.sql Phase 4 section).

**Shared models** (`shared/models/`):
- `profile.dart`: added `adminTier: String?` field and `isKitchenStaff`
  computed getter (true when role=admin and adminTier='kitchen_staff').
- `vendor.dart`: added `location: String?` and `contact: String?` fields.

**Admin service** (`lib/admin/services/`):
- `admin_service.dart`: `AdminService` — `fetchAllVendors()` (incl.
  inactive), `upsertVendor(...)`, `deleteVendor(id)`,
  `fetchAllVendorProducts(vendorId)` (incl. unavailable), `upsertProduct(...)`,
  `deleteProduct(id)`, `uploadProductImage(bytes, fileName)` (Supabase
  Storage), `streamKitchenOrders()` (async* stream with batch item fetch),
  `updateOrderStatus(orderId, newStatus)`, `getDashboardStats()`.
  `KitchenOrder` model (Order + items list).
- `admin_providers.dart`: `adminServiceProvider`, `allVendorsProvider`,
  `adminVendorProductsProvider` (FutureProvider.family),
  `kitchenOrdersProvider` (StreamProvider — Supabase Realtime),
  `dashboardStatsProvider`.

**Admin shell** (`lib/admin/admin_shell.dart`) — full rewrite:
- `ConsumerWidget` that reads `currentProfileProvider` for `adminTier`.
- `kitchen_staff` tier: Queue + Profile tabs only.
- `super_admin` (or null): Dashboard + Queue + Menu + Vendors + Profile.

**Admin screens** (`lib/admin/`):
- `dashboard/admin_dashboard_screen.dart` — SliverAppBar header, 2×2
  stat grid (orders today, revenue, pending, completed), status breakdown
  bar. Manual refresh button; uses `dashboardStatsProvider`.
- `kitchen/kitchen_queue_screen.dart` — live queue via
  `kitchenOrdersProvider` (StreamProvider). Orders grouped into
  Scheduled/Preparing/Ready sections. Each card shows order ID, time,
  delivery type, and items (expandable). Action button advances status:
  "Start Preparing" (placed→preparing) / "Mark Ready" (preparing→ready).
  Live indicator dot in AppBar.
- `menu/menu_management_screen.dart` — all Uniflex products grouped by
  category. Availability toggle (shows/hides in student catalog).
  Add/edit/delete via `product_form_screen.dart`.
- `menu/product_form_screen.dart` — name, description, category dropdown,
  price, image picker (gallery → Supabase Storage upload), availability
  toggle. Pre-fills for edit mode.
- `vendors/vendor_management_screen.dart` — all partner vendors (Uniflex
  excluded). Active/inactive toggle, add/edit/delete, "Manage Menu"
  shortcut to `vendor_products_screen.dart`.
- `vendors/vendor_form_screen.dart` — name, description, location,
  contact, active toggle.
- `vendors/vendor_products_screen.dart` — same product management UX as
  `menu_management_screen.dart` but scoped to the given partner vendor.
- `profile/admin_profile_screen.dart` — shows full name, email, and tier
  label (Kitchen Staff / Super Admin). Logout button.

**pubspec.yaml**:
- Added `image_picker: ^1.0.7` for admin product image picking.

**AndroidManifest.xml**:
- Added `READ_EXTERNAL_STORAGE` (maxSdkVersion=32) and
  `READ_MEDIA_IMAGES` permissions for image picker.

### Changed

- `lib/shared/models/profile.dart` — `Profile` gains `adminTier` and
  `isKitchenStaff` without breaking any existing call sites (new field is
  nullable, `isKitchenStaff` defaults to `false` for non-admin profiles).
- `lib/shared/models/vendor.dart` — `Vendor` gains `location` and
  `contact` (nullable); existing call sites unchanged.
- `lib/admin/admin_shell.dart` — replaced static placeholder with live
  tier-aware shell.
- `lib/admin/profile/admin_profile_screen.dart` — replaced placeholder
  with real profile + tier display.

### Notes

- **Partner vendor data is now real**: the `vendorsProvider` in the
  student shell already queries the `vendors` table — no code changes
  needed on the student side. When admin adds/edits partner vendors,
  those changes appear on the Student Home screen as soon as the provider
  next resolves (next navigation to home or hot-reload in dev). Order
  `source` is set from `vendor.isUniflex` (unchanged since Phase 2).
- **Kitchen Staff seeding**: see the Phase 4 SQL comments at the bottom
  of `supabase/schema.sql`. Create the auth user by hand, then insert a
  `profiles` row with `role='admin'` and `admin_tier='kitchen_staff'`.
- **product-images storage**: the bucket must be created and policies
  applied from the Supabase dashboard before product image upload will
  work. SQL for the policies is provided as commented-out code in
  `schema.sql`'s Phase 4 block.
- **Realtime publication**: the `DO` block in schema.sql idempotently adds
  `orders` to `supabase_realtime`. If that publication doesn't exist in
  your project (most Supabase projects have it by default), create it via
  Dashboard → Database → Replication first.

## Phase 3 — Wallet & payments (2026-09-11)

Real Paystack sandbox funding, server-side payment verification via a
Supabase Edge Function, wallet-deducted order placement (atomic, no
double-spend), Virtual Account issuance attempt with graceful fallback,
and a self-service Saving Plan feature. Scoped to the Student shell only.

### Added

**Supabase Edge Functions** (`supabase/functions/`):
- `verify-paystack-payment/index.ts` — receives a Paystack reference
  from the Flutter client after checkout, calls Paystack's
  `/transaction/verify/{ref}` using `PAYSTACK_SECRET_KEY` (never
  bundled in the app), and on success calls the `credit_wallet` RPC with
  the Supabase service-role client. Idempotent: duplicate references
  return 409 rather than double-crediting.
- `create-virtual-account/index.ts` — attempts to issue a real Paystack
  Dedicated Virtual Account (NUBAN) using the test secret key, then
  creates a Paystack customer if none exists. Catches Paystack API
  errors (typically business-verification requirement not yet met) and
  falls back gracefully to the Phase 1 placeholder VAN, returning
  `is_real_account: false` so the UI can show a "pending activation"
  notice. TODO: revisit once Paystack business verification is complete.

**Supabase schema** (`supabase/schema.sql`) — Phase 3 block appended:
- `wallet_transactions` table: `(id, user_id, type [credit|debit],
  amount, source [topup|order_payment|refund], order_id?, reference?,
  balance_after, created_at)`. All writes go through SECURITY DEFINER
  RPCs — no direct client INSERT policy; clients only SELECT own rows.
- `saving_plans` table: `(id, user_id UNIQUE, period [daily|weekly|
  monthly], budget, spent, period_start, is_active, created_at,
  updated_at)`. Managed directly by the client via RLS
  (insert/update/delete own row). `touch_updated_at` trigger applied.
- `credit_wallet(p_user_id, p_amount, p_reference)` RPC — atomically
  increments the wallet balance and records a credit transaction.
  Granted to `service_role` only (Edge Function); never callable by
  `authenticated` clients. Raises `DUPLICATE_REFERENCE` for idempotency.
- `place_food_order_with_payment(p_vendor_id, p_source, p_delivery_type,
  p_delivery_location, p_total_amount, p_estimated_time, p_line_items)`
  RPC — row-locks the wallet, checks balance, deducts, creates
  `orders` + `order_items` rows, records the debit transaction, and
  lazily updates the active saving plan's `spent` counter (resetting it
  if the period boundary has passed). Returns `{order_id, balance_after,
  plan_over_budget, plan_period_reset}`. Raises `INSUFFICIENT_BALANCE`
  on failure. Granted to `authenticated`.
- `place_around_with_payment(p_category, p_pickup_location,
  p_dropoff_location, p_item_description, p_total_amount)` RPC — same
  wallet-deduction guarantees as the food order path but for
  `type='around'` requests, creating `orders` + `around_requests`.
  Granted to `authenticated`.
- `get_wallet_info()` RPC — returns balance, virtual_account_number, and
  tier in one call (replaces the raw `wallets` SELECT in the wallet
  screen). Granted to `authenticated`.

**Shared models** (`shared/models/`):
- `wallet_transaction.dart`: `WalletTransaction` + `WalletTxType` enum
  (credit/debit) + `WalletTxSource` enum (topup/orderPayment/refund).
  `signedAmount` computed getter. `label` display string.
- `saving_plan.dart`: `SavingPlan` + `BudgetPeriod` enum
  (daily/weekly/monthly). `remainingBudget`, `isOverBudget`, and
  `periodLabel` computed getters.

**Shared services** (`shared/services/`):
- `wallet/wallet_service.dart`: `WalletService` — `getWalletInfo()`,
  `getTransactions()`, `verifyPaystackPayment(reference)` (invokes Edge
  Function), `createVirtualAccount()` (invokes Edge Function).
  `WalletException` and `VirtualAccountResult` types.
- `saving_plan/saving_plan_service.dart`: `SavingPlanService` —
  `fetchActivePlan()`, `upsertPlan(period, budget)`, `deactivatePlan()`.
  Period anchor computation (start of day/week/month in UTC).
- `saving_plan/saving_plan_providers.dart`: `savingPlanServiceProvider`,
  `activeSavingPlanProvider` (FutureProvider), `SavingPlanNotifier` +
  `savingPlanNotifierProvider` (AsyncNotifier — wraps upsert/deactivate).

**Wallet screen** (`student/wallet/`) — full set of new files:
- `paystack_checkout_page.dart`: full-screen WebView page loading the
  Paystack Popup JS inline. Communicates back to Flutter via a
  `JavaScriptChannel` named `PaystackChannel`. The Paystack reference is
  generated by the caller before pushing the page — the same reference
  is sent to the Edge Function for verification.
- `wallet_screen.dart`: rewritten from the Phase 2 placeholder. Balance
  card with Fund Wallet button → amount bottom sheet → Paystack checkout
  → Edge Function verification → provider invalidation. Virtual Account
  card (attempts DVA on first mount via `createVirtualAccount` Edge
  Function; shows pending notice on fallback). Saving Plan shortcut.
  Transaction history list with credit/debit styling and running balance.
  Pull-to-refresh on the whole screen.
- `saving_plan_screen.dart`: period chips (Daily/Weekly/Monthly), budget
  input, current plan summary card (budget/spent/remaining progress bar,
  over-budget warning chip), budget history (order-payment debits in the
  current period), Save/Update/Remove actions.

### Changed

- `shared/services/wallet/wallet_providers.dart` — kept `walletBalanceProvider`
  (still used by Home screen + Profile screen). Added `walletServiceProvider`,
  `walletInfoProvider` (FutureProvider for full wallet row), and
  `walletTransactionsProvider` (FutureProvider for transaction history).
- `student/ordering/order_repository.dart` — `placeFoodOrder()` and
  `placeAroundRequest()` now call the respective SECURITY DEFINER RPCs
  instead of raw multi-step inserts. `OrderPlacementState` gains
  `budgetWarning: bool`. After success, invalidates `walletBalanceProvider`,
  `walletInfoProvider`, and `walletTransactionsProvider` in addition to
  the order providers. `_mapError()` translates `INSUFFICIENT_BALANCE` /
  `WALLET_NOT_FOUND` Postgres exceptions to client-facing strings.
- `student/ordering/checkout_screen.dart` — removed the "Payment is
  mocked" notice. Confirm button is disabled when wallet balance < order
  total. A wallet balance row is shown in the total breakdown card.
  Insufficient-balance inline warning with a "Top up your wallet →" link.
  Post-order saving-plan budget-exceeded SnackBar shown when
  `OrderPlacementState.budgetWarning` is true.
- `student/around/around_screen.dart` — removed the "Payment is mocked"
  notice. Now handles `insufficient_balance` error string from
  `OrderNotifier` to show a specific top-up prompt. Shows budget-exceeded
  SnackBar when applicable.
- `pubspec.yaml` — added `webview_flutter: ^4.8.0` for Paystack checkout.
- `.env.example` — added `PAYSTACK_SECRET_KEY=` placeholder with a comment
  that this must **only** be set as a Supabase Edge Function secret, never
  in the Flutter `.env` file.
- `android/app/src/main/AndroidManifest.xml` — added
  `INTERNET` permission (required for the WebView-based Paystack checkout
  and for Supabase HTTP calls on Android).

### Notes

- **PAYSTACK_SECRET_KEY is never in the Flutter app.** It lives exclusively
  in the Supabase dashboard under Edge Functions → Secrets. The app only
  ever uses `PAYSTACK_PUBLIC_KEY` (safe to bundle).
- **Manual steps before testing**:
  1. Run the Phase 3 SQL block in the Supabase SQL editor (after Phase 2
     if not already applied).
  2. Deploy both Edge Functions: `supabase functions deploy
     verify-paystack-payment` and `supabase functions deploy
     create-virtual-account`.
  3. Set `PAYSTACK_SECRET_KEY=sk_test_...` as a secret in the Supabase
     dashboard for both functions.
  4. Set `PAYSTACK_PUBLIC_KEY=pk_test_...` in the local `.env` file.
  5. Fund the test wallet using Paystack's test card (4084 0840 8408 4081,
     expiry 01/99, CVV 408).
- **Dedicated Virtual Account**: Paystack DVA creation typically requires
  paid business verification even in test mode. The `create-virtual-account`
  Edge Function catches any API error and returns the Phase 1 placeholder
  VAN with `is_real_account: false`. Re-visit once business verification
  is complete.
- **Atomic order placement**: the food and around RPCs use `SELECT ... FOR
  UPDATE` to row-lock the wallet before deducting, preventing concurrent
  double-spend across two simultaneous checkout attempts from the same
  account.
- Verified via `flutter analyze` (clean) and `flutter test` (14/14 passing).
  On-device testing deferred per Phase 2 policy.

## Phase 2 — Home & core ordering flow (2026-09-10)

Student shell, the Home screen, the full food-delivery ordering flow,
Around (on-demand errand) requests, the Orders tab, and live order
tracking. Rider/Admin shells are untouched. No real payment processing
— the Confirm Order step inserts a placed order with status 'placed' and
no charge.

### Added

**Typography update (retrofitted into Phase 0's theme)**
- `google_fonts` added as a dependency; replaces the Phase 1 local
  ClashDisplay + Switzer font assets in `pubspec.yaml` font declarations
  (the .ttf files remain on disk but are no longer bundled).
- **Bricolage Grotesque** (via `google_fonts`) for all display/headline
  Material text theme slots and the `UniflexWordmark` — replaces Clash
  Display.
- **Plus Jakarta Sans** (via `google_fonts`) for all body, label, and
  meta slots — replaces Switzer.
- `app_typography.dart` fully rewritten; `app_theme.dart` and
  `UniflexWordmark` are unchanged (they reference `AppTypography` which
  now resolves to the new fonts automatically).

**Student Shell — 4 tabs (was 2)**
- Added `OrdersScreen` and `WalletScreen` tabs alongside Home and Profile.
- `student_shell.dart` updated; `app_bottom_nav_shell.dart` unchanged.

**Home screen** (`student/home/student_home_screen.dart`) — full rewrite:
- Branded gradient header: time-aware greeting (nickname from profile),
  wallet balance pill, decorative search bar.
- Around / Food Delivery segmented mode toggle.
- Promo banner carousel (3 static cards with page-dot indicator).
- Vendor list in Food Delivery mode: Uniflex featured card (large,
  emerald gradient, "Major" badge) then partner vendor cards beneath it.
- Around category grid: 5 categories (General Errand, Laundry Pickup &
  Dropoff, Hostel Transfer, Nearby Shop Fetch, Peer Courier). Each card
  shows the flat fee. Printing/photocopy is NOT included.

**Food delivery ordering flow** (9 steps end to end):
- `catalog_screen.dart` — menu grouped by category; "View Cart" FAB.
- `meal_customization_screen.dart` — step 2 quantity, step 3 protein
  (radio), step 4 extras (checkboxes), step 5 drink add-on (radio);
  "Add to Cart" disabled until a required protein is selected.
- `cart_screen.dart` — adjust quantities, remove items, running subtotal.
- `checkout_screen.dart` — pickup/delivery toggle (step 6), delivery
  location field when delivery (step 7), full order total with delivery
  fee; "Confirm Order" button does the mocked payment (step 8).
- `order_confirmation_screen.dart` — success screen with order reference,
  vendor, total, estimated time.
- `order_tracking_screen.dart` — vertical status timeline (step 9);
  refresh button; different step sets for pickup vs delivery vs Around.
- `cart_provider.dart` — `CartNotifier` / `CartState` (Riverpod
  `Notifier`). Cart is vendor-scoped; in-memory only.
- `product_repository.dart` — `vendorsProvider` and
  `vendorProductsProvider` (FutureProvider, FutureProvider.family).
- `order_repository.dart` — `studentOrdersProvider`,
  `orderByIdProvider` (FutureProvider, FutureProvider.family),
  `OrderNotifier` (places food orders and Around requests, clears cart,
  invalidates order list).

**Around mode** (`student/around/around_screen.dart`):
- Flow: pickup location → drop-off location → item description → flat
  fee estimate → mocked Confirm → tracking.
- 5 categories handled: errand, laundry, hostel, vendor_fetch,
  peer_courier. No printing/photocopy category.
- Produces a `type: 'around'` order record with a linked `around_requests`
  row.

**Orders screen** (`student/orders/orders_screen.dart`):
- 3 tabs: Cart (current in-memory cart), Preparing (active orders),
  Completed (completed + cancelled).
- Pull-to-refresh on active/completed tabs.
- Each order card shows short ID, vendor name, status badge, total, and
  a Track button for non-terminal orders.

**Wallet screen** (`student/wallet/wallet_screen.dart`):
- Shows live wallet balance; note that funding/withdrawals are Phase 3.

**Student Profile screen** (`student/profile/student_profile_screen.dart`):
- Real data from `currentProfileProvider`: avatar with initials,
  nickname, full name, matric, school, email, phone, tier, referral code
  (copyable), wallet balance. Logout button.

**Shared models** (`shared/models/`):
- `vendor.dart`, `product.dart` (+ `ProductOption`),
  `cart_item.dart` (+ `SelectedOption`), `order_item.dart`, `order.dart`
  (+ `OrderStatus` enum), `around_request.dart` (+ `AroundCategory` enum).

**Wallet provider** (`shared/services/wallet/wallet_providers.dart`):
- `walletBalanceProvider` — FutureProvider reading the signed-in
  student's `wallets.balance`.

**Supabase schema** (`supabase/schema.sql`) — Phase 2 block appended:
- Tables: `vendors`, `products`, `product_options`, `orders`,
  `order_items`, `around_requests`.
- `orders` has `source` ('uniflex'|'partner') and `type` ('food'|'around')
  columns; `status` constrained to the full state-machine set.
- RLS policies for all new tables (catalog is public-read for
  authenticated users; orders/items/around_requests are owner-only).
- Seed data: 4 vendors (Uniflex + 3 partners), 20 products across
  Uniflex categories (Protein Meals, Sides, Snacks, Drinks), 3 partner
  vendor menus, protein and extra options for all Uniflex protein meals.

### Changed

- `app_typography.dart` — full font replacement (see above).
- `pubspec.yaml` — added `google_fonts ^6.2.1`; removed `fonts:` entries
  for ClashDisplay and Switzer.
- `shared/widgets/inputs/app_text_field.dart` — added `maxLines`
  parameter (used by the Around description field).
- `student/student_shell.dart` — 4 tabs replacing the original 2.
- `student/home/student_home_screen.dart` — full real implementation
  replacing the Phase 0 placeholder.
- `student/profile/student_profile_screen.dart` — real profile replacing
  the placeholder.

### Notes

- **Manual SQL step required before testing**: run the Phase 2 block
  (everything after the "PHASE 2" separator) in the Supabase SQL editor,
  then run the seed inserts. The seed data uses fixed UUIDs for vendors
  and `ON CONFLICT DO NOTHING`, so re-running is safe.
- **Partner vendor source flag**: orders placed from any non-Uniflex
  vendor card are automatically flagged `source: 'partner'` — the
  `Vendor.isUniflex` getter (checks `is_featured == true && badge_label ==
  'Major'`) drives this; no manual override is needed.
- **Around: printing/photocopy intentionally absent** — the
  `AroundCategory` enum has exactly 5 values and the home screen's Around
  grid renders all of them. Adding a printing category here would require
  a separate file-upload + per-page pricing flow.
- Verified via `flutter analyze` (clean). On-device visual QA deferred
  to Phase 3 (consistent with Phase 1 policy).

## Design system update — visual handoff applied (2026-09-10)

Before starting Phase 2, the design system was rebuilt to match a visual
design handoff (10 screens + Foundations spec, produced in Claude
Design) rather than Phase 0's placeholder look. Applies to every role
equally — no screen-level one-offs.

### Changed

- **Colors** (`shared/theme/app_colors.dart`): matched exactly to the
  handoff's Foundations swatches — `matteBlack` #101312 (was #121212),
  `softGrey` #F5F6F5 (was #F3F4F6). Dark mode is now a deliberately
  separate palette rather than a filter over light mode: added
  `darkCanvas` #0C0F0E (page background), `darkCard` #141917 (surfaces),
  `darkHairline` (1px `rgba(255,255,255,.07)` borders — shadows do
  almost no work in the dark), `darkInkPrimary`/`darkInkSecondary` text
  colors, and `darkEmerald` #0A4433 (emerald's dark-mode job: full field
  → deep gradient accent). Orange stays full-chroma in both themes by
  design ("orange never dims").
- **Typography** (`shared/theme/app_typography.dart`): swapped Inter for
  the handoff's actual typefaces — **Clash Display** (600) for the
  wordmark only, **Switzer** for all other UI text (H1 28/600, H2 20/600,
  Body 15/400, Meta 13/500). Both are bundled as local font assets
  (`assets/fonts/`, declared in `pubspec.yaml`) since neither is on
  Google Fonts; the `google_fonts` dependency was removed.
- **Geometry** (`shared/theme/app_spacing.dart`): radius tokens renamed
  and matched to spec — `control` 14 (was `md` 16), `card` 22, `sheet` 32
  (was `lg` 24); added `screenGutter` (20, screen edge padding, distinct
  from the general spacing scale), `cardGap` (12), `controlHeight` (56,
  up from 52), `minTapTarget` (44).
- **App icon**: real logo (`assets/icon/app_icon.png`, background
  removed) now generates the actual Android/iOS launcher icons via
  `flutter_launcher_icons`, replacing Flutter's default icon. The
  in-app wordmark stays text-only per the handoff ("wordmark only, never
  the mark") — the app icon is the only place the U-mark itself appears.
- **Splash screen**: redrawn to match the handoff exactly — full-screen
  diagonal emerald→darkEmerald gradient, white wordmark bottom-left
  (was centered on a flat background).
- **Create Account / Complete Your Profile** (Steps One and Two): swapped
  the "Step X of 2" text label for a real progress bar + back button
  header (`shared/widgets/progress/onboarding_progress_bar.dart`),
  matched headline/subtext copy to the handoff, and laid out Complete
  Your Profile's Nickname + Date of Birth fields side-by-side as shown.

### Notes

- The handoff only covers 10 screens (Splash, Create Account, Complete
  Profile, Home ×3 modes, Meal Catalog, Cart & Checkout, Order Tracking,
  Wallet); screens outside that set (Login, this app's own
  onboarding/verify-phone flow beyond what's shown) were restyled to the
  same system rather than left unstyled, per the handoff's own note that
  it's a reference, not exhaustive coverage.
- The handoff's Home screens show a 4-tab bottom nav (Home, Orders,
  Wallet, Profile) — Phase 0/1 only ships Home + Profile tabs since
  Orders/Wallet don't exist as features yet. Phase 2 should add those
  tabs when it builds the ordering flow.
- Verified via `flutter analyze` (clean) and `flutter test` (14/14
  passing, including a test-file update for the new progress-bar
  header). Not verified: on-device visual QA — deferred to Phase 3
  alongside the rest of the emulator pass (see Phase 1 notes below).

## Phase 1 — Onboarding & auth (2026-09-10)

Real Supabase authentication, the full two-step Student onboarding flow,
and invite-only Rider/Admin login. No ordering, catalog, or other feature
screens — that starts in Phase 2. Payments are not integrated; the
Virtual Account Number created on signup is an explicit placeholder.

### Added

- **Splash screen** (`shared/router/splash_screen.dart`): full-screen
  branded background, centred wordmark with a fade + scale entrance
  animation, no buttons/text. Shown by `AuthGate` for a minimum stretch
  while session/profile data resolves.
- **AuthGate** (`shared/router/auth_gate.dart`): the app's real entry
  point (`app.dart`'s `home`, replacing `RoleRouter` directly). Watches
  the signed-in user's `profiles` row and shows exactly one of Splash,
  Login, "resume Step Two", or the correct role shell — see
  ARCHITECTURE.md for the full state diagram.
- **Step One — Create Account** (`shared/auth/screens/create_account_screen.dart`):
  email, password (8+ chars, 1+ digit, enforced client-side), phone
  number. Creates the Supabase Auth user, then triggers Termii phone OTP.
  Student self-signup only — no role picker anywhere in this flow.
- **Step 1b — Verify Phone** (`shared/auth/screens/verify_phone_screen.dart`):
  OTP entry + resend, verified against Termii. The account isn't
  considered created until this passes.
- **Step Two — Complete Your Profile** (`shared/auth/screens/complete_profile_screen.dart`):
  nickname (unique), full name, matric number (unique), school (only
  "Redeemer's University" offered, modelled as a plain field so more
  schools can be added without a schema change), date of birth, optional
  referral code (validated if entered). Submits to a single Postgres RPC
  that atomically creates the profile, a Wallet (balance 0, **mocked**
  Virtual Account Number, Bronze tier), the student's own referral code,
  and the referral relationship if a code was used.
- **Login screen** (`shared/auth/screens/login_screen.dart`): the one
  screen Students, Riders, and Admins all sign in from. Links to Create
  Account (Student only) — there is no path from here, or anywhere else
  in the public UI, to register as Rider or Admin.
- **Logout** (`shared/widgets/auth/logout_button.dart`): added to each
  role shell's Profile placeholder tab.
- `supabase/schema.sql`: `profiles`, `wallets`, `referrals` tables; RLS
  policies; `complete_student_onboarding()` and three
  availability/validation RPCs; instructions for seeding a test
  Rider/Admin account by hand (see "Notes").
- New dependencies: `supabase_flutter` (auth, database, session
  persistence) and `http` (direct REST calls to Termii — Supabase's
  built-in phone auth is not used, Termii is per spec).
- `shared/auth/validators.dart`: pure field-validation functions, unit
  tested in `test/auth_validators_test.dart`.

### Changed

- `RoleRouter` now takes `role` as a constructor argument instead of
  reading a provider itself — `AuthGate` resolves the role once, from the
  real `profiles.role` column, and hands it down.
- `AppTextField` gained `validator`/`autovalidateMode`/`maxLength` so
  screens can use it inside a `Form` instead of reaching for a raw
  `TextFormField`.
- `RolePlaceholderScreen` gained a `showLogout` flag (used by each
  shell's Profile tab) and no longer depends on the removed mock session
  provider.

### Removed

- `shared/services/auth/session_provider.dart` and
  `shared/router/mock_role_select_screen.dart` — the Phase 0 mock
  role-picker and its `StateProvider`. Superseded by `AuthGate` +
  `currentProfileProvider` (`shared/services/auth/auth_providers.dart`).

### Notes

- **Manual setup required before testing against a real backend** — this
  environment has only the Supabase project's anon key, not a
  service-role key or DB password, so `supabase/schema.sql` cannot be
  applied automatically. Run it once by hand in the Supabase SQL editor,
  and turn off Authentication → Providers → Email → "Confirm email" (this
  app verifies via Termii phone OTP, not an email link — leaving email
  confirmation on would strand a new account unable to sign in). The same
  file documents how to seed the one test Rider and one test Admin
  account the Definition of Done calls for.
- Verified via `flutter analyze` (clean) and `flutter test` (widget +
  unit tests, run against Supabase's in-memory local storage so they
  don't touch the real project or send real OTPs). Not verified: an
  actual signup run against the live Supabase/Termii project on a device
  or emulator — this development environment has no way to run the app
  on one; the SQL setup above and a manual pass on your end are needed to
  close that out before this phase is fully signed off.
- Termii's OTP send uses the shared generic sender ID (`"Termii"`); swap
  for a registered sender ID once the project has one.

## Phase 0 — Project scaffold & design system (2026-09-08)

Initial scaffold. No real feature screens, no real backend integration —
everything in this phase runs on mocked/local data.

### Added

- Flutter project initialized (`flutter create`), targeting Android and
  iOS, Dart/Flutter on the stable channel.
- Folder structure separating `student/`, `rider/`, `admin/`, and
  `shared/` (theme, reusable widgets, core services, config, router) —
  see [ARCHITECTURE.md](ARCHITECTURE.md).
- State management set up with Riverpod (`flutter_riverpod`),
  `ProviderScope` wrapping the app from `main.dart`.
- Design system (`lib/shared/theme/`): brand colours (Emerald `#10B981`,
  Orange `#F97316`, Matte Black, Pure White, Soft Grey), Inter typography
  scale, spacing/radius constants, and full light + dark `ThemeData`.
- Reusable component library (`lib/shared/widgets/`): `PrimaryButton`,
  `SecondaryButton`, `AppCard`, `AppTextField`, `UniflexAppBar`,
  `AppBottomNavShell`, and the `UniflexWordmark` text logo (no image
  asset yet, by design).
- Role router (`lib/shared/router/role_router.dart`): reads a `UserRole`
  (`student` / `rider` / `admin`) from `currentUserRoleProvider` and
  routes to one of three fully separate shells — `StudentShell`,
  `RiderShell`, `AdminShell` — each with its own placeholder home +
  profile screens confirming which role loaded.
- `MockRoleSelectScreen`: a Phase 0-only dev placeholder standing in for
  real sign-in, so the role router can be exercised end to end. Also
  hosts a light/dark mode toggle for manually verifying both themes.
  Replaced by real auth in Phase 1.
- `.env.example` at the project root listing every planned service key
  (Supabase, Paystack, Termii, Firebase, Google Maps) as placeholders
  only. Config loading via `flutter_dotenv`, wrapped in
  `lib/shared/config/env_config.dart`.
- `.gitignore` updated for a Flutter project, explicitly excluding `.env`
  (while `.env.example` stays tracked).
- Project documentation: this file, [README.md](README.md), and
  [ARCHITECTURE.md](ARCHITECTURE.md).
- Widget test suite covering the role router: mock picker renders, and
  each of the three role choices routes to its own shell.

### Notes

- No Supabase, Paystack, Firebase, or Google Maps integration yet — those
  start in their respective later phases.
- No onboarding or auth UI yet — `MockRoleSelectScreen` is a temporary
  stand-in, replaced in Phase 1.
- Verified end-to-end on a real Android emulator (Pixel 7 / API 34):
  clean `flutter analyze`, all 4 widget tests passing, and manual
  verification that the role router correctly loads each of the three
  shells with no cross-contamination, plus both light and dark theme
  modes rendering correctly against the exact brand palette.
- iOS requires Xcode/macOS to build and run — not available in this
  development environment (Windows); iOS code paths follow Flutter's
  standard platform-adaptive conventions (Cupertino page transitions,
  safe areas) but have not been run on a physical/simulated iOS device
  in this phase.
- Along the way, the Android platform files were migrated from the
  Groovy-based Gradle config generated by the initial (outdated) local
  Flutter SDK install to the Kotlin DSL config matching the
  current Flutter stable release (Flutter upgraded 3.19.6 → 3.47.2;
  Gradle 7.6.3 → 9.3.1; AGP 7.3.0 → 9.1.0; Kotlin 1.7.10 → 2.4.0). This
  is a one-time environment fix, not a deliberate design choice — later
  phases should just use whatever Gradle/AGP/Kotlin versions ship with
  the Flutter SDK in use at the time.
