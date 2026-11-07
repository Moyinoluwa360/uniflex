# Pack 4B — Part B: old-logic audit

**Status 2026-11-07:** the owner approved R1–R8, the rider PIN/fee fix (#1) and
the kitchen queue fix (#5). Applied to live by `supabase/pack_4b_followup.sql`
(R5 was replaced by the stricter R6: riders now have no table access at all).
Dart deletions done. **Still open:** R9 (test accounts/data) and the Dart
branches for legacy `around` / standalone-food sourcing (#7), and the
per-leg referral trigger (#11, kept — it pays once). The tables below are the
original report.

Evidence: Dart (`lib/`, `test/`), every `supabase/*.sql`, the Edge Functions, and
the *local* Postgres rebuilt from the full migration history (function bodies,
triggers, policies, constraints). **The live database was not queried** (the
CLI login reverted mid-pack) — `supabase/pack_4b_audit_queries.sql` is the
read-only script to run there; items marked "live?" depend on its output.

| # | What | Where used | Needed by current logic? | Proposal | Removal risk |
|---|------|-----------|--------------------------|----------|--------------|
| 1 | **Riders can read `delivery_pin`, `commitment_fee_total`, `service_charge` (and the legs' PIN) straight from `delivery_groups` / `orders`** via the rider RLS policies ("rider pool and assigned", "rider read group legs", "rider read own assigned"). Probe on the local DB as an assigned rider: `delivery_pin=CYSA commitment_fee=300 service_charge=30 leg_pin=D5BG`. | Policies in `schema.sql`/`round8`; `RiderService.streamGroupDetail` selects `*` | **No.** The app never shows them, but a rider can fetch the PIN and verify a delivery without the customer, and "riders never see fees" only holds in the UI. | **Needs your decision (R6).** Move PIN + fee columns to a private table the student/admin read; riders keep row access to the rest. Not in the removal block (it is a redesign, and rider live-updates depend on these policies). | High value, medium effort. |
| 2 | `get_group_items(uuid)` | Old rider `getGroupItems` (removed) | No — **this was A1**: `jsonb_agg(vendor_row order by vendor_name)` references a column that does not exist (`column "vendor_row" does not exist`), so it failed for every real group. Replaced by `get_order_breakdown`. | Drop (**R1**). | Old rider builds already fail on it. |
| 3 | Rider sourcing chain for deliveries: `confirm_pickup`, `confirm_group_leg_pickup`, `confirm_group_leg_sourcing`, `confirm_sourced_items`, `flag_item_unavailable`, `add_custom_item`, `approve_custom_item`, `reject_custom_item`; tables `order_item_flags`, `order_custom_items` (+ their rider/student policies) | No caller in Dart or Edge Functions. Student code: `pendingCustomItemsProvider`, `approveCustomItem`, `rejectCustomItem` (order_repository.dart), `adjust_order_screen.dart` (never opened from anywhere) | No — delivery = rider sets one final price. | Drop functions + tables (**R2**) and delete the Dart (below). | Rows in the two tables are lost → run audit query #5 first (live?). |
| 4 | Trigger `check_group_ready` / `_check_group_ready_after_kitchen` | Fires on every `orders` update | No, and **it is hazardous**: when kitchen marks the vendor parts `ready` it flips the whole group to `awaiting_final_payment` with no rider and no price. Reachable because the Admin kitchen queue (item 5) lists group legs. | Drop (**R4**). | None for the current flow. |
| 5 | Admin kitchen queue streams **all** `type='food'` orders, including vendor parts of deliveries, with preparing/ready/transfer buttons (`streamKitchenOrders`, `kitchen_queue_screen.dart`, `update_order_status`, `transfer_order_to_rider`, `deliveryStage=='picked_up'` text) | Admin → Kitchen | Only pickup orders need a kitchen. Deliveries are sourced by the rider. | Filter the queue to `delivery_group_id is null` + `delivery_type='pickup'`, and drop the transfer/picked-up UI. Not done in 4B: it is an Admin screen change — say if you want it in this pack or 4C. | Low once filtered. |
| 6 | Old rider pool visibility on `orders`: policy "orders: rider read pool" and the `source='uniflex' … ready/transferred`, `source='partner' … being_sourced`, `type='around'` branches of `job_pool_read` | RLS | No. Pool = `rider_job_pool()`; only the errand branch is needed (kept as the live-refresh trigger). | Replace by the slim policy in **R5**. | Medium — re-run `pack_4b_test.sql`; check audit #1/#2 for legacy rows first (live?). |
| 7 | Legacy order types/statuses: `'around'` (`Order.isErrand`, `admin_service` errand filter, `_after_order_placed`), `being_sourced` / `awaiting_final_payment` on **standalone food** (`order_tracking_screen` sourcing UI + "flagged items" text, `Order` enum, `orders_status_check`) | Student tracking, Admin | `being_sourced` is **still used by errands** (keep). `around`, food `being_sourced`/`awaiting_final_payment` are not produced any more. | Delete the Dart branches after audit #1/#2 show no live rows; then tighten `orders_type_check` (already `food/errand`) and drop `'around'` mentions. Not removed now (not provably unused on live). | Low–medium. |
| 8 | `delivery_type` values `campus_delivery`, `hostel_delivery`; `vendors.campus_delivery_fee/hostel_delivery_fee`; `_delivery_fee()` / `_delivery_fee_from_settings()`; `Order.isCampus…` | `orders_delivery_type_check`, `vendor.dart`, SQL helpers | Delivery fee is now location-based (`delivery_locations`, `_pack_brackets`). `_delivery_fee_from_settings` has no caller (**R3**). `_delivery_fee` is still called by older SQL. | Drop `_delivery_fee_from_settings` now (R3); the rest after the gifting/group pack. | Low. |
| 9 | `source='uniflex'` special-casing for deliveries | `orders_source_check`, kitchen queue header text, `create_errand_screen` (`source:'uniflex'`) | Still set on every order; only the *delivery-specific* branches (items 5/6) are old. | Remove with 5/6; keep the column. | Low. |
| 10 | `checkout_group_order` ×2 and `send_gift` ×2 overloads (no-PIN and PIN versions); shared-basket `group_orders`/`join_group_order`/`create_group_order` | `student_service.dart`, `group_checkout/*` | Group-basket and gifting are a different feature, not touched by 4B. The overloads are the same PostgREST ambiguity that broke support chat. | Drop the no-PIN overloads **in the gifting / group pack** (commented out, not in the block). | Medium (gifting flow). |
| 11 | Per-leg counting: `_after_order_placed` adds `total_orders + 1` for **each vendor part**; `_after_order_completed` (referral bonus) runs per leg (it happens to pay once because of the `referral_credits` guard) | Triggers on `orders` | Behaviour is counted per vendor, not per checkout. | **R8** — rewrite to count once per checkout (needs approval; it changes stats). | Changes lifetime stats. |
| 12 | `delivery_records` (one row **per leg**) — written by the verify functions, read by nothing now (history uses `rider_history()`); `rating` unused | SQL only | No. | Optional **R7**: stop writing, then drop. | Loses history rows; back-fill already aligned them. |
| 13 | Unused providers/models in the rider layer | see Dart list | No | Delete (below). | None. |
| 14 | Leftover test data in obsolete states | live DB | — | Not touched; **audit queries #1–#4, #7** list candidates. Deletes only after you review. | — |
| 15 | `unread_notification_count`, `update_delivery_setting` — no caller in the apps | SQL | Possibly (inbox, admin tooling) | **Keep**, revisit in 4C. | — |

## Dart deletion list (do NOT delete until approved)

Files with no remaining importer (verified by grep):
- `lib/rider/delivery/active_delivery_screen.dart` (redirect stub)
- `lib/rider/delivery/group_delivery_screen.dart` (redirect stub)
- `lib/rider/delivery/delivery_record.dart`
- `lib/rider/pool/pool_group.dart`
- `lib/rider/pool/pool_order.dart`
- `lib/student/ordering/adjust_order_screen.dart` (never opened) and `orderItemFlagsProvider`
- `lib/shared/models/custom_order_item.dart` + `pendingCustomItemsProvider`, `approveCustomItem`, `rejectCustomItem` in `lib/student/ordering/order_repository.dart`

Code inside kept files (after approval of items 5/7):
- `GroupCustomerInfo.deliveryPin` (always null now) in `rider_service.dart`
- Sourcing / "flagged items" blocks and `beingSourced` steps for standalone *food* in `order_tracking_screen.dart` (errand `beingSourced` stays)
- Kitchen transfer / picked-up UI in `kitchen_queue_screen.dart`
- `'around'` fallbacks in `order.dart` and `admin_service.dart`

The matching SQL is `supabase/pack_4b_removal_PENDING_APPROVAL.sql` (guarded so
it cannot run; dry-run on a throwaway local DB succeeded and was rolled back).
