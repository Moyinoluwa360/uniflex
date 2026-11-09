import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/delivery_group.dart';
import '../../shared/models/order.dart';
import '../../shared/models/support_conversation.dart';
import '../../shared/models/support_message.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/support/support_chat_service.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/chat/support_order_chip.dart';
import '../orders/admin_order_details_screen.dart';
import '../services/profile_basics.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../../shared/widgets/buttons/app_button.dart';

/// Admin chat view for a specific student conversation.
/// Shows student name + phone in the header, allows replying from any admin,
/// and provides a "Mark resolved" action.
class AdminSupportChatScreen extends ConsumerStatefulWidget {
  const AdminSupportChatScreen({super.key, required this.conversation});

  final SupportConversation conversation;

  @override
  ConsumerState<AdminSupportChatScreen> createState() =>
      _AdminSupportChatScreenState();
}

class _AdminSupportChatScreenState
    extends ConsumerState<AdminSupportChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_isSending) return; // Double-tap guard.
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      await ref.read(supportChatServiceProvider).sendMessage(
            text,
            conversationId: widget.conversation.id,
          );
      _controller.clear();
      _scrollToBottom();
    } on SupportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not send message. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _confirmResolve() async {
    final confirmed = await AppDialog.show(
      context,
      title: 'Mark as resolved?',
      body: 'This will close the conversation. '
          'The student can still send a message to reopen it.',
      secondaryLabel: 'Cancel',
      confirmLabel: 'Resolve',
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref
          .read(supportChatServiceProvider)
          .resolveConversation(widget.conversation.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conversation marked as resolved.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } on SupportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Newest message at the bottom (WhatsApp order). Runs after the next
  /// frame and again one frame later, once the list extent is final.
  void _scrollToBottom() {
    void jump() {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
      WidgetsBinding.instance.addPostFrameCallback((_) => jump());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myId = ref.watch(currentProfileProvider).valueOrNull?.id ?? '';
    final conv = widget.conversation;

    return Scaffold(
      appBar: _StudentHeader(
        studentId: conv.studentId,
        isResolved: conv.isResolved,
        onResolve: conv.isOpen ? _confirmResolve : null,
      ),
      body: Column(
        children: [
          // ── Resolved banner ─────────────────────────────────────────
          if (conv.isResolved)
            Container(
              width: double.infinity,
              color: context.colors.surfaceRaised,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                'Resolved — student can reopen by sending a new message.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // ── Message list ─────────────────────────────────────────────
          Expanded(
            child: _AdminMessageList(
              conversationId: conv.id,
              currentUserId: myId,
              scrollController: _scrollController,
              onScrollToBottom: _scrollToBottom,
              onLoaded: () {
                // Mark read when conversation is opened.
                ref.read(supportChatServiceProvider).markRead(conv.id);
              },
            ),
          ),

          // ── Error banner ─────────────────────────────────────────────
          if (_error != null)
            Container(
              width: double.infinity,
              color: context.colors.surfaceRaised,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: context.colors.dangerText, size: 16),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: context.colors.dangerText),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _error = null),
                    child: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),

          // ── Input ────────────────────────────────────────────────────
          SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Reply to student…',
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.control),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Semantics(
                    button: true,
                    enabled: !_isSending,
                    label: 'Send',
                    child: Material(
                      color: _isSending
                          ? context.colors.surfaceRaised
                          : context.colors.brand,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _isSending ? null : _send,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: _isSending
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: context.colors.textSecondary,
                                    ),
                                  )
                                : Icon(Icons.send_rounded,
                                    size: 18, color: context.colors.onBrand),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Student header AppBar ─────────────────────────────────────────────────────

class _StudentHeader extends ConsumerWidget implements PreferredSizeWidget {
  const _StudentHeader({
    required this.studentId,
    required this.isResolved,
    this.onResolve,
  });

  final String studentId;
  final bool isResolved;
  final VoidCallback? onResolve;

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref
        .watch(adminProfileBasicsProvider(profileIdsKey([studentId])))
        .valueOrNull?[studentId];
    final theme = Theme.of(context);
    final fullName = profile?.secondaryName;
    final phone = profile?.phone;

    return AppBar(
      toolbarHeight: 68,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            profile?.displayName('Student') ?? 'Student',
            key: const ValueKey('chat-header-name'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: context.colors.onBrand,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (fullName != null)
            Text(
              fullName,
              key: const ValueKey('chat-header-full-name'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: context.colors.onBrand.withValues(alpha: 0.9),
              ),
            ),
          if (phone != null && phone.isNotEmpty)
            Text(
              phone,
              style: theme.textTheme.labelSmall?.copyWith(
                color: context.colors.onBrand.withValues(alpha: 0.8),
              ),
            ),
        ],
      ),
      backgroundColor: Theme.of(context).colorScheme.primary,
      actions: [
        if (onResolve != null)
          TextButton.icon(
            onPressed: onResolve,
            icon: Icon(Icons.check_circle_outline,
                color: context.colors.onBrand, size: 16),
            label: Text(
              'Resolve',
              style: TextStyle(color: context.colors.onBrand),
            ),
          ),
      ],
    );
  }
}

// ── Admin message list ────────────────────────────────────────────────────────

class _AdminMessageList extends ConsumerStatefulWidget {
  const _AdminMessageList({
    required this.conversationId,
    required this.currentUserId,
    required this.scrollController,
    required this.onScrollToBottom,
    required this.onLoaded,
  });

  final String conversationId;
  final String currentUserId;
  final ScrollController scrollController;
  final VoidCallback onScrollToBottom;
  final VoidCallback onLoaded;

  @override
  ConsumerState<_AdminMessageList> createState() => _AdminMessageListState();
}

class _AdminMessageListState extends ConsumerState<_AdminMessageList> {
  List<SupportMessage>? _prev;
  bool _calledOnLoaded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msgsAsync =
        ref.watch(conversationMessagesProvider(widget.conversationId));

    return msgsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => RetrySection(
        message: 'Could not load messages.',
        onRetry: () =>
            ref.invalidate(conversationMessagesProvider(widget.conversationId)),
      ),
      data: (msgs) {
        if (!_calledOnLoaded) {
          _calledOnLoaded = true;
          Future.microtask(widget.onLoaded);
          Future.microtask(widget.onScrollToBottom);
        }

        if (_prev != null && msgs.length > _prev!.length) {
          widget.onScrollToBottom();
        }
        _prev = msgs;

        if (msgs.isEmpty) {
          return Center(
            child: Text(
              'No messages yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          );
        }

        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          itemCount: msgs.length,
          itemBuilder: (context, i) {
            final msg = msgs[i];
            final showDate =
                i == 0 || !_sameDay(msgs[i - 1].createdAt, msg.createdAt);
            final isMe = msg.senderId == widget.currentUserId;

            return Column(
              children: [
                if (showDate) _AdminDateSep(date: msg.createdAt),
                _AdminBubble(
                  message: msg,
                  isMe: isMe,
                  onOpenRef:
                      msg.attachedRefId == null ? null : () => _openRef(msg),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Tapping the order chip opens that order's admin details: the delivery
  /// group for a delivery, the order itself for an errand / pickup.
  Future<void> _openRef(SupportMessage msg) async {
    final service = ref.read(supportChatServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      Widget? screen;
      if (msg.deliveryGroupId != null) {
        final row = await service.fetchDeliveryGroup(msg.deliveryGroupId!);
        if (row != null) {
          screen =
              AdminOrderDetailsScreen.group(group: DeliveryGroup.fromMap(row));
        }
      } else if (msg.orderId != null) {
        final row = await service.fetchOrder(msg.orderId!);
        if (row != null) {
          screen = AdminOrderDetailsScreen.order(order: Order.fromMap(row));
        }
      }
      if (screen == null) {
        messenger.showSnackBar(const SnackBar(
          content: Text('That order could not be found.'),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      final target = screen;
      await navigator.push(MaterialPageRoute(builder: (_) => target));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Could not open that order. Please try again.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

class _AdminDateSep extends StatelessWidget {
  const _AdminDateSep({required this.date});
  final DateTime date;

  String _label() {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    }
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(child: Divider(color: theme.dividerColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              _label(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(child: Divider(color: theme.dividerColor)),
        ],
      ),
    );
  }
}

class _AdminBubble extends StatelessWidget {
  const _AdminBubble({
    required this.message,
    required this.isMe,
    this.onOpenRef,
  });

  final SupportMessage message;
  final bool isMe;

  /// Opens the attached order; null when the message has none.
  final VoidCallback? onOpenRef;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = isMe
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor =
        isMe ? context.colors.onBrand : theme.colorScheme.onSurface;
    final labelColor = isMe
        ? context.colors.onBrand.withValues(alpha: 0.7)
        : theme.colorScheme.onSurface.withValues(alpha: 0.5);

    // Admin messages show which admin sent them.
    // Student messages show the student's name.
    final senderLabel = message.isFromAdmin
        ? (isMe ? 'You' : message.senderName)
        : message.senderName;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(AppRadius.card),
              topRight: const Radius.circular(AppRadius.card),
              bottomLeft: Radius.circular(isMe ? AppRadius.card : 4),
              bottomRight: Radius.circular(isMe ? 4 : AppRadius.card),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  senderLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: labelColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (message.attachedRefId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: SupportOrderChip(
                    refId: message.attachedRefId!,
                    foreground: textColor,
                    onTap: onOpenRef,
                  ),
                ),
              Text(
                message.body,
                style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
              ),
              const SizedBox(height: 2),
              Text(
                _timeLabel(message.createdAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: labelColor,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeLabel(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
