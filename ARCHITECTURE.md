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
    ordering/                # Catalog, MealCustomization, Cart, Checkout, Confirmation
                              # + cart_provider, product_repository, order_repository
    around/                  # AroundScreen (errand requests with real wallet deduction)
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
                              # (Phase 6: BULK badge + campus/hostel delivery labels)
    scheduled/               # AdminScheduledOrdersScreen — Phase 6 pre-order countdown
    menu/                    # MenuManagementScreen, ProductFormScreen — Uniflex catalog CRUD
    vendors/                 # VendorManagementScreen, VendorFormScreen,
                              # VendorProductsScreen — partner vendor CRUD
    profile/                 # AdminProfileScreen — name, email, tier + logout

  shared/
    models/                  # Profile, Vendor, Product, Order, OrderItem, CartItem,
                              # AroundRequest, WalletTransaction, SavingPlan,
                              # Gift, Achievement (Phase 6)
    services/
      notifications/         # NotificationService — FCM init, token storage, local
                              # notification display (Phase 6)

supabase/
  schema.sql                 # All DDL and seed data (run by hand in Supabase SQL editor)
  functions/
    verify-paystack-payment/ # Edge Function: server-side Paystack verification + credit
    create-virtual-account/  # Edge Function: Paystack DVA issuance with graceful fallback
    send-notification/       # Edge Function: FCM push via legacy HTTP API (Phase 6)
    birthday-rewards/        # Edge Function: invokes birthday reward RPC (Phase 6)
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
  The cart is local state (no async), so a plain `Notifier` is the right
  fit. Cart is vendor-scoped: adding items from a different vendor
  requires clearing first (the UI asks the user).
- `OrderNotifier` (`student/ordering/order_repository.dart`) — `Notifier<OrderPlacementState>`.
  Wraps the two-step Supabase write (insert `orders` row, then insert
  `order_items` or `around_requests`). After a successful placement it
  clears the cart and invalidates `studentOrdersProvider`.
- `vendorProductsProvider` and `orderByIdProvider` use
  `FutureProvider.family` — the `.family` modifier creates a separate
  cached instance per vendor ID / order ID. Swap `FutureProvider` for
  `StreamProvider` (same `.family` pattern) in Phase 3 to get Supabase
  realtime order-status updates without touching the tracking screen UI.
- Providers are colocated with the feature that owns them (e.g.
  `student/ordering/`). Only promote to `shared/services/` if more than
  one role genuinely needs the provider (e.g. `walletBalanceProvider` is
  shared because it could be shown in any role's UI).

**Order status state machine** (`shared/models/order.dart` — `OrderStatus`):

```
placed → preparing → ready → out_for_delivery → completed
                           ↘ ready_for_pickup ↗
                  ↘ cancelled (from any non-terminal state)
```

The tracking screen builds its timeline steps from the order's `type`
and `delivery_type`; the actual status comes from Supabase. Swapping the
`FutureProvider.family` for a realtime stream in Phase 3 requires only a
one-line provider change — the timeline widget reads `OrderStatus` and
doesn't care about the data source.

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

Update this table as phases land so it stays a reliable map of the repo.

## Admin permission tiers (Phase 4)

All admin accounts share the same `role = 'admin'` in `profiles`. The
`admin_tier` column (nullable) subdivides admin accounts:

```
admin_tier = NULL or 'super_admin'  →  AdminShell: all 5 tabs
admin_tier = 'kitchen_staff'        →  AdminShell: Queue + Profile only
```

The tier check happens once, in `AdminShell.build()`, by reading
`currentProfileProvider.valueOrNull?.isKitchenStaff`. There is no
client-side gate — a kitchen_staff account simply never sees the
Dashboard, Menu, or Vendor tabs, so there are no buttons to press that
would reach those screens. Server-side, the admin RLS policies (which use
`is_admin()`, not a tier check) apply equally to both tiers; restricting
the kitchen_staff *further* at the DB level (e.g. only allowing ORDER
reads/writes) is a hardening step deferred to a later phase.

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
+ items). The screen filters by status (`placed | preparing | ready`)
client-side and groups them into visual sections.

Status transitions (`placed → preparing → ready`) go through the
`update_order_status` SECURITY DEFINER RPC rather than a direct UPDATE,
so the server validates both the caller's admin role and the status string
before writing. The Realtime subscription then delivers the change back to
all connected admin sessions automatically — no `ref.invalidate` is
needed after a status update.

## Rider job pool — pull model (Phase 5)

Riders see the pool of available orders on `JobPoolScreen`, which watches
`jobPoolProvider` (a `StreamProvider` backed by
`RiderService.streamJobPool()`). The stream:

1. Subscribes to `supabase.from('orders').stream(primaryKey: ['id'])`.
2. Filters client-side to pool-eligible rows (`rider_id IS NULL` + correct
   source/status/delivery_type combination).
3. Batch-fetches vendor rows (partner food) and `around_requests` rows
   (around orders) to build `PoolOrder` objects with pre-resolved pickup
   info.

When a rider taps **Accept**, `RiderService.acceptOrder()` calls the
`accept_order` SECURITY DEFINER RPC. The RPC:
- Locks the row with `FOR UPDATE NOWAIT` to prevent concurrent accepts.
- Re-validates eligibility (in case the pool changed between the tap and
  the DB write).
- Sets `rider_id = auth.uid()`, `delivery_stage = 'accepted'`,
  `status = 'out_for_delivery'`.

The row immediately disappears from the pool for all other riders (RLS
`rider_id IS NULL` filter) via the Realtime subscription.

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
