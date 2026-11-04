import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/support_conversation.dart';
import '../../models/support_message.dart';
import '../supabase/supabase_providers.dart';

/// Thrown when a support action fails in a way worth showing the user.
class SupportException implements Exception {
  SupportException(this.message);
  final String message;

  @override
  String toString() => 'SupportException: $message';
}

/// Service for the student ↔ admin support chat.
///
/// All writes go through the [send_support_message], [mark_support_read],
/// and [resolve_support_conversation] RPCs — the client never writes to
/// the tables directly.
class SupportChatService {
  const SupportChatService(this._client);

  final SupabaseClient _client;

  // ── Student: own conversation ─────────────────────────────────────────

  /// Live stream of the signed-in student's support conversation.
  /// Emits null when the student has not yet sent any message.
  Stream<SupportConversation?> watchMyConversation() async* {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      yield null;
      return;
    }

    // Initial fetch.
    yield await _fetchMyConversation(userId);

    // Realtime updates.
    try {
      final stream = _client
          .from('support_conversations')
          .stream(primaryKey: ['id'])
          .eq('student_id', userId);

      await for (final rows in stream) {
        if (rows.isEmpty) {
          yield null;
        } else {
          yield SupportConversation.fromMap(rows.first);
        }
      }
    } catch (_) {
      // Realtime failed; initial data already delivered.
    }
  }

  Future<SupportConversation?> _fetchMyConversation(String userId) async {
    final rows = await _client
        .from('support_conversations')
        .select()
        .eq('student_id', userId)
        .limit(1);
    if (rows.isEmpty) return null;
    return SupportConversation.fromMap(rows.first);
  }

  // ── Admin: all conversations ──────────────────────────────────────────

  /// Live stream of all support conversations, newest-first.
  Stream<List<SupportConversation>> watchAllConversations() async* {
    // Initial fetch.
    yield await _fetchAllConversations();

    // Realtime updates.
    try {
      final stream = _client
          .from('support_conversations')
          .stream(primaryKey: ['id'])
          .order('last_message_at', ascending: false);

      await for (final rows in stream) {
        final convs = rows.map(SupportConversation.fromMap).toList()
          ..sort((a, b) {
            if (a.lastMessageAt == null && b.lastMessageAt == null) return 0;
            if (a.lastMessageAt == null) return 1;
            if (b.lastMessageAt == null) return -1;
            return b.lastMessageAt!.compareTo(a.lastMessageAt!);
          });
        yield convs;
      }
    } catch (_) {
      // Realtime failed; initial data already delivered.
    }
  }

  Future<List<SupportConversation>> _fetchAllConversations() async {
    final rows = await _client
        .from('support_conversations')
        .select()
        .order('last_message_at', ascending: false);
    return rows.map(SupportConversation.fromMap).toList();
  }

  // ── Messages for a conversation ───────────────────────────────────────

  /// Live stream of messages in [conversationId], oldest-first so the
  /// chat list renders in chronological order.
  Stream<List<SupportMessage>> watchMessages(String conversationId) async* {
    // Initial fetch.
    yield await _fetchMessages(conversationId);

    // Realtime updates.
    try {
      final stream = _client
          .from('support_messages')
          .stream(primaryKey: ['id'])
          .eq('conversation_id', conversationId)
          .order('created_at');

      await for (final rows in stream) {
        yield rows.map(SupportMessage.fromMap).toList();
      }
    } catch (_) {
      // Realtime failed; initial data already delivered.
    }
  }

  Future<List<SupportMessage>> _fetchMessages(String conversationId) async {
    final rows = await _client
        .from('support_messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at');
    return rows.map(SupportMessage.fromMap).toList();
  }

  // ── Admin: load a student profile for the conversation header ─────────

  /// Returns { full_name, nickname, phone } for the conversation's student.
  Future<Map<String, dynamic>?> fetchStudentProfile(String studentId) async {
    final row = await _client
        .from('profiles')
        .select('full_name, nickname, phone')
        .eq('id', studentId)
        .maybeSingle();
    return row;
  }

  // ── Write actions (all via RPC) ───────────────────────────────────────

  /// Sends a message. Returns `{ message_id, conversation_id }`.
  ///
  /// [conversationId] is required for admin callers; ignored for students.
  /// [orderId] optionally attaches an order to this message (student only;
  /// the RPC validates it belongs to the caller).
  Future<Map<String, dynamic>> sendMessage(
    String body, {
    String? orderId,
    String? conversationId,
  }) async {
    try {
      final result = await _client.rpc('send_support_message', params: {
        'p_body': body.trim(),
        if (orderId != null) 'p_order_id': orderId,
        if (conversationId != null) 'p_conversation_id': conversationId,
      });
      return Map<String, dynamic>.from(result as Map);
    } on PostgrestException catch (e) {
      if (e.message.contains('RATE_LIMITED')) {
        throw SupportException('Slow down — you can send 20 messages per minute.');
      }
      if (e.message.contains('empty')) {
        throw SupportException('Message cannot be empty.');
      }
      if (e.message.contains('too long')) {
        throw SupportException('Message too long (2000 characters max).');
      }
      throw SupportException('Could not send message. Please try again.');
    }
  }

  /// Clears the caller's unread count for [conversationId].
  Future<void> markRead(String conversationId) async {
    try {
      await _client.rpc(
        'mark_support_read',
        params: {'p_conversation_id': conversationId},
      );
    } catch (_) {
      // Best-effort — don't surface mark-read failures to the user.
    }
  }

  /// Marks the conversation resolved (admin only).
  Future<void> resolveConversation(String conversationId) async {
    try {
      await _client.rpc(
        'resolve_support_conversation',
        params: {'p_conversation_id': conversationId},
      );
    } on PostgrestException catch (e) {
      throw SupportException(e.message);
    }
  }

  /// Total unread count for the caller:
  ///   student → their student_unread_count
  ///   admin   → sum of all admin_unread_counts
  Future<int> getUnreadTotal() async {
    try {
      final result =
          await _client.rpc('get_support_unread_total');
      return (result as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }
}

// ── Providers ─────────────────────────────────────────────────────────────

final supportChatServiceProvider = Provider<SupportChatService>((ref) {
  return SupportChatService(ref.watch(supabaseClientProvider));
});

/// Student: live stream of their own conversation (null if none yet).
final myConversationProvider =
    StreamProvider<SupportConversation?>((ref) {
  return ref.watch(supportChatServiceProvider).watchMyConversation();
});

/// Admin: live stream of all conversations, newest-first.
final allConversationsProvider =
    StreamProvider<List<SupportConversation>>((ref) {
  return ref.watch(supportChatServiceProvider).watchAllConversations();
});

/// Messages for a specific conversation. Family key is the conversation UUID.
final conversationMessagesProvider =
    StreamProvider.family<List<SupportMessage>, String>((ref, convId) {
  return ref.watch(supportChatServiceProvider).watchMessages(convId);
});

/// Total unread count for the caller (student or admin).
/// Polled on first load; re-fetched when conversations change via Realtime
/// (the allConversations stream drives admin; myConversation drives student).
final supportUnreadTotalProvider = FutureProvider<int>((ref) async {
  // Watching the stream ensures this re-runs when conversation rows change.
  ref.watch(allConversationsProvider);
  ref.watch(myConversationProvider);
  return ref.read(supportChatServiceProvider).getUnreadTotal();
});

/// Admin: sum of admin_unread_count across all live conversations.
/// Derived from the Realtime stream so it stays accurate without polling.
final adminSupportUnreadProvider = Provider<int>((ref) {
  final convs = ref.watch(allConversationsProvider).valueOrNull ?? [];
  return convs.fold(0, (sum, c) => sum + c.adminUnreadCount);
});
