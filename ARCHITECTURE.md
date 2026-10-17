# Architecture

This document explains how the Uniflex codebase is organized, the role
router pattern, the state management approach, and where future phases'
work should live. Keep this file updated as the project grows — it's the
map for anyone (including future-you) opening this repo cold.

## Big picture

Uniflex is **one Flutter app**, not three. A single codebase compiles to
a single binary that serves Student, Rider, and Admin users. There is no
separate web dashboard or separate app per role — everything routes
through role-based navigation inside this one app.

## Folder structure

```
lib/
  main.dart                  # Entry point: loads env, wraps app in ProviderScope
  app.dart                   # Root MaterialApp — theme + RoleRouter, nothing role-specific

  shared/                    # Used by ALL three roles. Nothing here should
                              # know which role is using it.
    theme/                   # Design system: colours, typography, spacing, ThemeData
    widgets/                 # Reusable components: buttons, cards, inputs, app bar,
                              # bottom nav shell, wordmark, dev placeholder screen,
                              # auth/logout_button.dart
    models/                  # Profile, Vendor, Product, Order, OrderItem, CartItem,
                              # AroundRequest, WalletTransaction, SavingPlan — shared data
    services/
      supabase/              # The shared SupabaseClient provider
      auth/                  # UserRole enum, AuthService, auth/profile Riverpod providers
      otp/                   # TermiiOtpService — phone OTP send/verify
      profile/               # ProfileService — onboarding RPC calls, uniqueness checks
      wallet/                # WalletService + walletBalanceProvider, walletInfoProvider,
                              # walletTransactionsProvider, walletServiceProvider
      saving_plan/           # SavingPlanService + activeSavingPlanProvider,
                              # savingPlanNotifierProvider
    auth/                    # Student sign-up + shared login screens (see "Auth" below)
      screens/
      validators.dart        # Pure field validation, no BuildContext
    config/                  # Env var loading (EnvConfig / flutter_dotenv)
    router/                  # AuthGate, SplashScreen, RoleRouter (see "Auth" below)

  student/                   # Student-only screens and navigation. Root: student_shell.dart
    home/                    # Home screen (Food Delivery + Around mode toggle, vendor list)
    ordering/                # Catalog (independent items, no combo-builder), Cart, Checkout
                              # (PIN gate + pack decision), PackAllocationScreen, Confirmation
                              # + cart_provider, product_repository, order_repository (realtime)
    around/                  # AroundScreen (reads categories from around_categories table)
                              # + around_category_providers.dart (active list, rider availability)
    orders/                  # OrdersScreen (Cart / Preparing / Completed tabs)
    tracking/                # OrderTrackingScreen (status timeline, refreshable)
    wallet/                  # WalletScreen, PaystackCheckoutPage, SavingPlanScreen
    profile/                 # StudentProfileScreen (rebuilt Phase 6) + sub-screens:
                              # MembershipCardScreen, ReferralScreen, GiftScreen,
                              # BadgesScreen, ScheduledOrdersStudentScreen,
                              # PreferencesScreen
    group_checkout/          # CreateGroupScreen (open group session) +
                              # GroupCheckoutScreen / JoinGroupScreen (Phase 6)
    services/                # StudentService + student Riverpod providers (Phase 6)

  rider/                     # Rider-only screens and navigation. Root: rider_shell.dart
    services/                # RiderService + rider Riverpod providers
    dashboard/               # RiderDashboardScreen — online/offline toggle + daily stats
    pool/                    # JobPoolScreen — live job pool (Supabase Realtime)
                             # pool_order.dart — enriched pool model
    delivery/                # ActiveDeliveryScreen — pickup/delivery workflow + PIN gate
                             # delivery_record.dart — history record model
    history/                 # DeliveryHistoryScreen — past deliveries list
    profile/                 # RiderProfileScreen — real profile + logout
  admin/                     # Admin-only screens and navigation. Root: admin_shell.dart
                              # (Admin also covers Kitchen Staff duties — no separate login)
    services/                # AdminService + admin Riverpod providers
    dashboard/               # AdminDashboardScreen — real-time stats
    kitchen/                 # KitchenQueueScreen — live queue via Supabase Realtime
                              # (Phase 6: BULK badge + campus/hostel delivery labels;
                              #  post-testing fixes: Ready split by pickup/delivery,
                              #  Transfer to Rider action)
    scheduled/               # AdminScheduledOrdersScreen — Phase 6 pre-order countdown
    menu/                    # MenuManagementScreen, ProductFormScreen — Uniflex catalog CRUD
                              # (+ Requires Pack toggle, Uniflex pack price editor)
    manage/                  # ManageHubScreen — single "Manage" nav entry branching into
                              # Vendors / Riders / Around Categories (post-testing fixes)
    vendors/                 # VendorManagementScreen, VendorFormScreen,
                              # VendorProductsScreen — partner vendor CRUD (+ pack price)
    riders/                  # RiderManagementScreen — invite/remove/reactivate riders
                              # (post-testing fixes)
    around_categories/       # AroundCategoriesScreen, AroundCategoryFormScreen — CRUD for
                              # the around_categories table (post-testing fixes)
    profile/                 # AdminProfileScreen — name, email, tier + logout

  shared/
    models/                  # Profile, Vendor, Product, Order, OrderItem, CartItem,
                              # AroundCategory, WalletTransaction, SavingPlan,
                              # Gift, Achievement (Phase 6)
    services/
      notifications/         # NotificationService — FCM init, token storage, local
                              # notification display (Phase 6); showLocal() is also used
                              # directly by the order-status-change listener (Section 12)
    widgets/
      async/                 # RetrySection — reusable "failed to load, tap to retry"
                              # control used by every realtime/live data screen
      pin/                   # showEnterPinSheet / showSetPinSheet — transaction PIN UI

supabase/
  schema.sql                 # All DDL and seed data (run by hand in Supabase SQL editor)
  functions/
    verify-paystack-payment/ # Edge Function: server-side Paystack verification + credit
    create-virtual-account/  # Edge Function: Paystack DVA issuance with graceful fallback
    send-notification/       # Edge Function: FCM push via legacy HTTP API (Phase 6)
    birthday-rewards/        # Edge Function: invokes birthday reward RPC (Phase 6)
    admin-create-rider/      # Edge Function: Supabase Admin API rider account creation
                              # (post-testing fixes — needs the service-role key, hence a
                              #  function rather than a client-side RPC)
```

**The rule that matters most:** `student/`, `rider/`, and `admin/` must
never import from each other. Each is a self-contained navigation stack.
The only things they're allowed to share are `shared/theme`,
`shared/widgets`, `shared/services`, and `shared/config`. If a change
needs a student screen to know about a rider screen, that's a sign the
feature belongs in `shared/` instead, or that the role boundary is being
violated — stop and reconsider rather than adding the import.

Within a role folder, group by feature, not by widget type — e.g.
`student/ordering/`, `student/tracking/`, not `student/screens/` +
`student/widgets/` as siblings of everything else. `home/` and `profile/`
in Phase 0 are the first two feature folders for each role; later phases
add more alongside them (e.g. `student/ordering/`, `student/cart/`,
`rider/jobs/`, `admin/orders/`, `admin/kitchen/`).

## Auth (Phase 1)

Real backend as of this phase: **Supabase** for the account + database,
**Termii** (not Supabase's built-in phone auth) for OTP delivery/verify.
Schema, RLS policies, and the onboarding RPC live in
`supabase/schema.sql` — that file is not applied automatically (this repo
has no service-role/DB credentials wired into any tooling), it's run by
hand once in the Supabase SQL editor. It also documents how to seed a
test Rider/Admin account, since there is no in-app path to create one.

### AuthGate — the real entry point

`lib/shared/router/auth_gate.dart` is what `app.dart` actually shows
(`home: const AuthGate()`); `RoleRouter` is one of several things it can
display, not the entry point itself anymore.

`AuthGate` watches `currentProfileProvider`
(`lib/shared/services/auth/auth_providers.dart`), a `FutureProvider<Profile?>`
that re-resolves any time Supabase's auth state changes (sign-in,
sign-out, token refresh) and, whenever there's a session, fetches that
user's `profiles` row. Based on what it sees:

```
AuthGate
 ├─ still resolving / < 900ms since launch → SplashScreen
 ├─ no session, or profile fetch failed    → LoginScreen
 ├─ session, profiles.onboarding_complete
 │  is false (Step One done, Step Two not) → CompleteProfileScreen (resumes Step Two)
 └─ session, onboarding_complete is true   → RoleRouter(role: profile.role)
```

`RoleRouter` (`lib/shared/router/role_router.dart`) now takes `role` as a
plain constructor argument instead of reading a provider itself — the
"which of the three roles" decision is made once, by `AuthGate`, from the
real `profiles.role` column. Its job is unchanged from Phase 0 otherwise:
return **exactly one** of `StudentShell`, `RiderShell`, or `AdminShell`,
each a fully separate widget tree/navigation stack built from the shared
`AppBottomNavShell`.

### Why nothing calls `Navigator.push` after login/signup/logout

Every screen under `lib/shared/auth/screens/` only ever *mutates auth
state* — sign in, sign up, verify OTP, complete onboarding, sign out.
None of them navigate to a shell or back to Login on success. Because
`AuthGate` watches `currentProfileProvider` and is what's actually
mounted at the root, a change to that provider's value is enough on its
own to swap what's on screen. Two consequences:

- After `CompleteProfileScreen` submits successfully, it calls
  `ref.invalidate(currentProfileProvider)` (the RPC changed the profile
  row directly in Postgres, which doesn't fire a Supabase auth event) and
  then does nothing else — `AuthGate` picks up
  `onboarding_complete == true` and swaps to `RoleRouter` on its own.
- `LogoutButton` (`lib/shared/widgets/auth/logout_button.dart`, used by
  each shell's Profile tab placeholder) calls `AuthService.signOut()` and
  nothing else — the resulting auth-state-change event flows through
  `currentProfileProvider` back to `AuthGate`, which swaps to
  `LoginScreen`.

If you add a new auth-adjacent screen, keep this pattern: mutate state,
don't navigate to where the state change should already take you.

### Sign-up flow (Student self-signup only)

There is no role picker anywhere in the auth UI — `CreateAccountScreen`
only ever produces a Student account. Rider/Admin accounts are
invite-only, seeded by hand directly in Supabase (see
`supabase/schema.sql`); `LoginScreen` is the one screen all three roles
sign in from, and it has no path to a signup screen for anything but
Student.

1. **Step One** (`create_account_screen.dart`) — email, password, phone.
   Creates the Supabase Auth user, writes a bare `profiles` stub row
   (role defaults to `student`, `onboarding_complete` defaults to
   `false` at the DB level), then calls `TermiiOtpService.sendOtp`.
2. **Step 1b** (`verify_phone_screen.dart`) — the OTP code from Termii.
   On a verified code, records `phone` + `phone_verified_at` on the stub
   row. The account is not considered "created" until this step passes.
3. **Step Two** (`complete_profile_screen.dart`) — nickname, full name,
   matric number, school (a plain string field, not an enum, so more
   schools can be added later with no schema change — only
   "Redeemer's University" is offered today), date of birth, optional
   referral code. Submits to the `complete_student_onboarding()` Postgres
   function, which in one transaction: validates the referral code (if
   any) exists, generates this student's own shareable referral code,
   writes the completed `profiles` row, creates their `wallets` row
   (balance 0, **mocked/placeholder** virtual account number — see the
   stub comment on `public.wallets` in `supabase/schema.sql`, real Paystack
   Dedicated Virtual Accounts are a later phase), sets tier to `Bronze`,
   and records the referral relationship. Either all of that lands, or
   none of it does.

Nickname/matric-number uniqueness and referral-code existence are checked
through dedicated RPCs (`is_nickname_available`, `is_matric_number_available`,
`is_referral_code_valid`) rather than raw `profiles` selects, so the
`profiles` table itself is never directly readable/insertable by other
users — see the RLS policies in `supabase/schema.sql`.

### Session persistence

`Supabase.initialize()` runs in `main.dart` before `runApp` and restores
any persisted session synchronously off local storage — by the time
`AuthGate` builds, `AuthService.currentSession` already reflects it (or
is `null`). Nothing in this app stores credentials itself; the session
token lifecycle is entirely Supabase Auth's.

## State management: Riverpod

The whole app uses [flutter_riverpod](https://riverpod.dev). Conventions
so far:

- `StateProvider` for simple mutable state (`themeModeProvider`).
- `StreamProvider` for things that emit over time (`authStateChangesProvider`
  wraps Supabase's `onAuthStateChange`).
- `FutureProvider` for one-shot async reads that should re-run when an
  upstream provider changes (`currentProfileProvider` re-fetches the
  signed-in user's `profiles` row whenever `authStateChangesProvider`
  fires, or when a screen calls `ref.invalidate(currentProfileProvider)`
  after writing to that row directly, e.g. `CompleteProfileScreen`).
- Widgets that read/write providers extend `ConsumerWidget` (or use
  `Consumer`/`ConsumerStatefulWidget` where local state is also needed).
- `ProviderScope` wraps the whole app once, in `main.dart`.

Phase 2 additions follow these conventions:

- `CartNotifier` (`student/ordering/cart_provider.dart`) — `Notifier<CartState>`.
  Cart is vendor-scoped: adding items from a different vendor requires
  clearing first (the UI asks the user). As of Round 2, the cart is
  **persisted to SharedPreferences** — every mutation serializes the full
  `CartState` (items + vendor) to JSON; `build()` restores it on startup.
  Corrupted data is silently discarded (fresh cart).
- `OrderNotifier` (`student/ordering/order_repository.dart`) — `Notifier<OrderPlacementState>`.
  Wraps the two-step Supabase write (insert `orders` row, then insert
  `order_items` or `around_requests`). After a successful placement it
  clears the cart and invalidates `studentOrdersProvider`.
- `vendorProductsProvider` uses `FutureProvider.family` (a one-shot
  catalog read is fine — the menu doesn't need to be live). `orderByIdProvider`
  and `studentOrdersProvider` are **`StreamProvider`/`StreamProvider.family`**
  as of the post-testing fixes pass — see "Order status sync" below for why
  this mattered.
- Providers are colocated with the feature that owns them (e.g.
  `student/ordering/`). Only promote to `shared/services/` if more than
  one role genuinely needs the provider (e.g. `walletBalanceProvider` is
  shared because it could be shown in any role's UI).

**Order status state machine** (`shared/models/order.dart` — `OrderStatus`):

```
placed → preparing → ready ─────────────────→ out_for_delivery → completed
       (pickup:)  ↘ ready_for_pickup → completed
                  ↘ cancelled (from any non-terminal state)
```

`ready` is delivery-only and `ready_for_pickup` is pickup-only — Kitchen's
"Mark Ready" action branches on `delivery_type` to set the right one (see
`kitchen_queue_screen.dart`). The two used to be conflated (Kitchen always
set `ready`), which is why a ready pickup order's tracking timeline used to
show nothing as done — its steps list only contains `ready_for_pickup`.

## Order status sync — single source of truth (post-testing fixes)

Audited end-to-end after testing found status changes not reliably
reaching every shell. The root cause: `studentOrdersProvider` and
`orderByIdProvider` were one-shot `FutureProvider`s — nothing re-fetched
them after Kitchen or a rider changed a status until the student manually
refreshed. Both are now `StreamProvider`s backed by
`supabase.from('orders').stream(primaryKey: ['id'])`, the same pattern
`kitchenOrdersProvider` and `jobPoolProvider` already used, so a change to
one order row now reaches Kitchen Queue, the rider pool/active-delivery
screen, and the student's Orders tab/tracking screen from the same
underlying Realtime event — one write, three shells update.

Two more gaps fixed in the same pass:

- **`update_order_status` had no transition guards.** Any admin call could
  set a delivery order (food delivery or Around) straight to
  `out_for_delivery`/`completed`, bypassing the rider PIN gate entirely.
  It's now hardened so those two statuses are only reachable through the
  existing rider workflow (`accept_order` → `confirm_pickup` →
  `verify_delivery`, which is what actually enforces "not completed until
  the PIN is confirmed") — this is enforced in the RPC itself, not just by
  which buttons the Kitchen Queue UI happens to show.
- **No explicit "Transfer to Rider" action existed.** A Uniflex delivery
  order becoming pool-eligible used to be an implicit side effect of
  `status = 'ready'`. There is now a `transferred_to_rider_at` column and a
  `transfer_order_to_rider()` RPC (admin-only) — a Ready delivery order
  only enters the rider pool once Admin/Kitchen explicitly taps "Transfer
  to Rider", which also attaches the student's delivery info to the job.
  The rider pool RLS policy and `accept_order()`'s eligibility check both
  require this column to be set.

`StudentShell` also watches `studentOrdersProvider` with `ref.listen` and
fires a local notification (`NotificationService.showLocal`) on
`preparing → ready(_for_pickup) → picked_up → out_for_delivery →
completed` transitions, using the same realtime stream — this only fires
while the app is open; background push still needs FCM fully configured
(a pre-existing gap from Phase 6, not closed by this pass).

## Design system

Matched to a visual design handoff (produced in Claude Design) rather
than invented — see the "Design system update" entry in
[CHANGELOG.md](CHANGELOG.md) for the full rationale behind each token.

`lib/shared/theme/`:

- `app_colors.dart` — the only place brand hex values should be defined.
  Light mode and dark mode are separate palettes, not one palette with a
  dark filter — dark mode has its own canvas/card/ink/hairline tokens.
- `app_typography.dart` — Clash Display (wordmark only) + Switzer
  (everything else), bundled as local font assets under `assets/fonts/`
  (declared in `pubspec.yaml`'s `fonts:` key) — not Google Fonts.
- `app_spacing.dart` — `AppSpacing` (general spacing scale, plus
  `screenGutter`/`cardGap`/`controlHeight`/`minTapTarget`) and
  `AppRadius` (`control`/`card`/`sheet`/`pill`).
- `app_theme.dart` — builds the light and dark `ThemeData` from the
  above. Both modes are first-class; `themeModeProvider` defaults to
  `ThemeMode.system`.

`lib/shared/widgets/` is the component library every screen should build
from: `buttons/` (`PrimaryButton` for CTAs, `SecondaryButton` for
secondary actions), `cards/app_card.dart`, `inputs/app_text_field.dart`,
`app_bar/uniflex_app_bar.dart`, `navigation/app_bottom_nav_shell.dart`,
`progress/onboarding_progress_bar.dart` (the back-button + progress-bar
header used by both onboarding steps), and `wordmark/uniflex_wordmark.dart`
(the text-only "Uniflex" wordmark — per the handoff, the wordmark never
uses the logo mark; the mark itself only appears as the app icon,
`assets/icon/app_icon.png`, generated via `flutter_launcher_icons`).

Don't hardcode colours, fonts, or one-off paddings in screen code — pull
from these files so a design change only has to happen in one place.

## Config / environment variables

`lib/shared/config/env_config.dart` wraps `flutter_dotenv`. `main.dart`
calls `EnvConfig.load()` before `runApp`. Add new keys to **both**
`.env.example` (placeholder, committed) and a getter in `EnvConfig` — screens
and services should call `EnvConfig.xxx`, never read `dotenv.env[...]`
directly, so there's one place that knows every key the app depends on.

## Where future phases' work goes

| Phase (indicative)              | Lives in |
|----------------------------------|----------|
| Onboarding & Auth ✅ (Phase 1)   | `shared/auth/`, `shared/router/auth_gate.dart` + `splash_screen.dart`, `shared/services/{auth,otp,profile,supabase}/` |
| Student ordering flow ✅ (Phase 2)| `student/ordering/`, `student/around/`, `student/orders/`, `student/tracking/`, `student/wallet/`, `shared/models/{vendor,product,order,order_item,cart_item,around_request}.dart`, `shared/services/wallet/` |
| Wallet & payments ✅ (Phase 3)   | `student/wallet/`, `shared/services/{wallet,saving_plan}/`, `shared/models/{wallet_transaction,saving_plan}.dart`, `supabase/functions/{verify-paystack-payment,create-virtual-account}/` |
| Admin & kitchen ✅ (Phase 4)     | `admin/` (all subfolders), `shared/services/` (wallet already shared), schema.sql Phase 4 block |
| Rider delivery flow              | `rider/jobs/`, `rider/navigation/`, `rider/earnings/` |
| Push notifications (Firebase)    | `shared/services/notifications/` |
| Maps / live tracking             | `shared/services/maps/`, consumed from `student/tracking/` and `rider/navigation/` |
| Post-testing fixes ✅ (first Android QA pass) | `admin/manage/`, `admin/riders/`, `admin/around_categories/`, `student/ordering/pack_allocation_screen.dart`, `shared/widgets/{async,pin}/`, `shared/models/around_category.dart`, `supabase/functions/admin-create-rider/`, schema.sql "POST-TESTING FIXES & CHANGES" block |
| Round 2 post-testing fixes ✅ (second QA pass) | `admin/analytics/`, `admin/admin_shell.dart` (4 tabs), `admin/manage/manage_hub_screen.dart` (expanded), `student/ordering/cart_provider.dart` (persistence), category normalization in `catalog_screen.dart`/`menu_management_screen.dart`/`product_form_screen.dart` |

Update this table as phases land so it stays a reliable map of the repo.

## Admin permission tiers (Phase 4)

All admin accounts share the same `role = 'admin'` in `profiles`. The
`admin_tier` column (nullable) subdivides admin accounts:

```
admin_tier = NULL or 'super_admin'  →  AdminShell: 4 tabs (Dashboard, Orders, Manage, Analytics)
admin_tier = 'kitchen_staff'        →  AdminShell: Orders only
```

The tier check happens once, in `AdminShell.build()`, by reading
`currentProfileProvider.valueOrNull?.isKitchenStaff`. There is no
client-side gate — a kitchen_staff account simply never sees the
Dashboard, Menu, or Manage tabs, so there are no buttons to press that
would reach those screens. Server-side, the admin RLS policies (which use
`is_admin()`, not a tier check) apply equally to both tiers; restricting
the kitchen_staff *further* at the DB level (e.g. only allowing ORDER
reads/writes) is a hardening step deferred to a later phase.

**"Manage" hub (post-testing fixes):** the `super_admin` bottom nav is
now **Dashboard / Orders / Manage / Analytics** (4 tabs, down from 6 in
Round 1). Menu Management, Scheduled Orders, and Profile & Settings moved
into `ManageHubScreen` entries alongside Vendors, Riders, Around
Categories, Referral Codes, and Advertisements. Kitchen staff see only 1
tab (Orders). New admin capabilities should add a hub entry, not a new
bottom-nav tab.

Seeding a kitchen_staff account:
1. Create the Supabase Auth user by hand (Dashboard → Authentication →
   Users → Add user).
2. Table editor → `profiles` → Insert row:
   - `role = 'admin'`
   - `admin_tier = 'kitchen_staff'`
   - `email`, `full_name`, `onboarding_complete = true`

## Kitchen Queue — Supabase Realtime wiring (Phase 4)

`KitchenQueueScreen` watches `kitchenOrdersProvider`, a `StreamProvider`
backed by `AdminService.streamKitchenOrders()`. That method uses:

```dart
supabase.from('orders')
    .stream(primaryKey: ['id'])
    .eq('source', 'uniflex')
    .order('created_at', ascending: false)
```

The `.stream()` call:
1. Fetches the initial result set.
2. Subscribes to Postgres NOTIFY events via the `supabase_realtime`
   publication (added in the Phase 4 schema block).
3. Re-emits the full filtered list whenever any `orders` row changes.

On each emission, the service batch-fetches `order_items` for all active
orders in one `inFilter` query, yielding a `List<KitchenOrder>` (order
+ items). The screen filters to `type = 'food'` and status in
`placed | preparing | ready | ready_for_pickup | out_for_delivery`
client-side and groups them into five visual sections: Scheduled,
Preparing, Ready for Pickup, Ready for Delivery, Out for Delivery.
Round 2 added `out_for_delivery` to the filter (orders used to disappear
from admin view once dispatched) and shows rider delivery stage
(accepted/picked_up) on dispatched order cards.

Status transitions go through the `update_order_status` SECURITY DEFINER
RPC rather than a direct UPDATE, so the server validates the caller's
admin role, the status string, **and** (post-testing fixes) the
transition itself — see "Order status sync" above. The primary action
button's label and target status both depend on the order's current
status and `delivery_type`:

| Current status | delivery_type | Button | RPC call |
|---|---|---|---|
| `placed` | any | Start Preparing | `update_order_status(..., 'preparing')` |
| `preparing` | pickup | Mark Ready for Pickup | `update_order_status(..., 'ready_for_pickup')` |
| `preparing` | delivery/campus/hostel | Mark Ready | `update_order_status(..., 'ready')` |
| `ready_for_pickup` | pickup | Mark Completed | `update_order_status(..., 'completed')` |
| `ready` | delivery/campus/hostel | Transfer to Rider | `transfer_order_to_rider(...)` |

The Realtime subscription then delivers each change back to all connected
admin sessions automatically — no `ref.invalidate` is needed after a
status update.

## Rider job pool — pull model (Phase 5)

Riders see the pool of available orders on `JobPoolScreen`, which watches
`jobPoolProvider` (a `StreamProvider` backed by
`RiderService.streamJobPool()`). The stream:

1. Subscribes to `supabase.from('orders').stream(primaryKey: ['id'])`.
2. Filters client-side to pool-eligible rows (`rider_id IS NULL` + correct
   source/status/delivery_type combination — for `source = 'uniflex'`
   delivery orders this now also requires `transferred_to_rider_at is not
   null`, set only by the admin "Transfer to Rider" action above; see
   "Order status sync").
3. Batch-fetches vendor rows (partner food) and `around_requests` rows
   (around orders) to build `PoolOrder` objects with pre-resolved pickup
   info.

When a rider taps **Accept**, `RiderService.acceptOrder()` calls the
`accept_order` SECURITY DEFINER RPC. The RPC:
- Locks the row with `FOR UPDATE NOWAIT` to prevent concurrent accepts.
- Re-validates eligibility (in case the pool changed between the tap and
  the DB write) — including the same `transferred_to_rider_at` check.
- Sets `rider_id = auth.uid()`, `delivery_stage = 'accepted'`,
  `status = 'out_for_delivery'`.

The row immediately disappears from the pool for all other riders (RLS
`rider_id IS NULL` filter) via the Realtime subscription. Once accepted,
the student can see the rider's name/phone via `get_rider_info()` (mirrors
`get_customer_info()`, which already gave the rider the student's
contact) — shown on `OrderTrackingScreen`.

## Delivery workflow and PIN gate (Phase 5)

Every delivery-type order (food delivery + around) receives a unique
4-char alphanumeric PIN, auto-generated by the `_generate_delivery_pin`
`BEFORE INSERT` trigger. The PIN:
- Is stored in `orders.delivery_pin` from the moment the order is placed.
- Is shown to the student on `OrderConfirmationScreen` and
  `OrderTrackingScreen` (with a tap-to-copy affordance).
- Is never transmitted to the rider via the app UI — the rider must ask
  the customer to show it at the door.

Delivery workflow stages:
```
accepted  →  [Confirm Pickup]  →  picked_up  →  [Enter PIN]  →  completed
```

`confirm_pickup` / `verify_delivery` are SECURITY DEFINER RPCs:
- They validate `rider_id = auth.uid()` and the expected `delivery_stage`
  server-side — neither the stage nor completion can be forced by a
  client-side state mutation.
- `verify_delivery` compares `upper(p_pin)` against `upper(delivery_pin)`;
  any mismatch raises an exception that the client surfaces as "Incorrect
  PIN".
- On success, `verify_delivery` writes a `delivery_records` row (for
  history) and sets `status = 'completed'`.

## Navigation and location (Phase 5)

The active delivery screen uses `url_launcher` to open Google Maps with
`mode: LaunchMode.externalApplication` — no embedded map widget, no
`google_maps_flutter` API key in `AndroidManifest.xml`. The deep-link
URL is:
```
https://maps.google.com/?saddr=<lat>,<lng>&daddr=<encoded_address>&dirflg=d
```

`geolocator` is called **once per "Navigate" tap** to get the current
position as the `saddr` origin. If the permission is denied or the fetch
times out, the URL falls back to a destination-only query. Location is
never polled in the background — `geolocator` has no background service
configured, and calls happen only within the lifecycle of
`ActiveDeliveryScreen`.

## Transaction PIN (post-testing fixes)

A 4-digit PIN, separate from the account password, gates every order
payment (food checkout and Around). Storage follows the same pattern as
`wallet_transactions`: a dedicated `transaction_pins` table with **no**
client SELECT/INSERT/UPDATE policy at all — every read/write goes through
a SECURITY DEFINER RPC keyed off `auth.uid()`:

- `set_transaction_pin(p_pin)` — hashes with `pgcrypto`'s `crypt()` +
  `gen_salt('bf')`, upserts.
- `has_transaction_pin()` — existence check only, never returns the hash.
- `verify_transaction_pin(p_pin)` — compares a fresh `crypt()` against the
  stored hash.

New students set a PIN as part of Step Two onboarding
(`CompleteProfileScreen`). Existing accounts have none; `CheckoutScreen`
and `AroundScreen` both call `has_transaction_pin()` before confirming and
show `showSetPinSheet` first if it's false, then always
`showEnterPinSheet`. The PIN itself is enforced **server-side**:
`place_food_order_with_payment` and `place_around_with_payment` both take
a `p_pin` param and raise `INVALID_PIN` via `verify_transaction_pin`
before touching the wallet — a client bug can't skip the check.

## Pack system (post-testing fixes, Section 11)

Some food items need to be packaged into a container to be handed over;
others (drinks) never do. `products.requires_pack` (admin toggle, per
item) marks which; `vendors.pack_price` (admin field, per vendor) sets
what one pack costs — Uniflex and each partner vendor price their own
packs independently, since the Uniflex vendor row is excluded from
`VendorManagementScreen`, its pack price is edited from
`MenuManagementScreen`'s app bar instead.

At checkout, if the cart contains any `requires_pack` items,
`CheckoutScreen` shows a "Packing" section asking "Will you be using
packs?" before the total is finalized. "Yes" pushes
`PackAllocationScreen`, which lets the student build one pack at a time —
a single pack can mix different pack-requiring items together (e.g. 6×
Jollof Rice + 2× Chicken in one pack) — repeating "Add Pack" until every
pack-requiring unit is allocated, then "Done". Each pack adds the
vendor's `pack_price` to the order total; non-pack items (drinks) are
just added normally, no pack step involved.

Pack contents are recorded server-side in a new `order_packs` table (one
row per pack, `items` jsonb array of `{product_id, product_name,
quantity}`), written by `place_food_order_with_payment` in the same
transaction as the order — Kitchen/Admin can see exactly what to put in
each pack, not just a total count. `orders.pack_count`/`pack_fee` mirror
the totals for quick display without joining `order_packs`.

## Menu categories: 3 fixed display categories (Round 2)

The DB `products.category` column stores whatever string the admin typed
(legacy values include "Protein Meals", "Main", "Sides", "Snacks",
"Grills", "Smoothies", "Juices", etc.). As of Round 2, both the student
catalog and admin menu management normalize these into exactly **3 fixed
display categories**: **Meals, Drinks, Others**.

The mapping (`_normalizeCategory()`, defined in `catalog_screen.dart`,
`menu_management_screen.dart`, and `product_form_screen.dart`):

```
Protein Meals / Main / Sides / Snacks / Grills  →  Meals
Smoothies / Juices                               →  Drinks
Everything else                                  →  Others
```

`ProductFormScreen`'s category dropdown now only offers the 3 fixed
values, so new products always get a clean category. Legacy products
display under the right group without a data migration.

## Catalog: independent items, no combo-builder (post-testing fixes, Section 11)

Phase 2's catalog modeled a "meal" as one product (e.g. "Jollof Rice +
Protein") with `product_options` bolted on for protein (radio, required)
and extras (checkboxes) — `MealCustomizationScreen` walked
quantity → protein → extras → drink as one guided flow per tap. That
screen and pattern are removed, not kept alongside the new one:

- Every product is independently orderable. Former protein choices
  (Chicken, Beef, Fish, Turkey, Egg) are now standalone products under a
  "Proteins" category, each with its own price and quantity.
- `CatalogScreen`'s `_ProductTile` adds directly to the cart via an
  inline "+" (or "− qty +" once added) — no navigation, no per-item
  wizard screen. Drinks are just products in a "Drinks" category, added
  the same way.
- `product_options`/`ProductOption` stay in the schema (harmless,
  unread by the new UI) rather than being dropped.

## Cart visibility (post-testing fixes, Section 13)

The cart (`cartProvider`) is a single app-wide `Notifier`, so every entry
point reads the same state with no extra wiring:

- `StudentHomeScreen` shows a persistent, badge-carrying FAB
  (`_HomeCartButton`) whenever the cart is non-empty, going straight to
  `CartScreen`.
- `CatalogScreen` keeps its own "View Cart (N)" FAB.
- The Orders tab's Cart view has a working "Proceed to Checkout" button
  (it used to be a dead-end "go to Home" message with nothing to tap).

## Rider account management (post-testing fixes, Section 7)

Rider accounts are still invite-only — there is no public Rider signup
path — but Admin can now invite one from `RiderManagementScreen` (under
the Manage hub) instead of seeding one by hand in the Supabase dashboard.
Creating an `auth.users` row needs the Supabase Admin API, which needs
the service-role key, so this goes through a new Edge Function,
`admin-create-rider`, rather than a client-side RPC — it verifies the
caller is an admin (via the `is_admin()` RPC over the caller's own JWT),
then calls `auth.admin.createUser()` and inserts the `profiles` row
itself using the service-role client.

"Remove" and "deactivate/reactivate" are both implemented as a single
`profiles.is_active` flag (default `true`, so it doesn't affect anyone
else) flipped via `admin_set_rider_active()` — never a hard delete.
`AuthGate` blocks sign-in for `is_active = false` (any role, though only
riders currently have UI to flip it) by showing a "deactivated" screen and
signing the session out; the account, its orders, and `delivery_records`
are all untouched. (A hard delete was deliberately avoided:
`delivery_records.rider_id` is `on delete cascade`, so deleting the auth
user would have silently wiped the rider's delivery history.)

## Around categories (post-testing fixes, Section 9)

The five Around categories used to be a hardcoded `AroundCategory` enum.
They're now rows in an `around_categories` table (`key`, `title`,
`subtitle`, `description`, `icon_name`, `flat_fee`, `is_active`,
`sort_order`), managed from `AroundCategoriesScreen` under the Manage hub.
`around_requests.category` is a foreign key into `around_categories.key`
instead of a fixed `CHECK` constraint, so adding a category needs no
schema change. Students only ever see `is_active = true` rows
(`activeAroundCategoriesProvider`); `AroundScreen` takes an
`AroundCategoryData` instead of an enum value.

`icon_name` is one of a small fixed set mapped to `IconData` in
`AroundCategoryData.iconFor()` (`shared/models/around_category.dart`) —
add a new admin-selectable icon there if a future category needs one not
already listed.

## Anonymous rider availability (post-testing fixes, Section 10)

The Around tab used to show an individual rider's name and an
"is online" badge tied to that person (e.g. "Emeka A. · Campus rider").
It's now a single anonymous signal: a green/grey dot plus "Riders
available nearby" / "No riders available right now", backed by
`any_riders_available()` (`SECURITY DEFINER`, checks whether any
`role = 'rider' and rider_is_online and is_active` row exists) — no name
or per-rider status ever leaves the server.
