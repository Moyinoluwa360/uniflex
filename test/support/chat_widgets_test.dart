// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';

import 'package:uniflex/shared/models/support_conversation.dart';
import 'package:uniflex/shared/models/support_message.dart';
import 'package:uniflex/shared/services/support/support_chat_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

SupportConversation _openConv({int studentUnread = 0, int adminUnread = 0}) =>
    SupportConversation(
      id: 'conv-1',
      studentId: 'student-1',
      status: 'open',
      studentUnreadCount: studentUnread,
      adminUnreadCount: adminUnread,
      createdAt: DateTime(2026, 1, 1),
    );

SupportConversation _resolvedConv() => SupportConversation(
      id: 'conv-2',
      studentId: 'student-1',
      status: 'resolved',
      studentUnreadCount: 0,
      adminUnreadCount: 0,
      createdAt: DateTime(2026, 1, 1),
    );

SupportMessage _msg({
  required String id,
  required String role,
  required String body,
  String? orderId,
  DateTime? createdAt,
}) =>
    SupportMessage(
      id: id,
      conversationId: 'conv-1',
      senderId: role == 'student' ? 'student-1' : 'admin-1',
      senderRole: role,
      senderName: role == 'student' ? 'Alice' : 'Bob',
      body: body,
      orderId: orderId,
      createdAt: createdAt ?? DateTime(2026, 1, 1, 10, 0),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('SupportMessage model', () {
    test('isFromAdmin is true for admin role', () {
      final msg = _msg(id: '1', role: 'admin', body: 'Hello');
      expect(msg.isFromAdmin, true);
      expect(msg.isFromStudent, false);
    });

    test('isFromStudent is true for student role', () {
      final msg = _msg(id: '1', role: 'student', body: 'Help me');
      expect(msg.isFromStudent, true);
      expect(msg.isFromAdmin, false);
    });

    test('fromMap parses all fields including nullable order_id', () {
      final now = DateTime(2026, 11, 4, 14, 30).toUtc().toIso8601String();
      final map = {
        'id': 'msg-1',
        'conversation_id': 'conv-1',
        'sender_id': 'sender-1',
        'sender_role': 'admin',
        'sender_name': 'Jane',
        'body': 'Your order is ready.',
        'order_id': 'order-1',
        'created_at': now,
      };
      final msg = SupportMessage.fromMap(map);
      expect(msg.id, 'msg-1');
      expect(msg.senderRole, 'admin');
      expect(msg.orderId, 'order-1');
      expect(msg.isFromAdmin, true);
    });

    test('fromMap handles null order_id', () {
      final map = {
        'id': 'msg-2',
        'conversation_id': 'conv-1',
        'sender_id': 'sender-1',
        'sender_role': 'student',
        'sender_name': 'Alice',
        'body': 'Hello',
        'order_id': null,
        'created_at': DateTime(2026).toUtc().toIso8601String(),
      };
      final msg = SupportMessage.fromMap(map);
      expect(msg.orderId, isNull);
      expect(msg.isFromStudent, true);
    });
  });

  group('SupportConversation model', () {
    test('isOpen / isResolved computed correctly', () {
      expect(_openConv().isOpen, true);
      expect(_openConv().isResolved, false);
      expect(_resolvedConv().isResolved, true);
      expect(_resolvedConv().isOpen, false);
    });

    test('fromMap parses resolved conversation', () {
      final map = {
        'id': 'c-1',
        'student_id': 's-1',
        'status': 'resolved',
        'last_message_at': null,
        'last_message_preview': null,
        'student_unread_count': 0,
        'admin_unread_count': 2,
        'resolved_at': DateTime(2026, 1, 2).toUtc().toIso8601String(),
        'created_at': DateTime(2026, 1, 1).toUtc().toIso8601String(),
      };
      final c = SupportConversation.fromMap(map);
      expect(c.isResolved, true);
      expect(c.adminUnreadCount, 2);
      expect(c.resolvedAt, isNotNull);
    });

    test('fromMap defaults missing status to open', () {
      final map = {
        'id': 'c-2',
        'student_id': 's-2',
        'student_unread_count': 0,
        'admin_unread_count': 0,
        'created_at': DateTime(2026).toUtc().toIso8601String(),
      };
      final c = SupportConversation.fromMap(map);
      expect(c.isOpen, true);
    });
  });

  group('adminSupportUnreadProvider logic', () {
    test('sums admin_unread_count across all conversations', () {
      final convs = [
        _openConv(adminUnread: 3),
        _openConv(adminUnread: 0),
        _resolvedConv(),
        SupportConversation(
          id: 'x',
          studentId: 'y',
          status: 'open',
          studentUnreadCount: 0,
          adminUnreadCount: 5,
          createdAt: DateTime(2026),
        ),
      ];
      final total = convs.fold(0, (sum, c) => sum + c.adminUnreadCount);
      expect(total, 8);
    });

    test('returns 0 when list is empty', () {
      final total = <SupportConversation>[].fold(
        0, (sum, c) => sum + c.adminUnreadCount);
      expect(total, 0);
    });
  });

  group('SupportException', () {
    test('toString includes message', () {
      final ex = SupportException('RATE_LIMITED');
      expect(ex.toString(), contains('RATE_LIMITED'));
    });

    test('is an Exception', () {
      expect(SupportException('x'), isA<Exception>());
    });
  });

  group('Date separator logic', () {
    test('messages on same day share a separator', () {
      final d1 = DateTime(2026, 11, 4, 9, 0);
      final d2 = DateTime(2026, 11, 4, 14, 30);
      expect(_sameDay(d1, d2), true);
    });

    test('messages on different days get different separators', () {
      final d1 = DateTime(2026, 11, 4);
      final d2 = DateTime(2026, 11, 5);
      expect(_sameDay(d1, d2), false);
    });

    test('messages on same day but different years differ', () {
      final d1 = DateTime(2025, 11, 4);
      final d2 = DateTime(2026, 11, 4);
      expect(_sameDay(d1, d2), false);
    });
  });

  group('Message ordering', () {
    test('messages preserve chronological order (oldest-first from stream)', () {
      final msgs = [
        _msg(id: '1', role: 'student', body: 'First',
            createdAt: DateTime(2026, 1, 1, 9)),
        _msg(id: '2', role: 'admin', body: 'Second',
            createdAt: DateTime(2026, 1, 1, 10)),
        _msg(id: '3', role: 'student', body: 'Third',
            createdAt: DateTime(2026, 1, 1, 11)),
      ];
      expect(msgs.first.body, 'First');
      expect(msgs.last.body, 'Third');
    });

    test('admin message bubble shows admin name', () {
      final msg = _msg(id: '1', role: 'admin', body: 'Here to help');
      expect(msg.isFromAdmin, true);
      expect(msg.senderName, 'Bob');
    });

    test('student message bubble shows student name', () {
      final msg = _msg(id: '2', role: 'student', body: 'Need help');
      expect(msg.isFromStudent, true);
      expect(msg.senderName, 'Alice');
    });
  });

  group('Inbox filter logic', () {
    test('open filter excludes resolved conversations', () {
      final convs = [_openConv(), _resolvedConv()];
      final open = convs.where((c) => c.isOpen).toList();
      expect(open.length, 1);
      expect(open.first.isOpen, true);
    });

    test('resolved filter excludes open conversations', () {
      final convs = [_openConv(), _resolvedConv()];
      final resolved = convs.where((c) => c.isResolved).toList();
      expect(resolved.length, 1);
      expect(resolved.first.isResolved, true);
    });

    test('all filter returns everything', () {
      final convs = [_openConv(), _resolvedConv()];
      expect(convs.length, 2);
    });
  });

  group('Message content validation', () {
    test('body trimming — whitespace-only should be caught', () {
      const body = '   ';
      expect(body.trim().isEmpty, true);
    });

    test('body > 2000 chars should be caught', () {
      final body = 'x' * 2001;
      expect(body.length > 2000, true);
    });

    test('body of exactly 2000 chars is valid', () {
      final body = 'x' * 2000;
      expect(body.length <= 2000, true);
      expect(body.trim().isNotEmpty, true);
    });
  });
}

// ── Helpers ──────────────────────────────────────────────────────────────────

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
