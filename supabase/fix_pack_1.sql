-- =====================================================================
-- Fix Pack 1 — Additive migration
--
-- Run once in the Supabase SQL editor.
-- All blocks are idempotent — safe to re-run.
--
-- Changes:
--   1. Add delivery_group_id column to support_messages
--   2. Replace send_support_message to accept p_group_id
-- =====================================================================


-- ─────────────────────────────────────────────────────────────────────
-- 1. support_messages.delivery_group_id
--
-- Students can now attach a multi-vendor delivery group to a message
-- (instead of a single-order id). Using a separate column avoids
-- violating the orders FK while keeping query paths clean.
-- ─────────────────────────────────────────────────────────────────────

alter table public.support_messages
  add column if not exists delivery_group_id uuid
    references public.delivery_groups(id)
    on delete set null;

create index if not exists support_messages_delivery_group
  on public.support_messages (delivery_group_id)
  where delivery_group_id is not null;


-- ─────────────────────────────────────────────────────────────────────
-- 2. send_support_message  (replace — adds p_group_id parameter)
--
-- New behaviour vs original:
--   • Accepts p_group_id uuid (nullable). When provided by a student,
--     validates the group belongs to this student and stores it in
--     delivery_group_id.
--   • p_order_id and p_group_id are mutually exclusive — supplying both
--     raises an error.
--   • Admin path is unchanged.
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.send_support_message(
  p_body            text,
  p_order_id        uuid default null,
  p_group_id        uuid default null,
  p_conversation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_caller_id   uuid    := auth.uid();
  v_is_admin    boolean;
  v_conv_id     uuid;
  v_sender_role text;
  v_sender_name text;
  v_msg_id      uuid;
  v_msg_count   int;
begin
  if v_caller_id is null then
    raise exception 'Unauthorized';
  end if;

  -- Trim and validate body.
  p_body := trim(p_body);
  if char_length(p_body) = 0 then
    raise exception 'Message body cannot be empty';
  end if;
  if char_length(p_body) > 2000 then
    raise exception 'Message too long (2000 characters max)';
  end if;

  -- Cannot attach both an order and a delivery group.
  if p_order_id is not null and p_group_id is not null then
    raise exception 'Provide either p_order_id or p_group_id, not both';
  end if;

  -- Rate limit: 20 messages per minute per user.
  select count(*) into v_msg_count
  from public.support_messages
  where sender_id = v_caller_id
    and created_at > now() - interval '1 minute';

  if v_msg_count >= 20 then
    raise exception 'RATE_LIMITED';
  end if;

  v_is_admin := public.is_admin();

  if v_is_admin then
    -- ── Admin path ───────────────────────────────────────────────────
    if p_conversation_id is null then
      raise exception 'p_conversation_id is required for admin messages';
    end if;

    if not exists (
      select 1 from public.support_conversations
      where id = p_conversation_id
    ) then
      raise exception 'Conversation not found';
    end if;

    v_conv_id     := p_conversation_id;
    v_sender_role := 'admin';

    select coalesce(nickname, full_name, 'Admin')
    into v_sender_name
    from public.profiles
    where id = v_caller_id;

  else
    -- ── Student path ─────────────────────────────────────────────────
    -- Find or create this student's conversation.
    select id into v_conv_id
    from public.support_conversations
    where student_id = v_caller_id;

    if not found then
      insert into public.support_conversations (student_id)
      values (v_caller_id)
      returning id into v_conv_id;
    end if;

    v_sender_role := 'student';

    select coalesce(nickname, full_name, 'Student')
    into v_sender_name
    from public.profiles
    where id = v_caller_id;

    -- Validate order_id: must belong to this student.
    if p_order_id is not null then
      if not exists (
        select 1 from public.orders
        where id = p_order_id
          and student_id = v_caller_id
      ) then
        raise exception 'Order not found or does not belong to you';
      end if;
    end if;

    -- Validate group_id: must belong to this student.
    if p_group_id is not null then
      if not exists (
        select 1 from public.delivery_groups
        where id = p_group_id
          and student_id = v_caller_id
      ) then
        raise exception 'Delivery group not found or does not belong to you';
      end if;
    end if;

    -- Reopen if previously resolved.
    update public.support_conversations
    set
      status      = 'open',
      resolved_at = null,
      resolved_by = null
    where id = v_conv_id
      and status = 'resolved';

  end if;

  -- Insert message.
  insert into public.support_messages
    (conversation_id, sender_id, sender_role, sender_name, body,
     order_id, delivery_group_id)
  values
    (v_conv_id, v_caller_id, v_sender_role, v_sender_name, p_body,
     p_order_id, p_group_id)
  returning id into v_msg_id;

  -- Update conversation metadata.
  update public.support_conversations
  set
    last_message_at      = now(),
    last_message_preview = left(p_body, 100),
    admin_unread_count   = case
                             when v_sender_role = 'student'
                             then admin_unread_count + 1
                             else admin_unread_count
                           end,
    student_unread_count = case
                             when v_sender_role = 'admin'
                             then student_unread_count + 1
                             else student_unread_count
                           end
  where id = v_conv_id;

  return jsonb_build_object(
    'message_id',      v_msg_id,
    'conversation_id', v_conv_id
  );
end;
$$;

-- Grant covers both old and new signature.
grant execute on function public.send_support_message(text, uuid, uuid, uuid)
  to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- NOTE: phase9_security_hardening.sql items
--
-- checkout_group_order and send_gift were hardened with PIN verification
-- in phase9_security_hardening.sql. If that file has not yet been
-- deployed to production, run it now. The RPCs below require PIN:
--   • place_food_order_with_payment  ✓ (original schema)
--   • pay_group_commitment_fee       ✓ (original schema)
--   • pay_commitment_fee             ✓ (original schema)
--   • pay_final_amount               ✓ (original schema)
--   • place_errand_with_payment      ✓ (original schema)
--   • checkout_group_order           ✓ (phase9_security_hardening.sql)
--   • send_gift                      ✓ (phase9_security_hardening.sql)
-- ─────────────────────────────────────────────────────────────────────
