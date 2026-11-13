-- =====================================================================
-- Pack 2 / S-15 — make 3 test wallets' history match their balance
-- (owner, 2026-11-13: option A). Balances do NOT change.
--
-- Three test accounts (wallet ids b78cc15d…, 5d6cdb88…, 223683c7…) were
-- seeded with ₦10,000 written straight into wallets.balance in testing, so
-- balance = sum(ledger) + 10,000. This adds the missing ledger row
-- (credit, source 'adjustment', unique reference) so they agree again.
--
-- Idempotent: only wallets that are still exactly ₦10,000 off and have no
-- adjustment row get one. Test: pack2_wallet_ledger_adjustment_test.sql.
-- Rollback:
--   delete from public.wallet_transactions where reference like 'ADJ-PACK2-SEED-%';
-- (the source value can stay; it is unused without rows.)
-- =====================================================================

alter table public.wallet_transactions drop constraint if exists wallet_transactions_source_check;
alter table public.wallet_transactions add constraint wallet_transactions_source_check
  check (source = any (array['topup', 'order_payment', 'refund', 'commitment_fee',
    'referral_bonus', 'gift_payment', 'birthday_reward', 'group_order_payment',
    'account_deleted', 'adjustment']));

with gaps as (
  select w.user_id, w.balance,
         w.balance - coalesce((select sum(case when t.type = 'credit' then t.amount else -t.amount end)
                                 from public.wallet_transactions t
                                where t.user_id = w.user_id), 0) as gap
    from public.wallets w
   where left(w.user_id::text, 8) in ('b78cc15d', '5d6cdb88', '223683c7')
)
insert into public.wallet_transactions (user_id, type, amount, source, balance_after, reference, created_at)
select g.user_id, 'credit', g.gap, 'adjustment', g.gap,
       'ADJ-PACK2-SEED-' || left(g.user_id::text, 8),
       -- dated before the wallet's first real entry, where the seeding happened
       coalesce((select min(t.created_at) from public.wallet_transactions t
                  where t.user_id = g.user_id), now()) - interval '1 second'
  from gaps g
 where g.gap = 10000
   and not exists (select 1 from public.wallet_transactions t
                    where t.reference = 'ADJ-PACK2-SEED-' || left(g.user_id::text, 8));
