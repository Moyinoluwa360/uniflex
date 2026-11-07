-- =====================================================================
-- SUPERSEDED / APPLIED 2026-11-07: the owner approved R1-R8. They were
-- applied (with R5 replaced by the stricter R6) by supabase/pack_4b_followup.sql.
-- Kept only as the record of what was proposed. DO NOT RUN. R9 (test data)
-- is still open and is NOT in any script.
-- =====================================================================
-- =====================================================================
-- Pack 4B Part B — REMOVAL — DO NOT RUN UNTIL APPROVED
-- =====================================================================
-- Nothing in this file has been run, and it cannot run as-is: the guard
-- below raises an error. To apply an item, the OWNER approves it by id
-- (R1, R2, ...). Then delete the guard and any items NOT approved, take a
-- backup, run the rest in one go, and re-run supabase/pack_4b_test.sql.
-- Plain `drop` (no cascade) is used on purpose: if something still depends
-- on an object, the statement fails and nothing is lost.
-- =====================================================================

do $$ begin
  raise exception 'NOT APPROVED — remove this guard only after the owner approves the items below.';
end $$;

begin;

-- R1  get_group_items — broken for riders, replaced by get_order_breakdown.
--     Risk: OLD rider builds still call it (they already fail on it).
drop function if exists public.get_group_items(uuid);

-- R2  Rider "sourcing / flag item / custom item" chain for deliveries.
--     Current delivery flow: rider sets ONE final price. None of these is
--     called by the Dart apps (checked: lib/ and supabase/functions/).
--     Risk: rows in order_item_flags / order_custom_items are lost —
--     run pack_4b_audit_queries.sql #5 first; export if the counts are > 0.
drop function if exists public.confirm_pickup(uuid);
drop function if exists public.confirm_group_leg_pickup(uuid);
drop function if exists public.confirm_group_leg_sourcing(uuid, numeric);
drop function if exists public.confirm_sourced_items(uuid, numeric);
drop function if exists public.flag_item_unavailable(uuid, uuid, text, integer);
drop function if exists public.add_custom_item(uuid, text, numeric);
drop function if exists public.approve_custom_item(uuid);
drop function if exists public.reject_custom_item(uuid);
drop table    if exists public.order_item_flags;
drop table    if exists public.order_custom_items;

-- R3  Helpers with no caller in the apps, Edge Functions or other SQL.
--     (update_delivery_setting and unread_notification_count are KEPT:
--      admin tooling / the notification inbox may still need them.)
drop function if exists public.cancel_delivery_group_before_accept(uuid);
drop function if exists public.any_riders_available();
drop function if exists public._delivery_fee_from_settings(text);

-- R4  Old kitchen -> group hand-off trigger. A kitchen "ready" on ONE vendor
--     part can flip the WHOLE group to awaiting_final_payment with no rider
--     and no price. The new flow never needs it.
--     Risk: none for the current flow; legacy kitchen-driven groups (none
--     expected) would no longer advance by themselves.
drop trigger  if exists check_group_ready on public.orders;
drop function if exists public._check_group_ready_after_kitchen();

-- R5  Old rider pool visibility on `orders` (pre-group delivery flow:
--     source='uniflex'/'partner' deliveries and the retired 'around' type).
--     Current pool = rider_job_pool() + errands (type='errand', placed, paid).
--     Replaces two policies; the other policies on `orders` are untouched.
--     Risk: medium — re-run pack_4b_test.sql after this; riders'
--     live refresh of errands depends on the errand branch kept below.
drop policy if exists "orders: rider read pool" on public.orders;
drop policy if exists "job_pool_read" on public.orders;
create policy "job_pool_read" on public.orders for select using (
     (student_id = auth.uid())
  or (select public.is_admin())
  or (rider_id = auth.uid())
  or (type = 'errand' and status = 'placed' and commitment_fee_paid = true)
);

-- R6  (NOT IN THIS BLOCK — needs a design decision, see PACK_4B_AUDIT.md #1)
--     Assigned riders can read delivery_pin and the fee columns straight
--     from delivery_groups / orders. Proposed fix: move delivery_pin and the
--     fee columns into a private table the student and admin can read, and
--     keep the riders' row-level access on the remaining columns.

-- R7  (OPTIONAL, ask first) delivery_records is written by the verify
--     functions and read by nothing. Proposal: stop writing it, then drop it.
--     -- drop table public.delivery_records;   -- NOT approved by default

-- R8  (OPTIONAL, ask first) Per-leg profile counters.
--     _after_order_placed adds +1 total_orders for EVERY vendor part.
--     Proposal: count once per checkout. This is a rewrite, not a removal.

-- R9  Leftover test data: fill the ids in from pack_4b_audit_queries.sql
--     #1/#2/#7, one reviewed DELETE per batch. Not generated blindly.

commit;
