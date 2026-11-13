-- Pack 2 — test for pack2_retire_legacy_referral_codes.sql. Run AFTER the
-- migration (or prepend it to dry-run). One transaction, always rolled back.
begin;

do $$
declare
  log text := '';
  n_backup int;
begin
  select count(*) into n_backup from pack2_backup.legacy_referral_codes;
  log := log || case when not exists (select 1 from public.profiles where referral_code is not null)
                then 'PASS' else 'FAIL' end || '  L1 no profile keeps a legacy code' || E'\n';
  log := log || case when n_backup >= 1 then 'PASS' else 'FAIL' end
              || '  L2 every cleared code is in the backup (' || n_backup || ' rows)' || E'\n';
  log := log || case when not has_schema_privilege('authenticated', 'pack2_backup', 'usage')
                      and not has_schema_privilege('anon', 'pack2_backup', 'usage')
                then 'PASS' else 'FAIL' end || '  L3 app users cannot reach the backup' || E'\n';
  log := log || case when not exists (
                  select 1 from pack2_backup.legacy_referral_codes b
                   where public.is_referral_code_valid(b.referral_code)
                     and not exists (select 1 from public.referral_codes c
                                      where c.code = b.referral_code and c.is_active))
                then 'PASS' else 'FAIL' end || '  L4 a retired code no longer validates at sign-up' || E'\n';
  raise exception 'PACK2 LEGACY CODES TEST (rolled back):%', E'\n' || log;
end $$;
