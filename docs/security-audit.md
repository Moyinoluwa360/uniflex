# Security and bug audit — Pack 2 (2026-11-12, branch `review-prep`)

Method: read-only queries against the **live** Supabase project (all 39 tables'
RLS, every policy, every grant, every function body via `pg_get_functiondef`,
triggers, Realtime publication, storage, cron), Edge Function sources plus their
deployed JWT settings, the Flutter `lib/`, `ios/`, `android/`, `pubspec`, the last
local release build (8 Nov), and the whole git history. New SQL was first run on
live **inside a transaction that always rolls back** (the pattern Packs 1–6 used),
then applied with the owner's go-ahead. No emulator, no device. Emails, phones and
keys are never printed here.

Status: **Applied** = fixed and live · **Fixed** = fixed in code (ships with the next
build) · **Needs owner** = dashboard step, secret or decision (see
`docs/launch-checklist.md`) · **Won't fix** = reason given.

## Counts

| Severity | Found | Fixed / applied | Needs owner | Won't fix (reported) |
|---|---|---|---|---|
| Critical | 3 | 3 (S-10 also needs a key rotation) | 1 (S-10 rotation) | 0 |
| High | 4 | 2 | 2 (S-11, S-12) | 0 |
| Medium | 6 | 6 | 1 (S-07 Auth setting) | 0 |
| Low | 14 | 10 | 2 | 3 |
| Info | 4 | — | 1 (optional) | — |

## Findings

### Database and server (A1–A3)

| ID | Sev | Area | Object | What was wrong / how it could be abused | Fix | Status | Test |
|---|---|---|---|---|---|---|---|
| S-01 | **Critical** | RLS / orders | policies `orders: insert own`, `order_items: insert own`, `errand_requests: insert own` | Any student could insert order rows straight into the tables. `orders.is_paid` **defaults to true**, so a hand-made row looked paid: a "paid" Uniflex **pickup** order with any items reached the kitchen as food to prepare (free food); a "paid" errand pushed *New errand job* to riders and *New order* to admins; the `_after_order_placed` trigger raised lifetime spending / points / **tier** (and so birthday wallet credits). Payment-first was only enforced by the app. | Policies dropped; all orders go through the SECURITY DEFINER checkout functions. | **Applied** | `pack2_security_hardening_test.sql` S01a–d (33/33 on live) |
| S-02 | **Critical** | RPC / wallet | `checkout_group_order(uuid,jsonb,numeric,text,text)` (old overload) | Still live, no PIN, no `search_path`; debited `p_my_total` **as sent by the client** (a negative total **adds** money) with client-supplied unit prices. Reachability over PostgREST was *plausible* (overload ambiguity), not proven. The group-order screens are unreachable, and the newer overload would charge for an order that stays hidden. | Old overload dropped; `create_group_order`, `join_group_order`, `checkout_group_order` revoked from app users. Dart screens left in place (dead code). | **Applied** | S02a–b |
| S-03 | **High** | RPC / orders | `_insert_order_items(order_id, items)` | Callable by any signed-in user; appended items to **any** order — free extra food on a prepaid pickup order, or junk on someone else's order. | Internal helpers revoked from app users (`_insert_order_items`, `_line_items_subtotal`, `_delivery_fee`, `_check_transaction_pin`). | **Applied** | S03, S03b |
| S-04 | **High** | Transaction PIN | `verify_transaction_pin`, `pay_final_amount`, `pay_group_final_amount`, `set_transaction_pin` | The 5-tries / 15-minute lockout could be bypassed: `verify_transaction_pin` answered true/false with **no counter**; errand final payment used it; delivery final payment **raised** on a wrong PIN, rolling back the counter; change-PIN compared the current PIN uncounted. With a stolen session the 4-digit PIN falls in ≤10,000 calls. | All three now use the counted check and **return** `{"error": …}` (as checkout already did); `verify_transaction_pin` revoked. App: `throwIfRpcError` at both final payments; `setTransactionPin` reads the returned error. | **Applied** (app part ships with next build) | S04a–o; `test/pack2/security_test.dart` |
| S-05 | Medium | Referrals | `referral_codes` owner policy, `referral_credits` / `referrals` read policies, `my_referral_code()`, `get_referral_leaderboard()` | "Students never see their own code or amounts" was UI-only: a student could read their admin-assigned code and use count, credit amounts, and other students' referral counts. | Admin-only read policies; both RPCs revoked. | **Applied** | S05a–d |
| S-05b | Low | Referrals | `profiles.referral_code` (12 legacy self-codes) | Readable through the student's own profile row and still accepted at sign-up. | Owner chose to retire them: cleared, backed up in `pack2_backup.legacy_referral_codes` (not API-exposed). Referrals already recorded still pay. | **Applied** | `pack2_retire_legacy_referral_codes_test.sql` 4/4 |
| S-06 | Low | RPC | `process_birthday_rewards()`, `can_notify_order()` | Callable by app users (credit idempotent per year; the other leaks rider/admin of an order). | Service role only (pg_cron runs as `postgres`). | **Applied** | S06 |
| S-07 | Medium | RLS / profiles | `profiles: insert own row` | Nothing guarded **insert**: an account made through the public Auth sign-up API could write its own profile with tier, points, `phone_verified_at`, `onboarding_complete` (skipping phone verification). | Policy dropped (profiles are created server-side). **Owner:** turn off public sign-ups in Auth (the app signs up through the `signup` function's admin API). | **Applied** + Needs owner | S07 |
| S-08 | Low | RLS | `group_orders: creator update` | Creator could change discount / status directly (dead feature). | Dropped. | **Applied** | — |
| S-09 | Low | Functions | 7 SECURITY DEFINER functions | No fixed `search_path`. | Set to `public`. | **Applied** | S09 (all definer functions) |
| S-11 | High | Secrets | legacy `service_role` JWT | The 2026-09-27 audit found it shipped inside an APK. The app still uses the legacy anon JWT, so legacy keys are on; unless the JWT secret was rotated, that key still works. (Testing it would use a credential against production — blocked, rightly.) | Edge Functions moved to the new keys (`_shared/keys.ts`), deployed 2026-11-13; app `.env` on the publishable key; **legacy API keys disabled 2026-11-13** — the leaked service-role JWT is dead. Verified after disabling: push (sent 1) and `birthday-rewards` with the new server key (200, no extra credits). Builds made before the switch can no longer connect. | **Fixed (legacy keys disabled)** | `security_test.dart` S-11 |
| S-12 | High | Payments go-live | `.env` `PAYSTACK_PUBLIC_KEY` vs secret `PAYSTACK_SECRET_KEY` | The app's `.env` now holds a **live** public key (`pk_live…`). If the server secret is still `sk_test_…`, a real card is charged but verification cannot find it → **money taken, wallet not credited**. Secrets can't be read back. | **Owner:** make both the same mode (checklist step 3). | Needs owner | — |
| S-13 | Low | Rider | `verify_delivery`, `verify_group_delivery` | Riders can guess a delivery PIN without limit. Riders are vetted staff. | Follow-up (needs a counter column). | Won't fix now | — |
| S-14 | Low | Enumeration | `is_matric_number_available`, `is_nickname_available`, `is_referral_code_valid` (anon) | Anyone can test whether a matric number / code exists; needed before sign-in. | Follow-up: fold into the rate-limited `signup` function. | Won't fix now | — |
| S-15 | Medium | Ledger | 3 wallets | Each ₦10,000 above the sum of its ledger (test seeding, Pack 1). No negative balances on live. | `pack2_wallet_ledger_adjustment.sql` (owner chose option A, applied 2026-11-13): one ₦10,000 `adjustment` credit per wallet, balances unchanged; now every wallet = sum of its ledger. Wallet history also labels every source (birthday reward, referral bonus, delivery fee … were all shown as "Order Payment"). | **Applied** | `pack2_wallet_ledger_adjustment_test.sql` 4/4 on live; `wallet_labels_test.dart` |
| S-16 | Info | Edge Functions | CORS `*` | Bearer-token auth (no cookies) — `*` grants nothing. | — | Won't fix | — |
| S-19 | Low | Edge Functions | `push-notification`, `send-notification`, `birthday-rewards` | Service-key comparison is not constant-time; 500 responses include `String(err)`. Service-only endpoints. | Follow-up. | Won't fix now | — |
| D-01 | **Store blocker** | Account deletion | (missing) | No in-app deletion (Apple 5.1.1(v), Google User Data policy). | `delete_my_account(pin)`: refused while anything is in progress; balance forfeited through the ledger; personal data deleted; login scrubbed (email replaced, password random, identities/sessions removed, banned); orders / wallet rows kept anonymised. Profile → Privacy → Delete account. | **Applied** (screen ships with next build) | `pack2_account_deletion_test.sql` 13/13 on live; `test/pack2/delete_account_test.dart` |

### Secrets, app and platform (A4–A5)

| ID | Sev | Area | Object | What was wrong | Fix | Status | Test |
|---|---|---|---|---|---|---|---|
| S-10 | **Critical (confirmed)** | Secrets | `.env` (bundled into every build) | Held a **`sb_secret_…` Supabase secret key** (full service access, bypasses RLS). **Confirmed inside the 8 Nov local release AAB and APK** (`build/app/outputs/…`). Anyone with that APK can read and change every table. Dart never read it. | Moved to `.env.tooling` (git-ignored, not bundled); Codemagic now refuses a `.env` containing a server secret; Dart test fails on one. **Rotated 2026-11-13:** new key in `PUSH_TRIGGER_SECRET`, vault `push_secret_key` and `.env.tooling`; old key deleted; push verified after deletion (sent 1); local build outputs deleted. Still to check: Codemagic `ENV_FILE_CONTENTS`, shared APK copies. | **Fixed (key rotated)** | `security_test.dart` S-10 |
| S-17 | Info | Secrets | `google-services.json`, `GoogleService-Info.plist` | Firebase **client** keys committed — public by design. | Optional: restrict the keys to the app ids in Google Cloud. | Needs owner (optional) | — |
| S-18 | Info | Git | all branches | History scanned for JWTs, `sk_live/test`, `sb_secret_`, private keys: **nothing real was ever committed**. `.env*`, `key.properties` ignored. | — | — | grep |
| A-01 | Medium | Permissions | `geolocator` + `ACCESS_FINE/COARSE_LOCATION`, `NSLocationWhenInUseUsageDescription` | The plugin was **not used anywhere** in `lib/`; it only added location permissions — the source of Apple's ITMS-90683 warning and Google's January 2027 location declaration. | Plugin, permissions and purpose string removed. | Fixed | `platform_test.dart` |
| A-02 | Medium | Permissions | `READ_MEDIA_IMAGES`, `READ_EXTERNAL_STORAGE`, `NSPhotoLibraryAddUsageDescription` | Image picking uses the system picker (no permission); Play restricts photo permissions to core use. Nothing saves photos. | Removed. Camera/photo strings reworded honestly (staff menu/advert photos). | Fixed | `platform_test.dart` |
| A-03 | Medium | Backup | Android `allowBackup` (default true) | The Supabase session (refresh token), cart and settings sit in shared preferences and were copied to Google cloud backup / new phones. | `allowBackup=false` + data-extraction rules excluding everything. | Fixed | `platform_test.dart` |
| A-04 | Medium | Privacy manifest | `ios/Runner/PrivacyInfo.xcprivacy` (missing) | Required-reason APIs need declared reasons; data types should match App Privacy. | Added (no tracking; 9 data types; UserDefaults CA92.1) and registered in the Resources build phase. | Fixed | `platform_test.dart` |
| A-05 | Low | WebView | Paystack checkout | Could navigate to any URL; JS escaping missed `<` / newlines; any failing sub-resource replaced the page with a raw error (no `mounted` check). | HTTPS-only navigation, full escaping, main-frame errors only with friendly text. | Fixed | `platform_test.dart` |
| A-06 | Low | Logging | `debugPrint` (≈30 calls) | Still writes to the device log in release builds (errors can carry ids / server text). | Silenced when `kReleaseMode`. | Fixed | `platform_test.dart` |
| A-07 | Low | Inputs | `AppTextField` (all PIN / password fields) | Keyboard suggestions, autocorrect and personalised learning were on for obscured fields. | Off whenever `obscureText`. | Fixed | widget test |
| A-08 | Low | Storage | Supabase session in shared preferences | Library default; Android sandbox + backups now off. Secure-storage session would be stronger but adds a custom `LocalStorage` and migration risk. | Reported. | Won't fix now | — |
| A-09 | Info | Dependencies | `pubspec.lock` | 36 in-range patch/minor updates applied (`supabase_flutter` 2.18.3, `image_picker` 1.2.4, `url_launcher` 6.3.3, `webview_flutter_wkwebview` 3.27.2…). Majors left: `firebase_core` 5 / `firebase_messaging` 17, `flutter_riverpod` 3, `flutter_local_notifications` 23, `share_plus` 13, `connectivity_plus` 7, `flutter_secure_storage` 11, `flutter_dotenv` 6 — none with a known security advisory that affects this app; upgrade after launch with device testing. `js` and `flutter_secure_storage_macos` are discontinued transitive packages (web/macOS only). | Updated in range; majors listed. | Fixed / follow-up | full suite |

### Bugs (Part B)

| ID | Sev | Area | What was wrong | Fix | Status | Test |
|---|---|---|---|---|---|---|
| B-01 | Low | Search | `search_products` listed deleted products / vendors; `%` and `_` were wildcards. | Filters + escaping + 1–60 chars. | **Applied** | SQL B01a–c |
| B-02 | Medium | Admin performance | Kitchen queue downloaded **every order ever** and filtered on the phone on each Realtime event; admin delivery / errand lists were unbounded (row cap + very long `in (…)` URLs as orders grow). | Kitchen filters on the server (same rules); history lists keep the newest 500. | Fixed | `bugs_test.dart` B-02 |
| B-03 | Low | Error text | 16 places showed raw exception text (`Error: $e`, `Could not load: $e`, `Failed: $e`, PIN sheet), incl. student Profile, Badges, Scheduled orders, Spending budget. | All through `AppErrorMapper`; guard test scans `lib/`. | Fixed | `bugs_test.dart` B-03, B-03b |
| B-04 | Low | Wording (Play financial policy) | "Saving Plan" is a spending budget (no money held, no interest) but reads like a savings product. | Shown as **Spending budget** (owner). | Fixed | `bugs_test.dart` |
| B-05 | Low | Time | Spending-budget periods start at UTC midnight (01:00 Lagos). | Reported (display-only). | Won't fix now | — |
| B-06 | Info | Money | Amounts are naira `numeric(10,2)` end to end (doubles in Dart). Every charge is computed on the server, so the client can't change what is charged. | Reported. | Won't fix | — |
| B-07 | Info | Tests | Stale SQL suites: `fix_pack_2_test` (renamed RPC), `pack_4b_test` / `pack_6_test` (a live product is now unavailable), `support_chat_test` (fixtures without auth users + a syntax error). Same result before and after Pack 2. | Reported. | Follow-up | — |

## Checked and fine (evidence on live, 2026-11-12)

- **RLS on all 39 tables in `public`.** No `USING (true)` on private data; "hide unpaid" on `orders` / `delivery_groups` is RESTRICTIVE.
- **Roles** come from `profiles.role`, protected by `guard_profile_privileged_columns` (role, tier, points, phone, referral fields …), checked by `is_admin()` / `is_rider()` / `is_super_admin()`; never from `user_metadata`. Riders only via `admin-create-rider` (admin JWT + `is_admin`). No profile UPDATE policy.
- **Wallet:** no client write policy; `credit_wallet` service-only with a unique reference; every debit locks the wallet row and checks the balance in the same transaction; no negative balances.
- **Checkout:** server prices every line, rejects other-vendor / unavailable / out-of-range items, enforces vendor ordering style (fixed menu: no packs, ≤ 20 per item, style must match), idempotency key + advisory lock, counted PIN, wallet row lock. Delivery fee and service charge computed on the server.
- **Riders:** 3-job cap inside the accept functions under a per-rider advisory lock; `for update nowait`; only the assigned rider sets the price or verifies delivery.
- **Cancel:** refused once a rider has accepted; no refund (business rule).
- **All 30+ admin / rider RPCs** gate on the role.
- **Realtime:** every published table has RLS; riders have no row access to `orders` / `delivery_groups`.
- **Storage:** one bucket `product-images` (public read, admin-only write, 5 MB, jpeg/png/webp).
- **Edge Functions:** webhook HMAC-SHA512 over the raw body before parsing, constant-time; user-facing functions verify the JWT themselves; push/birthday functions require the service or trigger key; `signup` / `phone-otp` rate-limit in Postgres (OTP length 6, attempts and resends limited server-side).
- **Notifications:** no balance or PIN value in any push text.
- **16 KB pages:** every native library in the last release bundle (`libapp`, `libflutter`, `libdartjni`, `libdatastore_shared_counter`, arm64 + x86_64) is aligned to ≥ 16 KB. Toolchain: Flutter 3.47.2, AGP 9.1.0, NDK r28, compile/target SDK 36, minSdk 24.

## Not verified (say so plainly)

- Supabase **Security / Performance Advisors** (dashboard only) — owner action.
- Whether the 8 Nov APK/AAB (with the secret key) was shared or uploaded; whether Codemagic's `ENV_FILE_CONTENTS` ever held it.
- Server Paystack key mode (S-12); Auth settings (public sign-ups, rate limits, leaked-password protection, email templates).
- On a device: the Paystack WebView with the HTTPS-only rule (3-D Secure pages are HTTPS; a bank-app hand-off link would now be refused), account deletion end to end, iPhone-only build, privacy manifest acceptance at upload.
