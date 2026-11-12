# Changelog

All notable changes to this project are documented here, phase by phase.

## Fix: previous account's balance shown after switching accounts (2026-11-12)

Found on the phone: log out of one student, sign up / log in as another
without closing the app → the new account showed the old account's wallet
balance. Display only (the server always served the right wallet), but every
cached per-user list had the same flaw (orders, notifications, support chat,
gifts, saving plan, stats, rider jobs/history).
- `lib/user_session_scope.dart`: the app's provider scope is rebuilt whenever
  a signed-in user signs out or another account signs in — the same clean
  slate as a cold start. Nobody → user (login, sign-up, password reset) does
  not rebuild, so those screens are not interrupted. Theme choice is kept.
- The saved cart is deleted at that moment too (`clearSavedCart`), so the
  next account never inherits it.
- Test: `test/pack1/user_session_scope_test.dart`.

## Pack 1 / Part 4 — wallet funding fixes and tests (2026-11-12)

Audit table: `docs/wallet-funding-audit.md`.

**Security (money)** — `supabase/pack1_wallet_funding_fixes.sql` + `_test.sql`
(**applied to live 2026-11-12**, test 12/12 on live, rolled back):
- `credit_wallet` was executable by anon and authenticated on live (anyone
  could credit any wallet). Now service role only. Also rejects amounts ≤ 0
  and turns a concurrent duplicate into `DUPLICATE_REFERENCE`.
- `_refund_order` was directly callable by app users (self-refund of a
  delivered order). Now internal only (`update_order_status` still uses it).

**Edge Functions** (**deployed 2026-11-12**; bad-signature smoke test → 401):
- `paystack-webhook`: the payer-email fallback was a LIKE pattern; now an
  exact, escaped, unambiguous match.
- `create-virtual-account`: bank chosen from the key's mode (`test-bank` for
  `sk_test_`, `PAYSTACK_DVA_BANK` / `wema-bank` for live — the hard-coded test
  bank would have failed every live request); requires full name + phone;
  never overwrites an already-saved account; test accounts labelled
  "(test mode)".

**App**: the top-up sheet only says "Test mode — no real money is moved" when
the bundled key is `pk_test_…`.

## Pack 1 / Part 3 — fixed-menu vendor ordering style (2026-11-12)

Map and design: `docs/vendor-ordering-styles.md`.

**Database** (`supabase/pack1_vendor_ordering_style.sql` + `_test.sql`, 39/39
**applied to live 2026-11-12**, test 39/39 on live, rolled back)
- `vendors.ordering_style` (`pack_based` default, `fixed_menu`; check
  constraint). Existing vendors back-filled as pack-based, nothing else changed.
- Admin-only (trigger + existing RLS); a change is refused while the vendor
  has an order that is not completed / cancelled.
- `_check_leg_style` in `create_paid_delivery_order` (so gifts too) and
  `create_paid_pickup_order`: fixed-menu legs may not have packs and at most
  20 of one item; a cart built for the other style → `VENDOR_STYLE_CHANGED`.
  Fixed-menu menu items: name + category required, price > 0 and ≤ ₦500,000,
  stored as plain items. No pack rows can ever attach to a fixed-menu order.

**App**
- Admin: "Ordering style" segmented control (Pack-based | Fixed menu) with a
  helper line on the vendor form; pack price only for pack-based. Fixed-menu
  menus are grouped by the admin's categories with one "+ Add item"; the item
  form asks for a category (with chips of existing ones) instead of a section.
- Student: a fixed-menu vendor page lists each category as a dropdown with
  `+` → `− n +` (max 20, 0 removes). No pack card, no pack screen. Both cart
  UIs show fixed-menu lines as plain rows with a stepper (capped at 20);
  checkout says "Food" (not "Food + packs") when every vendor is fixed-menu.
  Pack-based vendors are unchanged.
- The checkout RPC leg now carries the cart's `ordering_style`.
- Order views (student, rider, admin, tracking) already render vendor legs
  without packs as plain `2× Item` lines — no change needed.

## Pack 1 / Part 1 — nav gap and border, hidden balance, tap fixes (2026-11-12)

**Presentation only.** No service, SQL, payment, PIN or status logic changed.

- **Nav gap (1.1):** the glass bar's bottom edge now sits
  `AppSpacing.navBottomGap` = **20 pt** above the *physical* bottom of the
  screen (12 on phones without a home indicator); the safe-area inset is no
  longer added on top. One constant to tune after comparing with WhatsApp.
  `navClearanceOf` = 68 + gap + 12 (100 on a home-indicator iPhone, was 124);
  used by Home (scroll + cart button lift), Orders, Wallet and Profile.
- **Border (1.2):** the bar's top edge looked thicker because two layers were
  painted at the top only: an inner 1px highlight line (`glassHighlight`,
  white 24% in dark / pure white in light) and a white 16%→clear sheen. Both
  removed (tokens deleted); the bar keeps one uniform 1px `glassBorder`. The
  active capsule was already a plain fill. Home header panels and the Major
  chip already used one uniform border — unchanged.
- **Hidden balance (1.3):** hidden by default on Home and Wallet; one shared
  in-memory flag (`lib/shared/state/balance_visibility.dart`), reset when the
  student shell is created/disposed (sign-in / logout), never persisted.
  Hidden shows exactly `₦ ••••` (was six dots on Wallet). Home gets an eye
  button (32 visual / 44 hit). Icon: hidden = eye, shown = eye-off.
- **Tap effects (1.4):** new `AppTappable` (own transparent `Material` with the
  exact shape, clipped). The square highlight came from shapeless `InkWell`s
  painting on an ancestor `Material` outside the rounded clip — every
  `AppListRow`, accordion headers, notification rows, picker rows. Theme: no
  ripple (`NoSplash`), soft `pressOverlay` highlight; ListTiles rounded. Guard
  test: every `InkWell`/`InkResponse` outside `AppTappable` has a shape.
- **Change Transaction PIN row (1.4):** the sheet waited on a network check
  (`hasTransactionPin`) with no feedback, so taps looked ignored and repeats
  queued extra checks. The row now shows a spinner at once and ignores repeat
  taps until the sheet closes. The PIN flow itself is unchanged.

## Push: iOS fix + rider/admin alerts (2026-11-12)

**Fixed**
- iOS never asked for notification permission: `GoogleService-Info.plist` was
  in the repo but not in the Xcode project, so it was never bundled and
  `Firebase.initializeApp()` failed silently. Added to `project.pbxproj`.
- (Console, not code) the APNs key in Firebase was Sandbox-only, so Apple
  rejected TestFlight pushes (`BadEnvironmentKeyInToken`). Replaced with a
  Sandbox & Production key.

**Added** (`supabase/push_staff_alerts.sql`, applied to live; test 18/18)
- Riders: "New delivery job" / "New errand job" when a paid job enters the
  pool — every active rider who is online. Tap → Jobs tab.
- Admins (super admin + kitchen staff): "New order" for each paid checkout
  (food delivery once per checkout, gift, errand, pickup) and "Order cancelled"
  (whole checkout, or one shop in it) — not sent to the admin who cancelled.
  Tap → Orders.
- Rider app now handles push taps (`rider_shell.dart`): customer paid → that
  job; cancelled → Home.

## UI Polish 3 — login + create-account look (2026-11-09)

**Presentation only.** Every field, label/hint string, validator, keyboard type,
OTP length/resend/timer, route, referral and fire-once guard is unchanged.

**Changed**
- Login, sign-up steps 1-3, Forgot/Reset password, the legacy Resume-OTP and
  Complete-profile screens use a green header (Home gradient) with an orange
  accent circle, 56 px inputs, and one primary button pinned above the keyboard.
- Step 2's code is six boxes drawn over ONE hidden field (same controller).
- A field's label now sits inside its box as the placeholder; a separate hint
  becomes the helper line under it. The school dropdown opens an `AppSheet`.
- The only new text: Login's "Food / Deliveries / Errands" chips and the
  "Redeemer's University" caption.

**Added** `AppAuthHeader`, `AppStepProgress`, `AppAuthScaffold`,
`AppPinnedFooter`, `AppTextField(large)`, `AppPickerField`, `AppDropdownField`,
`AppOtpField`, `AppFormSection`, `AppChoiceChip`, `AppCheckboxRow`,
`AppFieldPair`; tokens `authAccent`, `authSub`. **Removed**
`OnboardingProgressHeader`.

## UI Polish 2 — every screen on the new look (2026-11-09)

**Presentation only.** Branch `ui-polish`, one commit per batch (A glass nav +
Home, B orders/cart/checkout/tracking/notifications, C wallet/profile/remaining
student screens, D auth/onboarding, E rider + admin). No service, repository,
model, route, SQL, Edge Function, payment/PIN/fee/referral logic changed.

**Changed**
- All screens read `context.colors` tokens and shared components. The legacy
  static palette (`AppColors.emerald/orange/info/...`) is **deleted**; the UI
  guard allowlist is **empty** and the contrast test passes.
- Tinted cards/pills/icon boxes replaced by plain `AppCard` / `AppListGroup` /
  `AppStatusLabel` (dot + words). Spending is neutral; money in is green.
- Admin deletes and rider price confirmation use `AppDialog` (solid red only on
  the final destructive confirm). Every Cancel is `quietDanger`.
- Money shows thousands separators everywhere (`₦3,000`).
- The only text changes: "In Rider Pool" reads "Finding a rider"; the Orders
  tab "Preparing" is labelled "Active".
- Log out now asks "Log out?" first (new, from the spec).

**Added**
- `OrderSummaryCard`, `QuantityStepper`, `CartItemRow`, `CartTotalRow`,
  `AddItemButton`, `SummaryRow`, `NotificationRow`, `TrackingStepper`,
  `PinDigitBoxes`, `WalletCard`, `TransactionRow`; tokens `chartFees`,
  `chartFood`, `chartPalette`, splash and `whatsapp` colours.
- Tests: `test/ui_polish/batch_a..e_test.dart` (both themes × text scale 1.0
  and 1.3 for each extracted widget).

**Not done / left as is**
- Rider and admin shells keep the classic bottom bar (their lists are not padded
  for the glass bar).
- Admin chat header, ad popup CTA, a few admin `SegmentedButton`/`FilterChip`s
  and the admin chat "Resolve" action keep the themed Material widgets.

## UI Polish 1 — design-system foundation (2026-11-09)

The layouts are fine; what felt "vibe coded" was the finish. This pack builds
the foundation that fixes it everywhere. **Presentation only, and no screen was
restyled** — UI Polish 2 moves the screens onto it. Do not ship Pack 1 on its
own: the global theme changed (green buttons, new font, new surfaces), so
unmigrated screens now look like a mix of old and new.

**Added**
- `AppColors` is now a `ThemeExtension` (`context.colors.x`) with light + dark
  values for every token in the spec, plus home-header / wallet-card / ad
  gradients, glass + nav tokens, and membership tier tokens (Bronze, Silver,
  Platinum from the spec; **Gold added by me**, same pattern, because the app
  has a Gold tier).
- Font: **Plus Jakarta Sans** (static 400/500/600/700, bundled, OFL).
  Figtree (the pack's choice) and its fallback Manrope were checked and have no
  naira sign, so the owner picked Plus Jakarta Sans, which has `₦` and
  tabular figures. Switzer removed. Clash Display kept for the wordmark and
  splash only.
- Components: `AppButton` (+ `TapGuard`), `AppIconButton`, `AppListGroup` /
  `AppListRow`, `AppSegmentedTabs`, `AppStatusLabel`, `AppSectionLabel`,
  `AppAvatar`, `AppDialog` (the only place solid red exists), `AppSheet`,
  `AppInlineNotice`, `TierHeader`, `AppGlassNavBar`.
- Helpers: `Money` / `MoneyText` / `MoneyHero`, `StatusPresenter` (every order,
  delivery-group and gift status -> label + tone; "In Rider Pool" now reads
  "Finding a rider"), `AppIcons` (outline family only).
- Guards: `test/ui_polish/ui_guard_test.dart` (no hard-coded or legacy colours;
  an allowlist of 80 files / 644 uses that can only shrink) and
  `contrast_test.dart` (WCAG ratios for the token pairs in both themes).
  `.claude/rules/ui.md`, `CLAUDE.md`, `docs/ui-audit.md`.

**Changed**
- `ThemeData` rebuilt entirely from the tokens (buttons, inputs, dialog, sheet,
  snackbar, tabs, switch, checkbox, progress, selection colours, ...).
- `PrimaryButton` / `SecondaryButton` now render `AppButton`, so their ~40 call
  sites pick up the new look and a double-tap guard. There was no shared
  fire-once guard before (only per-screen flags, which are untouched).
- `AppCard` and `AppAccordionCard` restyled (plain surface + border, no tint,
  no glow; the accordion icon is a plain glyph). `AppTextField` is styled by
  the theme (behaviour untouched).
- `AppRadius` / `AppSpacing` values per spec (card 20, sheet 28, control 52).
- Two tests in `pack_4a_test.dart` now find the pay button as `AppButton` /
  `PrimaryButton` instead of `ElevatedButton` (same assertions).

**Found, not fixed** — see the report-only list in `docs/ui-audit.md` (section 11).

## Push fix — phones now register on login, one row per phone (2026-11-08)

Reported after the first real-phone test: bell shows messages, but iPhone gets
no push and Android is hit-and-miss.

**Causes found in the code**
- The phone's push address (FCM token) was only sent to the server at *app
  launch*, and only if someone was already signed in. Open app → log in → the
  token was never sent (until the next restart). Worst on iPhone, where the
  token also arrives late.
- Sign-out never cleared the token (the call ran after the session had ended,
  so the server ignored it). A phone that changed account kept pushing to the
  old one.
- One token per account: a second phone overwrote the first.
- The push had no Android priority/channel → Doze delays it, and it files into
  a silent channel. A bad payload (`INVALID_ARGUMENT`) also erased the token.

**Fix**
- `supabase/push_devices.sql` (+ `push_devices_test.sql`, 12/12): table
  `push_devices` (one row per phone; a phone belongs to whoever is signed in on
  it), RPCs `register_push_token` / `unregister_push_token`; `store_fcm_token`
  kept for old builds. Existing tokens are backfilled. Nothing deleted.
- App: registers on every sign-in / token change, retries while iOS hands over
  its APNs token, unregisters in `AuthService.signOut` *before* the session
  ends, no longer holds up startup. iOS AppDelegate shows banners while the app
  is open; Android manifest sets the default channel.
- `push-notification` sends to **all** the person's phones and only drops a
  token when Google says the phone is gone. `send-notification` marks Android
  `HIGH` priority + channel `uniflex_high`, and sends iOS as an immediate alert.
- `supabase/push_diagnose.sql`: read-only health check.

**Deploy order:** run `push_devices.sql` → deploy `push-notification` and
`send-notification` (`--no-verify-jwt`) → build/install the new app.

## Pack 6 — Food gifting ("Send as a gift") + stuck text-selection fix (2026-11-07)

Last of the five packs. A gift is a normal food delivery order with a different
recipient — no new order system or payment flow. **Applied to live 2026-11-07:**
`pack_6.sql` run, `pack_6_test.sql` on live = 61/61 pass (rolled back; no leftover
gift rows or lookups). No Edge Function redeploy needed.

### What the old Gift feature did (and what happened to it)
`Profile → Send a Gift` opened a two-tab screen (Send Gift / History). The send
tab looked a student up by **matric number** and called the `send_gift` RPC,
which took a vendor, a client-supplied item list and a client-supplied
`total_amount`, debited the sender's wallet and made a normal order in the
recipient's name; History read `get_gifts()`. Problems: it trusted a
client-sent price, used matric numbers for lookup, and the recipient had no
dedicated view. **Removed:** the menu entry, `GiftScreen`, `Gift` model,
`giftsProvider`, `StudentService.sendGift/getGifts`. **Left unused in the
database (nothing deleted):** `gifts` table, `get_gifts()`, `send_gift()`
(execute revoked from clients), `orders.gifted_by`.

### Added
- `supabase/pack_6.sql` (one additive block, safe to run once; ordering inside it:
  columns → tables/RLS/realtime → helpers → lookup → publish → create → sync trigger
  → rider/pool functions → revokes) and `supabase/pack_6_test.sql` (rolled-back).
- Sender: "Send as a gift" at checkout (delivery only), recipient by registration
  email → Find → nickname + masked email → Change; optional message ≤ 200.
- Recipient: notifications (in-app + push) on gift / on its way / delivered /
  cancelled; Orders cards "Gift from <nickname>"; `GiftReceivedScreen` with live
  status, message, items **without prices** and the delivery PIN; reads only the
  `gift_deliveries` mirror table.
- Profile → **Gifts** (Sent / Received tabs, empty states).
- Rider: GIFT tag; after accepting, **Deliver to** + **Paid by** cards with
  Call/WhatsApp; never matric numbers; nothing personal before accepting.
- Admin: GIFT tag, sender (paid), recipient, message.
- `OrderBreakdown` / `OrderBreakdownView` gain `showPrices: false`.
- Friendly errors: `GIFT_SELF`, `GIFT_RECIPIENT_NOT_FOUND`, `GIFT_MESSAGE_TOO_LONG`.

### Fixed — selection highlight stuck on screen (all text fields)
Root cause: on phones Flutter does not unfocus a text field when you touch
elsewhere, so it kept its highlight/handles/toolbar; the app never unfocused
fields. `AppTextField` now unfocuses on tap-outside and collapses its selection
on any focus loss; `AppScrollBehavior` dismisses on scroll-drag app-wide;
`TapOutsideUnfocus` unfocuses on empty-screen taps; 18 raw fields moved onto
`AppTextField` with unchanged looks (list in ARCHITECTURE.md).

### Tests
`test/pack_6_test.dart` (28 widget/unit tests). Full suite 316 pass; the 3
`catalog_sections_test.dart` failures are the same stale ones as before.

## Pack 5 — Sign-up rebuilt: 3 steps, account created only at the very end (2026-11-07)

Do-only-5 pack. Orders, riders, Admin screens and gifting were not touched.
**Applied to live 2026-11-07:** `pack_5.sql` run (46/46 checks pass on live,
rolled back, no leftovers) and `signup` deployed; no-SMS smoke calls behave
(taken email → 409, bad proof → 400, no code → 410). The phone unique index was
skipped by its guard because two old test stubs share a verified phone; the
prechecks still enforce it. Cleanup block NOT run. Real-SMS check still needs
the two-phone list in BEFORE_YOU_BUILD §6.

### Why the app stayed on step one although the SMS arrived

Traced in code (`create_account_screen.dart` `_submit`, `auth_gate.dart`,
`resume_otp_screen.dart`, `phone-otp/index.ts`) and against the live
`otp_send_log`:

1. The old Step One did a lot *before* it showed the code screen: `signUp`
   (which also **signs the person in**), upsert a stub `profiles` row, fetch the
   profile, then send the SMS — and navigation to the code screen was the very
   last line, reached only after the Edge Function answered.
2. Signing in fired the auth-state event; `currentProfileProvider` re-resolved
   and `AuthGate` — still alive *underneath* the pushed sign-up route — swapped
   to `ResumeOtpScreen`, whose `initState` **auto-sends another SMS**. Confirmed
   in live data: two `otp_send_log` rows 32 ms apart for one brand-new account
   (2026-11-01 03:35:33). Two texts, two different codes; the code screen only
   knew the first.
3. Nothing bounded the wait. The client call had no timeout; the function only
   answers after Termii's reply plus a DB insert, and Termii hands the SMS to
   the carrier *before* it replies — so a slow or lost reply means "SMS
   arrived, spinner never ends". Any error after that point printed "Account
   created, but the verification code could not be sent…" on step one. The
   "already registered" retry path signed in and popped to the root and never
   went to the code screen at all.

**Not provable from here:** which of (2)/(3) fired on the reporter's phone —
that needs the Edge Function logs or a device. The cause is the design
(irreversible side effects and a session created *before* the SMS, navigation
depending on a chain of calls and on provider state instead of on the send
result); the rebuild removes all three: no session exists during steps 1–2,
one SMS per tap (server reserves the send atomically), 25 s client timeout, and
step 1 → 2 happens only on the server's "sent" answer.

### New flow

1. **Your details** — email, password, confirm, phone (`0803…` or `+234803…`).
   The server checks email and phone are free **before any SMS**
   (`EMAIL_TAKEN`, `EMAIL_STUCK`, `PHONE_TAKEN`), then sends; on any failure the
   person stays here with a short message.
2. **Verify phone** — masked number, 6-digit code, Resend disabled 60 s with a
   countdown, "Change number" (back to step 1, everything filled; the new number
   is re-checked and gets a fresh code; the old verification is discarded).
   A correct code creates **no account** — the server returns a one-time
   *proof* (random token, only its SHA-256 stored, tied to that phone, 30 min,
   single use).
3. **Final details** — nickname (live availability), full name, matric
   (optional, live), school, DOB, referral (live), PIN + confirm. "Finish setup"
   makes **one** server call that checks the proof, re-checks everything,
   creates the auth user (email pre-confirmed) and — in one Postgres transaction —
   profile, wallet, referral, hashed PIN; any failure rolls back and deletes the
   auth user. The app then signs in and `AuthGate` shows the Student shell.

Draft on the phone: step, fields, proof, last-send time in shared preferences;
**password in the OS keystore only** (`flutter_secure_storage`); **PIN never
stored**; expires 24 h after the last save; cleared on success / "Start over";
"Create account" resumes at the saved step; proof expired at step 3 → back to
step 2 with the rest kept; changing email/phone drops the proof.

### Limits (all enforced in Postgres, keyed per phone / IP / device)

60 s between sends to a number · 5 sends per number per 24 h · 20 sends/h per IP
· 10 sends/h per device · 5 tries per code (and 40 verify calls/h per IP) ·
40 availability checks per 10 min per IP · 15 sign-ups/h per IP · a failed
Termii call is cancelled and never counts · codes expire after 10 min.

### SQL — run order

1. `supabase/pack_5.sql` (additive, safe to run once; re-run harmless): 2 new
   tables (`signup_events`, `signup_phone_verifications`, RLS on, no client
   grants), `pack5_*` functions (**service_role only** — anon/authenticated
   cannot execute them), a partial unique index on verified phones (skipped with
   a NOTICE if live already has duplicates).
2. Optional checks: `pack_5_test.sql` (46 checks, rolled back),
   `pack_5_legacy_accounts.sql` (read-only list of half-made accounts).
3. **Never run without approval:** `pack_5_cleanup_DO_NOT_RUN_until_approved.sql`
   (removes stuck stubs ≥ 14 days old with no orders and a zero wallet; it ends
   in `ROLLBACK` so running it by accident changes nothing).

### To go live (owner)

- Run `pack_5.sql`, then `supabase functions deploy signup` (JWT verification
  stays on; the app sends its anon key). Secret: `TERMII_API_KEY` (already set
  for `phone-otp`; the same value is reused — nothing new to create).
- `phone-otp` stays deployed (legacy half-made accounts use it).
- Order matters: deploy SQL first, function second, then build the app.

### Termii key

Checked: the app never calls Termii and the key is not in the bundle (`.env`
has only Supabase URL/anon key; `.env` is the only bundled asset). The key is an
Edge Function secret only. Removed stale text that said otherwise (README
"`TERMII_API_KEY` is required" and a `pubspec.yaml` comment). A plaintext
Termii key exists in the **gitignored** `.env.tooling` / `.env.backup-preaudit`
files on this PC — not tracked, not bundled; consider deleting them and
rotating the key if the PC is shared.

### Code

- New: `lib/shared/auth/signup/` (`signup_draft`, `signup_api`,
  `signup_flow_controller`, `signup_final_step`, `signup_widgets`),
  `supabase/functions/signup/index.ts`, `supabase/pack_5*.sql`.
- Rebuilt: `create_account_screen.dart` (host + step 1), `verify_phone_screen.dart`.
- Removed: `AuthService.signUpWithEmail`, `ProfileService.createStubProfile`
  (nothing may create an account or stub before the end now).
- Changed: `AppErrorMapper` (sign-up refusals, timeouts), `auth_providers.dart`,
  `pubspec.yaml` (+`flutter_secure_storage`).
- Legacy kept working: `AuthGate`, `ResumeOtpScreen`, `CompleteProfileScreen`,
  `phone-otp`, `complete_student_onboarding()`.

### Tests

`flutter analyze` clean. `test/pack_5_test.dart`: 45 pass (draft store, every
step transition, resend cooldown, Change number, proof expiry, resume,
friendly messages, and widget tests of the exact bug: SMS sent → code screen
shown; send fails → stays on step 1). `supabase/pack_5_test.sql`: 46/46 pass
on the local Postgres copy (refusals: no/expired/other-phone/reused proof,
taken email/phone/nickname/matric; all-or-nothing with a forced late failure;
every send/attempt limit; anon/authenticated cannot call anything). Full suite:
288 pass, 3 fail — the same 3 stale `catalog_sections_test.dart` tests as before
this pack. `widget_test.dart` was updated (`1 / 2` → `1 / 3`, mock prefs and
in-memory secret store).

**Not testable here:** the deployed Edge Function end to end (Termii, the auth
admin API, HTTP statuses) and real SMS — needs the two-phone checklist in
`BEFORE_YOU_BUILD.md` §6. I also could not re-probe the live database this
session (the CLI's temporary login role returned 403), so live
`auth.users` triggers and duplicate phone numbers were not checked; the SQL is
written to cope with both (profile insert is an upsert; the unique index is
guarded).

### Decisions beyond the prompt

- One Edge Function `signup` (actions `send`/`verify`/`complete`) instead of
  two; `phone-otp` untouched.
- Auth user via the admin API with a compensating delete, rather than writing
  GoTrue's tables from SQL (fragile across versions).
- A phone is "taken" only if **verified** on another account; an unverified
  legacy stub does not block it. Side effect: legacy `phone-otp` can now refuse
  to verify a number that is already verified elsewhere.
- `TOO_SOON` at step 1 counts as "a code is on its way" and moves on.
- Draft expiry counts from the last save; the app treats the proof as expired at
  29 min. If the keystore loses the password, resume lands on step 1.
- Step 2 system-back = Change number; step 3 back leaves and keeps the draft.
- Lost reply on "Finish setup": retry gets `PROOF_USED`; the app tries to sign
  in with the typed credentials and, if that works, treats it as created.
- Availability checks for nickname / matric / referral use the existing
  anon-callable RPCs, so those can still be probed one value at a time (as
  before); email/phone checks are rate-limited server-side.
- The unused `http` dependency was left in `pubspec.yaml`.

## Pack 4C — Admin menu sections, support options & names, rider name, stats rebuilt, ads popup & carousel, referral cleanup (2026-11-07)

Do-only-4C pack. Registration, gifting and the rider app were not touched.
SQL: `supabase/pack_4c.sql` (additive, safe to run once; re-running is
harmless). Edge Functions: none changed. Tests: `test/pack_4c_test.dart` (48),
`supabase/pack_4c_test.sql` (33 checks, rolled back),
`supabase/pack_4c_metric_check.sql` (raw tables vs dashboard function).

### Fixed (root causes)

- **Admin names blank / no rider name.** `profiles` RLS only lets a user read
  their own row, so every Admin screen that read a student or rider profile
  got nothing: blank names in the support inbox, "Unknown" riders in
  analytics, and the order cards simply never looked the rider up (they only
  tested `rider_id != null` and printed "Rider assigned"). New admin-only
  function `admin_profile_basics(uuid[])` + `adminProfileBasicsProvider`.
- **Menu sections disagreed.** Admin grouped by the old free-text `category`
  (and mapped "Food" to Others) while students group by `section` /
  `food_subsection`; the partner screen was a flat list; the partner
  availability switch re-saved the item without its section. One
  `VendorMenuManager` for Uniflex and every partner, grouped like students.
- **Dashboard / analytics.** Still leg-based: Uniflex-only, UTC days,
  `created_at` for completions, unpaid and cancelled mixed in, group items
  missing, revenue = sum of leg totals (food + fees blurred), pending = only
  placed/preparing, no live refresh. Rebuilt on one `_stat_entries()` (one row
  per paid checkout, errands included, Africa/Lagos days, single
  `completed_at`/`cancelled_at`); fees collected and food payments are two
  separate numbers; the screens only render what the functions return.

### Added

- Admin menu: Meals / Proteins-Toppings / Drinks / Others, each with its own
  "+ Add" (no category choice), availability, edit, remove, photo, vendor
  pack price — same widget for Uniflex and partners.
- Support: inbox rows + chat header show nickname with full name underneath;
  search by nickname, full name or phone. Student Help & Support → Live chat
  or WhatsApp (`wa.me`, prefilled "Hi, this is <nickname>." + short order id
  from an order). Admin: Manage → Support settings (one WhatsApp number;
  `0803…` / `+234803…` accepted; stored as international digits). No number →
  WhatsApp hidden and live chat opens directly.
- Order cards and details (deliveries and errands) show the rider's name once
  accepted; "Waiting for rider" before.
- Dashboard: Orders today, Pending / in progress, Completed today, Cancelled
  today, Fees collected and Food payments (today / week / month). Analytics:
  periods, completion rate, orders by status, top items, rider performance,
  users. Refresh on tab open, pull-to-refresh, refresh button and when orders
  change. `delivery_groups.final_paid_at` (stamped once by trigger; back-filled)
  dates final food payments.
- Ads: tapping any ad opens a centred rounded popup (whole image, X and
  outside-tap close, "Visit" only when the ad has a link). Form: image + one
  optional link (http/https, `https://` auto-added); "tap action" removed;
  existing links kept. Carousel: auto-advance 5 s, 0.8 s slide, loops, pauses
  while touched, dots; a single ad stays still.
- Referral (student side): own code, amounts, counts, leaderboard and referral
  badges removed. "Refer a student" says to contact Admin and opens Help &
  Support. Registration and Admin referral codes unchanged.

### Notes

- Carousel bug caught by its test before release: starting an endless pager
  at page 10000 showed ad `10000 % n`, not ad 0; it now starts on a multiple of
  the ad count.
- `dart fix --apply` was run so `flutter analyze` is clean (mechanical lint
  fixes in a few untouched files).

## Pack 4B — One order breakdown everywhere, rider app fixes, one-entry-per-checkout history (2026-11-07)

Do-only-4B pack. Registration, gifting and the Admin menu/ads/analytics/support
screens were not touched. Part B (old-logic audit) is a report only — see
`PACK_4B_AUDIT.md`; nothing was removed.

### Fixed (root causes)

- **A1 "Could not load item details".** `get_group_items` aggregated
  `jsonb_agg(vendor_row order by vendor_name)` — `vendor_row` is not a column
  of the sub-select, so every call on a real group raised `column
  "vendor_row" does not exist`. Riders have no SELECT policy on `order_items`
  / `order_packs`, so there was no fallback; the screen swallowed the error
  into the friendly message. Fix: `get_order_breakdown` (works before and
  after accepting) and the provider now logs the real error in debug.
- **A2 Admin "Pack 1 ₦0" + flat list; student vendor dropdown empty.**
  `order_packs` never stored a price (only `orders.pack_fee` in total), so
  Admin read `price` = null → ₦0, and listed items flat. The student screen
  loaded the legs with `select()` only — no `order_items` — so each vendor
  dropdown had nothing to show. Fix: `order_packs.price` (back-filled from
  `pack_fee / pack_count`, set on insert) and ONE `get_order_breakdown` +
  `OrderBreakdown` widget used by rider preview, rider active job, Admin and
  student.
- **A3 Rider Home "Active delivery" loads forever.** The Home banner opened a
  legacy stub with an *order* id, which redirected to `FoodJobScreen.active`
  keyed by a *group* id; the group lookup returned null and the screen showed
  a spinner for that case forever. Also the Home list only knew errands. Fix:
  null → "no longer available" view; Home "Active jobs" card from
  `rider_active_jobs()`; the Jobs tab is pool-only.
- **A4 three history entries / later group time.** History merged
  `delivery_records` (one per vendor part) with the group → 3 rows for a
  2-vendor delivery. The group had no completion time of its own, so screens
  used generic `updated_at`/created times, which move on later writes, and
  `DateTime.parse` UTC values were shown with their UTC hour. Fix: one
  `completed_at`/`cancelled_at` (`timestamptz`) stamped once with the server
  `now()` on group, parts and records in the PIN transaction (immutable
  afterwards); all screens read it through `.toLocal()`.

### Added

- `supabase/pack_4b.sql`: `get_order_breakdown`, `rider_job_pool`,
  `rider_active_jobs`, `rider_history`, `rider_history_item`, rewritten
  `get_rider_stats` / `get_dashboard_stats` (count checkouts), job cap of 3
  inside `accept_delivery_group` / `accept_order` (advisory lock +
  `ACTIVE_JOB_LIMIT`), single-timestamp triggers, privacy of customer info
  after a job ends.
- Rider: Home "Active jobs" card + chooser, Active lists, "Delivery complete"
  screen, read-only history details (no phone/email), "Cancelled by customer".
- Student: "Delivered" card with the time on tracking.
- Tests: `test/pack_4b_test.dart` (33 widget/unit tests),
  `supabase/pack_4b_test.sql` (60 checks, rolled back).

### Not done / decisions

- Part B: report + unapplied `pack_4b_removal_PENDING_APPROVAL.sql`.
- Finding for the owner: assigned riders can still read `delivery_pin` and fee
  columns directly from the tables (RLS) — see `PACK_4B_AUDIT.md` #1.

### Pack 4B follow-up — approved removals + rider lockdown (2026-11-07)

- **Security:** an assigned rider could read `delivery_pin`, the fee columns
  and a customer's other order data straight from `delivery_groups` /
  `orders` (RLS allowed the row, and RLS cannot hide columns). Riders now have
  **no** read policy on `delivery_groups`, `orders` or `errand_requests`. They
  use `rider_job_pool / rider_active_jobs / rider_history(_item) /
  rider_group_detail / get_order_breakdown / get_group_customer_info`. Live
  refresh comes from `rider_job_signals` (ids only, riders-only read, pruned
  hourly) plus a 45 s safety refetch.
- **Removed (R1–R4, R7):** `get_group_items`, the sourcing / flag-item /
  custom-item functions and tables, `cancel_delivery_group_before_accept`,
  `any_riders_available`, `_delivery_fee_from_settings`, the
  `check_group_ready` kitchen→group trigger (it could flip a group to
  awaiting-payment with no rider or price), and `delivery_records` (verify
  functions no longer write it). `pack_4b.sql` must not be re-run after this
  (its back-fill reads `delivery_records`).
- **R8:** `_after_order_placed` counts `total_orders` once per checkout. Old
  counts were not rewritten.
- **Kitchen queue** lists only pickup orders (no delivery parts); the
  "Transfer to Rider" and rider-status UI were removed. `transfer_order_to_rider`
  still exists in SQL, unused.
- **Dart:** deleted the redirect stubs, `delivery_record`, `pool_group`,
  `pool_order`, `adjust_order_screen`, `custom_order_item` and the custom-item
  helpers. Student order list never shows a vendor part on its own.
- Tests: SQL 69/69 (rider reads no table rows, PIN unreadable, students/admin
  unaffected, counting, trigger gone); Dart 195 pass (+ same 3 old failures).
- Not done: R9 (test accounts), `around` / standalone-food sourcing Dart branches.

## Pack 4A — Payment-first checkout, ₦30 service charge, one notification pipeline, support chat repair, cart notice (2026-11-07)

Do-only-4A pack. Rider screens, Admin screens (except the new Service charge
page), registration and gifting were not touched.

### Fixed (root causes)

- **The checkout button created the order before it was paid.** "Place order"
  called `placeMultiVendorOrder`, which wrote a `delivery_groups` row + one
  `orders` leg per vendor (status `placed`, unpaid), **cleared the cart** and
  invalidated the order providers — and only then opened the Commitment Fee
  page, where paying finally moved the group to `commitment_paid` (the rider
  pool). Nothing in Admin lists, the kitchen queue, student lists or analytics
  filtered by payment status, so the unpaid legs showed up as a half-formed
  order. Fix: the button is now **Continue** and only validates; the order is
  created by a single paid RPC after PIN + debit. Backing out, a wrong PIN or
  a low balance leave nothing behind and the cart intact.
- **No notification when the rider sent the final price.** Order
  notifications came only from client code (Kitchen/Rider screens calling
  `notify-user` after a *standalone-order* status change, plus a local banner
  in `StudentShell` while the app was open). The Fix Pack 2 delivery-group
  flow (accept, set price, pay, decline, deliver) never called either, and
  `notify-user` only understood `orders` ids. Fix: database triggers now write
  the inbox row and a second trigger pushes it.
- **Support chat: direct message and Admin reply failed; order attach showed
  no chip.** `support_chat.sql` created `send_support_message(text, uuid,
  uuid)`; `fix_pack_1.sql` then created `send_support_message(text, uuid,
  uuid, uuid)` — a *second* function. Any call that omits `p_group_id`
  (direct student message, Admin reply, order-only message) matches both, and
  PostgREST answers "could not choose the best candidate function". Only the
  group-attached call matched one overload, so it "went through" — and its
  chip never showed because both bubbles looked at `order_id` only, never
  `delivery_group_id`. (Reproduced on a real Postgres: `function
  send_support_message(p_body => unknown) is not unique`.) Fix: `pack_4a.sql`
  drops every overload and creates exactly one of each support function; both
  bubbles show the chip for an order **or** a group; Admin taps it to open the
  order.
- **"Your cart was cleared…" appeared on a brand-new cart.** Not a persisted
  flag: `CartNotifier._expiredOnLoad` was an in-memory flag set when a stale
  saved cart was dropped at startup and **never reset**, and the provider
  lives for the whole app session, so `CartScreen` re-showed the snackbar
  every time it opened. Removed entirely; expired carts clear silently.
- **First-time "Set PIN" was ambiguous.** Found while testing:
  `set_transaction_pin` also existed twice, `(text)` and `(text, text
  default null)`, so a call sending only `p_pin` could not resolve. The pack
  keeps one. (Same bug class as the support chat.)

### Added

- **Payment page** (`CommitmentFeeScreen`, rebuilt on the shared
  `runPaymentFlow`): each vendor's delivery fee as its own line, the service
  charge once, the total, wallet balance with a top-up prompt. Pickup shows
  the full food amount only.
- **Three atomic RPCs** — `create_paid_delivery_order`,
  `create_paid_pickup_order`, `create_paid_errand`. Each: idempotency check →
  PIN → server-computed amounts → wallet lock + balance check → debit →
  create everything. Idempotency via `order_payment_attempts` (one UUID per
  payment page; a repeated key returns the existing order). The client sends
  choices only (ids, quantities, pack allocation, location id); the errand fee
  now comes from `errand_categories`, not the client.
- **₦30 service charge**, admin-editable (`app_settings`, `get_service_charge`,
  `admin_set_service_charge`), once per delivery/errand, never on pickup,
  stored on each order. **Manage → Service charge** screen.
- **Notification pipeline** — triggers on `delivery_groups` / `orders` /
  `support_messages` → `queue_notification()` → `notifications` row →
  `notifications_push` trigger → `push-notification` Edge Function. Events:
  rider accepted, final price (and every change), customer paid, cancelled
  by customer / by admin, delivered, ready for pickup, support messages.
  Push taps (including a cold start and a merely-backgrounded app) route to
  the right screen and mark the notification read; the in-app banner shows
  without storing a duplicate. `notifications` gained `type`, `group_id`,
  `conversation_id`.
- **One-time cart notice**: "Your cart will be cleared 1 hour after your last
  change." — first add to an empty cart only (`CartNoticeListener`).
- Legacy unpaid orders are flagged `is_paid = false` and hidden by
  RESTRICTIVE RLS (orders + delivery_groups) and the dashboard stats RPC;
  `pack_4a_queries.sql` lists them and has an optional "mark cancelled".
- `supabase/pack_4a.sql`, `pack_4a_test.sql` (76 checks, rolls back),
  `pack_4a_queries.sql`; `functions/push-notification/`;
  `test/pack_4a_test.dart` (24 tests).

### Changed

- `notify-user` no longer pushes by itself (the trigger does) and attaches
  `group_id`; clients no longer call it for status changes
  (`notifyOrderStatus` removed from `AdminService` / `RiderService`).
- `StudentShell`'s order-status local-notification listener removed.
- `get_dashboard_stats` ignores unpaid orders.
- Checkout: location dropdown is `isExpanded`; total rows no longer overflow
  on long vendor names.

### Removed

- Client: `placeFoodOrder`, `placeMultiVendorOrder`, `placePartnerFoodOrder`,
  `placeErrandRequest(Staged)`, `OrderNotifier`/`OrderPlacementState`,
  `MultiVendorOrderResult`, the old `CommitmentFeeScreen` modes, the dead
  `errand_screen.dart`, and the "cart was cleared" snackbar.
- Server (functions only, no data): `place_multi_vendor_order`,
  `pay_group_commitment_fee`, `pay_commitment_fee`, `place_errand_order`,
  `place_errand_with_payment`, `place_around_order`,
  `place_around_with_payment`, `place_partner_food_order`,
  `place_food_order_with_payment`.

### Now unused (kept, nothing dropped)

`delivery_groups` status `placed` for new rows, `pay_final_amount` /
`confirm_sourced_items` (legacy single-order flow), Edge Function
`support-notify` (replaced by `push-notification`), `notify-user`'s
`order_status` mode, `delivery_settings` campus/hostel fee keys.

### Known / not done here

- Rider screens do not route push taps yet and there is no rider inbox
  (rider notification rows are stored and pushed) — Pack 4B.
- `send_gift` and `checkout_group_order` each exist as two overloads in the
  repo's SQL history (same ambiguity risk); gifting was out of scope.
- 3 tests in `test/catalog_sections_test.dart` fail on the commit before this
  pack too (stale since the Round 8 accordion UI).

## Fix Pack 3 — Image Upload, Advertisements & Soft Delete (2026-11-05)

### Fixed

- **Image upload was silently broken** — the `product-images` storage
  bucket section in `schema.sql` was commented out, so no bucket ever
  existed. Every `uploadBinary` call failed immediately. `fix_pack_3.sql`
  creates the bucket with a 5 MB per-object limit and the correct
  `image/jpeg`, `image/png`, `image/webp` MIME whitelist.

- **Product availability toggle crashed silently** — `_toggleAvailability`
  in `MenuManagementScreen` called `upsertProduct` without forwarding
  `section` and `foodSubsection`. The defaults (`section='food'`,
  `food_subsection=null`) violated the DB CHECK constraint
  `products_subsection_only_for_food`, so the UPDATE was rejected on the
  server and the UI reverted without an error message. The fix passes the
  existing product's `section` and `foodSubsection` through the call.

- **Product / vendor delete was hard-blocked by FK** — `order_items`
  references `products.id` without `ON DELETE CASCADE`; `errand_requests`
  references `errand_categories.key` without cascade. Any row referenced
  by historical orders could not be deleted. Fixed with **soft delete**:
  `deleteProduct`, `deleteVendor`, and `deleteErrandCategory` now write
  `deleted_at = NOW()` instead of running `DELETE`.

- **`AdLinkType.fromName` returned `vendor`/`wallet` for legacy rows** —
  the `fromName` switch mapped those values to the enum variants of the
  same name. After the Fix Pack 3 migration those variants no longer exist
  in the DB, but the fix also makes old pre-migration rows safe to read:
  any unknown or legacy link type now falls through to `AdLinkType.none`.

### Added

- **`lib/shared/widgets/image_upload/image_upload_field.dart`** — shared
  `ImageUploadField` widget used by all three admin form screens
  (products, vendors, advertisements). Handles: gallery pick via
  `image_picker`, center-crop to square (optional, controlled by
  `cropToSquare`), resize (long side capped at 1200 px), JPEG encode at
  quality 80, upload progress overlay, preview on success, error strip
  with Retry, clear button to remove the current image.

- **`supabase/fix_pack_3.sql`** — 11-section idempotent migration:
  storage bucket + 4 RLS policies; `deleted_at` on `products`,
  `vendors`, `errand_categories`; updated student read policies that
  exclude soft-deleted rows; `place_multi_vendor_order` guard rejecting
  unavailable/deleted items; advertisement migration converting legacy
  `vendor`/`wallet` link types to `none`; narrowed `link_type` CHECK
  constraint to `('none', 'url')` only.

- **`supabase/fix_pack_3_test.sql`** — rollback-safe SQL test script:
  soft-delete column presence, storage bucket public, ad link_type
  constraint enforcement, deleted-row filtering for products/vendors/
  errand categories, subsection constraint still enforced.

- **`test/fix_pack_3_test.dart`** — 23 pure unit tests (all passing):
  URL auto-prepend logic, `AdLinkType.fromName` backward compat (vendor
  → none, wallet → none, null → none, garbage → none), `Advertisement.isLive`
  schedule logic, `Product` section constraint round-trip via
  `toMap`/`fromMap`, availability flag parsing, center-crop pixel math.

### Changed

- **Advertisements** — link type options narrowed to **Nothing** and
  **Opens a website** only. Vendor and wallet link types are removed from
  the admin form. The URL field validates the link before save and
  auto-prepends `https://` if the admin types a bare domain. External
  links open in the system browser (`LaunchMode.externalApplication`)
  with a friendly SnackBar on failure.

- **Admin form screens** — `ProductFormScreen`, `VendorFormScreen`, and
  `AdvertisementFormScreen` all replaced inline image-picker logic with
  the shared `ImageUploadField`. Vendor photo upload (previously
  missing) is now wired in. Ad banner uses `cropToSquare: false`;
  products and vendors use `cropToSquare: true`. Suggested ad banner
  size noted in the hint: **1200 × 460 px (~2.6:1)**.

- **`AdminService`** — added `uploadVendorImage`; refactored all three
  upload methods through a shared `_uploadImage(prefix, bytes, fileName)`
  helper that writes into `product-images/{prefix}/` paths.
  `fetchAllVendorProducts` and `fetchAllVendors` filter out soft-deleted
  rows with `.is_('deleted_at', null)`.

## Fix Pack 2 — Delivery Flow Overhaul (2026-11-05)

### Changed

- **Unified delivery lifecycle** — `delivery_groups` is now the single
  canonical entity for all deliveries (single-vendor included). The old
  Uniflex-special-casing (`source='uniflex'` branching) is removed from
  all RPCs. Every delivery goes through the same status ladder:
  `placed → commitment_paid → rider_accepted → awaiting_final_payment
  → out_for_delivery → completed` (or `cancelled`).

- **Rider flow rebuilt** — replaced the old per-vendor flag/confirm
  workflow with two purpose-built job screens:
  - **`lib/rider/jobs/food_job_screen.dart`** — covers both preview (from
    pool) and active job views. Single vendor → flat item list;
    multi-vendor → `AppAccordionCard` accordions all closed by default.
    Status stepper, customer card with Call/WhatsApp, `_EnterPriceSheet`
    to set final delivery price, PIN entry to complete.
  - **`lib/rider/jobs/errand_job_screen.dart`** — same pattern for errands.
    Two-step stepper: Accepted → Completed.

- **Job pool screen** (`lib/rider/pool/job_pool_screen.dart`) — now shows
  food groups and errands in a single unified stream. FOOD (green) and
  ERRAND (violet) badge chips; cards open detail screens before accepting.

- **Removed from rider flow** — per-vendor pickup confirm, flag item
  unavailable, add custom item, item sourcing confirm, `AdjustOrderScreen`.
  `ActiveDeliveryScreen` and `GroupDeliveryScreen` are now stubs that
  redirect to `FoodJobScreen`.

- **Student tracking** (`lib/student/tracking/order_tracking_screen.dart`)
  — updated for the new lifecycle:
  - 5-step `_GroupStatusTimeline`: Placed / Rider Accepted / Final Price
    Sent / Out for Delivery / Completed.
  - `_GroupFinalPaymentCard`: Pay + Decline buttons appear when status is
    `awaiting_final_payment`. Decline confirmation → cancels order.
  - `_GroupDeliveryConfirmedCard`: tappable PIN digit boxes when status is
    `out_for_delivery`.
  - Removed: custom-items approval panel, `AdjustOrderScreen` button.

- **Admin orders screen** (`lib/admin/orders/admin_orders_screen.dart`)
  — rebuilt with 2 tabs (Deliveries / Errands), filter chips
  Active/Completed/Cancelled, search bar, and navigation to
  `AdminOrderDetailsScreen`. Kitchen Queue for deliveries removed.

- **Admin order details** (`lib/admin/orders/admin_order_details_screen.dart`)
  — new screen covering both groups and errands: status badge, customer
  info, rider, item breakdown with packs, fees, timeline, cancel action.

### Added

- **`supabase/fix_pack_2.sql`** — 15-section idempotent migration:
  - Adds `rider_accepted` to `delivery_groups` status constraint.
  - Adds `rider_accepted_at` and `cancelled_by_student` columns.
  - Rider RLS: pool view (commitment_paid groups) + assigned view.
  - New/replaced RPCs: `accept_delivery_group` (NOWAIT race-safe),
    `set_delivery_group_final_price`, `pay_group_final_amount`,
    `decline_group_final_amount`, `cancel_delivery_group_before_accept`,
    `get_group_customer_info` (redacts PIN until `out_for_delivery`),
    `get_group_items`, `pay_group_commitment_fee` (source branching removed),
    `place_multi_vendor_order` (rejects `scheduled_for` on delivery),
    `verify_group_delivery` (graceful `delivery_records` insert).
  - `delivery_groups` added to `supabase_realtime` publication.

- **`supabase/fix_pack_2_test.sql`** — rollback-safe SQL test script:
  schema column checks, status constraint, RPC existence, final-price
  guard validation, `scheduled_for` on delivery rejection,
  Realtime publication check.

- **`test/fix_pack_2_test.dart`** — 30 pure unit tests: `DeliveryGroupStatus`
  enum roundtrip + labels, `DeliveryGroup` model parsing, `GroupCustomerInfo`
  fromMap + displayName + PIN redaction, `GroupLineItem` lineTotal + section
  helpers, `GroupPack` label, final-price acceptance range.

- **Fix Pack 1 (2026-11-04)** — also included in this deploy:
  - `supabase/fix_pack_1.sql`: adds `delivery_group_id` to
    `support_messages`, updates `send_support_message` RPC.
  - `lib/shared/models/support_message.dart`: `deliveryGroupId` field.
  - `lib/shared/services/connectivity/connectivity_service.dart`:
    OS network + reachability probe singleton.
  - `lib/shared/widgets/connectivity/connectivity_banner.dart`:
    offline (red) / restored (green auto-hide) banner wired into app root.

## Support Chat (2026-11-04)

### Added

- **Student ↔ Admin support chat** — live two-way messaging between students and
  the admin team. One conversation per student; admins share a single inbox.
  - **`supabase/support_chat.sql`** — `support_conversations` and
    `support_messages` tables; RLS (students see own, admins see all, no client
    writes); Realtime publication; RPCs: `send_support_message`,
    `mark_support_read`, `resolve_support_conversation`,
    `get_support_unread_total`; optional pg_net trigger for push.
  - **`supabase/functions/support-notify/index.ts`** — push dispatcher called
    after new messages; student → all admins, admin → that student; clears stale
    FCM tokens on delivery failure.
  - **`lib/shared/models/support_conversation.dart`** — `SupportConversation`
    model (one per student; open/resolved status; unread counts for both sides).
  - **`lib/shared/models/support_message.dart`** — `SupportMessage` model
    (sender_role, sender_name snapshot, optional order_id).
  - **`lib/shared/services/support/support_chat_service.dart`** —
    `SupportChatService` with Realtime-backed streams; Riverpod providers:
    `myConversationProvider`, `allConversationsProvider`,
    `conversationMessagesProvider`, `adminSupportUnreadProvider`.
  - **`lib/student/support/support_chat_screen.dart`** — Student chat screen:
    chat bubbles, date separators, resolved banner, removable order chip for
    "get help with this order" flow, rate-limit and retry error display,
    double-tap-guarded send button.
  - **`lib/admin/support/admin_support_inbox_screen.dart`** — Admin inbox: all
    conversations; filter chips Open/Resolved/All; name/preview search; unread
    badges; sorted newest-first; live Realtime updates.
  - **`lib/admin/support/admin_support_chat_screen.dart`** — Admin chat view:
    student name + phone in header; "Mark resolved" with confirmation; each
    admin message shows their own name on the bubble; order chip display.
  - **`test/support/chat_widgets_test.dart`** — 23 unit tests covering models,
    unread count logic, filters, date separators, message ordering, content
    validation; all passing.
  - **`supabase/support_chat_test.sql`** — SQL test script (runs in a rolled-back
    transaction): tests CHECK constraints, unique constraint, unread arithmetic,
    conversation reopen, rate-limit counter, `ON DELETE SET NULL` for order_id.

### Changed

- **`lib/student/profile/student_profile_screen.dart`** — Added "Help & Support"
  row in the More section with a live unread badge from `myConversationProvider`.
- **`lib/admin/manage/manage_hub_screen.dart`** — Added "Support" entry with
  unread badge from `adminSupportUnreadProvider`.
- **`lib/admin/admin_shell.dart`** — Added `badgeCounts` to pass support unread
  count to the Manage bottom-nav badge; push tap routing to `AdminSupportInboxScreen`.
- **`lib/student/student_shell.dart`** — Added push tap routing to
  `SupportChatScreen` on support notifications.
- **`lib/student/tracking/order_tracking_screen.dart`** — Added "Get help with
  this order" `OutlinedButton` in both standalone and group tracking views (only
  shown for non-terminal orders); pre-fills the order chip in the chat.
- **`lib/shared/widgets/navigation/app_bottom_nav_shell.dart`** — Added optional
  `badgeCounts: List<int>?` parameter; non-zero counts render a `Badge` on the
  corresponding `BottomNavigationBarItem` icon.
- **`lib/shared/services/notifications/notification_service.dart`** — Added push
  tap handlers (`onMessageOpenedApp`, `getInitialMessage`), `consumePendingNavigation()`;
  clears FCM token from DB on `AuthChangeEvent.signedOut`.
- **`supabase/functions/send-notification/index.ts`** — Added UNREGISTERED token
  cleanup: when FCM returns `UNREGISTERED`, the stale `fcm_token` is set to NULL
  in `profiles`.

---

## Round 9 — Admin & Rider Audit, Phase B (2026-11-04)

### Added

- **`lib/admin/orders/admin_orders_screen.dart`** — New tabbed order management
  screen (Food | Deliveries | Errands). Super admin sees all three tabs. Kitchen
  staff still see only the Food tab (same kitchen queue content, no tab bar).
  - Food tab: re-uses `KitchenQueueBody` extracted from `kitchen_queue_screen.dart`.
  - Deliveries tab: streams all non-terminal `delivery_groups` via
    `adminDeliveryGroupsProvider`; filter chips (All / Waiting / With Rider);
    each card shows vendor stops, delivery location, rider status; Cancel button
    with optional reason → calls `admin_cancel_delivery_group` RPC.
  - Errands tab: streams non-terminal errand orders via `adminErrandOrdersProvider`;
    filter chips (All / Open / In Progress); each card shows category, pickup,
    drop-off, item description, rider status; Cancel button → calls
    `admin_cancel_order` RPC.
- **`KitchenQueueBody`** extracted from `KitchenQueueScreen` — reusable body-only
  widget so the kitchen queue list can be embedded in any tab without nested scaffolds.
- **`AdminDeliveryGroupRow` / `AdminErrandRow`** model classes in
  `admin_service.dart` — carry enriched data for the admin order cards.
- **`streamAllDeliveryGroups()` / `streamErrandOrders()`** in `AdminService` —
  live Realtime-backed streams for the two new tabs; each enriches the rows with
  vendor names or errand request details in a single batch query.
- **`adminCancelOrder()` / `adminCancelDeliveryGroup()`** in `AdminService` —
  wrappers for the `admin_cancel_order` and `admin_cancel_delivery_group` RPCs
  written in Phase A.
- **`adminDeliveryGroupsProvider` / `adminErrandOrdersProvider`** in
  `admin_providers.dart`.

### Fixed

- **Analytics double-count** (`admin_service.dart:getAnalytics()`): the month
  orders query now filters `delivery_group_id IS NULL` so delivery group legs
  are not counted multiple times. A separate `delivery_groups` query adds group
  counts + revenue so multi-vendor checkouts register as one order each.
  `ordersThisMonth` is now `standalone_orders + delivery_groups`.
- **Admin shell** (`admin_shell.dart`): super_admin Orders tab now points to
  `AdminOrdersScreen` instead of `KitchenQueueScreen`.
- **Dashboard label** (`admin_dashboard_screen.dart`): `"Scheduled (Placed)"`
  → `"Placed"` in the Kitchen Stages breakdown.

---

## Round 9 — Admin & Rider Audit, Phase A (2026-11-03)

### Fixed

- **Rider pool — errand filter** (`rider/services/rider_service.dart`): client-side
  filter was checking `status == 'being_sourced'` for errands. After Round 8,
  errands use `status='placed' AND commitment_fee_paid=true`. Fixed to match.
  Legacy `around` orders still use `being_sourced` for backward compat.
- **Kitchen queue stale delivery_type labels** (`admin/kitchen/kitchen_queue_screen.dart`):
  removed `'campus_delivery' => 'Campus'` and `'hostel_delivery' => 'Hostel'`
  cases; now `'delivery' => 'Delivery'` and `_ => 'Pickup'`.
- **Group delivery screen stale labels** (`rider/delivery/group_delivery_screen.dart`):
  same cleanup — `'pickup' => 'Pickup'` and `_ => 'Delivery'`.
- **Job pool screen stale labels** (`rider/pool/job_pool_screen.dart`): same fix.
- **pool_order.dart comment** — updated doc comment to say "Errand" not "Around".

### Added

- **`supabase/round9_cancel.sql`** — four cancel RPCs:
  - `student_cancel_order(uuid)` — race-safe, fails if rider already accepted.
  - `student_cancel_delivery_group(uuid)` — same for multi-vendor checkouts.
  - `admin_cancel_order(uuid, text)` — admin cancels any non-terminal standalone order.
  - `admin_cancel_delivery_group(uuid, text)` — admin cancels group + all legs.
  - No automatic refunds on any cancellation (existing policy).
- **Student cancel button** — `_OrderCard` and `_GroupCard` in `orders_screen.dart`
  and `_ErrandOrderCard` in `student_home_screen.dart` now show a Cancel action
  when `riderId == null && !isTerminal`. Confirm dialog required. Races handled
  server-side by the RPC; client shows a clear error message if a rider accepted
  simultaneously.
- **`cancelOrder` / `cancelDeliveryGroup` / `mapCancelError`** — public helpers
  in `order_repository.dart` used by all cancel buttons.

### SQL to run

```
supabase/round9_cancel.sql  — run once in Supabase SQL Editor
```

---

## Round 8 — Unified orders, location-based fees, UI polish, bug fixes (2026-11-02)

### Summary

Six workstreams: (A) unified order identity — delivery orders display as a
single entry via `delivery_groups` instead of per-vendor legs; (B) delivery
locations replace old campus/hostel fee types — named locations with
pack-bracket pricing; (C) Around → Errand rename across all 22 files;
(D) acknowledgment sheets before payment + double-tap guards; (E) accordion
UI for vendor page, pack builder, and cart; (F) bug fixes for search,
mark-all-read, and see-all vendors.

### Added

- **`delivery_locations` table** — named delivery destinations with base
  prices (seeded: Engineering Hostel ₦300, Queen Esther Hall ₦200, etc.).
  Admin CRUD via `upsert_delivery_location` / `delete_delivery_location` RPCs.
- **`DeliveryLocation` model** (`shared/models/delivery_location.dart`).
- **`deliveryLocationsProvider`** — fetches active locations via
  `get_delivery_locations()` RPC.
- **`packBrackets(int)` / `vendorDeliveryFee(double, int)`** — pack-bracket
  fee calculation: `location.price × ceil(packs / 3)`, zero packs = 1×.
- **`search_products` RPC** — server-side product search (ILIKE, joined with
  vendor name, limited to 50 results).
- **`SearchScreen`** (`student/home/search_screen.dart`) — full-screen search
  with 300ms debounce, replaces "Search coming soon" snackbar.
- **`AllVendorsScreen`** (`student/home/all_vendors_screen.dart`) — lists all
  active vendors, "See all" now navigable from home.
- **`acknowledgment_sheet.dart`** (`shared/widgets/sheets/`) — modal
  bottom sheet with message + Continue button, shown before delivery checkout,
  commitment fee payment, and errand confirmation.
- **`StudentOrderEntry` union type** — unified display for delivery groups and
  standalone orders in the student orders list.
- **`OrderTrackingScreen.forGroup`** — group tracking with status timeline
  and per-vendor leg breakdown.
- **16 unit tests** (`test/round8_test.dart`) — pack brackets, vendor delivery
  fee, worked example, DeliveryLocation model.

### Changed

- **Around → Errand rename** — 22 files: `around_categories` → `errand_categories`,
  `around_requests` → `errand_requests`, all model/provider/screen class names
  and labels updated. Home toggle "Around" → "Errand".
- **Checkout screen** — delivery uses named locations dropdown + compulsory
  "Location details" field instead of campus/hostel toggle. Fee calculated
  per-vendor using pack brackets.
- **Admin delivery settings** — CRUD for `delivery_locations` table replaces
  the old key-value `delivery_settings` screen.
- **Commitment fee screen** — removed `deliveryFeePerVendor` param (fee now
  server-computed with pack brackets). Fee breakdown shows total with vendor
  count.
- **Errand screen** — optional delivery location dropdown for drop-off area.
- **Catalog screen** — Drinks and Others sections now expandable accordions
  (collapsed by default). Food section unchanged.
- **Pack builder screen** — Meals and Proteins/Toppings now expandable
  accordions (collapsed by default).
- **Cart screen** — single vendor: flat list (no header). Multiple vendors:
  expandable sections, first open by default.
- **Student home screen** — search bar navigates to `SearchScreen`. "See all"
  navigates to `AllVendorsScreen`. `_SectionHeader` gained `onAction` callback.
- **Notifications screen** — mark-all-read now invalidates provider after
  completion (was silently not refreshing).
- **Double-tap guards** — `_isSubmitting` flag added to checkout, commitment
  fee, and errand submit handlers.
- **Student orders screen** — queries `delivery_groups` for delivery orders
  and standalone `orders` for pickup/errands, presenting unified entries.

### SQL Migration

- `supabase/round8_migration.sql` — idempotent, run once in Supabase SQL
  Editor. Creates `delivery_locations` table + RPCs, renames around →
  errand tables, adds `delivery_location_id`/`location_details` to
  `delivery_groups` and `orders`, updates `place_multi_vendor_order` with
  pack-bracket fee calculation, adds `search_products` RPC.

## Round 8 Bug Fixes (2) — Errand payment flow, delivery_type constraint, rider pool (2026-11-03)

### Fixed

- **Errand payment flow** — errand screens (`ErrandScreen`, `CreateErrandScreen`)
  now call `place_errand_with_payment` (single upfront payment) instead of the
  two-step staged flow (`place_errand_order` + `CommitmentFeeScreen`). The
  correct sequence is: acknowledgment sheet → check/set PIN → PIN entry →
  atomic fee deduction + order creation → `ErrandConfirmationScreen`.
- **`delivery_groups.delivery_type` constraint** — the CHECK constraint only
  allowed `('pickup','campus_delivery','hostel_delivery')` but Round 8 sends
  `'delivery'`. `round8_bugfix.sql` migrates existing rows and narrows the
  constraint to `('pickup','delivery')`.
- **`pay_commitment_fee` guard** — now rejects `type in ('errand','around')`
  orders with a clear exception. Errand orders must never reach this function.
- **Rider pool (`job_pool_read`)** — updated policy includes
  `type='errand' AND status='placed' AND commitment_fee_paid=true` so errand
  orders are visible to riders after payment.
- **`accept_order`** — now handles `type='errand'`: eligibility check requires
  `status='placed' AND commitment_fee_paid=true`; on accept, status advances to
  `'being_sourced'` ("Rider assigned" in the errand timeline).
- **`confirm_pickup`** — errand orders now advance to `status='out_for_delivery'`
  ("On the way") when the rider confirms pickup.
- **Errand orders routing** — `_OrderCard` in `OrdersScreen` now routes
  `order.isErrand` to `ErrandTrackingScreen` instead of `OrderTrackingScreen`.

### Added

- **`ErrandConfirmationScreen`** (`student/errand/errand_confirmation_screen.dart`) —
  errand-specific confirmation: "Your errand has been sent. A rider will call
  you." + Track errand button → `ErrandTrackingScreen` + Back to home.
- **`supabase/round8_bugfix.sql`** — idempotent SQL fixing all 6 database-level
  bugs above. Run once in Supabase SQL Editor after `round8_migration.sql`.

---

## Round 8 Fixes — Errand page rebuild, AppAccordionCard, Create errand form (2026-11-03)

### Added

- **`AppAccordionCard`** (`shared/widgets/accordions/app_accordion_card.dart`) —
  shared accordion widget with emerald border when open, `AnimatedSize` 200ms
  content reveal, animated chevron rotation, and `buildAccordionLeadingIcon`
  helper. Replaces three separate inline accordion implementations.
- **`CreateErrandScreen`** (`student/errand/create_errand_screen.dart`) —
  standalone full-screen errand form: category dropdown (from
  `activeErrandCategoriesProvider`, no preselection), required description
  field, optional pickup/drop-off/location-details fields, pay button enabled
  only when category + description filled. No "non-refundable" wording.
- **`ErrandTrackingScreen`** (`student/tracking/errand_tracking_screen.dart`) —
  simplified tracking for errand orders: 4-step timeline (placed → rider
  assigned → on the way → done), rider name + Call + WhatsApp buttons once
  assigned, delivery PIN, fee display. No sourcing/final-payment steps.

### Changed

- **Student home screen (Errand mode)** — replaced category grid and rider
  availability widget with `_ErrandSection`: State A (no active errands —
  centred icon + copy + Create errand button) and State B (active errand cards
  + button). Category tiles never appear on the home screen.
- **Catalog screen** — Drinks and Others now use `AppAccordionCard`.
- **Pack builder screen** — Meals and Proteins/Toppings now use `AppAccordionCard`.
- **Cart screen** — multi-vendor groups now use `AppAccordionCard` with vendor
  image leading, vendor subtotal in subtitle, and remove confirmation dialog.
- **Commitment fee screen** — errand orders show errand-specific wording
  (no "non-refundable" copy anywhere in the errand payment flow).

### Removed

- `_ErrandServiceGrid`, `_ErrandServiceCard`, `_RunnersOnline` from
  `student_home_screen.dart`.
- `ridersAvailableNearbyProvider` from `errand_category_providers.dart`
  (was only used by `_RunnersOnline`).

### SQL (run manually)

```sql
-- Seed "Others" errand category (sort_order 6, after Moving Items)
INSERT INTO errand_categories (key, title, subtitle, description, icon_name, flat_fee, is_active, sort_order)
VALUES ('others', 'Others', 'Something else', 'For errands that don''t fit the other categories.', 'explore', 800, true, 6)
ON CONFLICT (key) DO NOTHING;
```

### Tests

- 16 new Round 8 unit tests (all passing).
- 23 existing Round 7 unit tests still passing.

---

## Round 7 Hotfix — Empty vendor menus, pack builder UI (2026-11-02)

### Root cause

Round 7 SQL migration added a `CHECK` constraint
(`products_subsection_only_for_food`) **before** running the backfill
`UPDATE`s. All existing products had `section='food'` (column default) with
`food_subsection=NULL`, violating the constraint. The `DO` block's exception
handler only caught `duplicate_object`, not `check_violation`, so the entire
Supabase SQL Editor transaction rolled back. No columns were added, no data
was backfilled. The client defaulted every product to `section='food'` with
`null` subsection — `isMeal` and `isProteinTopping` both returned false,
leaving the pack screen empty and Drinks/Others sections hidden.

### Fixed

- **schema.sql**: moved cross-column constraint to **after** the backfill
  `UPDATE`s so existing rows satisfy it before it's created.
- **hotfix_product_sections.sql**: standalone idempotent script to add columns,
  backfill, and add the constraint in the correct order on a live database.
- **CatalogScreen**: all 3 sections (Food, Drinks, Others) now render
  unconditionally. Empty sections show an italic placeholder message. Products
  with unknown/null `section` fall into Others with a `dev.log` warning.

### Changed

- **Pack count selector**: redesigned with large centered number, 52px circular
  +/- buttons, "How many packs of food?" label, and price/total below.
- **Spoon counter**: removed the visible "X / 8 meal spoons" text. The 8-spoon
  limit is still enforced. A warning banner now appears only when the pack is
  full: "This pack is full. Add another pack to get more." with an inline
  "Add pack" button.

### Tests

- 3 new widget tests (`catalog_sections_test.dart`): verifies all 3 section
  headers render, empty sections show placeholders, unknown sections route
  to Others.
- 23 existing round7 unit tests still pass.

---

## Round 7 — Pack-first ordering, vendor menu structure, multi-vendor cart, delivery groups (2026-11-02)

### Summary

Four workstreams: (A) pack-first ordering — choose pack count before filling
packs, with an 8-spoon capacity limit per pack; (B) vendor menu structure with
DB-backed `section` ('food'|'drinks'|'others') and `food_subsection`
('meal'|'protein_topping') fields; (C) multi-vendor cart allowing items from
multiple vendors in a single checkout, creating `delivery_groups` with
per-vendor order legs; (D) delivery fee = commitment fee, admin-editable via
`delivery_settings` table.

### Added

- **`delivery_groups` table** — parent record for multi-vendor checkouts with
  `status`, `rider_id`, `delivery_pin`, `delivery_stage`, `commitment_fee_total`,
  `final_amount`, `student_note`, `delivery_location`, `delivery_type`.
- **`delivery_settings` table** — admin-editable key-value store for
  `campus_delivery_fee` (default ₦200/vendor) and `hostel_delivery_fee`
  (default ₦300/vendor).
- **`place_multi_vendor_order` RPC** — creates a delivery group + per-vendor
  order legs without wallet deduction. Returns `{group_id, commitment_fee_total}`.
- **`pay_group_commitment_fee` RPC** — deducts fee from wallet, advances
  Uniflex legs to `preparing`, partner legs to `being_sourced`.
- **`accept_delivery_group` RPC** — assigns rider to entire group with
  `FOR UPDATE NOWAIT` to prevent double-accepts.
- **`confirm_group_leg_pickup` RPC** — marks individual vendor leg as picked up.
- **`verify_group_delivery` RPC** — PIN verification + completion for whole group.
- **`_check_group_ready_after_kitchen` trigger** — auto-advances group when all
  Uniflex legs reach `ready` status.
- **`get_delivery_settings` / `update_delivery_setting` RPCs** — read/write
  delivery fee settings.
- **`pack_constants.dart`** — shared `kPackMealCapacity = 8` constant.
- **`PackBuilderScreen`** — replaces old `PackAllocationScreen`; pack-first
  flow with per-pack meal capacity bar, meal vs protein_topping separation.
- **`GroupDeliveryScreen`** — multi-stop rider delivery screen with per-vendor
  pickup confirmation and single PIN delivery.
- **`PoolGroup` model** — delivery group in the rider job pool with vendor
  names and leg count.
- **`DeliveryGroup` model** — full delivery group model with status enum.
- **`delivery_settings_screen.dart`** — admin screen for editing delivery fees.
- **`deliverySettingsProvider`** — fetches fee settings from server.
- **`groupPoolProvider` / `groupDetailProvider` / `groupLegsProvider`** —
  rider-side providers for delivery group streaming.
- **23 unit tests** (`test/round7_test.dart`) — pack capacity, product
  classification, delivery fee calculation, multi-vendor cart grouping,
  serialization round-trip, legacy v1→v2 cart migration.

### Changed

- **`Product` model** — added `section`, `foodSubsection`, `requiresPack`
  fields; `isMeal`, `isProteinTopping`, `sectionLabel` computed getters.
- **`Order` model** — added `deliveryGroupId` field.
- **`CartState` / `VendorCartGroup`** — multi-vendor cart with per-vendor
  groups, pack metadata (`packCount`, `packFee`, `packContents`), v2 JSON
  format with v1 migration. `isUniflexOnly` / `hasPartnerVendor` getters.
- **`CartScreen`** — no longer takes a vendor param; shows items grouped by
  vendor.
- **`CheckoutScreen`** — rewritten for multi-vendor: pickup restricted to
  Uniflex-only carts; delivery creates group via `placeMultiVendorOrder` then
  routes to `CommitmentFeeScreen` in group mode.
- **`CommitmentFeeScreen`** — dual-mode: `CommitmentFeeScreen(groupId, ...)`
  for delivery groups, `CommitmentFeeScreen.forOrder(order)` for Around/legacy.
- **`CatalogScreen`** — removed vendor-locking; product quantities read from
  vendor-specific cart group; FAB shows for any non-empty cart.
- **`job_pool_screen.dart`** — watches both `jobPoolProvider` and
  `groupPoolProvider`; shows group cards with "Accept Group" button.
- **`RiderService`** — added `streamGroupPool`, `streamGroupDetail`,
  `acceptDeliveryGroup`, `confirmGroupLegPickup`, `verifyGroupDelivery`,
  `fetchGroupLegs` methods.
- **`kitchen_queue_screen.dart`** — "GROUP" badge on orders with
  `deliveryGroupId`.
- **`manage_hub_screen.dart`** — added "Delivery Fees" entry.

### Notes

- Run the Round 7 SQL block in the Supabase SQL editor.
- Payment/Paystack/PIN internals are untouched.
- The pack builder enforces `kPackMealCapacity = 8` client-side; the DB
  `pack_meal_capacity` setting in `delivery_settings` provides the server-side
  validation source.

---

## Round 5 — PIN / payment root-cause fix (2026-10-31)

### Root causes fixed

- **pgcrypto search_path**: All PIN-touching SECURITY DEFINER functions used
  `set search_path = public`, but on Supabase Cloud pgcrypto lives in the
  `extensions` schema. This override hid `crypt()` / `gen_salt()`, causing
  every PIN hash/verify call to fail. Fixed by re-creating every PIN function
  (and `pay_commitment_fee`) with `set search_path = public, extensions`.

- **Change PIN UI**: Phase 9 added a 2-param `set_transaction_pin(text, text)`
  overload requiring the current PIN when changing. The Flutter `showSetPinSheet`
  never collected the current PIN, so it always failed with
  `INVALID_CURRENT_PIN`. Fixed: sheet now detects whether a PIN exists and
  shows a "Current PIN" field when changing.

- **Error surfacing**: `_mapError()` in `commitment_fee_screen.dart` and
  `order_repository.dart` only matched 3 error patterns — all other failures
  showed a generic message. Expanded to cover all known error codes
  (`PIN_LOCKED`, `PIN_NOT_SET`, `INVALID_PIN`, `crypt`, etc.) with raw
  error fallback for debugging.

### Changed

- `supabase/schema.sql` — Round 5 block: 6 functions re-created with
  `search_path = public, extensions`.
- `lib/shared/widgets/pin/pin_entry_sheet.dart` — `showSetPinSheet` rewritten
  with current PIN detection and collection.
- `lib/shared/services/profile/profile_service.dart` — `setTransactionPin`
  conditionally includes `p_current_pin` param (critical for PostgREST
  overload resolution between 1-param and 2-param signatures).
- `lib/student/ordering/commitment_fee_screen.dart` — comprehensive `_mapError`.
- `lib/student/ordering/order_repository.dart` — `crypt` and raw error
  fallback added to `_mapError`.

---

## Round 4 — Registration fixes, ordering flow overhaul, custom items (2026-10-28)

### Summary

Three workstreams: (A) registration/signup hardening, (B) UI corrections,
(C) ordering flow overhaul separating Uniflex and partner vendor payment
paths, and (D) payment bug fixes.

### Added

- **Confirm Password field** on `CreateAccountScreen` — passwords must match
  before the account is created.
- **`place_partner_food_order` RPC** — creates a partner vendor order without
  wallet deduction or PIN. Student pays only the commitment fee next, then
  food cost after sourcing.
- **`order_custom_items` table** + RPCs (`add_custom_item`,
  `approve_custom_item`, `reject_custom_item`) — riders can add items during
  sourcing that require student in-app approval before they touch the bill.
- **Admin-only referral codes** — `referral_codes` and `referral_code_uses`
  tables. `complete_student_onboarding` updated to look up admin-minted codes
  first, then fall back to legacy per-student codes. Auto-generation of
  personal referral codes removed.
- **Notes field** — `p_notes` parameter added to `place_food_order_with_payment`,
  `place_partner_food_order`, and `place_around_order`. Displayed to riders
  and in the kitchen queue.

### Changed

- **Phone normalization** — `validators.dart` strips whitespace, dashes,
  parentheses, and dots before regex matching. Both `phone()` validator and
  `toE164()` use sanitized input.
- **Matric number optional** — `complete_student_onboarding` treats
  null/empty matric as NULL; uniqueness check skipped when null.
- **Checkout routing** — Uniflex vendors: full payment + PIN at checkout →
  `OrderConfirmationScreen`. Partner vendors: no payment → `CommitmentFeeScreen`.
- **Kitchen advance logic** — `preparing` + Uniflex delivery → `ready`
  (was incorrectly `awaiting_final_payment`).
- **Profile card** — tier-coloured header card with `tierBronze` color.
- **Home toggle** — Food Delivery renders first (left), Around second (right).
- **Referral screen** — "₦500" references replaced with generic "earn rewards"
  copy.
- **Rider fee hiding** — partner/around orders show "Amount TBD" instead of
  monetary amounts in the rider pool and active delivery screens.
- Keyboard overlap fix on checkout screen.
- Inline PIN mismatch error display (previously only showed in SnackBar).

### Notes

- Run the Round 4 SQL block after Round 3.
- `pay_commitment_fee` still used the old `search_path = public` (fixed in
  Round 5).

---

## Round 3 fixes (2026-10-26)

Two unrelated workstreams addressed in this round.

---

### Part A — OTP delivery & signup flow fixes

#### Root causes fixed

- **A1 — OTP not arriving at all**: The `phone-otp` Edge Function queries an
  `otp_send_log` table for rate limiting — that table was never created. Every
  OTP send returned a DB error before reaching Termii. Added `otp_send_log`
  (with RLS enabled, no client policies) to `schema.sql`.

- **A2 — Wrong screen after returning mid-signup**: `AuthGate` routed any
  session with `onboarding_complete = false` straight to `CompleteProfileScreen`
  (Step Two), even if the user was actually still at the OTP step (Step 1b) and
  `phone_verified_at` was null. The gate now distinguishes the two:
  `phoneVerifiedAt == null` → `ResumeOtpScreen`; `phoneVerifiedAt != null` →
  `CompleteProfileScreen` (unchanged).

- **A3 — Duplicate accounts on signup retry**: `createStubProfile` used a raw
  `INSERT`, which failed with a unique-constraint error if the same user ID
  already had a profile row. Changed to `.upsert(..., onConflict: 'id')`. The
  method now also saves the phone number so `ResumeOtpScreen` can pre-fill it.

- **A4 — General OTP flow stability**: OTP code length guard corrected from
  `< 4` to `< 6` (Termii sends 6-digit codes). `AuthException` messages
  containing "already"/"registered" now surface a clear "account exists, try
  logging in" message instead of a generic error.

#### Added

- **`lib/shared/auth/screens/resume_otp_screen.dart`** — new screen shown by
  `AuthGate` when a user returns with an unverified phone. Three phases:
  (A) phone unknown (legacy stub) → re-enter number; (B) phone known → confirm
  and request new code; (C) code sent → 6-digit input + Verify + Resend.
  Close button calls `signOut()` (returns to LoginScreen).
- **`otp_send_log` table** in `supabase/schema.sql` Round 3 block.
- One-time cleanup `DELETE` in the same block: removes incomplete signup
  profiles (`phone_verified_at IS NULL`, `onboarding_complete = false`) older
  than 7 days.

#### Changed

- `lib/shared/services/profile/profile_service.dart` — `createStubProfile`
  adds `required String phone`, uses `.upsert(onConflict: 'id')`.
- `lib/shared/auth/screens/create_account_screen.dart` — passes phone to
  `createStubProfile`; friendlier error for "already registered".
- `lib/shared/router/auth_gate.dart` — `!onboardingComplete` branch now checks
  `phoneVerifiedAt == null` and routes to `ResumeOtpScreen` when true.
- `lib/shared/auth/screens/verify_phone_screen.dart` — OTP length guard fixed
  (4 → 6).

#### Notes

- **Run the Round 3 schema block** in the Supabase SQL editor. It is additive
  and safe to run once.
- **Re-deploy `phone-otp`** Edge Function (`supabase functions deploy phone-otp`)
  — no code changes to the function itself, but the missing table must exist
  before the function will work.
- Test against real number 09160556368 after deploying.

---

### Part B — Commitment fee + adjustable order for uncertain-availability orders

Scope: **All delivery orders** (partner vendor, Uniflex delivery, and Around
requests). Pickup orders (Uniflex) are exempt — no rider is dispatched, so no
commitment fee applies. The ₦300 fee is **non-refundable** regardless of
outcome.

#### Problem solved

When sourcing food from a location Uniflex doesn't control, items may not be
available. This adds a two-stage payment flow instead of charging the full
amount upfront.

#### New flow

1. Student places a delivery order (partner vendor, Uniflex delivery, or Around request).
2. A new **CommitmentFeeScreen** prompts for a flat ₦300 commitment fee (same
   regardless of distance or order type). Paying this dispatches the rider.
3. Order enters **`being_sourced`** state and becomes pool-eligible (no admin
   "Transfer to Rider" step needed for these orders).
4. Rider accepts from the job pool; status stays `being_sourced` (not
   `out_for_delivery` — that only comes after final payment).
5. Rider sources items; can flag unavailable items via a new "Flag item
   unavailable" action in `ActiveDeliveryScreen`.
6. Student can view flagged items on the new **`AdjustOrderScreen`** and
   communicate adjustments via the existing messaging system.
7. Rider taps "Confirm Items" → enters the confirmed total → order moves to
   **`awaiting_final_payment`**.
8. Student is notified → pays the actual food cost from `OrderTrackingScreen`
   (PIN-gated, same as regular checkout).
9. Order moves to `out_for_delivery` → existing rider delivery + PIN gate at
   the door.

#### Policy: non-refundable fee

The ₦300 commitment fee is **never refunded** under any circumstances. Admin
must manually cancel an order that falls through completely — there is no
auto-refund logic.

#### Added

- **`lib/student/ordering/commitment_fee_screen.dart`** — ₦300 payment screen
  with wallet balance check, PIN gate, and non-refundable notice.
- **`lib/student/ordering/adjust_order_screen.dart`** — shows order items with
  rider-flagged items highlighted; `OrderItemFlag` model; `orderItemFlagsProvider`.
- **`supabase/schema.sql` Round 3 Part B block**:
  - `being_sourced` and `awaiting_final_payment` added to orders status CHECK.
  - 4 new columns on `orders`: `commitment_fee_paid`, `commitment_fee_amount`,
    `final_amount`, `final_payment_paid`.
  - `order_item_flags` table with RLS policies (rider inserts, student reads).
  - `job_pool_read` RLS policy updated: partner/around orders use `being_sourced`
    as pool-eligibility status (was `placed`).
  - New RPCs: `pay_commitment_fee`, `flag_item_unavailable`,
    `confirm_sourced_items`, `pay_final_amount`.
  - `accept_order` rewritten: `being_sourced` orders stay in that status after
    acceptance (previously always set `out_for_delivery`).
  - `wallet_transactions.source` constraint widened to include `commitment_fee`.

#### Changed

- `lib/shared/models/order.dart` — `beingSourced` and `awaitingFinalPayment`
  added to `OrderStatus`; 4 new fields on `Order` + `fromMap` + `copyWith`.
- `lib/student/ordering/checkout_screen.dart` — all delivery orders route to
  `CommitmentFeeScreen` after placement; pickup orders go straight to
  `OrderConfirmationScreen`.
- `lib/student/tracking/order_tracking_screen.dart` — timeline branch for the
  sourcing flow; "Pay Final Amount" button when `awaitingFinalPayment`.
- `lib/student/orders/orders_screen.dart` — `beingSourced` and
  `awaitingFinalPayment` added to active orders set; `_statusColor` switch fixed.
- `lib/rider/delivery/active_delivery_screen.dart` — "Flag Item Unavailable"
  and "Confirm Items" actions for `being_sourced` orders.
- `lib/rider/services/rider_service.dart` — `streamActiveDeliveries` includes
  `being_sourced`; `flagItemUnavailable` and `confirmSourcingItems` methods
  added.

#### Notes

- **Run the Round 3 schema block** (Parts A, B, and C) in the Supabase SQL
  editor before testing.
- The `job_pool_read` policy is recreated in the Part B block — the version
  in `schema.sql` body is superseded; only the Round 3 version matters after
  this point.
- ARCHITECTURE.md: update the "Where future phases' work goes" table to note
  that commitment-fee sourcing orders live in `student/ordering/` and
  `rider/delivery/`.

---

### Part C — Extend commitment fee to all delivery order types

Adds Around-request support to the staged flow and wires up the kitchen queue
to show the new statuses.

#### Added

- **`supabase/schema.sql` Round 3 Part C block**:
  - `place_around_order` RPC: creates an Around order without any wallet
    deduction (replaces `place_around_with_payment` in this path).
  - `pay_final_amount` updated: Uniflex delivery orders go to `ready` (admin
    then transfers to rider pool); partner food and Around orders go straight
    to `out_for_delivery` (rider already assigned at sourcing stage).
  - `update_order_status` updated: `being_sourced` and `awaiting_final_payment`
    added to the allowed target-status set; `being_sourced → preparing`
    transition permitted so the kitchen can start work once the fee is paid.

#### Changed

- `lib/student/around/around_screen.dart` — removed PIN collection; calls
  `placeAroundRequestStaged` (new staged RPC); routes to `CommitmentFeeScreen`.
- `lib/student/ordering/order_repository.dart` — `placeAroundRequestStaged`
  method added (calls `place_around_order`, no payment, no PIN).
- `lib/admin/kitchen/kitchen_queue_screen.dart` — "Being Sourced" and
  "Awaiting Final Payment" section groups added to the queue view;
  `_statusColor` handles both new statuses.
- `lib/student/ordering/commitment_fee_screen.dart` — "partner/external order"
  copy generalised; non-refundable language added; `TODO(policy)` removed.

---

## Round 2 post-testing fixes (2026-10-12)

Second on-device QA pass. Twelve items addressed; no automated tests
written (as with Round 1, a dedicated testing pass follows).

### Added

- **#2 — Admin Analytics screen**: new `admin/analytics/admin_analytics_screen.dart`
  with six sections — user counts (students/riders), orders by period
  (today/week/month with revenue), completion rate (completed vs cancelled
  with progress bar), orders by status breakdown, top-selling items (ranked
  list), rider performance (deliveries per rider). Backed by a new
  `getAnalytics()` method on `AdminService` and `adminAnalyticsProvider`.

- **#7 — Cart persistence**: cart state now survives app restarts. Added
  `shared_preferences` dependency; `CartState`, `CartItem`, `Product`, and
  `Vendor` gained `toJson`/`toMap` serialization; `CartNotifier` persists
  to SharedPreferences on every mutation and restores on startup.

### Changed

- **#1 — Overflow audit**: audited every screen for RenderFlex overflow
  patterns. The codebase was already well-structured (SingleChildScrollView /
  ListView / CustomScrollView used correctly throughout). Fixed one real
  issue: `admin_profile_screen.dart`'s `_InfoRow` had an unwrapped `Column`
  in a `Row` — long email addresses would overflow. Wrapped in `Expanded`.

- **#3 — Admin nav restructured to 4 tabs**: super_admin bottom nav
  reduced from 6 tabs (Dashboard, Orders, Scheduled, Menu, Manage, Profile)
  to 4: **Dashboard, Orders, Manage, Analytics**. Menu, Scheduled Orders,
  and Profile & Settings moved into ManageHubScreen entries. Kitchen staff
  reduced to 1 tab (Orders only).

- **#4 — Menu categories simplified to 3**: all legacy categories
  (Protein Meals, Main, Sides, Snacks, Grills, Smoothies, Juices, etc.)
  now normalize into exactly 3 fixed display categories: **Meals, Drinks,
  Others**. Applied consistently across `CatalogScreen` (student),
  `MenuManagementScreen` (admin), and `ProductFormScreen` (admin form
  dropdown). A `_normalizeCategory()` function maps any legacy DB value
  into one of the three.

- **#5 — Dispatched order visibility fixed**: orders with
  `out_for_delivery` status disappeared from the admin kitchen queue.
  **Root cause**: `streamKitchenOrders()` in `admin_service.dart` filtered
  for only `['placed', 'preparing', 'ready', 'ready_for_pickup']` —
  `out_for_delivery` was missing. Fixed by adding it to the filter and
  adding a visible "Out for Delivery" section to the queue UI.

- **#6 — Pre-order time picker simplified**: replaced the two-step
  `showDatePicker` + `showTimePicker` (calendar + clock dial) with a
  same-day time slot system — 30-min increment chips from the next rounded
  half-hour until 22:00, presented in a scrollable bottom sheet.

- **#9 — Saving Plan tracking fixed**: after placing an order, the plan
  summary card showed stale Budget/Spent/Remaining values.
  **Root cause**: `OrderNotifier` invalidated wallet providers after order
  placement but never invalidated `activeSavingPlanProvider`. The Postgres
  RPC correctly updated `spent` in the DB, but the frontend kept showing
  the stale cached value. Fixed by adding
  `ref.invalidate(activeSavingPlanProvider)` after both `placeFoodOrder`
  and `placeAroundRequest`.

- **#10 — Track button enlarged**: changed from a small `OutlinedButton.icon`
  with shrinkWrap styling to a larger `FilledButton.icon` with emerald
  background, white text, `minimumSize: Size(120, 44)`, label changed from
  "Track" to "Track Order".

- **#11 — Admin rider delivery status visibility**: the kitchen queue now
  shows rider delivery stage for dispatched orders — "Rider assigned —
  heading to pickup" (accepted), "Rider has picked up — delivering now"
  (picked_up), or "Out for delivery" (default). Also shows "Waiting for a
  rider to accept…" for ready-for-delivery orders that have been
  transferred but not yet picked up.

- **#12 — Admin order status tab cleanup**: `_statusColor()` in the
  kitchen queue card now handles `outForDelivery` with orange (was falling
  through to the default gray `outline` color, mismatching the section
  header).

### Confirmed (no change needed)

- **#8 — PIN setup in onboarding**: confirmed that `complete_profile_screen.dart`
  already has PIN and Confirm PIN fields (lines 270–313) and calls
  `setTransactionPin()` as best-effort after the onboarding RPC. No fix
  needed.

### Known issues

- **Matric number**: flagged during testing but deliberately not fixed in
  this pass. The matric number field/validation needs further discussion
  before changes are made.

---

## Post-testing fixes & changes (2026-09-19)

First on-device Android QA pass across all three shells. Thirteen issues
found; addressed here in order. Sections 11, 12, and 13 are structural
changes to how Phase 2's catalog, the cross-shell order status flow, and
cart/checkout navigation work, not small tweaks — see ARCHITECTURE.md for
the full explanation of each.

Not done in this pass, deliberately: no automated tests were written for
any of the fixes below (a dedicated testing pass follows once this is
verified manually).

### Added

- **1 — Profile navigation**: the Student home header's avatar is now a
  real tappable `Material`/`InkWell` routing to the Profile tab (it was
  an inert `Container` with no `onTap` at all). Rider/Admin dashboards
  don't have this avatar-in-header pattern, so nothing to fix there.
- **3 — Forgot password**: `AuthService.sendPasswordResetOtp` /
  `verifyPasswordResetOtp` / `updatePassword`, two new screens
  (`ForgotPasswordScreen`, `ResetPasswordScreen`), and a "Forgot
  password?" link on `LoginScreen`. Uses Supabase Auth's OTP-based
  recovery (`resetPasswordForEmail` + `verifyOTP(type: recovery)`) rather
  than an email deep link, matching this app's existing in-app-OTP-entry
  pattern (Termii) and needing no native URL-scheme setup. **Manual step
  required**: edit the "Reset Password" email template in the Supabase
  dashboard to include `{{ .Token }}` so the email carries a 6-digit code.
- **5 — Retry control**: `shared/widgets/async/retry_section.dart`
  (`RetrySection`) — a small icon/message/Retry-button widget — applied
  to every realtime/live data section: wallet balance, wallet transaction
  history, Kitchen Queue, order tracking, the Orders list, the admin
  dashboard, admin Scheduled Orders, the rider Job Pool, the rider
  active-delivery screen, and the student vendor/Around-categories lists.
  Replaces the admin dashboard's own one-off `_ErrorCard`.
- **6 — Transaction PIN**: `transaction_pins` table + `set_transaction_pin`
  / `has_transaction_pin` / `verify_transaction_pin` RPCs (pgcrypto
  hash, no client SELECT/INSERT policy — mirrors the `wallet_transactions`
  pattern). New students set a 4-digit PIN during Step Two onboarding;
  existing accounts are prompted via `showSetPinSheet` the first time
  they confirm an order. `CheckoutScreen` and `AroundScreen` both collect
  the PIN via `showEnterPinSheet` before calling the order-placement RPC,
  which itself calls `verify_transaction_pin` server-side and raises
  `INVALID_PIN` on mismatch — the gate can't be skipped by a client bug.
  "Change Transaction PIN" added to the Student profile's More menu.
- **7 — Admin rider management**: `RiderManagementScreen` (invite via a
  new `admin-create-rider` Edge Function using the Supabase Admin API;
  remove/reactivate via a new `profiles.is_active` flag +
  `admin_set_rider_active()`). `AuthGate` blocks sign-in for a deactivated
  account without deleting anything — account and delivery history are
  untouched (a hard delete was avoided on purpose:
  `delivery_records.rider_id` cascades on delete, which would have wiped
  the rider's history).
- **8 — Admin "Manage" hub**: `ManageHubScreen`, replacing the standalone
  "Vendors" bottom-nav tab with "Manage", branching into Manage Vendors
  (relocated, unchanged), Manage Riders, and Around Categories. Future
  admin capabilities should add a hub entry, not a new tab.
- **9 — Admin-configurable Around categories**: `around_categories` table
  (seeded with the 5 former hardcoded values) + full admin CRUD
  (`AroundCategoriesScreen`/`AroundCategoryFormScreen`, under the Manage
  hub). `around_requests.category` is now a foreign key into it instead
  of a fixed `CHECK` constraint. The Student Around grid reads the active
  list live via `activeAroundCategoriesProvider`.
- **11 — Pack system**: `products.requires_pack` (admin toggle per item)
  + `vendors.pack_price` (admin field per vendor — Uniflex's own is
  edited from Menu Management's app bar, since Uniflex is excluded from
  Vendor Management). New `PackAllocationScreen`: at checkout, if the
  cart has pack-requiring items, the student is asked "Will you be using
  packs?"; if yes, they build one pack at a time (mixing different
  pack-requiring items freely) until every unit is allocated. Each pack
  adds the vendor's pack price to the total. Pack contents are recorded
  per-order in a new `order_packs` table.
- **12 — Order status sync**: `transferred_to_rider_at` column +
  `transfer_order_to_rider()` RPC (the "Transfer to Rider" admin action —
  see Changed below), `get_rider_info()` RPC (student sees their assigned
  rider's contact, mirroring `get_customer_info()`), and a
  `StudentShell`-level realtime listener that fires a local notification
  on `preparing → ready(_for_pickup) → picked_up → out_for_delivery →
  completed`.
- **13 — Cart visibility**: persistent badge-carrying cart FAB on the
  Student home screen (`_HomeCartButton`), visible whenever the cart is
  non-empty, going straight to `CartScreen`.

### Changed

- **2 — Greeting**: removed the "Good night" branch from the Student home
  greeting — only Good Morning / Good Afternoon / Good Evening now,
  Evening covering the rest of the day into the night.
- **4 — Wallet top-up loaders**: removed the two redundant custom loaders
  stacked on top of Paystack's own SDK loading state on
  `PaystackCheckoutPage` (a native `CircularProgressIndicator` layered
  over the WebView, plus a custom HTML/CSS spinner shown until Paystack's
  `inline.js` loaded) — exactly one loading state is visible at a time
  now.
- **10 — Anonymous rider availability**: replaced the "Emeka A. · Campus
  rider · online" card on the Student home Around mode with an anonymous
  green/grey dot + "Riders available nearby" / "No riders available right
  now", backed by a new `any_riders_available()` RPC. No individual rider
  name or per-person online status is shown before booking.
- **11 — Catalog rework**: removed `MealCustomizationScreen` and the
  quantity → protein → extras → drink combo-builder wizard entirely (not
  kept alongside the new flow). Former protein `product_options`
  (Chicken, Beef, Fish, Turkey, Egg) became standalone Uniflex "Proteins"
  category products via a seed migration that updates the existing Phase
  2 rows in place. `CatalogScreen` now adds each item directly via an
  inline "+"/"− qty +" stepper on its own tile — no per-item navigation.
  `product_options`/`ProductOption` are left in the schema (unread by the
  new UI) rather than dropped.
- **12 — Order status sync (root cause + fix)**: `studentOrdersProvider`
  and `orderByIdProvider` were one-shot `FutureProvider`s — nothing ever
  re-fetched them after Kitchen/a rider changed a status until the
  student manually refreshed. Both are now Supabase Realtime
  `StreamProvider`s, the same pattern `kitchenOrdersProvider` already
  used. Also: Kitchen Queue was mixing Around requests into the food
  queue (`type = 'food'` filter added); Kitchen's "Mark Ready" always set
  `status = 'ready'` even for pickup orders, whose tracking timeline
  expects `ready_for_pickup` (now branches on `delivery_type`); there was
  no way to mark a pickup order Completed at all (added); and
  `update_order_status` had no transition guards, so an admin call could
  set a delivery order straight to `out_for_delivery`/`completed`,
  bypassing the rider PIN gate — it's now hardened so the only path to
  `completed` on a delivery order (food delivery or Around) is the
  existing rider workflow (`accept_order` → `confirm_pickup` →
  `verify_delivery`).
- **13 — Cart / checkout dead-end**: the Orders tab's Cart view's
  "Go to the Home tab to complete checkout" text (with nothing to tap)
  is now a working "Proceed to Checkout" button.

### Notes

- **Run the new schema.sql block** — everything above lives in the
  "POST-TESTING FIXES & CHANGES" section appended to the end of
  `supabase/schema.sql`. Additive only, safe to run once against the
  already-migrated project.
- **Deploy the new Edge Function**: `supabase functions deploy
  admin-create-rider --no-verify-jwt` (Section 7).
- **Edit the recovery email template** in the Supabase dashboard to
  include `{{ .Token }}` (Section 3) — without this, `resetPasswordForEmail`
  still sends an email, but it won't contain the 6-digit code
  `ResetPasswordScreen` asks for.
- Verified via `flutter analyze` (clean) and `flutter test` (14/14
  passing). On-device re-verification of these specific fixes on Android
  is the natural next step before the dedicated testing pass.

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
