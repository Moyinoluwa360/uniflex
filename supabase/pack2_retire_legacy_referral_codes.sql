-- =====================================================================
-- Pack 2 — retire the legacy per-student referral codes (owner decision
-- 2026-11-12). Finding S-05b in docs/security-audit.md.
--
-- Business rule: referral codes are admin-assigned; students never see
-- their own. 12 students still had an old self-made code in
-- profiles.referral_code, readable through their own profile row and still
-- accepted at sign-up. After this, only admin-minted codes
-- (public.referral_codes) work: the sign-up / onboarding lookups of
-- profiles.referral_code simply find nothing. Referrals already recorded
-- (public.referrals) are untouched, so pending first-order bonuses still pay.
--
-- Backup: pack2_backup.legacy_referral_codes (schema not exposed to the API,
-- no grants to app roles). Rollback:
--   update public.profiles p set referral_code = b.referral_code
--     from pack2_backup.legacy_referral_codes b where b.profile_id = p.id;
--   (run with: select set_config('uniflex.trusted_write','on',true); first)
-- Idempotent: re-running backs up nothing new and clears nothing new.
-- =====================================================================

create schema if not exists pack2_backup;
revoke all on schema pack2_backup from public, anon, authenticated;

create table if not exists pack2_backup.legacy_referral_codes (
  profile_id    uuid primary key,
  referral_code text not null,
  backed_up_at  timestamptz not null default now()
);
revoke all on pack2_backup.legacy_referral_codes from public, anon, authenticated;

insert into pack2_backup.legacy_referral_codes (profile_id, referral_code)
select id, referral_code from public.profiles where referral_code is not null
on conflict (profile_id) do nothing;

select set_config('uniflex.trusted_write', 'on', true);
update public.profiles set referral_code = null where referral_code is not null;
select set_config('uniflex.trusted_write', 'off', true);
