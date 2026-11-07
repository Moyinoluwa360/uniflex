import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/support_message.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/support/support_chat_service.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/chat/support_order_chip.dart';
import '../../shared/widgets/inputs/app_text_field.dart';

/// Student-facing support chat.
///
/// Usage:
///   Navigator.of(context).push(MaterialPageRoute(
///     builder: (_) => const SupportChatScreen(),
///   ));
///
/// Pre-attach an order to the first message:
///   SupportChatScreen(initialOrderId: order.id, initialOrderLabel: '#AB12 · Preparing')
class SupportChatScreen extends ConsumerStatefulWidget {
  const SupportChatScreen({
    super.key,
    this.initialOrderId,
    this.initialOrderLabel,
    this.initialGroupId,
    this.initialGroupLabel,
  });

  /// Pre-fill a standalone order chip. Null for a plain conversation.
  final String? initialOrderId;

  /// Short label shown on the order chip, e.g. "#AB12 · Uniflex · Preparing".
  final String? initialOrderLabel;

  /// Pre-fill a delivery-group chip (multi-vendor checkout).
  final String? initialGroupId;

  /// Short label for the group chip, e.g. "#GRP1234 · Delivery".
  final String? initialGroupLabel;

  @override
  ConsumerState<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends ConsumerState<SupportChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;
  String? _error;
  String? _attachedOrderId;
  String? _attachedOrderLabel;
  String? _attachedGroupId;
  String? _attachedGroupLabel;

  @override
  void initState() {
    super.initState();
    _attachedOrderId = widget.initialOrderId;
    _attachedOrderLabel = widget.initialOrderLabel;
    _attachedGroupId = widget.initialGroupId;
    _attachedGroupLabel = widget.initialGroupLabel;
  }

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

    final orderId = _attachedOrderId;
    final groupId = _attachedGroupId;
    try {
      await ref.read(supportChatServiceProvider).sendMessage(
            text,
            orderId: orderId,
            groupId: groupId,
          );
      _controller.clear();
      // Detach the chip after the first send.
      if (mounted && (orderId != null || groupId != null)) {
        setState(() {
          _attachedOrderId = null;
          _attachedOrderLabel = null;
          _attachedGroupId = null;
          _attachedGroupLabel = null;
        });
      }
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

  /// Newest message is at the bottom (WhatsApp order). Scrolls after the
  /// next frame, and again one frame later, because a long list's extent
  /// is only final once the last items have been laid out.
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
    final convAsync = ref.watch(myConversationProvider);
    final userId = ref.watch(currentProfileProvider).valueOrNull?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: AppColors.pureWhite,
        actions: const [
          IconButton(
            icon: Icon(Icons.headset_mic_outlined),
            tooltip: 'Support',
            onPressed: null,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Status bar (resolved) ─────────────────────────────────────
          convAsync
                  .whenData(
                    (conv) => conv != null && conv.isResolved
                        ? Container(
                            width: double.infinity,
                            color: AppColors.mediumGrey.withValues(alpha: 0.1),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                            child: Text(
                              'This conversation was marked resolved. '
                              'Send a message to reopen it.',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : const SizedBox.shrink(),
                  )
                  .value ??
              const SizedBox.shrink(),

          // ── Message list ─────────────────────────────────────────────
          Expanded(
            child: convAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => RetrySection(
                message: 'Could not load messages.',
                onRetry: () => ref.invalidate(myConversationProvider),
              ),
              data: (conv) {
                // Mark read when screen is open.
                if (conv != null && conv.studentUnreadCount > 0) {
                  Future.microtask(() =>
                      ref.read(supportChatServiceProvider).markRead(conv.id));
                }

                if (conv == null) {
                  return _EmptyState(theme: theme);
                }

                return _MessageList(
                  conversationId: conv.id,
                  currentUserId: userId,
                  scrollController: _scrollController,
                  onScrollToBottom: _scrollToBottom,
                );
              },
            ),
          ),

          // ── Error banner ─────────────────────────────────────────────
          if (_error != null)
            Container(
              width: double.infinity,
              color: AppColors.error.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.error, size: 16),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.error),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _error = null),
                    child: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),

          // ── Input area ───────────────────────────────────────────────
          _InputBar(
            controller: _controller,
            isSending: _isSending,
            // Show whichever chip is set — order takes precedence.
            attachedOrderId: _attachedOrderId ?? _attachedGroupId,
            attachedOrderLabel: _attachedOrderLabel ?? _attachedGroupLabel,
            onDetachOrder: () => setState(() {
              _attachedOrderId = null;
              _attachedOrderLabel = null;
              _attachedGroupId = null;
              _attachedGroupLabel = null;
            }),
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.support_agent_outlined,
              size: 56,
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Hi! How can we help?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Send us a message and we\'ll get back to you as soon as possible.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Message list ──────────────────────────────────────────────────────────────

class _MessageList extends ConsumerStatefulWidget {
  const _MessageList({
    required this.conversationId,
    required this.currentUserId,
    required this.scrollController,
    required this.onScrollToBottom,
  });

  final String conversationId;
  final String currentUserId;
  final ScrollController scrollController;
  final VoidCallback onScrollToBottom;

  @override
  ConsumerState<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends ConsumerState<_MessageList> {
  List<SupportMessage>? _prev;

  @override
  Widget build(BuildContext context) {
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
        // Scroll to bottom on initial load and when new messages arrive.
        if (msgs.isNotEmpty && (_prev == null || msgs.length > _prev!.length)) {
          widget.onScrollToBottom();
        }
        _prev = msgs;

        if (msgs.isEmpty) {
          return const SizedBox.shrink();
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

            return Column(
              children: [
                if (showDate) _DateSeparator(date: msg.createdAt),
                _ChatBubble(
                  message: msg,
                  isMe: msg.senderId == widget.currentUserId,
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
}

// ── Date separator ────────────────────────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});
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

// ── Chat bubble ───────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.isMe});

  final SupportMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = isMe
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isMe ? AppColors.pureWhite : theme.colorScheme.onSurface;
    final labelColor = isMe
        ? AppColors.pureWhite.withValues(alpha: 0.7)
        : theme.colorScheme.onSurface.withValues(alpha: 0.5);

    final senderLabel = message.isFromAdmin
        ? 'Uniflex Support · ${message.senderName.split(' ').first}'
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
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    senderLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: labelColor, fontWeight: FontWeight.w600),
                  ),
                ),
              // Order chip — shown for an attached order OR delivery group.
              if (message.attachedRefId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: SupportOrderChip(
                    refId: message.attachedRefId!,
                    foreground: textColor,
                  ),
                ),
              Text(
                message.body,
                style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
              ),
              const SizedBox(height: 2),
              Text(
                _timeLabel(message.createdAt),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: labelColor, fontSize: 10),
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

// ── Input bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.isSending,
    required this.attachedOrderId,
    required this.attachedOrderLabel,
    required this.onDetachOrder,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final String? attachedOrderId;
  final String? attachedOrderLabel;
  final VoidCallback onDetachOrder;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Order chip (removable)
            if (attachedOrderId != null && attachedOrderLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: InputChip(
                  label: Text(
                    attachedOrderLabel!,
                    style: theme.textTheme.labelSmall,
                  ),
                  avatar: const Icon(Icons.receipt_long_outlined, size: 14),
                  onDeleted: onDetachOrder,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AppTextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Write a message…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
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
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _SendButton(isSending: isSending, onPressed: onSend),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.isSending, required this.onPressed});
  final bool isSending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: FilledButton(
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
        onPressed: isSending ? null : onPressed,
        child: isSending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.pureWhite),
              )
            : const Icon(Icons.send_rounded, size: 18),
      ),
    );
  }
}
