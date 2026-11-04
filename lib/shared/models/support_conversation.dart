/// One support conversation per student. Created the first time a student
/// sends a message; never deleted. Admins see all conversations; a student
/// can only see their own.
class SupportConversation {
  const SupportConversation({
    required this.id,
    required this.studentId,
    required this.status,
    this.lastMessageAt,
    this.lastMessagePreview,
    required this.studentUnreadCount,
    required this.adminUnreadCount,
    this.resolvedAt,
    required this.createdAt,
  });

  factory SupportConversation.fromMap(Map<String, dynamic> m) {
    return SupportConversation(
      id: m['id'] as String,
      studentId: m['student_id'] as String,
      status: m['status'] as String? ?? 'open',
      lastMessageAt: m['last_message_at'] == null
          ? null
          : DateTime.parse(m['last_message_at'] as String).toLocal(),
      lastMessagePreview: m['last_message_preview'] as String?,
      studentUnreadCount: m['student_unread_count'] as int? ?? 0,
      adminUnreadCount: m['admin_unread_count'] as int? ?? 0,
      resolvedAt: m['resolved_at'] == null
          ? null
          : DateTime.parse(m['resolved_at'] as String).toLocal(),
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    );
  }

  final String id;
  final String studentId;

  /// 'open' | 'resolved'
  final String status;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final int studentUnreadCount;
  final int adminUnreadCount;
  final DateTime? resolvedAt;
  final DateTime createdAt;

  bool get isOpen => status == 'open';
  bool get isResolved => status == 'resolved';
}
