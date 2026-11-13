# Store requirements — Apple App Store and Google Play (Pack 2, 2026-11-12)

Checked against the code on `review-prep` after the Pack 2 fixes. Sources marked
**✔ fetched** were read on 2026-11-12; the others are the official page for that
topic but were not re-read this session — **verify against current docs** before
submitting. "In place" is only used where the evidence was looked at.

App facts used below: bundle id `com.uniflex.uniflex` (iOS) /
`com.uniflex.myapp` (Android) · version 1.0.3 · iOS build number from
Codemagic's counter (must be > 31) · Android `versionCode` 4 (pubspec `+4`) ·
Flutter 3.47.2, AGP 9.1.0, NDK r28, compile/target SDK 36, minSdk 24, iOS 16.0 ·
website https://uniflex.live.

## Apple App Store

| # | Requirement | Official source | Status | Evidence | Fix or owner step |
|---|---|---|---|---|---|
| 1 | Account deletion in the app (5.1.1(v)) | [Offering account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/) | **In place (next build)** | Profile → Privacy → Delete account → `delete_my_account` (live, 13/13 SQL checks; widget tests) | Ship the next build; test once on TestFlight with a spare account. |
| 2 | Privacy policy link in app + App Store Connect | [App Review Guidelines 5.1.1](https://developer.apple.com/app-store/review/guidelines/) | **In place (next build)** + Needs owner | Profile → Privacy Policy / Terms; sign-up step 1 links both (`LegalLinks`) | Deploy the corrected policy (`uniflex-website/src/PrivacyPolicy.jsx`, uncommitted) to uniflex.live, then enter https://uniflex.live/privacy in App Store Connect → App Privacy. |
| 3 | App Privacy answers match the app | [App privacy details](https://developer.apple.com/app-store/app-privacy-details/) | Needs owner | Answers drafted in `docs/store-submission-answers.md` §1, matching `PrivacyInfo.xcprivacy` | Paste the answers. |
| 4 | Purpose strings only for used features; no location / tracking (ITMS-90683) | [Guidelines 5.1.1(i–iv)](https://developer.apple.com/app-store/review/guidelines/) | **In place (next build)** | `geolocator` removed from `pubspec`; Info.plist keeps only Photo Library + Camera (image_picker, staff photos); no location / tracking / contacts / mic / Bluetooth; `platform_test.dart` | After the next upload, confirm the ITMS-90683 location warning is gone. |
| 5 | Privacy manifest + required-reason APIs (since 1 May 2024) | [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) ✔ fetched | **In place (next build)** | `ios/Runner/PrivacyInfo.xcprivacy` in the Resources phase; plugins ship their own | Watch the upload e-mail for "ITMS-91053 missing API declaration"; send it to me if one arrives. |
| 6 | Export compliance | [Complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations) | **In place** | `ITSAppUsesNonExemptEncryption = false` (HTTPS only) | — |
| 7 | Built with Xcode 26 / iOS 26 SDK (since 28 Apr 2026); target iOS 13+ (since 9 Sep 2026) | [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) ✔ fetched | **In place** | `codemagic.yaml` `xcode: latest`; deployment target 16.0 | Check the Codemagic log shows Xcode 26.x. |
| 8 | Version / build numbers | [App Store Connect help](https://developer.apple.com/help/app-store-connect/) | **In place** | Codemagic `--build-name=1.0.3 --build-number=$PROJECT_BUILD_NUMBER` | Confirm the next build number shown in TestFlight is above 31. |
| 9 | Icon 1024 px, no alpha; launch screen | [Guidelines 2.3](https://developer.apple.com/app-store/review/guidelines/) | **In place** (quality: see step) | `Icon-App-1024x1024@1x.png` 1024², no alpha; `LaunchScreen` storyboard | Source artwork is 500×500, upscaled → supply a 1024×1024 master and re-run `flutter_launcher_icons`. |
| 10 | iPhone-only vs iPad | [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications) | **In place** | `TARGETED_DEVICE_FAMILY = 1` (owner: iPhone-only) | iPhone screenshots only: 6.9" (1320×2868 or 1290×2796) required — verify current sizes. |
| 11 | Age rating (new questionnaire, answers due 31 Jan 2026) | [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) ✔ fetched | Needs owner | Answers in `store-submission-answers.md` §3 | Answer in App Store Connect → App Information. |
| 12 | Metadata: no placeholder / test text, support URL, contact in app | [Guidelines 2.3, 1.5](https://developer.apple.com/app-store/review/guidelines/) | Partly in place | In app: Help & Support (live chat / WhatsApp). The top-up sheet says "Test mode" only with a `pk_test_` key; the `.env` now has `pk_live_` | Support URL: https://uniflex.live/#contact. **Add a support e-mail** to the website (only a phone number today). |
| 13 | Reviewer access (2.1) | [Guidelines 2.1](https://developer.apple.com/app-store/review/guidelines/) | Needs owner | Owner chose: demo student with a ledger-credited balance + always-open demo vendor | Set up per `store-submission-answers.md` §6; reviewers can't complete delivery without a rider — the notes explain. |
| 14 | Payments for physical goods/services outside IAP (3.1.3(e)/3.1.5) | [Guidelines 3.1](https://developer.apple.com/app-store/review/guidelines/) | **In place** | Wallet pays only for food, errands, delivery; membership tiers are free (earned by spending) and give real-world perks (birthday wallet credit); no digital goods sold | State it in the review notes (§5). |
| 15 | Sign in with Apple (4.8) | [Guidelines 4.8](https://developer.apple.com/app-store/review/guidelines/) | Not applicable | E-mail + password only | — |
| 16 | User-generated content (1.2) | [Guidelines 1.2](https://developer.apple.com/app-store/review/guidelines/) | **In place (low risk)** | Chat is student ↔ Uniflex support only; gift message (≤ 200 chars) goes to a recipient the sender names by e-mail; no public content; contact via Help & Support | Mention in review notes. If Apple asks: add "report" to the gift view (follow-up). |
| 17 | Push notifications | [Guidelines 4.5.4](https://developer.apple.com/app-store/review/guidelines/) | **In place** | `aps-environment` entitlement; `remote-notification` background mode; no marketing pushes; no balance/PIN in texts | Permission is asked at first launch (acceptable); moving it to after login is a later nicety. |
| 18 | Availability: Nigeria only (avoids EU DSA trader obligations) | [Upcoming requirements — DSA](https://developer.apple.com/news/upcoming-requirements/) ✔ fetched | Needs owner | — | App Store Connect → Pricing and Availability → only Nigeria. If the EU stays on, trader status is required. |
| 19 | Warnings from builds 29–31 | App Store Connect e-mails | Needs owner | Location (ITMS-90683) fixed at source (A-01) | Forward any other warning e-mails. |

**Apple counts:** In place 12 (7 need the next build) · Missing 0 · Needs owner 6 · Not applicable 1.

## Google Play

| # | Requirement | Official source | Status | Evidence | Fix or owner step |
|---|---|---|---|---|---|
| 1 | Target API 36 for new apps / updates (since 31 Aug 2026) | [Target API level](https://support.google.com/googleplay/android-developer/answer/11926878) ✔ fetched | **In place** | Merged manifest `targetSdkVersion=36`, compileSdk 36, minSdk 24 | Build an **AAB** with Play App Signing. |
| 2 | 16 KB memory pages (updates blocked from 1 Feb 2027) | [16 KB page sizes](https://developer.android.com/guide/practices/page-sizes) ✔ fetched | **In place** | All `.so` in the 8 Nov AAB aligned ≥ 16 KB; AGP 9.1, NDK r28 | Play Console → App bundle explorer shows "16 KB: supported" after upload. |
| 3 | Permissions: minimum set; location policy (mandatory 27 Jan 2027) | [Permissions policy](https://support.google.com/googleplay/android-developer/answer/9888170), Google e-mail Nov 2026 | **In place (next build)** | Manifest now: INTERNET, POST_NOTIFICATIONS (+ plugin: NETWORK_STATE, WAKE_LOCK, VIBRATE, C2DM RECEIVE). **No location, photos, contacts, exact alarm, local network.** | Rebuild; check Play Console → App content → no sensitive-permission declarations requested. |
| 4 | Data safety form | [Data safety](https://support.google.com/googleplay/android-developer/answer/10787469) | Needs owner | Draft in `store-submission-answers.md` §2 | Paste. |
| 5 | Account deletion: in app **and** web URL | [Account deletion](https://support.google.com/googleplay/android-developer/answer/13327111) ✔ fetched | **In place (next build)** + Needs owner | In-app path (D-01); https://uniflex.live/delete-account (steps corrected, uncommitted in `uniflex-website`) | Deploy the website, then enter the URL in Data safety → Delete account URL. |
| 6 | Financial features declaration (all apps) | [Financial features declaration](https://support.google.com/googleplay/android-developer/answer/13849271) ✔ fetched | Needs owner | Wallet + card top-ups; rewards / tiers / referral bonus; no loans, savings, investment, crypto | Declare **Mobile payments and digital wallets** and **Rewards, points … and other incentives** (§4). |
| 7 | App access, content rating, target audience, ads, news/health/government | [App content](https://support.google.com/googleplay/android-developer/answer/9859455) | Needs owner | Answers in §3, §6 | Paste; Ads = No; target audience 18+ / not for children (§3). |
| 8 | Payments policy (no Play Billing for physical goods) | [Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738) | **In place** | Food, errands, delivery only | — |
| 9 | New personal account: closed test, **12 testers × 14 consecutive days** (accounts created after 13 Nov 2023) | [Testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465) ✔ fetched | Needs owner | — | Start the closed test now (checklist step 8); production access is requested after day 14. |
| 10 | Trader status (Play Console requirement from Nov 2026, per Google e-mail) + developer contact | Google e-mail Nov 2026; [Developer verification / trader](https://support.google.com/googleplay/android-developer/answer/13628312) (verify) | Needs owner | — | Play Console → Settings → Developer account → declare trader / non-trader; public e-mail required. |
| 11 | Quality: memory / code-optimisation thresholds (Feb 2027), Android vitals | Google e-mail Nov 2026; [Android vitals](https://developer.android.com/topic/performance/vitals) | Partly in place | Release logs silenced; kitchen query fixed (B-02); no heavy start-up work beyond Firebase + env load | Watch Android vitals after the closed test; R8/code-shrinking review is a follow-up. |
| 12 | Store listing assets | [Graphic assets](https://support.google.com/googleplay/android-developer/answer/9866151) | Needs owner | Icon source is 500×500 | Need: 512×512 icon (32-bit PNG), 1024×500 feature graphic, ≥ 2 phone screenshots, short (≤ 80) + full (≤ 4000) description. |
| 13 | Google e-mail items: Local Network, Manage Contacts, AppFunctions, student-plan subscriptions, Japan, XR | Google e-mail Nov 2026 | Not applicable | None of these permissions / features; no subscriptions | — |

**Google counts:** In place 6 (3 need the next build) · Missing 0 · Needs owner 7 · Not applicable 1 (row 13 groups six items).

### What Google's e-mail asked, and coverage

| E-mail item | Applies? | Covered by |
|---|---|---|
| Location: minimum scope, mandatory 27 Jan 2027; FINE needs a declaration | Yes (was requested) | Removed entirely (A-01) — no declaration needed |
| Local Network permission (API 37+) | No | Not requested |
| Manage Contacts permission | No | Not requested |
| AppFunctions | No | — |
| Subscriptions with eligibility discounts (student plans) | No | No subscriptions; membership is free |
| Deceptive behaviour / review manipulation | Yes (general) | Honest review notes; demo vendor clearly named |
| SMS / Call Log | No | OTP by SMS server-side (Termii); no SMS permissions |
| Trader status from Nov 2026 | Yes | Row 10 — owner |
| Memory & code-optimisation thresholds, Feb 2027 | Yes | Row 11 |
| Japan payments authorisation (1 Dec 2026) | No (Nigeria only) | — |
| Play Age Signals (optional) | Optional | Not used |

## Blocks submission

**Apple**
1. A new build containing Pack 2 (account deletion screen, privacy links, no location code, privacy manifest, iPhone-only).
2. Privacy policy deployed to uniflex.live and its URL in App Store Connect; App Privacy answers entered.
3. Reviewer access ready: demo student with balance + always-open demo vendor + review notes (§5–6).
4. Paystack keys in the same mode (S-12) — a reviewer top-up must not lose money.
5. Age-rating questionnaire answered; iPhone 6.9" screenshots.

**Google Play**
1. Same new build as an AAB.
2. Closed test: 12 testers for 14 consecutive days (personal account) before production.
3. Data safety (with the deletion URL), Financial features, App access, Content rating, Target audience, Ads declarations.
4. Website deletion page deployed; trader status declared; store listing assets (512 icon, feature graphic, screenshots).
5. Paystack key mode (S-12).

**Security items that must be done before going public (not store rules):** rotate the `sb_secret_` key (S-10) and deal with legacy API keys (S-11).

## Can wait until after launch

Delivery-PIN attempt limit (S-13); moving availability checks into the signup function (S-14); constant-time compare in push functions (S-19); secure-storage session (A-08); major dependency upgrades (A-09); spending-budget Lagos day boundary (B-05); "report" on gift messages; asking for push permission after login; R8 / code-shrinking review; stale SQL tests (B-07).
