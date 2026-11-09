# UI audit (Part A of UI Polish) — drives Pack 2

Read-only audit of `lib/` on 2026-11-09, branch `ui-polish` (cut from `main`).
Numbers come from `grep` and exclude `lib/shared/theme/` unless stated.
"SEEN" = the owner has seen the screen; everything else the owner could not
screenshot, so it needs extra care in Pack 2.

## 0. Corrections to the pack's premise (trust the code)

| Pack said | Code actually has |
|---|---|
| Bricolage Grotesque + Plus Jakarta Sans via `google_fonts` | **Clash Display (Semibold) + Switzer**, bundled in `assets/fonts/`. `google_fonts` was removed earlier (CHANGELOG ~line 2240). `ARCHITECTURE.md` was right. |
| "find the current fire-once helper" | **There is none.** `PrimaryButton` only disables while `isLoading`. Guards are per-screen flags (`_inFlight`, `_isSending`, `_isSubmitting`). `AppButton` therefore ships its own guard. |
| Four-item nav | Student, Rider, Super-admin = 4 tabs. **Kitchen staff = 1 tab.** The glass bar must work for 1..n items. |

## 1. Screens

Navigation is `Navigator.push(MaterialPageRoute)`; no named routes. Shell tabs are in an `IndexedStack`.

### Student (`lib/student/`)
| Screen | File | Seen | Migrated |
|---|---|---|---|
| Home | `home/student_home_screen.dart` (1134 lines) | SEEN | A ✅ |
| Search / All vendors / Ad popup / Ad carousel | `home/search_screen.dart`, `all_vendors_screen.dart`, `ad_popup.dart`, `ad_carousel.dart` | | A (ad carousel + popup ✅; search / all vendors pending C) |
| Orders tabs (Cart / Preparing=Active / Completed) | `orders/orders_screen.dart` | SEEN |  |
| Uniflex vendor page (catalog) | `ordering/catalog_screen.dart` | SEEN |  |
| Food Packs | `ordering/pack_builder_screen.dart` | SEEN |  |
| Your Cart (vendor-grouped) | `ordering/cart_screen.dart` | SEEN |  |
| Checkout | `ordering/checkout_screen.dart` | |  |
| Pay delivery fee (+ PIN sheet) | `ordering/commitment_fee_screen.dart`, `shared/widgets/pin/pin_entry_sheet.dart` | SEEN |  |
| Order confirmation | `ordering/order_confirmation_screen.dart` | |  |
| Track Order / Errand tracking | `tracking/order_tracking_screen.dart` (1467 lines), `errand_tracking_screen.dart` | SEEN (Track Order) |  |
| Wallet | `wallet/wallet_screen.dart` | SEEN |  |
| Saving Plan | `wallet/saving_plan_screen.dart` | SEEN |  |
| Paystack checkout (WebView) | `wallet/paystack_checkout_*.dart` | |  |
| Profile | `profile/student_profile_screen.dart` | SEEN |  |
| Membership card / Badges / Preferences / Refer / Scheduled orders | `profile/*.dart` | |  |
| Notifications | `notifications/notifications_screen.dart` | SEEN |  |
| Gifts (send / list / received) | `gifts/*.dart` | |  |
| Group checkout | `group_checkout/*.dart` | |  |
| Errand create / confirmation | `errand/*.dart` | |  |
| Support options / chat | `support/*.dart` | |  |

### Rider (`lib/rider/`)
Dashboard `dashboard/rider_dashboard_screen.dart` · Job pool `pool/job_pool_screen.dart` · Active jobs `jobs/active_jobs_screen.dart` · Food job `jobs/food_job_screen.dart` (1184) · Errand job `jobs/errand_job_screen.dart` (741) · Delivery complete `jobs/delivery_complete_screen.dart` · History `history/delivery_history_screen.dart`, `rider_history_detail_screen.dart` · Profile `profile/rider_profile_screen.dart`. None seen.

### Admin (`lib/admin/`)
Dashboard `dashboard/admin_dashboard_screen.dart` (+`money_cards.dart`) · Orders `orders/admin_orders_screen.dart`, `admin_order_details_screen.dart` (925) · Kitchen queue `kitchen/kitchen_queue_screen.dart` · Manage hub `manage/manage_hub_screen.dart` · Analytics `analytics/admin_analytics_screen.dart` · Vendors, menu, riders, ads, referrals, errand categories, delivery settings, service charge, scheduled orders, support inbox/chat/settings, profile. None seen.

### Shared / auth (`lib/shared/`)
Splash, auth gate (`router/`), Login, Create account, Verify phone, Complete profile, Forgot / Reset password, Resume OTP (`auth/screens/`), signup steps (`auth/signup/`). None seen.

## 2. Style inventory

| Thing | Count / where | Shared? |
|---|---|---|
| Primary button | `PrimaryButton` ×35 (`widgets/buttons/primary_button.dart`, wraps `ElevatedButton`, orange pill) | shared, **no fire-once guard** |
| Secondary button | `SecondaryButton` ×5 (`OutlinedButton`) | shared |
| Raw buttons | `FilledButton` 57, `TextButton` 60, `OutlinedButton` 28, `ElevatedButton` 5, `IconButton` 35, `FloatingActionButton` 7, `styleFrom` 34 | one-off |
| Solid-red button | `Colors.red`/`AppColors.error` as `foregroundColor`/`backgroundColor`, e.g. `admin_order_details_screen.dart:110,594-595` | one-off |
| Cards | `AppCard` ×1 only; `Card(` 13; hand-built `Container`+`BoxDecoration` is the norm (212 `BorderRadius.circular`, many sizes) | mostly one-off |
| Accordion | `AppAccordionCard` (`widgets/accordions`), used by catalog / pack builder / cart | shared |
| Status pills | `_StatusChip` (`admin_orders_screen.dart:724`), `_StatusBadge` (`admin_order_details_screen.dart:545`), kitchen queue chip, ad status chip (`advertisements_screen.dart:194`), `_Badge` (`student_home_screen.dart:865`) | copies |
| Coloured icon boxes | ~131 `AppColors.X.withValues(alpha:)` fills (452 `withValues(alpha:` in total) | one-off |
| Dialogs | `AlertDialog` 16, `showDialog` 17 | one-off |
| Sheets | `showModalBottomSheet` 12; shared: `acknowledgment_sheet`, `pin_entry_sheet`, `message_customer_sheet` | mixed |
| Snackbars | `SnackBar(` 144 (themed via `snackBarTheme`); `ConnectivityBanner` (own green/red) | one-off content |
| Text fields | `AppTextField` ×80 of 81 (good) | shared |
| Tabs | `TabBar` ×3 (`orders_screen`, `gifts_screen`, `admin_orders_screen`), `SegmentedButton` ×2, `ChoiceChip`/`FilterChip` ×4 | one-off |
| Lists | `ListTile` 10, `Divider` 26, `CircleAvatar` 5, `Switch` 12 | one-off |
| Progress | `CircularProgressIndicator` 82, `LinearProgressIndicator` 4 | one-off |

## 3. Hard-coded colours (outside `theme/`)

Real raw literals are few:
- `Color(0x…)`: **5** — `0xFF25D366` WhatsApp green ×4 (`food_job_screen.dart:652-654`, `errand_job_screen.dart:536-538`), `0xFF2E7D32`/`0xFFC62828` (`connectivity_banner.dart:111`).
- `Color.fromRGBO`: **3** (`splash_screen.dart:76-77,98`).
- `Colors.<x>` (not transparent): **12** — `Colors.red` ×3 (admin order details), `Colors.white` ×6, `Colors.black.withValues` ×3 (`app_accordion_card.dart:76`, `image_upload_field.dart:234`, `student_home_screen.dart:540`). `Colors.transparent`: 3 (allowed).

**The real problem is the legacy `AppColors` palette** (static consts used screen by screen):

| Legacy token | Uses | Files | Issue |
|---|---|---|---|
| `emerald` | 221 | many | used for text, fills, tints |
| `error` | 102 | 34 | solid red buttons, red tints |
| `pureWhite` | 99 | | |
| `orange` | 73 | 25 | spending amounts, statuses, buttons. Worst: `order_tracking_screen` 11, `kitchen_queue_screen` 8, `pack_builder_screen` 7, `student_home_screen` 6, admin orders/details 6+6 |
| `warning` (amber) | 31 | 9 | `order_tracking_screen` 14 |
| `info` (blue) | 26 | 13 | commitment fee, kitchen, tracking, orders |
| `accentViolet` (purple) | 22 | 5 | `errand_job_screen` 14, `rider_job_card` 3, admin orders ×4, `active_jobs_screen` 1 |
| tiers (`tierBronze/Silver/Gold/Platinum`) | 11 | `membership_card_screen`, `student_profile_screen`, `badges_screen` | **Gold exists** (no Gold token in the pack) |

Files with most raw/legacy colour references: `order_tracking_screen` 74, `student_home_screen` 45, `food_job_screen` 28, `orders_screen` 24, `kitchen_queue_screen` 23, `admin_order_details_screen` 22, `errand_job_screen` 20, `admin_orders_screen` 19, `student_profile_screen` 18, `admin_analytics_screen` 17.

Migration approach used by the guard test: legacy `AppColors.<name>` statics stay compiling during Pack 1 and are counted per file in an allowlist (a ratchet) that Pack 2 drives to zero.

## 4. Theme setup
- `lib/shared/theme/app_theme.dart` builds light/dark from the legacy `AppColors` statics. Default button = **orange pill** (`ElevatedButton`), scaffold light `#FFFFFF` / dark `#0C0F0E`, inputs filled with no border, one `bottomNavigationBarTheme`.
- `themeModeProvider` default **`ThemeMode.system`**; a manual System/Light/Dark selector exists in `student/profile/preferences_screen.dart`.
- Brightness/`isDark` checks inside feature files (belong in the theme): 8 auth screens compute `secondaryInk` (`login`, `create_account`, `complete_profile`, `forgot_password`, `reset_password`, `resume_otp`, `verify_phone`, `signup_final_step`), `app_accordion_card.dart:51`, `app_image.dart:75`, `student_home_screen.dart:203,395` (≈14 uses). `ad.isDark` is ad data, not theming.

## 5. Fonts
- `GoogleFonts.`: **0**. Nothing fetched at runtime. `fontFamily:` in features: 1 (`'monospace'`, `create_group_screen.dart:181`).
- Clash Display 600 for display/headline/title slots; Switzer 400/500/600 for body/labels. Wordmark uses Clash Display.
- **Cause of the collapsed word spacing:** Clash Display's space glyph is 0.154 em wide (Switzer 0.20, Plus Jakarta 0.17–0.18) and `_display()` adds `letterSpacing = size × −0.02` to every title/headline. Result: gaps shrink to ≈0.11 em. No `wordSpacing` is set anywhere.
- Neither Clash nor Switzer contains `₦` (U+20A6), and Switzer has no `tnum`; `₦` falls back to the OS font. `tabularFigures` used: 0.
- `letterSpacing` in features (18): all positive, for PIN/OTP/codes (8–16) or small caps labels (0.5–2). Fine.
- `fontSize:` literals 19, `TextStyle(` 24, `FontWeight.` 148, `textTheme.` 660 (healthy).

## 6. Icons
Material Icons only (no Cupertino, no icon package). 476 uses, 143 distinct: 78 `_outlined`, 8 `_rounded`, **57 filled**. 20 glyphs are used in **both** filled and outlined form: account_balance_wallet, bar_chart, dashboard, delivery_dining, emoji_events, history, home, hourglass_empty, inbox, receipt_long, restaurant_menu, restaurant, schedule, search_off, search, storefront, tune, two_wheeler, wifi_off, workspace_premium. Nav uses outline when idle and filled when selected.

## 7. Navigation shells
One shared widget: `widgets/navigation/app_bottom_nav_shell.dart` — `Scaffold(body: SafeArea(IndexedStack), bottomNavigationBar: BottomNavigationBar)`, `AppNavTab(label, icon, selectedIcon, screen)`, `AppNavShellScope.go/currentIndex`, `shellTabRequestProvider`, optional `badgeCounts`. Role shells: Student (Home, Orders, Wallet, Profile), Rider (Home, Jobs, History, Profile), Admin super (Dashboard, Orders, Manage[badge], Analytics), Admin kitchen (Orders only). Tab logic must not change; `AppGlassNavBar` takes the same index + callback.

## 8. Money
No shared formatter, no `intl`. `₦` appears on 124 lines in 42 files: `'₦${x.toStringAsFixed(0)}'` (~40, **no thousands separators**, e.g. `₦39210`), `toStringAsFixed(2)` ×5 (`₦39210.00`), one private comma formatter in `admin/dashboard/money_cards.dart:23`, hard-typed literals (`₦5,000`, `₦500,000`, tier thresholds), and `prefixText: '₦ '` ×4. No tabular figures anywhere.

## 9. Status values and labels

`OrderStatus` (9, `shared/models/order.dart`): placed "Order Placed", preparing "Preparing", ready "Ready", out_for_delivery "Out for Delivery", ready_for_pickup "Ready for Pickup", completed "Completed", cancelled "Cancelled", being_sourced "Being Sourced", awaiting_final_payment "Awaiting Final Payment".
`DeliveryGroupStatus` (7, `shared/models/delivery_group.dart`): placed "Placed", commitment_paid **"In Rider Pool"**, rider_accepted "Rider Accepted", awaiting_final_payment "Awaiting Payment", out_for_delivery, completed, cancelled.
Gift status (strings, `gift_models.dart:59`): preparing "Being prepared", on_the_way "On its way", delivered, cancelled, default "Order placed".
Errand display override (`student_home_screen.dart:1004`): placed "Errand placed", being_sourced "Rider assigned", out_for_delivery "On the way".
Others (not order status): ad Live/Paused/Scheduled/Ended (`advertisement.dart:88`); support conversation open/resolved.

Status → colour is re-implemented in: `admin_orders_screen.dart:299,553`, `admin_order_details_screen.dart:437-454`, `kitchen_queue_screen.dart:641`, `student_home_screen.dart:~995`, `order_tracking_screen.dart`, `errand_tracking_screen.dart`, `orders_screen.dart`, `rider_job_card.dart`, `advertisements_screen.dart:133`. They use orange / blue / purple / amber / red inconsistently (e.g. `placed` is orange in admin, `awaitingFinalPayment` is blue).

## 10. The two cart UIs
- **Orders → Cart** (`orders_screen.dart` `_CartTab`, ~l.61-195): flat `ListView.separated` of `Row`s: `"{qty}× {name}"`, options summary, `₦` line total, bare `GestureDetector` ✕ → `cartProvider.notifier.removeAt(i)`; subtotal row + a checkout `PrimaryButton`. No vendor grouping, no images.
- **Your Cart** (`ordering/cart_screen.dart`): vendor-grouped via `_VendorItemList` and `_CartItemTile` (48×48 `AppImage` thumbnail, name, options, qty stepper `_SmallButton`), delivery/service-charge lines, per-vendor accordion.
Both read `cartProvider` (`cart.items`, `item.lineTotal`, `item.optionsSummary`, `removeAt`, `subtotal`). They can share a presentation-only item row and a vendor-group header **without touching `cart_provider.dart`**; `_CartItemTile` takes `dynamic item` (typing it as `CartItem` is a safe Pack 2 cleanup).

## 11. Report-only findings (not fixed)
1. `admin/referrals/referral_code_form_screen.dart:217` says a student earns ₦500 "each time someone signs up with the code **and completes a first order**". The owner's rule is **referral = sign-ups only**; text contradicts it (and `_after_order_completed` may still pay a first-order bonus — already an open item).
2. `badges_screen.dart:149` "Place your first order" is a badge, not a referral; fine, listed for completeness.
3. No `autovalidateMode` is passed by any caller (only the field supports it), so premature validation messages come from submit-time validators, not live validation; check each form in Pack 2 by reading, not assuming.
4. `DeliveryGroupStatus.commitmentPaid` label "In Rider Pool" is internal wording; Part B changes only the display to "Finding a rider" (enum untouched).
5. Three statuses are reachable from `OrderStatus.fromString` only via the `_ => placed` fallback: an unknown server status silently renders "Order Placed".
6. `_CartItemTile.item` is `dynamic` (type safety).
7. Only `PrimaryButton` is shared; ~150 raw `FilledButton`/`TextButton`/`OutlinedButton` calls will each need a decision (replace with `AppButton`, or leave in dialogs).
8. Tapping an old notification: `notification_router.dart` opens the order screen from the payload without checking the order's current state (read-only note — verify in Pack 2 whether a stale "pay now" notification can open a pay sheet for an order that is already paid/cancelled).
