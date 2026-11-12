# Store submission answers — ready to paste (Pack 2, 2026-11-12)

Drafted from the code on `review-prep`. Read, correct anything wrong, then paste.
**OWNER TO CONFIRM** marks things the code cannot answer. Keep the Apple and Google
answers, the privacy policy (uniflex.live/privacy) and
`ios/Runner/PrivacyInfo.xcprivacy` saying the same thing.

## 1. Apple — App Privacy ("Data collection")

Tracking: **No** (no ads, no advertising ID, no data shared with data brokers, no
tracking SDKs). Every type below: **Linked to the user: Yes · Used for tracking: No ·
Purpose: App Functionality** (not analytics, not advertising, not personalisation).

| Apple data type | What it is in Uniflex |
|---|---|
| Contact Info → Name | Full name, nickname |
| Contact Info → Email Address | Login e-mail |
| Contact Info → Phone Number | Verified by SMS; riders see it for delivery |
| Contact Info → Physical Address | Delivery location + details the student types (campus / hostel / room) |
| Identifiers → User ID | Account id |
| Identifiers → Device ID | Push notification token (FCM) |
| Purchases → Purchase History | Orders, errands, gifts, wallet transactions |
| User Content → Customer Support | Support chat messages |
| User Content → Other User Content | Order notes, gift messages |
| Other Data → Other Data Types | Matric number, school, date of birth |

Not collected: location (device), contacts, photos (students never upload), health,
financial card details (entered on Paystack's page — Paystack is the processor),
browsing history, search history (search is not stored), diagnostics/crash data
(no crash SDK — **OWNER TO CONFIRM** you haven't enabled Firebase Crashlytics or
Analytics in the Firebase console), sensitive info.

## 2. Google Play — Data safety

- Does your app collect or share user data? **Yes** (collects; does not share).
- Is all data encrypted in transit? **Yes** (HTTPS only; no cleartext).
- Can users request deletion? **Yes** — in the app (Profile → Privacy → Delete account)
  and at **https://uniflex.live/delete-account**.
- Sharing: **None.** Supabase (database), Firebase (push), Termii (SMS) and Paystack
  (payments) are service providers acting for Uniflex, which Google does not count as sharing.

| Category → type | Collected | Shared | Optional? | Purposes |
|---|---|---|---|---|
| Personal info → Name | Yes | No | Required | App functionality, Account management |
| Personal info → Email address | Yes | No | Required | App functionality, Account management |
| Personal info → User IDs | Yes | No | Required | App functionality, Account management |
| Personal info → Address | Yes | No | Required for delivery | App functionality |
| Personal info → Phone number | Yes | No | Required | App functionality, Account management, Fraud prevention |
| Personal info → Other info | Yes (matric number, school, date of birth) | No | Required | Account management |
| Financial info → Purchase history | Yes | No | Required | App functionality |
| Financial info → Other financial info | Yes (wallet balance, top-up references) | No | Required | App functionality |
| Messages → Other in-app messages | Yes (support chat, gift messages) | No | Optional | App functionality, Customer support |
| App activity → Other user-generated content | Yes (order notes) | No | Optional | App functionality |
| Device or other IDs | Yes (push token) | No | Required for notifications | App functionality |

Not collected: location, contacts, photos/videos, audio, files, calendar, health,
web browsing, app interactions/analytics, crash logs (**OWNER TO CONFIRM** as above).
Data retention: order and payment records are kept up to 6 years without name, e-mail,
phone or address (stated on the deletion page and in the privacy policy).

## 3. Age and content rating

**Apple (new questionnaire, App Store Connect → App Information → Age Rating):**
violence, sexual content, profanity, horror, drugs / tobacco: **None** · simulated
or real gambling, contests, loot boxes: **No** · unrestricted web access: **No** (the
only web view is Paystack's payment page) · user-generated content shared publicly:
**No** · messaging between users: **Limited** — a one-way gift note (≤ 200 characters)
to a recipient the sender names by e-mail; chat only with Uniflex support · medical /
treatment info: **No** · age assurance / parental controls: **No**.
Alcohol: **OWNER TO CONFIRM** that no vendor sells alcohol through Uniflex (if any
does, answer "frequent/intense alcohol references" and expect 18+).
Recommended category: **Food & Drink** (secondary: Lifestyle).

**Google (IARC questionnaire):** category *Utility, productivity, communication or
other*; violence, sexuality, language, controlled substances, gambling: **No**; users
interact / exchange content: **Yes, limited** (gift notes, support chat); shares
location with other users: **No** (riders see the typed delivery address of their own
job); digital purchases: **No**.
**Target audience:** university students. Sign-up allows age **14+** (server check).
Recommended Play target age groups: **16–17 and 18+**, "not designed for children".
**OWNER TO CONFIRM:** if you select only 18+, raise the server minimum age to 18 so the
app and the declaration agree.

**Ads:** No ads. Advertising ID: not used (no `AD_ID` permission in the merged manifest).
News / health / government / COVID / VPN declarations: **Not applicable**.

## 4. Google Play — Financial features declaration

Select:
- **Payments and transfers → Mobile payments and digital wallets** — a prepaid
  in-app wallet, topped up by card or bank transfer through Paystack (licensed
  processor) and spent only on food, errands and delivery inside Uniflex. No
  peer-to-peer transfers, no withdrawals to bank, no interest.
- **Purchase agreements → Rewards, points … and other incentives** — free
  membership tiers (Bronze → Platinum) earned by spending, reward points (no cash
  value, not redeemable for cash), a small wallet credit on the student's birthday
  for Silver+ tiers, and a referral bonus credited to the referrer when a referred
  student completes a first order (admin-assigned codes).

Do **not** select: loans, BNPL, banking, savings, investments, crypto, insurance.
The "Spending budget" is a self-set spending limit with a warning — no money is held
or moved by it.

## 5. Review notes (paste into both stores)

> **What Uniflex is.** A campus app for Redeemer's University, Nigeria: students order
> food from campus vendors and send errands; Uniflex riders (staff) deliver. One app
> serves students, riders and admins; reviewers only need the student role.
>
> **Payments are for physical goods and services only** (food, errands, delivery), so
> they use Paystack, not In-App Purchase. Students top up a prepaid wallet (card or bank
> transfer through Paystack) and pay from it with a 4-digit transaction PIN. Membership
> tiers are free and earned by spending; nothing digital is sold.
>
> **Sign in:** use the demo account below (e-mail + password). New sign-ups need a
> Nigerian phone number for an SMS code, so please use the demo account.
>
> **To place a test order:** Home → "Review Demo Kitchen" (open at all hours) → add an
> item → Cart → Checkout → Delivery → choose any location, type a room → Pay → PIN.
> The delivery fee is paid first; a campus rider then accepts the job, buys the food and
> asks for the food price, so a test order will stay at "Waiting for rider" outside
> campus hours — that is expected. You can cancel it until a rider accepts
> (Orders → the order → Cancel).
>
> **Wallet:** the demo account already has a balance, so no card is needed.
> **Spending budget** (Wallet tab) is only a spending limit with a warning.
>
> **Account deletion:** Profile → Privacy → Delete account (PIN required).
> Privacy policy: https://uniflex.live/privacy · Support: Profile → Help & Support,
> or https://uniflex.live/#contact.
>
> **Demo login:** e-mail `OWNER TO FILL` · password `OWNER TO FILL` · transaction PIN `OWNER TO FILL`

## 6. Demo-account checklist (owner)

1. Create a normal student account for review (use a real phone you control for the
   SMS step), set a 4-digit PIN. Don't use a personal account.
2. Credit it once **through the ledger** (never by editing `wallets` directly), e.g.
   ₦20,000 with a unique reference, via the service role:
   `select public.credit_wallet('<demo user id>', 20000, 'REVIEW-DEMO-2026-11');`
   (SQL editor, as postgres). Top it up again after each review round.
3. Create vendor **"Review Demo Kitchen"** (Fixed menu, active) with 3–4 cheap items.
   Optionally a second "Review Demo Packs" (Pack-based) so both styles are visible.
   No opening hours exist, so it is always orderable.
4. Tell the riders to ignore jobs from that vendor, and cancel demo orders as admin
   after each review (no refund needed — it's demo money; or credit back via step 2).
5. Never delete these accounts while a review is open. After approval, deactivate the
   demo vendor if you don't want students to see it (`is_active = false`).
6. Play's **App access** form: "All or some functionality is restricted" → give the same
   login, PIN and the steps above.

## 7. Account deletion

- In app: **Profile → Privacy → Delete account** → read → *Delete my account* →
  *Delete* → PIN. Refused while an order, errand or gift is in progress; a positive
  wallet balance is lost (shown first).
- Web (Google's required URL): **https://uniflex.live/delete-account** — explains the
  in-app steps and how to ask support if the app is unavailable.
- What is deleted / kept: as on that page — personal data and the login are removed;
  order and payment records are kept up to 6 years with nothing identifying.
- **OWNER TO CONFIRM:** add a support e-mail to that page and the privacy policy
  (today only a phone number and postal address are listed).
