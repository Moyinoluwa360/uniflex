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
                              # ErrandRequest, DeliveryLocation, WalletTransaction,
                              # SavingPlan — shared data
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
    home/                    # Home screen (Food Delivery + Errand mode toggle, vendor list,
                              # SearchScreen, AllVendorsScreen)
    ordering/                # Catalog (accordion sections), Cart (multi-vendor accordion),
                              # Checkout (location-based fees), PackBuilderScreen (accordion),
                              # CommitmentFeeScreen, Confirmation
                              # + cart_provider, product_repository, order_repository (realtime)
                              # Pack 4A: checkout_draft, order_payment_repository, cart_notice_listener
    errand/                  # ErrandScreen (reads categories from errand_categories table)
                              # + errand_category_providers.dart (active list, rider availability)
    orders/                  # OrdersScreen (Cart / Preparing / Completed tabs)
    tracking/                # OrderTrackingScreen (status timeline, refreshable)
    wallet/                  # WalletScreen, PaystackCheckoutPage, SavingPlanScreen
    support/                 # SupportChatScreen — student ↔ admin chat (see "Customer Support Chat")
    gifts/                   # Pack 6: GiftSection (checkout), GiftsScreen, GiftReceivedScreen — see "Food gifting (Pack 6)"
    profile/                 # StudentProfileScreen (rebuilt Phase 6) + sub-screens:
                              # MembershipCardScreen, ReferralScreen,
                              # BadgesScreen, ScheduledOrdersStudentScreen,
                              # PreferencesScreen
    group_checkout/          # CreateGroupScreen (open group session) +
                              # GroupCheckoutScreen / JoinGroupScreen (Phase 6)
    services/                # StudentService + student Riverpod providers (Phase 6)

  rider/                     # Rider-only screens and navigation. Root: rider_shell.dart
    services/                # RiderService + rider Riverpod providers
                             #   streamPool() → unified {groups, errands} pool stream
                             #   streamActiveWork() → unified {groups, errands} active work
                             #   getGroupCustomerInfo(id), getGroupItems(id),
                             #   setGroupFinalPrice(id, amount)
    dashboard/               # RiderDashboardScreen — online/offline toggle + daily stats
    pool/                    # JobPoolScreen — unified pool (food groups + errands)
                             #   pool_group.dart / pool_order.dart — enriched pool models
    jobs/                    # FoodJobScreen — preview + active food delivery job
                             # ErrandJobScreen — preview + active errand job
    delivery/                # ActiveDeliveryScreen / GroupDeliveryScreen — legacy stubs
                             #   both redirect to FoodJobScreen; kept for old call sites
                             #   delivery_record.dart — history record model
    history/                 # DeliveryHistoryScreen — past deliveries (includes cancelled)
    profile/                 # RiderProfileScreen — real profile + logout
  admin/                     # Admin-only screens and navigation. Root: admin_shell.dart
                              # (Admin also covers Kitchen Staff duties — no separate login)
    services/                # AdminService + admin Riverpod providers
    dashboard/               # AdminDashboardScreen — real-time stats
    kitchen/                 # KitchenQueueScreen — scheduled pickups only (no deliveries)
    orders/                  # AdminOrdersScreen — 2 tabs (Deliveries / Errands),
                              #   filter chips Active/Completed/Cancelled, search bar
                              # AdminOrderDetailsScreen — group or errand detail + cancel
    scheduled/               # AdminScheduledOrdersScreen — pre-order countdown + mark ready
    menu/                    # MenuManagementScreen, ProductFormScreen — Uniflex catalog CRUD
                              # (+ Requires Pack toggle, Uniflex pack price editor)
    service_charge/          # ServiceChargeScreen — edit the ₦ service charge (Pack 4A)
    manage/                  # ManageHubScreen — single "Manage" nav entry branching into
                              # Vendors / Riders / Errand Categories / Delivery Locations / Support
    support/                 # AdminSupportInboxScreen + AdminSupportChatScreen (see "Customer Support Chat")
    vendors/                 # VendorManagementScreen, VendorFormScreen,
                              # VendorProductsScreen — partner vendor CRUD (+ pack price)
    riders/                  # RiderManagementScreen — invite/remove/reactivate riders
    errand_categories/       # ErrandCategoriesScreen, ErrandCategoryFormScreen — CRUD for
                              # the errand_categories table
    delivery_locations/      # DeliveryLocationsScreen — CRUD for location-based delivery fees
    profile/                 # AdminProfileScreen — name, email, tier + logout

  shared/
    models/                  # Profile, Vendor, Product, Order, OrderItem, CartItem,
                              # ErrandCategory, DeliveryLocation, WalletTransaction,
                              # SavingPlan, Achievement (Phase 6)
    services/
      support/               # SupportChatService + all support providers (see "Customer Support Chat")
      notifications/         # NotificationService — FCM init, token storage, local
                              # notification display (Phase 6); showLocal() is also used
                              # directly by the order-status-change listener (Section 12)
    widgets/
      async/                 # RetrySection — reusable "failed to load, tap to retry"
                              # control used by every realtime/live data screen
      pin/                   # showEnterPinSheet / showSetPinSheet — transaction PIN UI
      sheets/                # acknowledgment_sheet.dart — pre-payment confirmation modal
      image_upload/          # ImageUploadField — pick/crop/resize/upload/preview (Fix Pack 3)

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
 ├─ session, onboarding_complete = false      (LEGACY half-made accounts only —
 │  │                                         Pack 5 never creates these any more)
 │  ├─ phone_verified_at is null           → ResumeOtpScreen (resumes the phone code)
 │  └─ phone_verified_at is set            → CompleteProfileScreen (resumes the profile step)
 ├─ session, onboarding_complete = true,
 │  is_active = false                      → _AccountDeactivatedScreen (signs out)
 └─ session, onboarding_complete = true,
    is_active = true                       → RoleRouter(role: profile.role)
```

**Pack 5:** while someone is signing up there is *no session*, so `AuthGate`
simply shows `LoginScreen` underneath the sign-up screens (`CreateAccountScreen`
is pushed on top of it). The account is created at the very last step; the
app then signs in and closes the sign-up screens (`popUntil(isFirst)`), and
`AuthGate` — which already switched to `RoleRouter` underneath — is what the
person sees. The `onboarding_complete = false` branches above exist only so
accounts made by the OLD 2-step flow can still finish.

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

- (Legacy accounts) After `CompleteProfileScreen` submits successfully, it calls
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

### Sign-up flow (Student self-signup only) — rebuilt in Pack 5

There is no role picker anywhere in the auth UI — sign-up only ever
produces a Student account. Rider/Admin accounts are invite-only, seeded by
hand directly in Supabase (see `supabase/schema.sql`).

**Rule: nothing exists in the backend until the very last step.** Steps 1–2
only send/check an SMS code; the draft lives on the phone.

```
 Step 1  Your details ──send OK──▶ Step 2  Verify phone ──code OK──▶ Step 3  Final details
 (email, password,       ▲          (6-digit code, 60 s            (nickname, name, matric,
  phone)                 │           resend, Change number)         school, DOB, referral, PIN)
                         └──change number──┘◀── proof expired ───────┘
                                                                        │ "Finish setup"
                                                                        ▼
                                          ONE server call `signup`/complete → account, then sign in
```

| Piece | Where |
|---|---|
| Host + step 1 | `lib/shared/auth/screens/create_account_screen.dart` (`CreateAccountScreen` is the host; it loads the saved draft and shows the current step) |
| Step 2 | `lib/shared/auth/screens/verify_phone_screen.dart` |
| Step 3 | `lib/shared/auth/signup/signup_final_step.dart` |
| All logic / transitions | `lib/shared/auth/signup/signup_flow_controller.dart` (no widgets; unit-tested) |
| Phone draft | `lib/shared/auth/signup/signup_draft.dart` |
| Server client + friendly errors | `lib/shared/auth/signup/signup_api.dart` |
| Edge Function | `supabase/functions/signup/index.ts` (actions `send`, `verify`, `complete`) |
| SQL | `supabase/pack_5.sql` (+ `pack_5_test.sql`) |

**Step 1 → 2 only when the server says the SMS was sent.** `send` first asks
Postgres whether the email / phone are free (`pack5_identity_status`) and
answers `EMAIL_TAKEN` / `EMAIL_STUCK` / `PHONE_TAKEN` *before any SMS is
sent*. Then limits (60 s between sends to one number, 5 per number per 24 h,
20/h per IP, 10/h per device) are reserved atomically, Termii is called
(20 s timeout), and a failed send is cancelled so it never counts. If a code
for that number went out a moment ago (double tap / lost reply) the server
answers `TOO_SOON` and the app moves on to step 2 with the remaining wait.
The client has a 25 s timeout on every call — a lost reply can no longer
leave the button spinning forever.

**The proof.** `verify` checks the code with Termii (max 5 tries per code,
per-IP cap; only the newest code for a number is valid). On success the
function makes a random 32-byte token, stores only its SHA-256 next to that
phone number (`signup_phone_verifications`), and returns the token. It is
valid 30 minutes, works for that phone only, and can be spent once. The
app keeps it in the draft (treating it as expired after 29 min).

**Creating the account.** `complete` re-checks the proof, then email /
phone / nickname / matric are free, creates the auth user through the admin
API (email pre-confirmed, so no confirmation email), then calls
`pack5_finish_signup()` — one Postgres transaction that locks and spends
the proof and writes profile (verified phone, `onboarding_complete = true`),
wallet, referral relationship and the bcrypt-hashed transaction PIN. If that
function raises for any reason, Postgres rolls everything back and the Edge
Function deletes the just-created auth user: all or nothing. (Postgres
cannot create the auth user inside the same transaction without writing
GoTrue's tables by hand, so the auth user is created first and removed on
failure.) The app then signs in with the typed email/password; `AuthGate`
shows the Student shell.

**The draft** (`SignupDraftStore`): step, typed fields, proof and the
last-send time are JSON in shared preferences; the **password is only in
secure storage** (Android Keystore / iOS Keychain via `flutter_secure_storage`,
`SecretStore` interface); the **PIN is never stored** anywhere. It expires 24 h
after the last save, is cleared on success or "Start over", and opening
"Create account" resumes the saved step. If the proof ran out the person
goes back to step 2 with everything else kept. Changing the email or phone
discards the proof. "Log in" always goes to the normal login screen.

**Legacy half-made accounts** (made by the old flow: auth user + stub profile,
`onboarding_complete = false`) are untouched. They still resume through
`AuthGate` → `ResumeOtpScreen` / `CompleteProfileScreen`, which still use the
old authenticated `phone-otp` function and `complete_student_onboarding()` RPC.
Registering with an email that belongs to one returns `EMAIL_STUCK`: "You
already started creating an account with this email. Log in to continue where
you stopped." `supabase/pack_5_legacy_accounts.sql` lists them (read-only);
`supabase/pack_5_cleanup_DO_NOT_RUN_until_approved.sql` removes stale ones but
ends in `ROLLBACK` and is for the owner to approve and run.

**Termii.** The app never calls Termii and does not contain its key. The key
exists only as the `TERMII_API_KEY` secret on the `signup` and `phone-otp`
Edge Functions.

Nickname/matric-number uniqueness and referral-code existence are checked
on step 3 through the existing RPCs (`is_nickname_available`,
`is_matric_number_available`, `is_referral_code_valid`, callable before login)
as a courtesy while typing; the server re-checks at the end and the database
unique constraints have the final word.

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
- ~~`OrderNotifier`~~ — **removed in Pack 4A.** Orders are created only by
  `OrderPaymentRepository` (`student/ordering/order_payment_repository.dart`),
  one paid RPC per order type; see "Payment-first order creation".
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
  set a delivery order (food delivery or errand) straight to
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

> **Superseded in Pack 4A.** `StudentShell` no longer watches
> `studentOrdersProvider` to fire local notifications (it only worked while
> the app was open and duplicated the server's push). Every notification is
> now written and pushed by the server — see "Notification pipeline (Pack
> 4A)" below.

## Design system

Rebuilt in **UI Polish 1** (2026-11-09); every screen moved onto it in
**UI Polish 2** (2026-11-09). Rules in one page:
[.claude/rules/ui.md](.claude/rules/ui.md). Audit of the screens it has to
reach: [docs/ui-audit.md](docs/ui-audit.md).

**Tokens — `lib/shared/theme/`**

- `app_colors.dart` — `AppColors`, a `ThemeExtension` with a light and a dark
  value for every token, read as `context.colors.surface` etc. (falls back to
  the ambient brightness if a test has no `AppTheme`). The old static palette
  (`emerald`, `orange`, `info`, ...) was **deleted in UI Polish 2**; every
  screen now reads tokens, and `test/ui_polish/ui_guard_test.dart` runs with an
  **empty allowlist** (no raw or legacy colour outside `lib/shared/theme/`).
  Extra tokens added in UI Polish 2: `chartFees` / `chartFood` /
  `chartPalette` (admin charts), splash gradient + highlight + shadow,
  `whatsapp`, `adDark`, `onMedia`, `barrier`, `notifyDot`.
- `tier_tokens.dart` — membership tier washes (Bronze, Silver, Gold, Platinum;
  unknown tier = plain surface).
- `app_typography.dart` — **Plus Jakarta Sans** (static 400/500/600/700,
  bundled in `assets/fonts/`, no runtime fetching) for all UI text. Picked
  after checking the font files: it has the naira sign (U+20A6) and tabular
  figures; Figtree, Manrope, Switzer and Clash Display do not have `₦`.
  **Clash Display Semibold stays only for the "Uniflex" wordmark and splash.**
  No negative letter spacing except −0.01em on 28px+ headings; no negative
  word spacing (the old headings lost their word gaps: Clash's space glyph is
  0.154em and every title also got −0.02em tracking).
- `app_spacing.dart` — `AppSpacing` (gutter 20, card padding 16, list row 56,
  nav bar sizes, `navClearance` / `navClearanceOf(context)`) and `AppRadius`
  (card 20, large card 24, button 14, sheet 28, nav 34, ...).
- `app_icons.dart` — the single icon source: Material *outlined* only.
- `app_theme.dart` — light/dark `ThemeData` built entirely from the tokens
  (colour scheme, text theme, buttons, inputs, dialog, sheet, snackbar, tabs,
  switch, checkbox, progress, selection). `themeModeProvider` defaults to
  `ThemeMode.system`.

**UI Polish 2 additions (shared components)** — `cards/order_summary_card.dart`
(Orders list card; Cancel is `quietDanger`), `cart/cart_widgets.dart`
(`QuantityStepper`, `CartItemRow`, `CartTotalRow`, `AddItemButton`),
`cart/summary_row.dart`, `lists/notification_row.dart`,
`tracking/tracking_stepper.dart`, `tracking/pin_digit_boxes.dart`,
`wallet/wallet_card.dart` (hide/show balance), `wallet/transaction_row.dart`.
Rider/admin shells keep the classic bottom bar: their scrollables are not
padded for the floating glass bar.

**UI Polish 3 additions (login + sign-up look)** — `auth/app_auth_header.dart`
(`AppAuthHeader.login/.compact`, `AppStepProgress`: the Home-header gradient
with the orange `authAccent` circle; text is width-limited so it never sits on
the circle), `auth/auth_scaffold.dart` (`AppAuthScaffold`: header + body scroll
together, `AppPinnedFooter` pinned above the keyboard with a 22 px fade),
`inputs/app_text_field.dart` (`large: true` 56 px look; `AppFieldErrorRow`,
`appLargeInputDecoration`), `inputs/app_picker_field.dart` (`AppPickerField`,
`AppDropdownField` -> `AppSheet`), `inputs/app_otp_field.dart` (digit boxes
painted from ONE hidden `AppTextField`, so paste/backspace/one-time-code work as
before), `inputs/app_form_parts.dart` (`AppFormSection`, `AppChoiceChip`,
`AppCheckboxRow`, `AppFieldPair`). Tokens: `authAccent`, `authSub` (white in
light so header sub-text reaches 4.5:1), halo/disc/track colours. The old
`OnboardingProgressHeader` is deleted.

**Components — `lib/shared/widgets/`**

`buttons/app_button.dart` (`AppButton`: primary / secondary / text /
quietDanger / disabled; solid red exists only inside `AppDialog`, which is a
`part` of the same library so nothing else can build it) with
`buttons/tap_guard.dart` (fire-once guard); `PrimaryButton` /
`SecondaryButton` now just wrap `AppButton`. `cards/app_card.dart`,
`lists/app_list_group.dart` (`AppListGroup`/`AppListRow`),
`tabs/app_segmented_tabs.dart`, `status/app_status_label.dart` (dot + words,
never a pill) and `status/status_presentation.dart` (`StatusPresenter`: every
order / delivery-group / gift status -> label + tone), `buttons/app_icon_button.dart`,
`text/app_section_label.dart`, `avatar/app_avatar.dart`,
`dialogs/app_dialog.dart`, `sheets/app_sheet.dart`,
`notice/app_inline_notice.dart`, `tier/tier_header.dart`,
`format/money.dart` (`Money`, `MoneyText`, `MoneyHero`: `₦39,210`, tabular
figures), `accordions/app_accordion_card.dart` (an `AppCard` now),
`inputs/app_text_field.dart` (styled by the theme), and
`navigation/app_glass_nav_bar.dart` (floating glass bar: one blur, sliding
capsule, same index/callback as the shells; **not wired into the shells yet** —
`navigation/app_bottom_nav_shell.dart` still builds a `BottomNavigationBar`).

Don't hardcode colours, fonts, or one-off paddings in screen code. Pull from
the tokens and components so a design change happens in one place.

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
| Student ordering flow ✅ (Phase 2)| `student/ordering/`, `student/errand/` (was `around/`), `student/orders/`, `student/tracking/`, `student/wallet/`, `shared/models/{vendor,product,order,order_item,cart_item,errand_request}.dart`, `shared/services/wallet/` |
| Wallet & payments ✅ (Phase 3)   | `student/wallet/`, `shared/services/{wallet,saving_plan}/`, `shared/models/{wallet_transaction,saving_plan}.dart`, `supabase/functions/{verify-paystack-payment,create-virtual-account}/` |
| Admin & kitchen ✅ (Phase 4)     | `admin/` (all subfolders), `shared/services/` (wallet already shared), schema.sql Phase 4 block |
| Rider delivery flow              | `rider/jobs/`, `rider/navigation/`, `rider/earnings/` |
| Push notifications (Firebase)    | `shared/services/notifications/` |
| Maps / live tracking             | `shared/services/maps/`, consumed from `student/tracking/` and `rider/navigation/` |
| Post-testing fixes ✅ (first Android QA pass) | `admin/manage/`, `admin/riders/`, `admin/errand_categories/` (was `around_categories/`), `student/ordering/pack_allocation_screen.dart`, `shared/widgets/{async,pin}/`, `shared/models/errand_category.dart`, `supabase/functions/admin-create-rider/`, schema.sql "POST-TESTING FIXES & CHANGES" block |
| Round 2 post-testing fixes ✅ (second QA pass) | `admin/analytics/`, `admin/admin_shell.dart` (4 tabs), `admin/manage/manage_hub_screen.dart` (expanded), `student/ordering/cart_provider.dart` (persistence), category normalization in `catalog_screen.dart`/`menu_management_screen.dart`/`product_form_screen.dart` |
| Round 3 ✅ (commitment fee + adjustable orders) | `student/ordering/commitment_fee_screen.dart`, `student/ordering/adjust_order_screen.dart`, `order_item_flags` table, `being_sourced`/`awaiting_final_payment` statuses, `pay_commitment_fee`/`confirm_sourced_items`/`pay_final_amount` RPCs |
| Round 4 ✅ (registration fixes + ordering overhaul) | `place_partner_food_order` RPC, `order_custom_items` table, admin referral codes (`referral_codes`/`referral_code_uses`), confirm password field, optional matric, phone normalization, partner checkout routing, notes field on orders |
| Round 5 ✅ (PIN / payment root-cause fix) | All PIN functions + `pay_commitment_fee` re-created with `search_path = public, extensions`; `showSetPinSheet` rewritten with current-PIN detection; comprehensive `_mapError` coverage |
| Round 7 ✅ (pack-first, multi-vendor, delivery groups) | `delivery_groups`/`delivery_settings` tables, `place_multi_vendor_order`/`pay_group_commitment_fee`/`accept_delivery_group`/`verify_group_delivery` RPCs, `PackBuilderScreen`, multi-vendor `CartState`, `GroupDeliveryScreen`, `DeliverySettingsScreen`, `deliveryFeePerVendor` helper |
| Round 8 ✅ (locations, errands, unified orders, UI polish) | `delivery_locations` table + RPCs, location-based fees replacing `delivery_settings`, errand rename (around→errand across ~22 files), unified order identity via `delivery_groups`, accordion UI (catalog/pack builder/cart), `acknowledgment_sheet.dart`, double-tap guards, `SearchScreen`, `AllVendorsScreen`, `DeliveryLocationsScreen` |
| Pack 4A ✅ (2026-11-07) | `supabase/pack_4a.sql` (+ `_test.sql`, `_queries.sql`), `student/ordering/{checkout_draft,order_payment_repository,commitment_fee_screen,cart_notice_listener}.dart`, `student/notifications/notification_router.dart`, `admin/service_charge/`, `shared/services/settings/`, `shared/widgets/chat/`, `supabase/functions/push-notification/` |
| Support Chat ✅ (2026-11-04) | `support_conversations`/`support_messages` tables + 4 RPCs, `shared/services/support/support_chat_service.dart`, `student/support/support_chat_screen.dart`, `admin/support/` inbox + chat screens, `supabase/functions/support-notify/`, push tap routing in both shells, token hygiene on sign-out |

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
into `ManageHubScreen` entries alongside Vendors, Riders, Errand
Categories, Delivery Locations, Referral Codes, and Advertisements. Kitchen staff see only 1
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

## Image upload & storage (Fix Pack 3)

### Storage bucket

All admin-uploaded images go into a single Supabase Storage bucket called
`product-images` (created by `fix_pack_3.sql`, Section 1). Objects are
organised by prefix:

```
product-images/
  products/   ← food/vendor product photos
  vendors/    ← partner vendor logos / photos
  ads/        ← advertisement banner images
```

The bucket is **public** (read without auth) with a 5 MB per-object cap and
MIME whitelist `image/jpeg`, `image/png`, `image/webp`. RLS on
`storage.objects`:

| Operation | Who can |
|---|---|
| INSERT | Authenticated admin (`is_admin()`) |
| UPDATE | Authenticated admin |
| DELETE | Authenticated admin |
| SELECT | Everyone (public read) |

### `ImageUploadField` widget

`lib/shared/widgets/image_upload/image_upload_field.dart` is a reusable
form field that owns the full pick → process → upload → preview lifecycle:

1. **Pick** — `ImagePicker.pickImage` from gallery (source-agnostic; iOS
   and Android permissions are requested by the plugin automatically).
2. **Process** — pure-Dart `image` package (no native code; works in tests
   and on simulator):
   - `cropToSquare: true` → center-crop to `min(W, H)` then resize to
     1200 × 1200 at JPEG quality 80. Used for product and vendor photos.
   - `cropToSquare: false` → resize so the long side ≤ 1200 px, preserve
     aspect ratio, JPEG quality 80. Used for ad banners.
3. **Upload** — calls the `uploadFn` callback provided by the caller
   (e.g. `adminService.uploadProductImage`). A `LinearProgressIndicator`
   is shown during the upload.
4. **Preview** — the returned URL is stored in state and shown in a
   `ClipRRect` with a ×-button to clear.
5. **Error** — a red strip with a "Retry" link replaces the progress bar
   on failure; tapping retry re-runs from step 1.

The widget is stateful; the caller is notified of URL changes via
`onChanged: (String? url)`.

### Ad banner aspect ratio

The student home carousel renders each card at viewport × 86 % width and
128 pt height. On a standard 390 pt wide phone that is roughly 335 × 128 pt
— approximately **2.6 : 1**. The admin form hints **1200 × 460 px** as the
recommended upload size.

### Soft delete (Fix Pack 3)

Products, vendors, and errand categories now have a `deleted_at timestamptz`
column (nullable). "Delete" in admin screens means writing
`deleted_at = NOW()` — the row is never `DELETE`d. This solves the FK
constraint: `order_items.product_id` and `errand_requests.category`
reference rows that historical orders point to; a hard delete is blocked by
the DB and would destroy order history.

Student-facing read policies exclude soft-deleted rows:
- `products`: `is_available = true AND deleted_at IS NULL`
- `vendors`: `deleted_at IS NULL`
- `errand_categories`: `is_active = true AND deleted_at IS NULL`

Admin reads every row (`is_admin()` bypasses the filter) so soft-deleted
items remain visible in the admin lists (e.g. greyed-out or filterable in a
future phase).

## Delivery lifecycle (Fix Pack 2)

`delivery_groups` is the canonical entity for every food delivery. Even a
single-vendor order creates a group; each vendor's portion becomes a leg
(`orders` row linked via `delivery_group_id`). The status ladder:

```
placed
  → commitment_paid      (student paid commitment fee; group enters rider pool)
  → rider_accepted       (rider accepted; rider sees customer info + items)
  → awaiting_final_payment (rider set a final price; student must Pay or Decline)
  → out_for_delivery     (student paid; PIN revealed to student)
  → completed            (rider entered PIN at door)
     or cancelled        (admin cancel, or student cancelled before rider accepted)
```

### Rider visibility rules

- **Pool** (`commitment_paid`, `rider_id IS NULL`): riders see groups ready
  to accept. `RiderService.streamPool()` returns a combined record
  `({List<PoolGroup> groups, List<PoolOrder> errands})`.
- **Accepted** (`rider_accepted` or later, `rider_id = auth.uid()`): the
  assigned rider sees their active jobs. Customer info (name, phone, PIN) is
  returned by `get_group_customer_info`. PIN is redacted until
  `out_for_delivery`.
- **Items** (`get_group_items`): vendor-grouped jsonb with per-item quantity,
  unit price, section, and pack assignments. Fetched once on job open.

### Final payment flow

1. Rider taps "Enter Final Price" → `set_delivery_group_final_price(id, amount)`.
   - SQL guard: `amount > 0 AND amount ≤ 500,000`.
   - Sets `final_amount`, advances status to `awaiting_final_payment`.
   - Rider may correct the price from both `rider_accepted` and
     `awaiting_final_payment` states.
2. Student sees `_GroupFinalPaymentCard` on `OrderTrackingScreen`.
   - **Pay** → `pay_group_final_amount` (uses `final_amount` from group, not
     leg sum) → status becomes `out_for_delivery`; PIN revealed.
   - **Decline** → confirmation dialog → `decline_group_final_amount` →
     `cancelled_by_student = true`. Rider sees a cancelled-by-student view
     and auto-pops after a short delay.

### Student cancel before rider accepts

`cancel_delivery_group_before_accept` requires `status = 'commitment_paid'`
and `rider_id IS NULL` — the NOWAIT lock prevents a race where a rider
accepts at the same moment. After `rider_accepted` the student can no longer
cancel unilaterally; they must Decline the final price instead.

### Admin orders

`AdminOrdersScreen` (2 tabs: Deliveries / Errands) streams all statuses from
`AdminService.streamAllDeliveryGroups()` / `streamErrandOrders()` and
filters client-side by Active / Completed / Cancelled chips. Tapping a card
opens `AdminOrderDetailsScreen`, which shows full item breakdown, fees,
timeline, and a cancel button (calls `admin_cancel_delivery_group` RPC).

### Scheduled orders and Kitchen Queue

`scheduled_for` is only valid for `delivery_type = 'pickup'`.
`place_multi_vendor_order` raises an exception if a delivery order arrives
with a `scheduled_for` timestamp. `KitchenQueueScreen` and
`AdminScheduledOrdersScreen` therefore only ever show pickup orders;
delivery orders are never scheduled.

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
3. Batch-fetches vendor rows (partner food) and `errand_requests` rows
   (errand orders) to build `PoolOrder` objects with pre-resolved pickup
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

Every delivery-type order (food delivery + errand) receives a unique
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
payment (food checkout and errand). Storage follows the same pattern as
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
and `ErrandScreen` both call `has_transaction_pin()` before confirming and
show `showSetPinSheet` first if it's false, then always
`showEnterPinSheet`. The PIN itself is enforced **server-side**:
`create_paid_delivery_order`, `create_paid_pickup_order` and
`create_paid_errand` (Pack 4A) all take a `p_pin` and check it with the
lockout-aware `_check_transaction_pin` before touching the wallet — a client
bug can't skip the check. (`set_transaction_pin` is now a single function
`(p_pin, p_current_pin default null)`; a duplicate one-argument overload used
to make a first-time "set PIN" call ambiguous.)

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

## Multi-vendor cart and delivery groups (Round 7)

The cart (`CartState` in `cart_provider.dart`) is multi-vendor: a map of
`vendorId → VendorCartGroup`, each containing items, pack metadata, and the
vendor reference. Adding items from different vendors no longer clears the
cart — `CatalogScreen` reads/writes the vendor-specific group directly.

**Checkout routing (rebuilt in Pack 4A — payment first):**
- The checkout form's button is **Continue**. It validates the form and
  opens the payment page with the cart + chosen options held in memory
  (`CheckoutDraft`). It creates nothing and does not touch the cart.
- The payment page (`CommitmentFeeScreen`) shows the fees, then runs the
  shared payment step and **one** RPC that verifies the PIN, computes every
  amount, debits the wallet and creates the whole order — see "Payment-first
  order creation (Pack 4A)". The cart is cleared only after that succeeds.

**Delivery group lifecycle:**
```
placed → commitment_paid → [kitchen prepares Uniflex legs] →
  [trigger checks all ready] → out_for_delivery → completed
```

The `_check_group_ready_after_kitchen` trigger fires on each Uniflex leg
status change; when all legs reach `ready`, it auto-advances the group. The
rider pool shows committed groups via `groupPoolProvider`; accepting assigns
the rider to the whole group. `GroupDeliveryScreen` shows per-vendor pickup
stops; the rider confirms each leg individually, then delivers with a single
PIN at the customer's door.

**Delivery fees** are location-based as of Round 8. The `delivery_locations`
table stores named locations (e.g. "Engineering Hostel" ₦300, "Main Campus"
₦300) with a base price each. The student selects a location at checkout;
per-vendor fee = `location.price × packBrackets(foodPacks)` where
`packBrackets(n) = n <= 0 ? 1 : ((n + 2) ~/ 3)` — i.e. 1–3 packs = 1×,
4–6 = 2×, 7–9 = 3×, etc. A vendor with zero food packs (drinks only) still
pays 1× the base price. The commitment fee = sum of all per-vendor delivery
fees. The old `delivery_settings` key-value table is superseded.

## Vendor menu structure (Round 7)

Products now have a `section` field ('food'|'drinks'|'others') and an
optional `food_subsection` ('meal'|'protein_topping'). `CatalogScreen`
groups by section, with food items further split by subsection.

- **Meal items** (`section='food', food_subsection='meal'`) count toward the
  pack's 8-spoon capacity (`kPackMealCapacity` in `pack_constants.dart`).
- **Protein/toppings** (`food_subsection='protein_topping'`) go in packs but
  have no capacity limit.
- **Drinks/Others** are added directly — no pack step.

The pack builder (`PackBuilderScreen`) enforces pack-first ordering: choose
pack count → fill each pack up to 8 meal spoons → add to cart. The capacity
bar shows current/max per pack with color feedback.

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

## Errand categories (post-testing fixes Section 9, renamed Round 8)

The five Errand categories (formerly "Around") used to be a hardcoded enum.
They're now rows in an `errand_categories` table (`key`, `title`,
`subtitle`, `description`, `icon_name`, `flat_fee`, `is_active`,
`sort_order`), managed from `ErrandCategoriesScreen` under the Manage hub.
`errand_requests.category` is a foreign key into `errand_categories.key`
instead of a fixed `CHECK` constraint, so adding a category needs no
schema change. Students only ever see `is_active = true` rows
(`activeErrandCategoriesProvider`); `ErrandScreen` takes an
`ErrandCategoryData` instead of an enum value.

`icon_name` is one of a small fixed set mapped to `IconData` in
`ErrandCategoryData.iconFor()` (`shared/models/errand_category.dart`) —
add a new admin-selectable icon there if a future category needs one not
already listed.

## Anonymous rider availability (post-testing fixes, Section 10)

The Errand tab (formerly "Around") used to show an individual rider's name
and an "is online" badge tied to that person. It's now a single anonymous
signal: a green/grey dot plus "Riders available nearby" / "No riders
available right now", backed by
`any_riders_available()` (`SECURITY DEFINER`, checks whether any
`role = 'rider' and rider_is_online and is_active` row exists) — no name
or per-rider status ever leaves the server.

## Customer Support Chat (2026-11-04)

One-to-one Student ↔ Admin chat. Students open a conversation from their
Profile → "Help & Support" or via "Get help with this order" on any active
tracking screen. Admins reply from a shared inbox (all conversations, one
pool — not assigned to individuals). Each student has at most one
conversation at a time (`UNIQUE(student_id)` on `support_conversations`).

### Schema (`supabase/support_chat.sql`)

```
support_conversations
  id uuid PK, student_id uuid UNIQUE FK profiles,
  status text CHECK('open'|'resolved') DEFAULT 'open',
  last_message_at timestamptz, last_message_preview text,
  student_unread_count int DEFAULT 0, admin_unread_count int DEFAULT 0,
  resolved_at timestamptz, created_at timestamptz

support_messages
  id uuid PK, conversation_id uuid FK→CASCADE,
  sender_id uuid FK→CASCADE, sender_role text CHECK('student'|'admin'),
  sender_name text,          ← snapshot at send time
  body text CHECK(1 ≤ trim(length) ≤ 2000),
  order_id uuid FK orders ON DELETE SET NULL,
  created_at timestamptz
```

Both tables are in the `supabase_realtime` publication.

RLS (no client INSERT/UPDATE/DELETE — all writes go through RPCs):
- `support_conversations`: student sees own row; admin sees all.
- `support_messages`: student sees messages in own conversation; admin sees all.

### RPCs

| RPC | Who | What |
|-----|-----|-------|
| `send_support_message(p_body, p_order_id, p_group_id, p_conversation_id)` | student or admin | Student path: race-safe find-or-create conversation, validate that the attached order **or** delivery group belongs to the student, reopen if resolved, increment `admin_unread_count`. Admin path: requires `p_conversation_id`, verifies `is_admin()`, increments `student_unread_count`. Both: snapshot `sender_name`, rate-limit 20 msg/min. **Exactly one overload exists** (Pack 4A dropped the old 3-argument one). |
| `mark_support_read(p_conversation_id, p_role)` | student or admin | Zeros the caller's unread counter; called best-effort on screen open. |
| `resolve_support_conversation(p_conversation_id)` | admin only | Sets `status='resolved'`, `resolved_at`, zeros both counters. |
| `get_support_unread_total()` | student only | Returns `student_unread_count` for the caller's conversation. |

### Providers (`lib/shared/services/support/support_chat_service.dart`)

```
supportChatServiceProvider       → SupportChatService
myConversationProvider           → StreamProvider<SupportConversation?>  (student)
allConversationsProvider         → StreamProvider<List<SupportConversation>> (admin)
conversationMessagesProvider     → StreamProvider.family<List<SupportMessage>, String>
supportUnreadTotalProvider       → FutureProvider<int>  (student badge)
adminSupportUnreadProvider       → Provider<int>  (sum of adminUnreadCount across all convs)
```

Streams use `supabase.from('…').stream(primaryKey: ['id'])` — the same
Realtime pattern as kitchen orders and the job pool. No `.subscribe()`
channels, no manual reconnect logic.

### Client screens

**Student:**
- `lib/student/support/support_chat_screen.dart` — bubbles (admin left,
  student right), date separators, order chip (attached once per message,
  detached after first send), resolved banner, rate-limit error banner,
  double-tap guard (`bool _isSending`).
- Badge on "Help & Support" profile row watches `myConversationProvider`
  → `.studentUnreadCount`.
- "Get help with this order" `OutlinedButton.icon` on
  `OrderTrackingScreen` and `GroupDeliveryScreen` pre-attaches `orderId`
  and label to `SupportChatScreen`.

**Admin:**
- `lib/admin/support/admin_support_inbox_screen.dart` — `Open / Resolved / All`
  filter chips; name search backed by async `fetchStudentProfile` calls
  populating `Map<String, String> _names`; unread badge pill per tile.
- `lib/admin/support/admin_support_chat_screen.dart` — `_StudentHeader`
  (`PreferredSizeWidget`) with student name/nickname/phone fetched once
  via `FutureBuilder`; "Mark Resolved" `AlertDialog` confirm.
- Unread badge on Manage tab: `adminSupportUnreadProvider` passed to
  `AppBottomNavShell(badgeCounts: [0, 0, unread, 0])` by `AdminShell`.
  Manage hub shows the same count on the "Support" entry.

### Push notifications for support messages

Since Pack 4A chat notifications use the same pipeline as every other
notification (see "Notification pipeline (Pack 4A)"): the
`on_support_message_insert` trigger writes `notifications` rows (student →
every active admin; admin reply → that student, `type = 'support'`,
`conversation_id` set) and the generic push trigger sends them.
`mark_support_read` also marks the matching inbox rows read. The old
`support-notify` Edge Function is no longer called.

**Push tap routing** (`lib/shared/services/notifications/notification_service.dart`):
- `onMessageOpenedApp`, `getInitialMessage()` and taps on the in-app banner
  all set the `NotificationService.pendingNavigation` `ValueNotifier`.
- `StudentShell` / `AdminShell` listen to it (so a tap while the app is only
  backgrounded works) and also read it once after the first frame (cold
  start). The payload keys are `type`, `notification_id`, `order_id`,
  `group_id`, `conversation_id`.
- Students: `openNotificationTarget()` (`student/notifications/notification_router.dart`)
  marks the notification read and opens the support chat, the delivery-group
  tracking screen or a single order. The Notifications screen uses the same
  function. Admins: `type == 'support'` opens the support inbox. The Rider
  shell does not route taps yet (Pack 4B).

**Token hygiene (updated 2026-11-08):** one row per phone in `push_devices`
(`register_push_token` / `unregister_push_token`; a token belongs to whoever
is signed in on that phone). The app registers on every sign-in and token
refresh, and `AuthService.signOut` unregisters *before* ending the session.
`push-notification` pushes to all of a person's phones and removes a token only
on `UNREGISTERED` / "invalid registration token". `profiles.fcm_token` is kept
as a fallback for old builds. Sign-out also clears any pending tap payload.

**Chip / order identity:** a support message carries `order_id` (errand,
pickup) **or** `delivery_group_id` (a delivery — the one order the student,
rider and Admin all see). Both render as the same `SupportOrderChip`
(`shared/widgets/chat/`); on the Admin side the chip opens that order's
details.

## Payment-first order creation (Pack 4A)

**No unpaid order can exist.** Nothing is written to the database until the
student has paid. The old "create the order now, pay the commitment fee
afterwards" split (`place_multi_vendor_order` → `pay_group_commitment_fee`,
`place_errand_order`, `place_partner_food_order`, `place_food_order_with_payment`,
`pay_commitment_fee`, …) is gone — `pack_4a.sql` drops those functions and the
client code that called them.

```
Checkout form ──Continue──► CommitmentFeeScreen (payment page)
   (validates only;            fee lines + total
    nothing created,           │ Pay → note → PIN   (runPaymentFlow, shared)
    cart untouched)            ▼
                          ONE rpc, one transaction:
                            idempotency check → verify PIN → compute every
                            amount → lock wallet, check balance → debit →
                            create group/legs/items/packs (or pickup / errand)
                               │ success only
                               ▼
                          clear cart, refresh wallet/orders, open tracking
```

| RPC | Creates | Charged |
|---|---|---|
| `create_paid_delivery_order(key, pin, legs, location_id, details, note)` | `delivery_groups` row already at `commitment_paid` (→ rider pool) + one leg per vendor with items and packs | Σ per-vendor delivery fee (`location.price × packBrackets`) + service charge **once** |
| `create_paid_pickup_order(key, pin, vendor_id, items, packs, scheduled_for, notes)` | one `orders` row (pickup) | full food + packs; **no** delivery fee, **no** service charge |
| `create_paid_errand(key, pin, category, pickup, dropoff, description, location_id, details)` | `orders` (errand) + `errand_requests` | category `flat_fee` + service charge |

Rules every one of them follows:

- **The client sends choices only** — product ids, quantities, pack
  allocation, location id, category key. Prices, fees, vendor type and the
  service charge are all read server-side. No parameter is named price/fee/
  amount/total (asserted in `pack_4a_test.sql`).
- **Idempotency.** The client makes one UUID per payment page
  (`newUuidV4()`), re-sent unchanged on every retry. The RPC takes a
  transaction advisory lock on it and stores `{key → result}` in
  `order_payment_attempts` (primary key). A repeated key returns the existing
  result with `replayed: true`; it never creates a second order or debits
  twice. A different user presenting the same key gets `IDEMPOTENCY_KEY_IN_USE`.
- **PIN problems are *returned*, everything else is *raised*.** Wrong /
  locked / missing PIN comes back as `{error: 'INVALID_PIN'|…}` so the
  failed-attempt counter (15-minute lockout) is committed; any other failure
  raises, which rolls back the whole transaction — no partial order, no debit.
  The client turns the returned code into a `PaymentException`, which
  `AppErrorMapper` maps to the friendly line.
- **Legacy unpaid orders** (left by the old button) are flagged
  `is_paid = false` and hidden by `RESTRICTIVE` RLS policies on `orders` and
  `delivery_groups`, so students, riders, Admin lists, the rider pool,
  Realtime streams and analytics (`get_dashboard_stats` is filtered too) can
  never see them. Notification triggers skip them. Nothing was deleted;
  `pack_4a_queries.sql` lists them and has an optional "mark cancelled".

Client files: `student/ordering/checkout_draft.dart` (in-memory draft + fee
preview, display only), `order_payment_repository.dart` (the three calls +
`PaidOrderResult`/`PaymentException`), `commitment_fee_screen.dart` (the
payment page), `shared/widgets/payment/run_payment_flow.dart` (the shared
note → PIN step, now actually used), `student/errand/create_errand_screen.dart`
(errand: pay button → note → PIN → one RPC; fee + service charge shown on the
form).

## Service charge (Pack 4A)

A flat fee, default **₦30**, added **once per order** to food deliveries and
errands when the student pays — never to pickup. Stored in
`app_settings (key, value)` (RLS on, no policies: reached only through
`get_service_charge()` / `admin_set_service_charge(int)`; the latter is
super-admin only and validates a whole number 0–100000). The amount actually
charged is written to `delivery_groups.service_charge` (deliveries) or
`orders.service_charge` (errands), so changing the setting never alters past
orders. Riders never see it; it will feed Admin's "Fees collected" (Pack 4C).
Admin edits it at **Manage → Service charge** (`admin/service_charge/`).
`serviceChargeProvider` (shared) lets the payment page display it; the server
is the only authority on what is charged.

## Notification pipeline (Pack 4A)

One server-side pipeline for every notification:

```
event ─(DB trigger)─► queue_notification() ─► INSERT notifications row
                                                    │ AFTER INSERT trigger
                                                    ▼
                                    pg_net → push-notification Edge Function
                                                    ▼
                                    send-notification → FCM → phone
```

The inbox row and the push are produced together, so they always match and
work whether the app is open, backgrounded or closed. The app only *displays*
(and routes taps): with the app open FCM `onMessage` shows an in-app banner —
nothing is stored by the client, so there are no duplicates.

| Event | Trigger | To | Text |
|---|---|---|---|
| Rider accepts (group / errand) | `delivery_groups_notify`, `orders_notify` | student | "A rider has accepted your order." |
| Rider sets / changes the final price | `delivery_groups_notify` | student | "Pay for your order: ₦X. Tap to pay." |
| Student pays the final price | `delivery_groups_notify` / `orders_notify` | rider | "Customer has paid. You can deliver." |
| Student declines / cancels | same | rider (if any) | "Order cancelled by customer." |
| Admin cancels | same | student + rider | "Your order was cancelled." |
| Delivered / errand completed | same | student | "Your order has been delivered." |
| Pickup becomes ready | `orders_notify` | student | "Your order is ready for pickup." |
| Support message / reply | `on_support_message_insert` | admins / student | message preview |

`notifications` gained `type`, `group_id`, `conversation_id` (the tap target).
Group legs never notify on their own — the group row does, once. Rows for
never-paid orders are skipped. `notify-user` (free-text message from Admin or
the assigned rider) now only records a row; the same trigger pushes it.

**Before Pack 4A (why the final-price alert never arrived):** order
notifications were produced by *client* code only — Kitchen/Rider screens
called `notify-user` after an order-status change (standalone orders), and
`StudentShell` fired a local banner while the app was open. The Fix Pack 2
delivery-group flow (accept, final price, pay, decline, deliver) goes through
`delivery_groups` RPCs that call neither, and `notify-user` only understood
`orders` ids — so a final price produced no notification at all.

The push needs the DB settings `app.supabase_project_url` and
`app.supabase_service_role_key` (already required by the support-chat push)
and the `push-notification` + `send-notification` functions deployed with the
Firebase service-account secret. If the settings are missing the inbox row
is still stored; only the push is skipped.

## Pack 4B — shared order breakdown, rider home, timestamps, one entry per checkout

### One way to load and show an order
- Server: `get_order_breakdown(p_id)` (SECURITY DEFINER). `p_id` is a delivery
  group, a standalone order, or a leg (answers for its parent). Access: the
  owning student, admin, the assigned rider, or any rider while the group is
  `commitment_paid`, unassigned and paid. It returns vendors → packs
  (`index`, `price`, items), plain food items, drinks, others, per-vendor
  totals. It never returns fees, phone, email or matric number.
- Client: `lib/shared/order_breakdown/` — `OrderBreakdown(orderId)` (loads via
  `orderBreakdownProvider`, errors logged in debug, `RetrySection` on failure)
  and `OrderBreakdownView(data)` (pure). Single vendor = plain header + closed
  `AppAccordionCard` packs ("Pack 1 · ₦200") + plain Drinks/Others; multi
  vendor = closed vendor dropdowns with the same body inside. Used by the
  rider pool preview, rider active job, rider history details, Admin order
  details and student tracking. Do not add a second copy.
- `order_packs.price` is stored per pack (pack_fee / pack_count at back-fill,
  set by trigger on insert).

### Rider app
- Reads only rider-safe RPCs: `rider_job_pool()`, `rider_active_jobs()`,
  `rider_history()`, `rider_history_item(id)`, `rider_group_detail(id)`,
  `get_rider_stats()`. **Riders have no read policy on `delivery_groups`,
  `orders` or `errand_requests`** (those rows hold the delivery PIN and fee
  columns, and RLS cannot hide columns). Live refresh = a Realtime stream of
  `rider_job_signals` (ids only; written by triggers on groups and standalone
  errands) used purely as a "refetch now" nudge, plus a 45 s safety refetch.
  Never re-add a rider SELECT policy on those tables. One entry per checkout;
  vendor parts never appear.
- The Admin kitchen queue lists pickup orders only; deliveries have no kitchen
  step.
- Jobs tab = pool only. Home shows "Active jobs" (count) beside Today / All
  time; tap → chooser if both kinds are active, else that list directly
  (`activeJobsTarget`); with none it opens the food list's empty state.
- Max 3 active jobs per rider, enforced in `accept_delivery_group` /
  `accept_order` (advisory lock per rider, then `ACTIVE_JOB_LIMIT`), before the
  existing `for update nowait` race guard.
- After a correct delivery PIN the sheet returns true and the job screen is
  replaced by `DeliveryCompleteScreen` (icon, order id, customer, server time,
  Done). History item → read-only `RiderHistoryDetailScreen` (no phone/email).

### Single timestamp rule
`completed_at` / `cancelled_at` are `timestamptz`, stamped ONCE by a
BEFORE trigger with server `now()` the first time the status becomes
completed/cancelled, and never changed afterwards. `verify_group_delivery`
completes group, parts and records in one transaction so all carry the same
value. Screens read it and convert with `.toLocal()` (`shared/utils/local_time.dart`);
never display `DateTime.parse(...)` hours directly.

### One entry per checkout
The parent (`delivery_groups` row, or a standalone pickup/errand order) is the
only thing listed, counted or timestamped. Vendor parts (`orders` rows with a
`delivery_group_id`) must never be listed, counted or given their own time:
rider history/active/pool, Admin orders, student orders, stats and dashboard
all follow this.

## Pack 4C — shared menu manager, support options, stats, ads popup, referral display

### Admin menu: one widget for every vendor
`lib/admin/menu/vendor_menu_manager.dart` → `VendorMenuManager(vendorId, title)`
is the ONLY menu-management screen. `MenuManagementScreen` (Uniflex, fixed
vendor id `0000…0001`) and `VendorProductsScreen` (partners) are one-line
wrappers. Four sections — Meals, Proteins / Toppings, Drinks, Others — chosen by
`MenuSection.of(product)` from `products.section` + `food_subsection`, exactly
what the student catalog groups by. The old free-text `category` column is
legacy and is only written as a readable label; nothing groups by it. Each
section has its own "+ Add" → `ProductFormScreen(initialSection:)` with no
category picker (edit mode keeps a "Section" picker so a mis-filed item can be
moved). The availability switch calls `setProductAvailability` (changes
`is_available` only); the old toggle re-saved the whole item and, for partners,
dropped its section. Vendor pack price lives in the AppBar of the same widget.
Errors are shown through `AppErrorMapper` (never raw database text).

### Admin reads names through one function
`profiles` RLS is "read own row only" and RLS cannot hide columns, so Admin
reading a student/rider profile directly returns nothing (this was the cause of
blank names in the support inbox, no rider name on order cards, "Unknown" in
analytics). Admin now uses the admin-only SECURITY DEFINER function
`admin_profile_basics(uuid[])` → id, role, nickname, full_name, phone, email,
wrapped by `adminProfileBasicsProvider(profileIdsKey(ids))` and `ProfileBasics`
(`displayName()` = nickname else full name; `secondaryName` = full name shown
underneath; `matches(q)` = nickname/full name/phone). Used by the support inbox
+ chat header, order cards/details (customer + rider) and rider performance.
Never add a broad "admin can read all profiles" policy for this.

### Support options
- `app_settings` key `support_whatsapp` holds ONE number as international
  digits (`2348031234567`). `admin_set_support_whatsapp(text)` (super admin)
  accepts `0803…`, `+234803…`, spaces/dashes, normalises, and clears on blank;
  `get_support_whatsapp()` is readable by any signed-in user.
- Student "Help & Support" (profile row and "Get help with this order") opens
  `SupportOptionsScreen`: Live chat | WhatsApp. When no number is set (or it
  cannot be read) the screen IS the live chat — no empty choice. WhatsApp opens
  `https://wa.me/<digits>?text=Hi, this is <nickname>.[ Order #<short id>.]` in
  the external app. Admin sets it under Manage → Support settings.

### Stats definitions (dashboard + analytics)
Single source: `_stat_entries()` (SQL, not callable by clients) → one row per
checkout, **paid only**: every `delivery_groups` row + every standalone order
(`delivery_group_id is null`); vendor parts never. Errands included. Day / week
(Monday) / month boundaries are `Africa/Lagos`. `get_dashboard_stats()` and
`get_admin_analytics()` both read it, so the two screens cannot disagree.
- Orders today = entries created today. Pending / in progress = every entry
  not completed/cancelled. Completed / Cancelled today = by the single
  `completed_at` / `cancelled_at`.
- **Fees collected** = delivery/commitment fees + service charges (groups,
  errands). Charged at creation, non-refundable, so cancelled ones still count
  (a cancelled *pickup* is refunded in full → 0).
- **Food payments** = a group's final payment (dated by the new
  `delivery_groups.final_paid_at`, stamped once by trigger) + pickup order
  totals (not cancelled).
- The two money numbers are shown side by side and are never added together.
- Top items = items on checkouts completed this month (each line belongs to one
  vendor part, so a multi-vendor checkout never double counts). Rider
  performance = completed checkouts per rider this month, once per checkout.
  Completion rate = completed ÷ (completed + cancelled) finished this month.
- Client: `AdminDashboardScreen`/`AdminAnalyticsScreen` only render; they
  refetch on tab open (`RefreshOnTabVisible` via `AppNavShellScope.currentIndex`),
  pull-to-refresh, the refresh button, and ~0.8 s after the admin order streams
  change (`StatsLiveRefresh` mixin).

### Ads
Tapping any ad opens `showAdPopup` (centred rounded dialog, ≤85% of the screen,
image `BoxFit.contain`, X + outside-tap close, "Visit" only when
`Advertisement.hasLink`). The old "tap action" choice is gone; the form has one
optional link, validated/normalised by `shared/utils/ad_link.dart` (http/https
only; bare domains get `https://`). DB columns are unchanged (`link_type` stays
`none|url`; the form sets it from whether a link was typed). `AdCarousel`:
auto-advance 5 s, 0.8 s eased slide, loops, pauses while a finger is down, dots,
a single ad is static.

### Referral (student side)
The student app no longer shows a referral code, amounts, counts, the
leaderboard or referral badges. "Refer a student" (`ReferAStudentScreen`) says
to contact Admin for a code and opens Help & Support. Registration still
accepts someone else's code (untouched); Admin still mints/assigns codes. The
backend referral logic is unchanged.

---

## Food gifting (Pack 6)

**A gift is an ordinary food delivery order with a different recipient.** There
is no second order system and no second payment flow. `create_paid_gift_order`
validates the recipient, then calls the unchanged `create_paid_delivery_order`
(same idempotency, PIN check, wallet debit, fees, service charge, final-price
step, delivery PIN, cancellation rules). Only the **sender** is the order's
`student_id`: only the sender pays, declines, cancels or contacts support.

### Data
- `delivery_groups` (the parent order) gains `is_gift`, `gift_recipient_id`,
  `gift_recipient_nickname`, `gift_message` (≤ 200 chars). Set by the server
  right after the normal order is created.
- `gift_deliveries` — the **recipient's own table** (one row per gift, primary
  key = the order id): `recipient_id`, `sender_nickname`, `message`, `status`
  (`placed | preparing | on_the_way | delivered | cancelled`), `delivery_pin`,
  `delivery_location`, `location_details`, `items` (the order breakdown with
  every price/total removed by `_gift_strip_prices`). It has **no money column
  at all**. RLS: the recipient can `select` their rows, nobody can write; it is
  in the Realtime publication so status changes appear live.
- `gift_lookup_log` — one row per lookup, for the 10-per-hour limit. No client
  grants.
- Kept unused (nothing deleted): the old `gifts` table, `get_gifts()`,
  `send_gift()` (execute revoked from clients), `orders.gifted_by`.

### Why a mirror table (privacy)
The recipient must see status, message, items and the delivery PIN, but must
never be able to read the sender's order — the order row holds the final price,
fees, wallet/payment links and the sender's identity. Instead of loosening the
RLS on `delivery_groups`/`orders`/`order_items`/`order_packs` (and then trusting
every client query to leave columns out), the server **copies the safe subset**
into `gift_deliveries` and keeps it in step with an `AFTER UPDATE` trigger on
`delivery_groups` (`_gift_sync_group`). The recipient's access is then
"select my rows from a table that contains nothing secret". The PIN is cleared
when the gift is delivered or cancelled. A third student reads nothing.

### Server functions
| Function | Who | What |
|---|---|---|
| `lookup_gift_recipient(email)` | any student | `{ok, nickname, masked_email}` or `{ok:false, reason: NOT_FOUND\|SELF\|RATE_LIMITED}`. Recipient must be a real student with a completed account. Logs every lookup; > 10/hour → `RATE_LIMITED`. Never returns anything else about the person. |
| `create_paid_gift_order(…same as delivery…, p_recipient_email, p_gift_message)` | sender | Re-resolves the recipient (never trusts the client), refuses self / unknown / message > 200, creates the normal order, marks it a gift, publishes the mirror row and the recipient notification, awards the Gifter badge. Replays are idempotent. |
| `_gift_sync_group()` trigger | system | Mirrors status/PIN; notifies the recipient when it goes out for delivery (`gift_on_the_way`), completes (`gift_delivered`) or is cancelled by sender/Admin/decline (`gift_cancelled`). |
| `get_group_customer_info(group)` | accepted rider | Now also returns `is_gift` and `gift: {recipient, sender}` (name, nickname, phone, email, location details); phones/emails go null once the job ends; never a matric number or PIN. |
| `rider_job_pool()` / `rider_active_jobs()` | rider | Add `is_gift` to food jobs. Still no personal details before accepting. |

### Notifications
All through the existing pipeline (`queue_notification` → trigger → push).
Types: `gift_received` ("<sender> sent you a food gift 🎁" + the message),
`gift_on_the_way`, `gift_delivered`, `gift_cancelled`. The recipient cannot read
the group, so `NotificationTarget.isGift` opens `GiftReceivedScreen` instead of
order tracking. The sender's own notifications are the normal order ones.

### Client
- **Checkout** (`GiftSection`): the switch exists only for delivery (hidden for
  pickup; errands have their own flow). Email + **Find** →
  "Sending to: **Nickname** (j***@gmail.com)" + **Change**; the typed address is
  not shown again. Continue is blocked until a recipient is found. The draft
  (`CheckoutDraft.giftRecipient/giftMessage`) drops the gift for pickup.
  `OrderPaymentRepository.payDelivery` calls `create_paid_gift_order` when
  `draft.isGift`, otherwise the normal function.
- **Recipient**: Orders → "Gift from <nickname>" cards (`GiftReceivedCard`, from
  `receivedGiftsProvider`, a live stream of `gift_deliveries`) → `GiftReceivedScreen`
  (status steps, message, items via `OrderBreakdownView(showPrices: false)`, the
  PIN). There is no button that pays, declines, cancels or edits.
- **Sender**: gift orders carry "🎁 Gift to <nickname>" on the Orders card, a
  banner with the message on tracking, and no PIN card (the recipient gives it).
- **Profile → Gifts** (`GiftsScreen`): Sent (from the sender's own groups) and
  Received tabs, with empty states. Replaces the old Send-a-Gift screen.
- **Rider**: pool card tagged GIFT; preview says "you see both contacts after
  you accept"; after accepting, `RiderCustomerCard` shows **Deliver to**
  (recipient) and **Paid by** (sender), each with Call + WhatsApp, and the
  reminder to ask the recipient for the PIN.
- **Admin**: order details show the GIFT tag, sender (paid), recipient and
  message.
- **`OrderBreakdown` "no prices" mode** (`showPrices: false`): pack titles lose
  their price; vendor totals and line amounts are not drawn.

### Not built (deliberately)
Gifting errands or pickup; the recipient accepting/refusing a gift; gifting by
phone number or matric number; scheduled gifts; group gifts.

---

## Text fields and the stuck selection highlight (Pack 6)

**Cause.** In Flutter a touch outside a text field does *not* take focus away
from it on Android/iOS (that only happens on desktop/web). A focused field keeps
painting its selection highlight and keeps its handles/toolbar, so after
selecting text and tapping elsewhere, scrolling or cancelling, the highlight
looked frozen on screen. Nothing in the app unfocused fields (no
`onTapOutside`, no `keyboardDismissBehavior`). A control test in
`test/pack_6_test.dart` demonstrates it with a plain `TextField`.

**Fix.**
- `AppTextField` (the app's one text field) is now stateful: it gives up focus
  when a tap *ends* outside it (pointer-up, so taps on buttons still fire), and
  collapses any highlighted range in its controller whenever focus is lost for
  any reason.
- `AppScrollBehavior` (set once on `MaterialApp.scrollBehavior`) makes dragging
  any scroll view dismiss the keyboard/focus.
- `TapOutsideUnfocus` (wrapped once in `MaterialApp.builder`) unfocuses on a tap
  on empty screen, covering any future raw field.
- Every raw `TextField`/`TextFormField` (18 of them: admin order dialog and
  search, service charge, support settings/inbox/chat, rider price + PIN sheets,
  rider errand PIN, PIN sheets ×4, group-join, home search, student support
  chat, saving plan, wallet top-up) now uses `AppTextField`, which accepts the
  same decoration/style/keyboard options so nothing looks different. A test
  fails if a raw field reappears outside `app_text_field.dart`.


## Security model (Pack 2, 2026-11-12)

- **Roles:** `profiles.role` (`student` / `rider` / `admin`, plus `admin_tier`) is the
  only source of authorisation, read by `is_admin()`, `is_super_admin()`, `is_rider()`.
  The `guard_profile_privileged_columns` trigger blocks clients from changing role,
  tier, points, spending, phone / verification, referral fields; trusted SECURITY
  DEFINER functions set `uniflex.trusted_write` for their own writes. There is no
  profile INSERT or UPDATE policy: profiles are created by the `signup` Edge Function
  (admin API) / `complete_student_onboarding`, riders by `admin-create-rider`.
  `user_metadata` is never used for decisions.
- **RLS approach:** RLS on every table. Clients **read** their own rows through
  policies (`auth.uid()`); every **write** that matters goes through a SECURITY DEFINER
  function with `set search_path`, a role check inside, and `EXECUTE` revoked from
  `anon` (and from `authenticated` for helpers whose name starts with `_`). Unpaid
  orders / groups are hidden by RESTRICTIVE policies. Riders read jobs only through
  `rider_*` functions and `rider_job_signals`.
- **Money flow:** wallet top-ups are credited only by the service role
  (`verify-paystack-payment` after `transaction/verify`, or `paystack-webhook` after an
  HMAC-SHA512 check of the raw body) through `credit_wallet` with a unique reference.
  Every debit (`create_paid_*`, `pay_final_amount`, `pay_group_final_amount`) locks the
  wallet row, checks the balance in the same transaction and writes a
  `wallet_transactions` row; prices, delivery fees and service charge are computed on the
  server from `products` / `delivery_locations` / settings; an idempotency key stops
  double charges. Balance must equal the sum of the ledger (forfeits on account
  deletion are a ledger row, source `account_deleted`).
- **Transaction PIN:** bcrypt hash in `transaction_pins` (`crypt` + `gen_salt('bf')`),
  set only by `set_transaction_pin` / sign-up, never readable. Checked only by
  `_check_transaction_pin` (server-only): 5 wrong tries → 15-minute lock. Callers
  **return** `{"error": "INVALID_PIN" | "PIN_LOCKED" | "PIN_NOT_SET"}` instead of
  raising, so the counter is not rolled back; the app turns that into a message with
  `throwIfRpcError` (`lib/shared/utils/rpc_result.dart`).
- **Account deletion:** `delete_my_account(pin)` (students only) — see
  `supabase/pack2_account_deletion.sql` for what is deleted, kept and why the auth row
  is scrubbed instead of deleted (cascades would remove financial records).
- **Secrets:** the app bundles `.env` — public values only (Supabase URL + anon /
  publishable key, Paystack public key, Firebase client config). Server secrets live in
  Edge Function secrets, the vault (`push_secret_key`) and the local, git-ignored
  `.env.tooling`. Codemagic and `test/pack2/security_test.dart` refuse a bundled secret.
