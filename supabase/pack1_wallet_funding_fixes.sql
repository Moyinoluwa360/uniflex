-- =====================================================================
-- Pack 1 / Part 4 — wallet funding money-safety fixes (2026-11-12)
--
-- Found on the live project:
--   1. credit_wallet(user, amount, reference) is SECURITY DEFINER and was
--      EXECUTABLE BY anon AND authenticated. Anyone holding the app's public
--      key could credit any wallet any amount without paying. Only the two
--      Edge Functions (service role) are meant to call it.
--   2. _refund_order(order_id) is SECURITY DEFINER, has no caller or status
--      check, and was executable by anon and authenticated: a student could
--      refund an order to themselves (once per order), breaking "no refunds".
--      Its only legitimate caller is update_order_status (SECURITY DEFINER,
--      owner postgres), which is unaffected by this revoke.
--   3. credit_wallet: two simultaneous deliveries of the same reference
--      (webhook + verify call) could both pass the "exists" check; the
--      unique index then failed the second with a raw unique_violation
--      (safe — rolled back — but the caller saw an error). It now answers
--      DUPLICATE_REFERENCE in that case too, and rejects amounts <= 0.
--
-- Idempotent; safe to re-run. Nothing else about the functions changes.
-- =====================================================================

create or replace function public.credit_wallet(
  p_user_id   uuid,
  p_amount    numeric,
  p_reference text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_balance numeric;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;
  if nullif(trim(coalesce(p_reference, '')), '') is null then
    raise exception 'REFERENCE_REQUIRED';
  end if;

  -- Idempotency: reject duplicate Paystack references
  if exists (
    select 1 from public.wallet_transactions
    where reference = p_reference and type = 'credit'
  ) then
    raise exception 'DUPLICATE_REFERENCE';
  end if;

  update public.wallets
    set balance = balance + p_amount
  where user_id = p_user_id
  returning balance into v_new_balance;

  if not found then
    raise exception 'WALLET_NOT_FOUND';
  end if;

  begin
    insert into public.wallet_transactions
      (user_id, type, amount, source, reference, balance_after)
    values
      (p_user_id, 'credit', p_amount, 'topup', p_reference, v_new_balance);
  exception when unique_violation then
    -- A concurrent call credited this reference first; raising here rolls
    -- back the balance update above, so the money is counted exactly once.
    raise exception 'DUPLICATE_REFERENCE';
  end;

  return jsonb_build_object('balance', v_new_balance);
end;
$$;

-- Only the service role (the Edge Functions) may credit a wallet.
revoke all on function public.credit_wallet(uuid, numeric, text) from public, anon, authenticated;
grant execute on function public.credit_wallet(uuid, numeric, text) to service_role;

-- Refunds only through update_order_status / the cancellation rules.
revoke all on function public._refund_order(uuid) from public, anon, authenticated;
grant execute on function public._refund_order(uuid) to service_role;
