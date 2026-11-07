-- =====================================================================
-- Pack 5 — READ-ONLY: list half-made ("legacy stuck") accounts
--
-- These are accounts made by the OLD 2-step flow that never finished:
-- an auth user (+ maybe a stub profile) exists but onboarding_complete is
-- false. They still work: AuthGate sends them to ResumeOtpScreen (phone not
-- verified) or CompleteProfileScreen (phone verified) when they log in.
--
-- SELECT only. Changes nothing. Safe to run any time.
-- =====================================================================
select
  u.email,
  p.phone,
  u.created_at,
  (p.phone_verified_at is not null)                       as phone_verified,
  case when p.id is null then 'no profile row'
       when p.phone_verified_at is null then 'stuck at phone code'
       else 'stuck at profile details' end                as stuck_at,
  floor(extract(epoch from (now() - u.created_at)) / 86400)::int as age_days,
  (select count(*) from public.orders o where o.student_id = u.id) as orders
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null
   or (p.onboarding_complete = false and p.role = 'student')
order by u.created_at;
