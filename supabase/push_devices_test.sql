-- Push devices — SQL test. Runs in ONE transaction that is rolled back.
-- Paste into the Supabase SQL editor (or: supabase db query -f ...) AFTER push_devices.sql.
begin;
create schema uf_test;
grant usage on schema uf_test to public;
create function uf_test.ok(p_name text, p_cond boolean) returns void language plpgsql as $$
begin
  perform set_config('uf.log', coalesce(current_setting('uf.log', true), '') ||
    case when coalesce(p_cond, false) then 'PASS  ' else 'FAIL  ' end || p_name || E'\n', true);
end $$;
grant execute on function uf_test.ok(text, boolean) to public;
create function uf_test.as_user(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
end $$;
grant execute on function uf_test.as_user(uuid) to public;

do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid();
  t1 text := repeat('a', 40); t2 text := repeat('b', 40);
  n int; owner uuid; v text;
begin
  insert into auth.users (id, email) values (a, 'pd_a@test.local'), (b, 'pd_b@test.local');
  -- profiles may be created by a trigger; make sure both exist
  insert into public.profiles (id, email, role) select a, 'pd_a@test.local', 'student' where not exists (select 1 from public.profiles where id = a);
  insert into public.profiles (id, email, role) select b, 'pd_b@test.local', 'student' where not exists (select 1 from public.profiles where id = b);

  set local role authenticated;

  -- direct table access is closed
  begin
    perform 1 from public.push_devices; perform uf_test.ok('direct select on push_devices is denied', false);
  exception when insufficient_privilege then perform uf_test.ok('direct select on push_devices is denied', true); end;

  -- A registers two phones
  perform uf_test.as_user(a);
  perform public.register_push_token(t1, 'android');
  perform public.register_push_token(t2, 'ios');
  reset role;
  select count(*) into n from public.push_devices where user_id = a;
  perform uf_test.ok('one user can have two phones', n = 2);
  select fcm_token into v from public.profiles where id = a;
  perform uf_test.ok('legacy column holds the latest token', v = t2);

  -- registering twice does not duplicate
  set local role authenticated; perform uf_test.as_user(a);
  perform public.register_push_token(t1, 'android');
  reset role;
  select count(*) into n from public.push_devices where user_id = a;
  perform uf_test.ok('registering the same phone twice is idempotent', n = 2);

  -- B signs in on phone t1: it moves to B, A keeps t2
  set local role authenticated; perform uf_test.as_user(b);
  perform public.register_push_token(t1, 'android');
  reset role;
  select user_id into owner from public.push_devices where token = t1;
  perform uf_test.ok('a phone belongs to the last person signed in', owner = b);
  select count(*) into n from public.push_devices where user_id = a;
  perform uf_test.ok('the previous owner keeps their other phone only', n = 1);

  -- A cannot unregister B's phone
  set local role authenticated; perform uf_test.as_user(a);
  perform public.unregister_push_token(t1);
  reset role;
  select count(*) into n from public.push_devices where token = t1;
  perform uf_test.ok('you cannot unregister someone else''s phone', n = 1);

  -- B unregisters own phone
  set local role authenticated; perform uf_test.as_user(b);
  perform public.unregister_push_token(t1);
  reset role;
  select count(*) into n from public.push_devices where token = t1;
  perform uf_test.ok('unregister removes your phone', n = 0);

  -- old-build call keeps working; null does not wipe other phones
  set local role authenticated; perform uf_test.as_user(a);
  perform public.store_fcm_token(repeat('c', 40));
  perform public.store_fcm_token(null);
  reset role;
  select count(*) into n from public.push_devices where user_id = a;
  perform uf_test.ok('old store_fcm_token feeds push_devices', n = 2);
  perform uf_test.ok('null token does not delete devices', n = 2);

  -- bad input / not signed in
  set local role authenticated; perform uf_test.as_user(a);
  begin perform public.register_push_token('short', null); perform uf_test.ok('short token rejected', false);
  exception when others then perform uf_test.ok('short token rejected', true); end;
  perform set_config('request.jwt.claims', '', true);
  begin perform public.register_push_token(repeat('d', 40), null); perform uf_test.ok('signed-out call rejected', false);
  exception when others then perform uf_test.ok('signed-out call rejected', true); end;
  reset role;
end $$;

select regexp_split_to_table(current_setting('uf.log', true), E'\n') as result;
rollback;
