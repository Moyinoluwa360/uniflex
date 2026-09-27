import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../buttons/primary_button.dart';
import '../inputs/app_text_field.dart';

/// Bottom sheet for sending a one-off message to an order's customer.
///
/// Used by both the Admin kitchen queue and the Rider active-delivery screen,
/// which differ only in who does the sending — hence [onSend] rather than a
/// service dependency baked in here.
///
/// Returns true when a message was sent.
Future<bool> showMessageCustomerSheet(
  BuildContext context, {
  required Future<void> Function(String message) onSend,
  String? customerName,
  List<String> quickReplies = const [],
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _MessageCustomerSheet(
      onSend: onSend,
      customerName: customerName,
      quickReplies: quickReplies,
    ),
  );
  return sent ?? false;
}

class _MessageCustomerSheet extends StatefulWidget {
  const _MessageCustomerSheet({
    required this.onSend,
    this.customerName,
    this.quickReplies = const [],
  });

  final Future<void> Function(String message) onSend;
  final String? customerName;
  final List<String> quickReplies;

  @override
  State<_MessageCustomerSheet> createState() => _MessageCustomerSheetState();
}

class _MessageCustomerSheetState extends State<_MessageCustomerSheet> {
  final _controller = TextEditingController();
  bool _isSending = false;
  String? _error;

  static const _maxLength = 300;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Type a message first.');
      return;
    }

    setState(() {
      _isSending = true;
      _error = null;
    });
    try {
      await widget.onSend(text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is Exception
            ? e.toString().replaceFirst(RegExp(r'^\w+Exception: '), '')
            : 'Could not send the message.');
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = widget.customerName;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenGutter,
        right: AppSpacing.screenGutter,
        top: AppSpacing.lg,
        // Keep the field above the keyboard.
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.chat_bubble_outline, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  who == null ? 'Message customer' : 'Message $who',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'They get a push notification and it is saved to their in-app '
            'notifications.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          if (widget.quickReplies.isNotEmpty) ...[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: widget.quickReplies
                  .map(
                    (reply) => ActionChip(
                      label: Text(reply),
                      onPressed: () => setState(() {
                        _controller.text = reply;
                        _error = null;
                      }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          AppTextField(
            controller: _controller,
            hint: 'Type your message…',
            maxLines: 3,
            maxLength: _maxLength,
            errorText: _error,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'Send',
            icon: Icons.send_outlined,
            isLoading: _isSending,
            onPressed: _send,
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: _isSending ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.mediumGrey)),
            ),
          ),
        ],
      ),
    );
  }
}
