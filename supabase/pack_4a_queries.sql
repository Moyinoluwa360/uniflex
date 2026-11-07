-- =====================================================================
-- Pack 4A — read-only queries and the optional clean-up
-- Paste each block into the Supabase SQL editor on its own.
-- Blocks 1-4 only READ. Block 5 is the optional clean-up (it changes
-- rows, deletes nothing) — run it only after reading block 1.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Orders that were NEVER PAID (left by the old "Place order" button)
--    "not pickup, commitment fee not paid, still placed"
--    Run this in the SQL editor (it sees everything; the app cannot see
--    these rows any more — they are hidden from students, riders, Admin
--    lists, the rider pool and analytics once pack_4a.sql has run).
-- ---------------------------------------------------------------------
-- 1a. Standalone orders
select o.id,
       left(o.id::text, 8)                     as short_id,
       p.nickname, p.full_name,
       o.type, o.source, o.delivery_type,
       o.total_amount, o.status, o.created_at
  from public.orders o
  join public.profiles p on p.id = o.student_id
 where o.delivery_group_id is null
   and not o.is_paid
   and o.status = 'placed'
 order by o.created_at desc;

-- 1b. Delivery groups (and how many legs each one dragged along)
select g.id,
       left(g.id::text, 8)                     as short_id,
       p.nickname, p.full_name,
       g.commitment_fee_total, g.status, g.created_at,
       (select count(*) from public.orders o where o.delivery_group_id = g.id) as legs
  from public.delivery_groups g
  join public.profiles p on p.id = g.student_id
 where not g.is_paid
   and g.status = 'placed'
 order by g.created_at desc;

-- 1c. Sanity check — a real wallet debit must never exist for an unpaid row
select o.id, wt.amount, wt.created_at
  from public.orders o
  join public.wallet_transactions wt on wt.order_id = o.id and wt.type = 'debit'
 where not o.is_paid;
-- (expected: zero rows)


-- ---------------------------------------------------------------------
-- 2. Every deployed signature of the support functions
--    Exactly ONE row per function name is correct. Two rows for
--    send_support_message was the bug.
-- ---------------------------------------------------------------------
select p.proname                          as function,
       pg_get_function_identity_arguments(p.oid) as arguments,
       p.oid::regprocedure                as signature
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('send_support_message', 'mark_support_read',
                     'resolve_support_conversation', 'get_support_unread_total')
 order by p.proname, 2;

-- 2b. Same check for every other function that exists more than once
--     under the same name (this is how set_transaction_pin was found).
select proname, count(*) as copies,
       string_agg(pg_get_function_identity_arguments(oid), '  |  ') as signatures
  from pg_proc
 where pronamespace = 'public'::regnamespace
 group by proname
having count(*) > 1
 order by proname;


-- ---------------------------------------------------------------------
-- 3. Push pipeline health
-- ---------------------------------------------------------------------
-- 3a. The two settings the database trigger needs to call the Edge
--     Function. Both must be non-empty. (They were already set for the
--     support-chat push; if either is NULL/empty, set them:
--       alter database postgres set app.supabase_project_url = 'https://YOUR_REF.supabase.co';
--       alter database postgres set app.supabase_service_role_key = 'YOUR_SERVICE_ROLE_KEY';
--     then reconnect / reload.)
select current_setting('app.supabase_project_url', true)              as project_url,
       (current_setting('app.supabase_service_role_key', true) <> '') as has_service_key;

-- 3b. pg_net installed?
select extname from pg_extension where extname = 'pg_net';

-- 3c. Which triggers push? Expect: notifications_push on notifications,
--     on_support_message_insert on support_messages (rows only, no HTTP).
select event_object_table as "table", trigger_name
  from information_schema.triggers
 where trigger_schema = 'public'
   and trigger_name in ('notifications_push', 'on_support_message_insert',
                        'delivery_groups_notify', 'orders_notify')
 order by 1, 2;

-- 3d. Is an OLD Database Webhook still pointing at support-notify?
--     (If this returns a row for support_messages, DELETE it in
--      Dashboard -> Database -> Webhooks, or support replies will push twice.)
select * from supabase_functions.hooks;
-- (If this errors with "relation does not exist", you have no webhooks: fine.)

-- 3e. Did pg_net actually fire for recent notifications? (latest 10 calls)
select id, status_code, error_msg, created
  from net._http_response
 order by created desc
 limit 10;

-- 3f. Latest notifications and whether a device token exists to push to
select n.created_at, n.type, n.title, n.body, n.read_at,
       (p.fcm_token is not null) as user_has_device_token
  from public.notifications n
  join public.profiles p on p.id = n.user_id
 order by n.created_at desc
 limit 20;


-- ---------------------------------------------------------------------
-- 4. Current service charge
-- ---------------------------------------------------------------------
select key, value, updated_at from public.app_settings where key = 'service_charge';


-- ---------------------------------------------------------------------
-- 5. OPTIONAL clean-up — mark the never-paid orders CANCELLED
--    Review block 1 first. Nothing is deleted; the rows stay hidden from
--    the app either way (is_paid = false). This just makes their status
--    honest for anyone querying the table directly.
--    No notification is sent for them (the triggers skip unpaid rows).
-- ---------------------------------------------------------------------
-- begin;
--   update public.delivery_groups set status = 'cancelled'
--    where not is_paid and status = 'placed';
--   update public.orders          set status = 'cancelled'
--    where not is_paid and status = 'placed';
-- commit;
