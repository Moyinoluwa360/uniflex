-- =====================================================================
-- Support Chat Migration
--
-- Run once in the Supabase SQL editor.
-- All blocks are idempotent — safe to re-run.
--
-- Creates:
--   1. support_conversations table (one per student)
--   2. support_messages table
--   3. RLS policies (student sees own; admin sees all; no client writes)
--   4. Realtime publication for both tables
--   5. RPCs: send_support_message, mark_support_read,
--            resolve_support_conversation, get_support_unread_total
--   6. pg_net trigger (optional — see Section 6 comment below)
-- =====================================================================


-- ─────────────────────────────────────────────────────────────────────
-- 1. support_conversations
-- One row per student — unique on student_id.
-- ─────────────────────────────────────────────────────────────────────

create table if not exists public.support_conversations (
  id                   uuid        primary key default gen_random_uuid(),
  student_id           uuid        not null unique
                                   references public.profiles(id)
                                   on delete cascade,
  status               text        not null default 'open'
                                   check (status in ('open', 'resolved')),
  last_message_at      timestamptz,
  last_message_preview text,
  student_unread_count int         not null default 0
                                   check (student_unread_count >= 0),
  admin_unread_count   int         not null default 0
                                   check (admin_unread_count   >= 0),
  resolved_at          timestamptz,
  resolved_by          uuid        references public.profiles(id)
                                   on delete set null,
  created_at           timestamptz not null default now()
);


-- ─────────────────────────────────────────────────────────────────────
-- 2. support_messages
-- order_id is nullable and ON DELETE SET NULL so deleting an order
-- never cascades a failure here.
-- ─────────────────────────────────────────────────────────────────────

create table if not exists public.support_messages (
  id              uuid        primary key default gen_random_uuid(),
  conversation_id uuid        not null
                              references public.support_conversations(id)
                              on delete cascade,
  sender_id       uuid        not null
                              references public.profiles(id)
                              on delete cascade,
  sender_role     text        not null
                              check (sender_role in ('student', 'admin')),
  sender_name     text        not null,
  body            text        not null
                              check (
                                char_length(trim(body)) >= 1
                                and char_length(body) <= 2000
                              ),
  order_id        uuid        references public.orders(id)
                              on delete set null,
  created_at      timestamptz not null default now()
);

create index if not exists support_messages_conversation_created
  on public.support_messages (conversation_id, created_at desc);


-- ─────────────────────────────────────────────────────────────────────
-- 3. RLS
-- Students see only their own conversation and messages.
-- Admins see all.
-- No client INSERT / UPDATE / DELETE — all writes go through RPCs.
-- ─────────────────────────────────────────────────────────────────────

alter table public.support_conversations enable row level security;
alter table public.support_messages      enable row level security;

drop policy if exists "support_conv_select" on public.support_conversations;
create policy "support_conv_select" on public.support_conversations
  for select to authenticated
  using (
    student_id = auth.uid()
    or (select public.is_admin())
  );

drop policy if exists "support_msg_select" on public.support_messages;
create policy "support_msg_select" on public.support_messages
  for select to authenticated
  using (
    exists (
      select 1 from public.support_conversations c
      where c.id = conversation_id
        and (
          c.student_id = auth.uid()
          or (select public.is_admin())
        )
    )
  );


-- ─────────────────────────────────────────────────────────────────────
-- 4. Realtime publication
-- ─────────────────────────────────────────────────────────────────────

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'support_conversations'
  ) then
    alter publication supabase_realtime
      add table public.support_conversations;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'support_messages'
  ) then
    alter publication supabase_realtime
      add table public.support_messages;
  end if;
end $$;


-- ─────────────────────────────────────────────────────────────────────
-- 5a. send_support_message
--
-- Unified send for both students and admins.
--
-- Student path:
--   - Finds or creates the student's own conversation.
--   - Ignores p_conversation_id (students cannot choose a conversation).
--   - Validates that p_order_id (if supplied) belongs to this student.
--   - Reopens the conversation if it was resolved.
--   - Increments admin_unread_count.
--
-- Admin path:
--   - Requires p_conversation_id.
--   - Verifies is_admin().
--   - Increments student_unread_count.
--
-- Both paths:
--   - Trims and validates body (1–2000 chars).
--   - Rate-limits to 20 messages per minute per user.
--   - Snapshots sender_name from profiles at send time.
--   - Updates last_message_at and last_message_preview on the conversation.
--
-- Returns: { message_id, conversation_id }
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.send_support_message(
  p_body            text,
  p_order_id        uuid default null,
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
    (conversation_id, sender_id, sender_role, sender_name, body, order_id)
  values
    (v_conv_id, v_caller_id, v_sender_role, v_sender_name, p_body, p_order_id)
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

grant execute on function public.send_support_message(text, uuid, uuid)
  to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 5b. mark_support_read
-- Student: clears student_unread_count on their own conversation.
-- Admin:   clears admin_unread_count on any conversation.
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.mark_support_read(
  p_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
begin
  if v_caller_id is null then
    raise exception 'Unauthorized';
  end if;

  if public.is_admin() then
    update public.support_conversations
    set admin_unread_count = 0
    where id = p_conversation_id;
  else
    update public.support_conversations
    set student_unread_count = 0
    where id = p_conversation_id
      and student_id = v_caller_id;
  end if;
end;
$$;

grant execute on function public.mark_support_read(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 5c. resolve_support_conversation
-- Admin only.
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.resolve_support_conversation(
  p_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Unauthorized';
  end if;

  update public.support_conversations
  set
    status      = 'resolved',
    resolved_at = now(),
    resolved_by = auth.uid()
  where id = p_conversation_id;

  if not found then
    raise exception 'Conversation not found';
  end if;
end;
$$;

grant execute on function public.resolve_support_conversation(uuid)
  to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 5d. get_support_unread_total
-- Student: their student_unread_count (0 if no conversation yet).
-- Admin:   sum of all admin_unread_counts across all conversations.
-- Used for the unread badge in both apps.
-- ─────────────────────────────────────────────────────────────────────

create or replace function public.get_support_unread_total()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid := auth.uid();
  v_count     int;
begin
  if v_caller_id is null then
    return 0;
  end if;

  if public.is_admin() then
    select coalesce(sum(admin_unread_count)::int, 0)
    into v_count
    from public.support_conversations;
  else
    select coalesce(student_unread_count, 0)
    into v_count
    from public.support_conversations
    where student_id = v_caller_id;

    if not found then
      v_count := 0;
    end if;
  end if;

  return v_count;
end;
$$;

grant execute on function public.get_support_unread_total() to authenticated;


-- ─────────────────────────────────────────────────────────────────────
-- 6. Push trigger via pg_net (OPTIONAL)
--
-- This trigger fires after every INSERT on support_messages and calls
-- the support-notify Edge Function so push notifications are sent
-- server-side, independent of the sender's app.
--
-- Prerequisites before enabling:
--   a) Enable pg_net extension: Database → Extensions → pg_net
--   b) Deploy the support-notify Edge Function
--   c) Run these two commands once to store your project config:
--
--      alter database postgres
--        set app.supabase_project_url = 'https://YOUR_PROJECT.supabase.co';
--      alter database postgres
--        set app.supabase_service_role_key = 'YOUR_SERVICE_ROLE_KEY';
--
-- If you prefer a no-code alternative, skip this section and set up a
-- Supabase Database Webhook instead (see ARCHITECTURE.md § Push flow).
-- ─────────────────────────────────────────────────────────────────────

create or replace function public._trigger_support_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project_url text;
  v_service_key text;
begin
  -- Read project URL and service key stored by the owner (see comment above).
  begin
    v_project_url := current_setting('app.supabase_project_url');
    v_service_key := current_setting('app.supabase_service_role_key');
  exception when others then
    -- Settings not configured — skip push silently, never block the insert.
    return new;
  end;

  if v_project_url is null or v_service_key is null then
    return new;
  end if;

  -- Non-blocking HTTP POST to support-notify Edge Function.
  perform net.http_post(
    url     := v_project_url || '/functions/v1/support-notify',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body    := jsonb_build_object(
      'message_id',      new.id,
      'conversation_id', new.conversation_id,
      'sender_id',       new.sender_id,
      'sender_role',     new.sender_role,
      'sender_name',     new.sender_name,
      'body',            left(new.body, 100)
    )
  );

  return new;
exception when others then
  -- pg_net not installed or any other error — fail silently.
  return new;
end;
$$;

-- Only create the trigger if pg_net is available.
do $$
begin
  if exists (
    select 1 from pg_extension where extname = 'pg_net'
  ) then
    drop trigger if exists on_support_message_insert
      on public.support_messages;

    create trigger on_support_message_insert
      after insert on public.support_messages
      for each row
      execute function public._trigger_support_notify();
  end if;
end $$;
