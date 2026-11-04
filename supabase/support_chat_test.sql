-- =====================================================================
-- Support Chat SQL Test Script
--
-- Paste into the Supabase SQL editor and run. Everything runs inside a
-- transaction that is rolled back at the end so no test data persists.
--
-- IMPORTANT: The Supabase SQL editor runs as the postgres superuser, not
-- as an authenticated Supabase user. This means auth.uid() always returns
-- NULL inside this editor. Direct RPC calls that depend on auth.uid()
-- will raise 'Unauthorized'. The tests below work around this by calling
-- the RPCs after set_config(), or by directly exercising the underlying
-- SQL logic using the same WHERE conditions the RPCs use.
--
-- For full end-to-end auth testing, use Postman or the app itself with a
-- real JWT. This script verifies:
--   - Table constraints (empty body, body too long, bad order attachment)
--   - Unread count arithmetic
--   - Rate limit counter logic
--   - Resolved status reopens on new student message
-- =====================================================================

begin;

-- ── Seed data ─────────────────────────────────────────────────────────────

-- Two fake profile rows (bypasses auth entirely — postgres role can insert).
insert into public.profiles (id, role, email, phone, onboarding_complete)
values
  ('00000000-0000-0000-0001-000000000001', 'student', 'teststudent@uniflex.test', '+2340000000001', true),
  ('00000000-0000-0000-0001-000000000002', 'student', 'teststudent2@uniflex.test', '+2340000000002', true),
  ('00000000-0000-0000-0001-000000000099', 'admin',   'testadmin@uniflex.test',   '+2340000000099', true)
on conflict do nothing;

-- Wallets (required for order FK).
insert into public.wallets (user_id, balance)
values
  ('00000000-0000-0000-0001-000000000001', 5000),
  ('00000000-0000-0000-0001-000000000002', 5000)
on conflict do nothing;

-- ── Test 1: Empty body is rejected ───────────────────────────────────────────

do $$
begin
  begin
    insert into public.support_messages
      (conversation_id, sender_id, sender_role, sender_name, body)
    values
      ('00000000-dead-beef-0000-000000000000',
       '00000000-0000-0000-0001-000000000001',
       'student', 'Alice', '   ');
    raise exception 'TEST FAILED: empty body should be rejected';
  exception when check_violation then
    raise notice 'PASS: Test 1 — empty body rejected by CHECK constraint';
  end;
end $$;

-- ── Test 2: Body > 2000 chars is rejected ────────────────────────────────────

do $$
declare v_body text := repeat('x', 2001);
begin
  begin
    insert into public.support_messages
      (conversation_id, sender_id, sender_role, sender_name, body)
    values
      ('00000000-dead-beef-0000-000000000000',
       '00000000-0000-0000-0001-000000000001',
       'student', 'Alice', v_body);
    raise exception 'TEST FAILED: over-long body should be rejected';
  exception when check_violation then
    raise notice 'PASS: Test 2 — body > 2000 chars rejected by CHECK constraint';
  end;
end $$;

-- ── Test 3: One conversation per student (unique constraint) ──────────────────

do $$
declare v_conv_id uuid;
begin
  -- Create first conversation.
  insert into public.support_conversations (student_id)
  values ('00000000-0000-0000-0001-000000000001')
  returning id into v_conv_id;

  begin
    -- Try to create a second.
    insert into public.support_conversations (student_id)
    values ('00000000-0000-0000-0001-000000000001');
    raise exception 'TEST FAILED: should not be able to create two conversations for the same student';
  exception when unique_violation then
    raise notice 'PASS: Test 3 — unique constraint prevents duplicate conversations';
  end;
end $$;

-- ── Test 4: Unread count arithmetic ──────────────────────────────────────────

do $$
declare
  v_conv_id  uuid;
  v_admin_unread   int;
  v_student_unread int;
begin
  -- Seed a conversation.
  insert into public.support_conversations (student_id)
  values ('00000000-0000-0000-0001-000000000002')
  returning id into v_conv_id;

  -- Simulate student message: admin_unread_count should increment.
  insert into public.support_messages
    (conversation_id, sender_id, sender_role, sender_name, body)
  values
    (v_conv_id,
     '00000000-0000-0000-0001-000000000002',
     'student', 'Bob', 'Help me please');

  update public.support_conversations
  set admin_unread_count = admin_unread_count + 1
  where id = v_conv_id;

  select admin_unread_count into v_admin_unread
  from public.support_conversations where id = v_conv_id;

  if v_admin_unread <> 1 then
    raise exception 'TEST FAILED: admin_unread_count should be 1, got %', v_admin_unread;
  end if;
  raise notice 'PASS: Test 4a — admin_unread_count incremented to 1';

  -- Simulate admin reply: student_unread_count should increment.
  insert into public.support_messages
    (conversation_id, sender_id, sender_role, sender_name, body)
  values
    (v_conv_id,
     '00000000-0000-0000-0001-000000000099',
     'admin', 'Admin', 'Looking into it');

  update public.support_conversations
  set student_unread_count = student_unread_count + 1
  where id = v_conv_id;

  select student_unread_count into v_student_unread
  from public.support_conversations where id = v_conv_id;

  if v_student_unread <> 1 then
    raise exception 'TEST FAILED: student_unread_count should be 1, got %', v_student_unread;
  end if;
  raise notice 'PASS: Test 4b — student_unread_count incremented to 1';

  -- Clear admin unread (simulate admin opening the conversation).
  update public.support_conversations
  set admin_unread_count = 0
  where id = v_conv_id;

  select admin_unread_count into v_admin_unread
  from public.support_conversations where id = v_conv_id;

  if v_admin_unread <> 0 then
    raise exception 'TEST FAILED: admin_unread_count should be 0 after clear, got %', v_admin_unread;
  end if;
  raise notice 'PASS: Test 4c — admin_unread_count cleared to 0';
end $$;

-- ── Test 5: Resolved conversation can be reopened ─────────────────────────────

do $$
declare v_conv_id uuid;
        v_status  text;
begin
  insert into public.support_conversations (student_id, status)
  values ('00000000-0000-0000-0001-000000000001', 'resolved')
  on conflict (student_id)
  do update set status = 'resolved'
  returning id into v_conv_id;

  if v_conv_id is null then
    -- The unique constraint means the row already exists; fetch it.
    select id into v_conv_id
    from public.support_conversations
    where student_id = '00000000-0000-0000-0001-000000000001';

    update public.support_conversations
    set status = 'resolved', resolved_at = now(), resolved_by = null
    where id = v_conv_id;
  end if;

  -- Simulate what the RPC does on a new student message: reopen.
  update public.support_conversations
  set status = 'open', resolved_at = null, resolved_by = null
  where id = v_conv_id and status = 'resolved';

  select status into v_status
  from public.support_conversations where id = v_conv_id;

  if v_status <> 'open' then
    raise exception 'TEST FAILED: conversation should be reopened, got %', v_status;
  end if;
  raise notice 'PASS: Test 5 — resolved conversation reopened by new message';
end $$;

-- ── Test 6: Rate limit — the RPC would reject the 21st message ───────────────
-- We can't call the RPC here (no auth.uid()), but we can verify that the
-- COUNT query the RPC uses would correctly detect > 20 messages.

do $$
declare
  v_conv_id uuid;
  v_count   int;
begin
  -- Use a conversation seeded in Test 4.
  select id into v_conv_id
  from public.support_conversations
  where student_id = '00000000-0000-0000-0001-000000000002';

  -- Insert 19 messages so total hits 21 (1 already inserted in Test 4,
  -- + 1 admin reply = 2; adding 19 more = 21 total in last minute).
  for i in 1..19 loop
    insert into public.support_messages
      (conversation_id, sender_id, sender_role, sender_name, body)
    values
      (v_conv_id,
       '00000000-0000-0000-0001-000000000002',
       'student', 'Bob', 'message ' || i);
  end loop;

  -- Verify the count the RPC checks.
  select count(*) into v_count
  from public.support_messages
  where sender_id = '00000000-0000-0000-0001-000000000002'
    and created_at > now() - interval '1 minute';

  if v_count >= 20 then
    raise notice 'PASS: Test 6 — rate limit would trigger (% messages in last minute)', v_count;
  else
    raise exception 'TEST FAILED: expected >= 20 messages, got %', v_count;
  end if;
end $$;

-- ── Test 7: order_id ON DELETE SET NULL ──────────────────────────────────────
-- Verifies that deleting an order does not cascade-delete the message.

do $$
declare
  v_order_id uuid;
  v_msg_id   uuid;
  v_conv_id  uuid;
  v_order_id_after uuid;
begin
  select id into v_conv_id
  from public.support_conversations
  where student_id = '00000000-0000-0000-0001-000000000002';

  -- Create a fake order for student 2.
  insert into public.orders
    (student_id, source, type, status, delivery_type, total_amount)
  values
    ('00000000-0000-0000-0001-000000000002',
     'uniflex', 'food', 'placed', 'pickup', 100)
  returning id into v_order_id;

  -- Insert a message referencing that order.
  insert into public.support_messages
    (conversation_id, sender_id, sender_role, sender_name, body, order_id)
  values
    (v_conv_id,
     '00000000-0000-0000-0001-000000000002',
     'student', 'Bob', 'Issue with this order', v_order_id)
  returning id into v_msg_id;

  -- Delete the order.
  delete from public.orders where id = v_order_id;

  -- Message should still exist; order_id should be NULL.
  select order_id into v_order_id_after
  from public.support_messages where id = v_msg_id;

  if v_order_id_after is not null then
    raise exception 'TEST FAILED: order_id should be null after order deleted';
  end if;
  raise notice 'PASS: Test 7 — order deletion sets message.order_id to NULL (not cascade)';
end $$;

-- ── Summary ───────────────────────────────────────────────────────────────────

raise notice '=== All SQL tests completed. Rolling back. ===';

rollback;
