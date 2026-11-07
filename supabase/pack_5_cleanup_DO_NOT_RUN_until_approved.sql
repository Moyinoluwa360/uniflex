-- =====================================================================
-- !!!  CLEANUP — DO NOT RUN UNTIL APPROVED BY THE OWNER  !!!
--
-- Removes stuck legacy sign-ups (see pack_5_legacy_accounts.sql) that are
-- OLDER than the threshold below and have NEVER been used for anything
-- (no orders, wallet balance 0). Deleting the auth user cascades to its
-- stub profile / wallet / PIN rows.
--
-- This file is built so that running it by accident changes nothing:
--   step 1 shows exactly what WOULD be deleted,
--   step 2 deletes inside a transaction,
--   and the transaction ends in ROLLBACK. To really delete, the owner must
--   (a) review step 1's list, then (b) change the last line to COMMIT.
-- NOT run by Claude. NOT applied to live.
-- =====================================================================
begin;

-- threshold: 14 days old or more
create temp table _stale_stubs on commit drop as
select u.id, u.email, u.created_at
from auth.users u
left join public.profiles p on p.id = u.id
where (p.id is null or (p.onboarding_complete = false and p.role = 'student'))
  and u.created_at < now() - interval '14 days'
  and not exists (select 1 from public.orders o where o.student_id = u.id)
  and coalesce((select w.balance from public.wallets w where w.user_id = u.id), 0) = 0;

-- step 1: WHAT WOULD BE DELETED
select * from _stale_stubs order by created_at;

-- step 2: delete them
delete from auth.users where id in (select id from _stale_stubs);

-- step 3: leave this as ROLLBACK until the owner approves, then change to COMMIT
rollback;
