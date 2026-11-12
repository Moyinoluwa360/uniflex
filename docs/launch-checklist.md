# Launch checklist (owner) — after Pack 2, 2026-11-12

Do these in order. Each step says where, what, why, and what to tell Claude after.
Details: `docs/security-audit.md`, `docs/store-requirements.md`,
`docs/store-submission-answers.md`.

## A. Secrets — today

1. **Rotate the Supabase secret key (S-10, critical).** The 8 Nov Android release
   build contained it.
   Supabase Dashboard → Project Settings → API Keys → *Secret keys* → create a new
   secret key → then update, in this order: Edge Functions → Secrets →
   `PUSH_TRIGGER_SECRET` = new key; SQL editor:
   `select vault.update_secret((select id from vault.secrets where name='push_secret_key'), '<new key>');`
   → put the new key in `.env.tooling` (never `.env`) → **delete the old key**.
   Then delete the local `build/` folder (`flutter clean`) and any copy of the
   8 Nov APK/AAB you shared. Also open Codemagic → `env_file` group →
   `ENV_FILE_CONTENTS` and make sure it has only `SUPABASE_URL`,
   `SUPABASE_ANON_KEY`, `PAYSTACK_PUBLIC_KEY`, `FIREBASE_API_KEY`,
   `FIREBASE_PROJECT_ID` (the build now fails if a secret is there).
   *Tell Claude:* "rotated" — I'll send a test push to confirm push still works.
2. **Legacy API keys (S-11).** Same page → *Legacy API keys*. The service-role JWT
   shipped in a September APK. Best: switch the app to the **publishable** key
   (`sb_publishable_…` into `SUPABASE_ANON_KEY` in `.env` and Codemagic), build, then
   **Disable legacy API keys**. Edge Functions use the injected keys and keep working.
   *Tell Claude* which you did.

## B. Payments go-live

3. **Paystack key mode (S-12).** The app's `.env` has a **live** public key. In
   Supabase → Edge Functions → Secrets, `PAYSTACK_SECRET_KEY` must be the matching
   `sk_live_…` (Paystack Dashboard → Settings → API Keys & Webhooks, *Live* tab).
   Same page: live **Webhook URL** =
   `https://svhjdmpnpfewuoqbundw.supabase.co/functions/v1/paystack-webhook`.
   If the business isn't live-approved yet, put `pk_test_…` back in `.env`/Codemagic
   instead — never mix.
   *Verify:* top up ₦100 with a real card on TestFlight → balance +₦100 once →
   Paystack Live → Transactions shows it. Optional `PAYSTACK_DVA_BANK` secret for live
   bank accounts (default `wema-bank`).

## C. Supabase settings

4. Authentication → Sign In / Providers → **turn off "Allow new users to sign up"**
   (S-07; the app signs up through the `signup` function, which uses the admin API and
   keeps working). Test one sign-up on TestFlight afterwards.
5. Authentication → Rate limits: keep e-mail sends and token refreshes at defaults or
   lower; Attack Protection → **leaked-password protection** on (Pro plan) and CAPTCHA
   optional.
6. Authentication → Emails: the recovery template must contain `{{ .Token }}` (6-digit
   code, used by Forgot password) — check it.
7. Database → Backups: the CLI shows no backups listed and PITR off. Confirm daily
   backups exist on your plan (Pro) or take a manual dump before launch day.
8. Advisors → run **Security Advisor** and **Performance Advisor**; send me anything red.
9. Wallet ledger (S-15): 3 test wallets are ₦10,000 above their ledger. Tell me to add
   "adjustment" rows, or reset them if they are test accounts.

## D. Website (uniflex.live)

10. Review and deploy the two edited pages in `uniflex-website`
    (`src/PrivacyPolicy.jsx`, `src/DeleteAccount.jsx` — uncommitted): they now match
    what the app collects and the real deletion steps. **Add a support e-mail** to both
    and to the footer.

## E. Build

11. Build the new iOS app on Codemagic (TestFlight) and an Android **AAB**
    (`flutter build appbundle --release`) — both from `review-prep` after you merge it.
    Check the Codemagic log: Xcode 26.x, build number > 31.

## F. TestFlight regression (iPhone)

- Sign up (one SMS), log in, log out (balance hidden again).
- Profile: Privacy Policy and Terms open the website; sign-up step 1 shows both links.
- **Fixed-menu vendor:** dropdowns, `+` → `− 1 +`, max 20, cart without pack wording,
  pay delivery fee, order shows `2× Item` for student / rider / admin.
- **Pack-based vendor:** packs, spoons, drinks, others — unchanged.
- One checkout with one vendor of each style.
- Final payment: wrong PIN → "Incorrect PIN" (not "Payment successful"); 5 wrong →
  "locked for 15 minutes"; right PIN pays once.
- Change PIN with a wrong current PIN → "That is not your current PIN".
- Wallet top-up (step 3); "Spending budget" label on the Wallet tab.
- **Delete account** with a spare student: with an active order → refused; after it
  completes → balance warning → PIN → signed out; log-in with the old e-mail fails;
  signing up again with the same e-mail works.
- Admin: kitchen queue loads and updates; delivery and errand lists load.
- App Store Connect upload e-mail: no ITMS-90683 (location) warning, no ITMS-91053.

## G. App Store Connect

12. App Privacy (answers §1) · privacy URL https://uniflex.live/privacy · support URL
    https://uniflex.live/#contact · age rating (§3) · category Food & Drink ·
    availability **Nigeria only** · iPhone 6.9" screenshots · review notes + demo
    login (§5–6) · export compliance already answered in the build.

## H. Play Console

13. Create the app (`com.uniflex.myapp`), Play App Signing on, back up the upload
    keystore + `key.properties` somewhere safe (not git).
14. **Closed testing now:** 12 testers opted in for **14 consecutive days**, then apply
    for production.
15. App content: Data safety (§2, deletion URL https://uniflex.live/delete-account),
    Financial features (§4), App access (§6), Ads = No, Content rating (§3), Target
    audience (§3), news/health/government = No.
16. Settings → Developer account: trader status + public contact e-mail.
17. Store listing: 512×512 icon, 1024×500 feature graphic, phone screenshots, short
    and full description. (The icon source is 500×500 — provide a 1024×1024 master.)

## I. After launch

S-13 delivery-PIN attempts, S-14, S-19, A-08, A-09 major upgrades, B-05, B-07 (see
the audit). Remove the demo vendor's visibility after approval if you want.

## Rollback (if anything goes wrong with Pack 2's database changes)

`supabase/pack2_security_hardening_ROLLBACK.sql` (re-opens the holes — emergency
only); account deletion: `drop function public.delete_my_account(text);`; legacy
codes: see the header of `pack2_retire_legacy_referral_codes.sql`. Run with
`supabase db query --linked --project-ref svhjdmpnpfewuoqbundw -f <file>`.
