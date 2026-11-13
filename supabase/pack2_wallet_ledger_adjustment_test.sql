-- Pack 2 — test for pack2_wallet_ledger_adjustment.sql. Run AFTER it (or
-- prepend it to dry-run). One transaction, always rolled back.
begin;

do $$
declare
  log text := '';
  n_off int; n_adj int; n_neg int;
begin
  select count(*) into n_off from public.wallets w
   where w.balance <> coalesce((select sum(case when t.type = 'credit' then t.amount else -t.amount end)
                                  from public.wallet_transactions t where t.user_id = w.user_id), 0);
  select count(*) into n_adj from public.wallet_transactions where reference like 'ADJ-PACK2-SEED-%';
  select count(*) into n_neg from public.wallets where balance < 0;
  log := log || case when n_off = 0 then 'PASS' else 'FAIL' end || '  A1 every wallet balance = sum of its ledger (' || n_off || ' off)' || E'\n';
  log := log || case when n_adj = 3 then 'PASS' else 'FAIL' end || '  A2 exactly 3 adjustment rows (' || n_adj || ')' || E'\n';
  log := log || case when not exists (select 1 from public.wallet_transactions
                       where reference like 'ADJ-PACK2-SEED-%' and (amount <> 10000 or type <> 'credit'))
                then 'PASS' else 'FAIL' end || '  A3 each is a ₦10,000 credit' || E'\n';
  log := log || case when n_neg = 0 then 'PASS' else 'FAIL' end || '  A4 no negative balances' || E'\n';
  raise exception 'PACK2 LEDGER ADJUSTMENT TEST (rolled back):%', E'\n' || log;
end $$;
