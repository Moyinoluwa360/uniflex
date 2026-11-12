-- =====================================================================
-- Pack 1 / Part 4 — SQL test for the wallet funding fixes.
-- Run AFTER pack1_wallet_funding_fixes.sql:
--   supabase db query --linked -f supabase/pack1_wallet_funding_fixes_test.sql
-- One transaction; the last block RAISES the PASS/FAIL log, which rolls
-- everything back (no test user, wallet or credit survives).
-- =====================================================================
begin;

create schema uf_t4;
grant usage on schema uf_t4 to public;

create function uf_t4.ok(p_name text, p_cond boolean) returns void
language plpgsql as $$
begin
  perform set_config('uf.log',
    coalesce(current_setting('uf.log', true), '') ||
    case when coalesce(p_cond, false) then 'PASS  ' else 'FAIL  ' end ||
    p_name || E'\n', true);
end $$;
grant execute on function uf_t4.ok(text, boolean) to public;

create function uf_t4.raises(p_sql text, p_expect text) returns boolean
language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return position(p_expect in sqlerrm) > 0;
end $$;
grant execute on function uf_t4.raises(text, text) to public;

do $$
declare
  s uuid := gen_random_uuid();
  o uuid := gen_random_uuid();
  bal numeric;
  n int;
  v_ref text := 'P1T4-' || gen_random_uuid();
begin
  insert into auth.users (id, email) values (s, 'p1t4@example.invalid'), (o, 'p1t4o@example.invalid');
  insert into public.profiles (id, role, email, nickname, full_name, phone, matric_number, onboarding_complete)
  values (s, 'student', 'p1t4@example.invalid', 'p1t4', 'P1 T4', '+2348090000001', 'MAT/P1T4', true),
         (o, 'student', 'p1t4o@example.invalid', 'p1t4o', 'P1 T4 Other', '+2348090000002', 'MAT/P1T4O', true);
  insert into public.wallets (user_id, balance, virtual_account_number)
  values (s, 0, 'UFX-P1T4-' || left(s::text, 6)), (o, 0, 'UFX-P1T4-' || left(o::text, 6));

  -- 1. App users can no longer call the money functions.
  perform uf_t4.ok('W1 anon cannot execute credit_wallet',
    not has_function_privilege('anon', 'public.credit_wallet(uuid,numeric,text)', 'execute'));
  perform uf_t4.ok('W2 authenticated cannot execute credit_wallet',
    not has_function_privilege('authenticated', 'public.credit_wallet(uuid,numeric,text)', 'execute'));
  perform uf_t4.ok('W3 service_role (Edge Functions) still can',
    has_function_privilege('service_role', 'public.credit_wallet(uuid,numeric,text)', 'execute'));
  perform uf_t4.ok('W4 nobody in the app can call _refund_order directly',
    not has_function_privilege('anon', 'public._refund_order(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public._refund_order(uuid)', 'execute'));

  perform set_config('request.jwt.claims',
    json_build_object('sub', s, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform uf_t4.ok('W5 a student calling credit_wallet on themselves is refused',
    uf_t4.raises(format($q$select public.credit_wallet(%L, 1000000, 'free-money')$q$, s), 'permission denied'));
  reset role;
  perform uf_t4.ok('W6 … and their balance did not move',
    (select balance from public.wallets where user_id = s) = 0);

  -- 2. Crediting (as the service role does).
  perform public.credit_wallet(s, 2500, v_ref);
  perform uf_t4.ok('W7 a verified top-up credits once',
    (select balance from public.wallets where user_id = s) = 2500);
  perform uf_t4.ok('W8 the same reference again → DUPLICATE_REFERENCE, no second credit',
    uf_t4.raises(format($q$select public.credit_wallet(%L, 2500, %L)$q$, s, v_ref), 'DUPLICATE_REFERENCE')
    and (select balance from public.wallets where user_id = s) = 2500);
  perform uf_t4.ok('W9 the same reference for ANOTHER user is also refused',
    uf_t4.raises(format($q$select public.credit_wallet(%L, 2500, %L)$q$, o, v_ref), 'DUPLICATE_REFERENCE')
    and (select balance from public.wallets where user_id = o) = 0);
  perform uf_t4.ok('W10 zero / negative amounts are refused',
    uf_t4.raises(format($q$select public.credit_wallet(%L, 0, 'z-%s')$q$, s, s), 'INVALID_AMOUNT')
    and uf_t4.raises(format($q$select public.credit_wallet(%L, -50, 'n-%s')$q$, s, s), 'INVALID_AMOUNT'));
  perform uf_t4.ok('W11 an unknown wallet is refused (and leaves no ledger row)',
    uf_t4.raises(format($q$select public.credit_wallet(%L, 100, 'u-%s')$q$, gen_random_uuid(), s), 'WALLET_NOT_FOUND')
    and not exists (select 1 from public.wallet_transactions where reference = 'u-' || s));

  -- 3. Ledger and balance agree.
  select count(*) into n from public.wallet_transactions where user_id = s;
  perform uf_t4.ok('W12 balance = sum of the ledger (one credit row)',
    n = 1 and (select balance from public.wallets where user_id = s) =
      (select sum(case when type = 'credit' then amount else -amount end)
         from public.wallet_transactions where user_id = s));
end $$;

do $$
begin
  raise exception 'PACK1 PART4 TEST RESULTS (rolled back):%', E'\n' || current_setting('uf.log', true);
end $$;
