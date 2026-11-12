# Before you build (Codemagic → TestFlight)

## 1. If the build fails at signing with "aps-environment"

Plain version: Apple keeps a "signing profile" for the app. The old one was made
before Push Notifications was switched on, so it may not allow push.

Only if the Codemagic log says something like
`Provisioning profile … doesn't include the aps-environment entitlement`:

1. Go to developer.apple.com → Certificates, IDs & Profiles → **Profiles**.
2. Find the **App Store** profile for `com.uniflex.uniflex` and **delete** it.
3. Run the Codemagic build again. It creates a new one by itself.

If the build passes, ignore this.

## 2. After the app is on the iPhone

1. Open the app and tap **Allow** when it asks about notifications.
   (If you tapped Don't Allow: iPhone Settings → Uniflex → Notifications → on.)
2. Log in once.
3. Ask Claude to check that your account has a device token saved
   (`profiles.fcm_token`). If it does, Apple + Firebase + the app are connected.

## 3. Already done (nothing to do)

- Pack 4A SQL applied on Supabase; Edge Functions deployed; push secrets stored.
- Old `support-notify` webhook removed.
- APNs key uploaded to Firebase.

## 4. Remember

- The OLD TestFlight build cannot place orders any more (its checkout functions
  were removed from the database). Testers need the NEW build.
- Test on the phone after building: pay → back out → wrong PIN (no order must
  appear), errand, pickup, service charge, notifications (app closed), support
  chat with an order attached, cart notice.

## 5. Pack 4C — check on the phone (after Pack 6, when you build)

Admin:
- Manage → Menu and a partner vendor's menu look the same: Meals, Proteins /
  Toppings, Drinks, Others. "+ Add" in each section opens the form already set
  to it. Add one item per section, then open that vendor as a student and
  confirm each lands in the right place. Switch an item off/on.
- Support inbox rows show the nickname with the full name below; search by a
  name and by a phone number. Open a chat: header shows nickname, full name,
  phone.
- Manage → Support settings: save `0803…` and see it come back as `+234803…`.
  Clear it and save: students should only get live chat.
- Orders: a delivery and an errand someone has accepted show "Rider: <name>";
  before that "Waiting for rider".
- Dashboard: open the tab (numbers load), pull down to refresh, then place or
  complete an order and watch the numbers move. Fees collected and Food
  payments are separate. Compare with the "side-by-side" SQL check.
- Analytics: same checks; top items and rider performance fill in.
- Advertisements: new ad with an image and no link; one with `example.com`;
  type nonsense and see the friendly message. Existing ads keep their links.

Student:
- Profile → Help & Support: with a WhatsApp number set you get two options;
  WhatsApp opens with "Hi, this is <nickname>." (and the order id from an
  order). With no number it opens live chat directly.
- Home: ads slide by themselves about every 5 s, loop, stop while you hold
  them, and one ad alone stays still. Tap an ad: centred popup with the whole
  image; X and tapping outside close it; "Visit" only on ads with a link.
- Profile has no referral code row. "Refer a student" says to contact Admin and
  its button opens Help & Support.

## 6. Pack 5 — deploy, then check on TWO real phones (after Pack 6, when you build)

Deploy first (needs the owner's go-ahead): run `supabase/pack_5.sql`, then
`supabase functions deploy signup` (secret `TERMII_API_KEY` is already set).
Optional: `pack_5_test.sql` in the SQL editor (all lines should say PASS).

Use a real number you can receive SMS on (Phone A) and a second one (Phone B).

1. Normal signup: Create Account → email, password, `0803…` number → Continue.
   You land on "Verify your phone" showing `+234 803 ••• 1234`, and exactly ONE
   SMS arrives. Enter the code → "Complete your profile" shows "Phone verified".
   Fill everything, Finish setup → you are in the Student app. Log out, log in
   with the same email/password.
2. Stop at step 2: get to the code screen, swipe the app away, reopen → Create
   Account → you are back on the code screen (countdown continues).
3. Change number: on the code screen tap Change number → step 1 with everything
   still filled → type Phone B's number → Continue → code arrives on Phone B only;
   the old code (Phone A) no longer works.
4. Wrong code: enter a wrong code → "incorrect, N tries left"; after 5 wrong →
   "Too many wrong codes. Request a new code."
5. Resend: Resend is greyed with "Resend code in 0:59…"; at 0:00 it enables; one
   tap sends one new SMS; the older code stops working.
6. Leave at step 3: verify the phone, fill a few fields, close the app, reopen →
   Create Account → still on step 3 with the fields filled (PIN empty). Wait 30+
   minutes and reopen → it sends you back to step 2 with the other details kept.
7. Email already used: sign up with an email that already has an account →
   "An account with this email already exists. Try logging in." and NO SMS is sent.
   Same with an already-registered phone number.
8. A half-made old account (e.g. `og@gmail.com`): signing up with its email says to
   log in and continue; logging in still takes you to the old resume screens.
9. Limits: tap Continue repeatedly on step 1 → still only one SMS; after 5 SMS to
   one number in a day → "Too many codes were requested for this number today".
10. Airplane mode: Continue shows "No internet connection" (or "took too long"),
    stays on step 1, no spinner stuck.

## 7. Pack 6 — food gifting: check on TWO phones + a rider (after the build)

Needs: Phone A (sender), Phone B (recipient, a different student account), a
rider account, and Admin. `pack_6.sql` is already applied to live (no function redeploy needed).

1. **A:** add food from any vendor → Checkout → Delivery → switch on "Send as a
   gift". Type B's registration email → Find → "Sending to: **B's nickname**
   (b***@gmail.com)". Tap Change → back to the email box. Try an unknown email →
   "No student found with that email."; try your own → "You can't send a gift to
   yourself." Find B again, write a message, pick a location + details → Continue.
2. Switch to Pickup (Uniflex-only cart) → the gift switch disappears.
3. **A:** pay the delivery fee. **B** should get a push (even with the app closed)
   "You got a food gift 🎁 … <message>"; tapping it opens the gift.
4. **B:** Orders → "Gift from A's nickname" with status and message, the items
   (no ₦ anywhere), the delivery PIN; nothing to pay/cancel. Profile → Gifts →
   Received lists it; A's Gifts → Sent lists it.
5. **Rider:** the job in the pool is tagged GIFT with no names/phones. Accept →
   "Deliver to" (B) and "Paid by" (A), each with Call + WhatsApp. No matric number
   anywhere.
6. **Rider** sets the food price → **A** pays (or declines: B is told it was
   cancelled). Rider goes out for delivery → B gets "on its way". Rider asks B for
   the PIN, enters it → B sees Delivered (PIN gone) and gets a notification.
7. Cancel before a rider accepts (A) and Admin-cancel another one → B is notified
   each time. A third student has no way to see either gift.
8. **Admin:** the order details show GIFT, sender, recipient and the message.
9. Ten Finds in an hour from A → the next says "Too many searches…".

### 1-minute check for the text-selection fix (any phone, especially iPhone)
Open any form (e.g. Checkout → Note, or Wallet top-up). Type a word, double-tap
to select it (blue highlight + handles). Then, one at a time: tap empty space;
scroll the page; tap a button; tap Cancel/back. Each time the highlight and
handles must vanish and the keyboard close. Also: tap from one field straight
into another — the second must focus normally.



## 8. Push notifications check (after the 2026-11-08 push fix)

Do this order: run `supabase/push_devices.sql` → deploy `push-notification` and
`send-notification` with `--no-verify-jwt` → build the new app.

1. Install, open the app **signed out**, then log in. Run `supabase/push_diagnose.sql`
   (query 1): your account must now show a row with the right platform
   (`ios` / `android`). No row = the phone never registered → check the phone's
   Settings → Notifications → Uniflex is allowed.
2. Lock the phone, trigger any notification from another account. It should
   arrive within seconds, with sound.
3. Log in on a second phone with the same account: both phones get the push.
4. Sign out on one phone: only the other one gets it.
5. iPhone only: if step 1 shows a row but nothing arrives, check Firebase →
   Project settings → Cloud Messaging → the APNs key (p8) is uploaded for
   `com.uniflex.uniflex`; and the App ID has the Push Notifications capability.
   The key must be **Sandbox & Production** — a Sandbox-only key fails on
   TestFlight with `BadEnvironmentKeyInToken`.

## 9. Rider + admin alerts (push_staff_alerts.sql — already applied)

Needs the NEW build on the rider/admin phones (old Android builds never
register a token after login).
1. Rider phone: log in as the rider, switch **online**. From a student
   account place a food delivery → rider gets "New delivery job"; tap → Jobs tab.
2. Same with an errand → "New errand job" with pickup → drop-off.
3. Switch the rider **offline**, place another order → no push.
4. Admin phone: every paid order → "New order" (name · type · shops · ₦ food
   total). Tap → Orders tab.
5. Cancel an order as the student → admins get "Order cancelled … by the
   customer". Cancel one as admin A → admin B is told, admin A is not.

## 10. Pack 1 — check on TestFlight (SQL + functions already live)

1. **Nav gap:** on Home, Orders, Wallet, Profile the glass bar's bottom edge
   sits 20 pt above the screen edge (compare with WhatsApp), in dark and light;
   it never covers the home indicator and the last item of every tab scrolls
   fully above it. To change the gap: `AppSpacing.navBottomGap` (one number).
2. **Border:** look closely at the bar's top edge in dark and in light — it
   should look exactly like the other three sides.
3. **Hidden balance:** a fresh open shows `₦ ••••` on Home and Wallet (fund a
   large balance first: still four dots). The eye on Home shows it on both;
   hiding it on Wallet hides Home too. Log out and in → hidden again.
4. **Taps:** press and hold list rows (Profile, accordions, notifications):
   a soft rounded highlight, no square, no ripple.
5. **Change Transaction PIN:** scroll Profile to the bottom, tap the row ten
   times quickly → one sheet; a spinner shows at once on a slow network.
6. **Fixed-menu vendor:** Admin → Vendors → Add → Ordering style "Fixed menu"
   (pack price disappears) → save → Menu → Add item (name, category e.g.
   "Rice", price) ×3 in two categories. As a student: the vendor page shows one
   dropdown per category, `+` → `− 1 +`, `+` greys out at 20; cart rows have
   steppers and no pack wording; pay the delivery fee; the rider job and the
   student/admin order show `2× Item` lines, no packs. Try switching the
   vendor back to Pack-based while that order is active → refused.
7. **Pack-based vendor:** order from Uniflex exactly as before (packs, spoons,
   drinks, others).
8. **Card top-up (test mode):** Fund Wallet ₦500 → card 4084 0840 8408 4081,
   CVV 408, any future expiry, PIN 0000, OTP 123456 → balance +₦500 once.

mmmmm