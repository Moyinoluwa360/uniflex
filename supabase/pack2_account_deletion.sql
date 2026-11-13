-- =====================================================================
-- Pack 2 — in-app account deletion (Apple 5.1.1(v), Google Play
-- User Data policy). 2026-11-12. Run AFTER pack2_security_hardening.sql.
-- Idempotent. Test: pack2_account_deletion_test.sql (rolled back).
-- Rollback: drop function public.delete_my_account(text); and restore the
-- old wallet_transactions_source_check (list without 'account_deleted').
--
-- Owner decision (2026-11-12, matches https://uniflex.live/delete-account):
--   * refused while any paid order, errand or delivery (also a gift being
--     delivered TO the student) is still in progress;
--   * a positive wallet balance is forfeited — the app shows it first and
--     the student confirms with their transaction PIN;
--   * the login and every personal field are removed; orders and wallet
--     records are KEPT for financial records with no name, email, phone,
--     matric number, address or message attached.
--
-- Why the login row is scrubbed instead of deleted: deleting auth.users
-- cascades to profiles → orders, wallet_transactions, delivery_groups (ON
-- DELETE CASCADE), which would destroy the financial records the policy
-- keeps. Instead the auth row keeps only its random id: email replaced by
-- an undeliverable placeholder, password randomised, identities / sessions /
-- refresh tokens / MFA removed, banned for 100 years. Nobody can sign in to
-- it and nothing in it identifies the person; the email and phone can be
-- used again for a new account.
--
-- Only students delete themselves in the app. Rider / admin accounts are
-- created by admins and removed by admins (STAFF_ACCOUNT).
-- =====================================================================

-- The forfeited balance is written to the ledger so balance = sum(ledger).
alter table public.wallet_transactions drop constraint if exists wallet_transactions_source_check;
alter table public.wallet_transactions add constraint wallet_transactions_source_check
  check (source = any (array['topup', 'order_payment', 'refund', 'commitment_fee',
    'referral_bonus', 'gift_payment', 'birthday_reward', 'group_order_payment',
    'account_deleted']));

create or replace function public.delete_my_account(p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid      uuid := auth.uid();
  v_profile  public.profiles%rowtype;
  v_status   text;
  v_balance  numeric := 0;
  v_forfeit  numeric := 0;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;

  select * into v_profile from public.profiles where id = v_uid for update;
  if not found then raise exception 'PROFILE_NOT_FOUND'; end if;
  if v_profile.role <> 'student' then
    return jsonb_build_object('error', 'STAFF_ACCOUNT');
  end if;

  -- Counted PIN check (returned, not raised, so the lockout persists).
  v_status := public._check_transaction_pin(p_pin);
  if v_status <> 'ok' then
    return jsonb_build_object('error', case v_status
      when 'locked'  then 'PIN_LOCKED'
      when 'not_set' then 'PIN_NOT_SET'
      else 'INVALID_PIN' end);
  end if;

  -- Nothing may be in progress (paid rows only — unpaid rows are invisible
  -- leftovers and can never move).
  if exists (select 1 from public.orders
              where student_id = v_uid and coalesce(is_paid, true)
                and status not in ('completed', 'cancelled'))
     or exists (select 1 from public.delivery_groups
                 where (student_id = v_uid or gift_recipient_id = v_uid)
                   and coalesce(is_paid, true)
                   and status not in ('completed', 'cancelled')) then
    return jsonb_build_object('error', 'ACTIVE_ORDERS');
  end if;

  -- Forfeit the balance through the ledger (owner policy).
  select balance into v_balance from public.wallets where user_id = v_uid for update;
  if coalesce(v_balance, 0) > 0 then
    v_forfeit := v_balance;
    update public.wallets set balance = 0 where user_id = v_uid;
    insert into public.wallet_transactions (user_id, type, amount, source, balance_after)
    values (v_uid, 'debit', v_forfeit, 'account_deleted', 0);
  end if;
  update public.wallets
     set virtual_account_number = 'DELETED-' || left(v_uid::text, 8)
   where user_id = v_uid;

  -- Personal-only data: removed.
  delete from public.push_devices        where user_id = v_uid;
  delete from public.notifications       where user_id = v_uid;
  delete from public.saving_plans        where user_id = v_uid;
  delete from public.transaction_pins    where user_id = v_uid;
  delete from public.support_conversations where student_id = v_uid;  -- messages cascade
  delete from public.gift_deliveries     where recipient_id = v_uid;
  delete from public.gift_lookup_log     where user_id = v_uid;
  delete from public.otp_send_log        where user_id = v_uid;
  delete from public.user_achievements   where user_id = v_uid;
  if v_profile.phone is not null then
    delete from public.signup_phone_verifications where phone = v_profile.phone;
  end if;

  -- Kept records: free text and addresses removed.
  update public.orders
     set notes = null, location_details = null
   where student_id = v_uid;
  update public.delivery_groups
     set student_note = null, location_details = null, gift_message = null
   where student_id = v_uid;
  update public.delivery_groups
     set gift_recipient_nickname = null, gift_message = null
   where gift_recipient_id = v_uid;
  update public.errand_requests r
     set item_description = '(removed)', pickup_location = '(removed)',
         dropoff_location = '(removed)'
    from public.orders o
   where o.id = r.order_id and o.student_id = v_uid;

  -- The profile: no personal field left, account inactive.
  perform set_config('uniflex.trusted_write', 'on', true);
  update public.profiles
     set email = null, phone = null, phone_verified_at = null,
         nickname = null, full_name = 'Deleted user', matric_number = null,
         school = null, date_of_birth = null, referral_code = null,
         referred_by_code = null, fcm_token = null, is_active = false
   where id = v_uid;
  perform set_config('uniflex.trusted_write', 'off', true);

  -- The login: unusable and anonymous (see header for why not deleted).
  delete from auth.identities  where user_id = v_uid;
  delete from auth.sessions    where user_id = v_uid;
  delete from auth.refresh_tokens where user_id = v_uid::text;
  delete from auth.mfa_factors where user_id = v_uid;
  update auth.users
     set email              = 'deleted-' || v_uid::text || '@deleted.uniflex.invalid',
         phone              = null,
         encrypted_password = crypt(gen_random_uuid()::text, gen_salt('bf')),
         raw_user_meta_data = '{}'::jsonb,
         banned_until       = now() + interval '100 years',
         updated_at         = now()
   where id = v_uid;

  return jsonb_build_object('ok', true, 'forfeited', v_forfeit);
end;
$$;

revoke all on function public.delete_my_account(text) from public, anon;
grant execute on function public.delete_my_account(text) to authenticated, service_role;
