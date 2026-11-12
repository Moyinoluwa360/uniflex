# Wallet funding audit (Pack 1 / Part 4, 2026-11-12)

Paystack, **test mode**. Checked against Paystack's current docs (Dedicated
Virtual Accounts, Webhooks) and the live Supabase project.

## Map

| Piece | Where |
|---|---|
| Top-up sheet (amount, min ₦100), random `UFX-<16 hex>` reference | `lib/student/wallet/wallet_screen.dart` (`_openFundWallet`, `_showAmountSheet`) |
| Paystack window (inline JS, public key, amount in kobo, NGN, `metadata.user_id`) | `lib/student/wallet/paystack_checkout_native.dart` (+ `_web.dart`) |
| Verify after the window closes | Edge Function `verify-paystack-payment` → `transaction/verify/:ref` → `credit_wallet` |
| Account number card + copy | `WalletCard` (`lib/shared/widgets/wallet/wallet_card.dart`), data from `create-virtual-account` |
| Issue a dedicated account | Edge Function `create-virtual-account` (POST `/customer`, POST `/dedicated_account`), saves to `wallets.virtual_account_number` |
| Bank transfers in | Edge Function `paystack-webhook` (`charge.success`) → `credit_wallet` |
| Ledger | `wallets` (balance, virtual_account_number), `wallet_transactions` (unique credit `reference`) |
| RLS | `wallets` / `wallet_transactions`: read own row only; no insert/update/delete policies (RLS on) |
| Secrets (names only) | Edge: `PAYSTACK_SECRET_KEY`, optional `PAYSTACK_DVA_BANK` (new); app `.env`: `PAYSTACK_PUBLIC_KEY` (git-ignored) |

## Results

| Link | Status | Evidence / note |
|---|---|---|
| **A1** Initialise server-side, kobo, NGN, unique ref, user id from session | **Partly** | Initialised in the app with the public key (`paystack_checkout_native.dart:143`). Kobo + NGN + random ref are right. Safe in practice because the credit uses Paystack's verified amount, never the app's. Server-side `transaction/initialize` would be cleaner (small–medium). |
| A2 Secret key never on the client | Works | Only `pk_test_…` in `.env`; `sk_` only in Edge secrets. |
| A3 Credit from server verification, not the client callback | Works | `verify-paystack-payment` calls `transaction/verify`, checks success + NGN + owner (metadata user id or email). |
| A4 Credited exactly once, atomic | Works (fixed) | Unique index on credit `reference`; balance + ledger in one function. Race between webhook and verify now answers `DUPLICATE_REFERENCE` instead of a raw error. |
| A5 Failed / abandoned / pending don't credit | Works | Only `status = success` is credited. |
| **A6 A user cannot credit themselves** | **Was broken → fixed (not yet applied)** | `credit_wallet` was executable by **anon and authenticated** on live: anyone could mint wallet money. Revoked in `pack1_wallet_funding_fixes.sql`. |
| A7 Min / max top-up | Partly | Min ₦100 in the app only; no max. Server credits whatever was really paid. |
| **B1** Creation once per student, idempotent, race-safe, required details | **Partly** | Called when the Wallet tab opens. Live mode was broken: `preferred_bank` was hard-coded to `test-bank` (fixed: chosen from the key; live uses `PAYSTACK_DVA_BANK`, default `wema-bank`). Now requires full name (2 parts) + phone as Paystack does; saves only over the placeholder. Not fully race-safe at Paystack's side (two taps could ask twice; Paystack keeps one account per customer). No retry button — retried next time the tab opens. |
| B2 Stored server-side, read own only, clients can't write | Works | RLS read-own; no write policies. Bank name / account name are not stored (bank shown from the configured mode). |
| B3 Display + copy, no fake number shown as real | Works (improved) | Placeholder shows "Pending Activation / Awaiting Paystack business verification" with no copy button. Test accounts now say "Test Bank (test mode)". The top-up sheet only says "Test mode" with a `pk_test_` key. |
| B4 Crediting inbound transfers | Works (fixed) | `charge.success` → metadata user id, else `authorization.receiver_bank_account_number` → wallet, else payer email. The email fallback was a LIKE pattern (`_`/`%` could match another student) — now an exact, escaped match that must be unambiguous. Unknown accounts and non-NGN are logged and acknowledged. Paystack's fees are not deducted from the credit (owner decision). |
| B5 Webhook security | Works | HMAC-SHA512 over the raw body with the secret key, before parsing; constant-time compare; 401 on bad signature; replays hit the unique reference. Not done: IP allow-list (52.31.139.75, 52.49.173.169, 52.214.14.220) — optional. |
| B6 Test vs live separation | Partly | One `PAYSTACK_SECRET_KEY` secret; the mode follows the key. The app's `.env` holds `pk_test_…`, so a release build stays in test mode until the owner swaps both keys. |
| Ledger = balance | 3 wallets differ by exactly ₦10,000 each (ids b78cc15d…, 223683c7…, 5d6cdb88…) — looks like test seeding written straight to `wallets`, not a code path. |

Also found (same class, fixed): `_refund_order` was callable directly by any
signed-in user (no caller / status check) — a student could refund a
delivered order to themselves once. Revoked; `update_order_status` still uses it.

For Pack 2: `process_birthday_rewards()` is callable by app users (harmless —
one credit per real birthday per year — but should be service-role only).

## Testing in test mode (owner)

- **Card:** Fund Wallet → any amount ≥ ₦100 → test card `4084 0840 8408 4081`,
  any future expiry, CVV `408`, PIN `0000`, OTP `123456`. The balance should
  rise once; Paystack Dashboard (Test) → Transactions shows it.
- **Bank transfer into the test account:** open the Wallet tab (a "Test Bank
  (test mode)" number appears once the profile has a full name + phone), then
  send money to that number from Paystack's demo bank app
  (demobank.paystackintegrations.com). The wallet should rise within minutes;
  Dashboard (Test) → Settings → API Keys & Webhooks → webhook log shows the
  `charge.success` delivery and our 200.
- Only provable in **live**: real NUBANs from Wema / Paystack-Titan (needs the
  business to have completed go-live), settlement, Paystack fees, and the
  live webhook URL.
