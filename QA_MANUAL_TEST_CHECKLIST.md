# Uniflex — Manual Testing Guide (Physical Android Phone)

Use this to run the app on a real phone and test every feature yourself.
Test mode is on (Paystack test cards, no real money moves).

---

## PART 1 — Connect your phone & run the app

### A. Prepare the phone (one-time)
1. Settings → **About phone** → tap **Build number** 7 times (enables Developer options).
2. Settings → **System → Developer options** → turn on **USB debugging**.
3. (Optional) turn on **Install via USB** / **Stay awake** while there.

### B. Connect
1. Plug the phone into the PC with a **USB data cable** (not charge-only).
2. On the phone, a prompt appears: **"Allow USB debugging?"** → tick "Always allow from this computer" → **Allow**.
3. Open a **Windows PowerShell** (or Command Prompt) — the Flutter/adb toolchain is on the Windows side.
4. Go to the project folder:
   ```
   cd "C:\Users\ogund\Documents\Important stuffs\GIGS\Uniflex app\uniflex"
   ```
5. Confirm the phone is seen:
   ```
   flutter devices
   ```
   You should see your phone listed with a device ID (e.g. `SM_A536 (mobile)`).
   If it says "unauthorized", re-accept the prompt on the phone.

### C. Run the app — pick ONE
**Option 1 — Live run (tethered, quickest to start):**
```
flutter run --release -d <deviceId>
```
Leave the cable connected; the app installs and launches. Fast and smooth.

**Option 2 — Installable APK (untethered, best for real-world walking-around testing):**
```
flutter build apk --release
flutter install -d <deviceId>
```
Then unplug the phone and use the app anywhere on Wi-Fi or mobile data.
(The built file is `build\app\outputs\flutter-apk\app-release.apk` if you want to
share/sideload it.)

> The phone needs **internet** (Wi-Fi or data) to reach the backend. A real network
> is more reliable than the emulator — the "Could not connect" glitches we saw are
> emulator-only.

### D. Test-mode reference
- **Paystack test card:** `4084 0840 8408 4081`, CVV `408`, expiry any future date (e.g. `09/27`), PIN `0000`, OTP `123456`. **No real money is charged.** Do not use a real card.
- **Pre-made role accounts** (for admin/rider/kitchen testing):
  - Admin (full): `test.admin@uniflex.app` / `UniflexAdmin99`
  - Kitchen staff: `test.kitchen@uniflex.app` / `UniflexKitchen99`
  - Rider: `test.rider@uniflex.app` / `UniflexRider99`
- **Student account:** `test.student@uniflex.app` / `TestStudent99` (existing student with wallet + order history). Or sign up fresh with your real phone number to also test OTP.
- ⚠️ **OTP caveat:** fresh signup sends an SMS OTP via Termii. If the Termii Sender ID
  ("Uniflex") isn't approved yet, the code may not arrive — in that case use a ready
  student account instead and note "signup OTP blocked by Termii".
- 🔎 **Known not-yet-built:** the in-app **Search** bar is a "coming soon" placeholder.

---

## PART 2 — What to test (full checklist)

Tick each box. For anything that fails, note: what you did, what you expected, what happened, and a screenshot.

### 🎓 STUDENT

**Onboarding & Auth**
- [ ] Splash screen shows the Uniflex logo, then routes correctly.
- [ ] **Create Account:** enter email, phone, password → proceeds to OTP.
- [ ] **Verify phone (OTP):** receive the SMS code, enter it, it's accepted. (Termii-dependent.)
- [ ] Wrong OTP is rejected with a clear message.
- [ ] **Complete profile:** name, matric number, school, etc. saved.
- [ ] Lands on the student Home after onboarding.
- [ ] **Log out**, then **Log in** again with the same credentials.
- [ ] Kill the app and reopen — you stay logged in (session persists).

**Home**
- [ ] Greeting + wallet balance shown at top.
- [ ] **Top up** button opens the wallet funding flow.
- [ ] Promo / "Refer a friend, earn ₦500" banner displays.
- [ ] Vendor list loads with names, descriptions, images.
- [ ] "Around / Errand request" entry point is present.
- [ ] Tapping a vendor opens its catalog.

**Ordering (food)**
- [ ] Vendor **catalog** loads products grouped by category with prices.
- [ ] Open a product → **customization** screen (options / add-ons) works; price updates.
- [ ] **Add to cart**; adjust quantity.
- [ ] **Cart** shows items, quantities, subtotal; can remove an item / edit.
- [ ] **Checkout:** choose fulfillment — **Pickup**, **Campus delivery**, **Hostel delivery**.
- [ ] Delivery location field appears for Campus/Hostel; delivery fee added correctly
      (Campus ₦200, Hostel ₦300; Pickup ₦0).
- [ ] **Pay with wallet** → succeeds; wallet balance drops by the order total.
- [ ] If wallet is short, you get a clear "insufficient balance" message.
- [ ] **Order confirmation** screen shows an order number.
- [ ] **Schedule for later** (scheduled order) — place one and confirm it's marked scheduled.

**Order tracking**
- [ ] Open the placed order → **tracking** screen shows current status.
- [ ] Status updates **live** as the kitchen advances it (Placed → Preparing → Ready …)
      — verify this by advancing it from the Admin account (see Admin section) and watching
      the student screen change without manual refresh.
- [ ] For a **delivery** order, the **delivery PIN** is shown to you (the customer).
- [ ] Delivery status updates when a rider picks up / delivers.

**Wallet**
- [ ] Wallet screen shows balance, virtual account number, tier.
- [ ] **Fund with card (Paystack):** use the test card → funding succeeds → balance increases.
- [ ] Cancelling the Paystack popup returns you cleanly (no crash, no double charge).
- [ ] **Transaction history** lists top-ups and order payments with correct signs/amounts.
- [ ] **Saving plan** screen: create/adjust a saving plan; over-budget warning behaves.

**Around / Errands**
- [ ] Open **Around** → pick a category, enter pickup + drop-off + description → submit.
- [ ] Errand is paid from wallet and appears as an active request.
- [ ] Errand can be tracked and is picked up by a rider (see Rider section).

**Group orders**
- [ ] **Create a group** order; share/join flow works.
- [ ] Group checkout splits/collects correctly and places the order.

**Growth & rewards**
- [ ] **Referral:** your referral code is shown and copyable; a new user signing up with it
      credits the referral bonus.
- [ ] **Gift:** send a wallet gift to another student → their balance goes up, yours down.
- [ ] **Badges / Membership & Rewards:** tier, points, and badges display correctly.
- [ ] **Scheduled Orders** list (from profile) shows upcoming scheduled orders.
- [ ] Birthday reward credits on the birthday (if testable).

**Profile**
- [ ] Profile shows name, tier, points, wallet, matric, school, email, phone, referral code.
- [ ] **Preferences** screen: change a preference → it saves and persists.
- [ ] **Log out** works.

---

### 🏍️ RIDER  (`test.rider@uniflex.app` / `UniflexRider99`)

- [ ] Log in → Rider dashboard ("Test Rider").
- [ ] **Go online** toggle works; offline hides you from new jobs.
- [ ] Today / All-time stats display.
- [ ] **Available Jobs** pool lists deliverable orders (food deliveries + errands), **live**.
      Place a Campus/Hostel delivery as a student and confirm it appears here.
- [ ] **Accept** a job → becomes your active delivery; it disappears from other riders' pools.
- [ ] Active delivery shows **pickup point, deliver-to address, customer name + phone**.
- [ ] **Confirm Pickup** → status flips to "heading to customer".
- [ ] **Verify Delivery → enter the correct PIN** (from the customer) → delivery completes.
- [ ] **Wrong PIN** is rejected (order stays undelivered).
- [ ] **History** tab lists your completed deliveries.
- [ ] Rider profile shows correct info; log out works.

---

### 🛠️ ADMIN

**Super admin** (`test.admin@uniflex.app` / `UniflexAdmin99`)
- [ ] Log in → Admin dashboard with 6 tabs (Dashboard, Queue, Scheduled, Menu, Vendors, Profile).
- [ ] **Dashboard:** Today's overview (orders, revenue, pending, completed) reflects real orders;
      Kitchen stages counts are correct.
- [ ] **Kitchen Queue** (live): a new Uniflex order appears; advance it
      **Start Preparing → Mark Ready**; each stage updates live and the student's tracking follows.
- [ ] **Scheduled** tab lists upcoming scheduled orders.
- [ ] **Menu management:** Add an item (name, category, price, availability) → it appears in the
      student catalog. Edit an item. Toggle availability → unavailable items hide from students.
      Delete an item.
- [ ] **Vendors:** Add a vendor → it appears on the student Home. Edit / toggle active / manage
      its menu.
- [ ] Profile shows "Super Admin"; log out works.

**Kitchen staff** (`test.kitchen@uniflex.app` / `UniflexKitchen99`) — permissions check
- [ ] Log in → sees the **kitchen-relevant** tabs (Queue / Scheduled) but **not** Menu, Vendors,
      or dashboard financials/revenue (restricted access).
- [ ] Can advance order statuses in the queue.

---

### 🔔 CROSS-CUTTING
- [ ] **Realtime across roles:** with two devices (or device + emulator), a status change on one
      (kitchen advances an order) shows on the other (student tracking / rider) without refresh.
- [ ] **Push notifications** (FCM): order status changes / delivery updates arrive in the phone's
      notification tray. (Requires Firebase config; may be disabled — note if nothing arrives.)
- [ ] **Offline / poor network:** turn off data mid-use → app shows a graceful error, and recovers
      when the network returns (note anywhere it gets permanently stuck on an error screen).
- [ ] **Design/polish pass:** on every screen, check fonts, colours, spacing, and images against
      the intended design; note anything off (many screens beyond Home are not yet redesigned).

---

### How to report issues
For each problem: **Screen → what you tapped → what you expected → what happened → screenshot.**
Group them by role so fixes can be batched.
