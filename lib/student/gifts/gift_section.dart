import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/utils/app_error_mapper.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import 'gift_models.dart';
import 'gift_repository.dart';

/// Longest gift message the server accepts.
const int kGiftMessageMax = 200;

/// The "Send as a gift" part of checkout (food delivery only — the parent
/// simply does not build it for pickup).
///
/// The parent owns the three pieces of state ([enabled], [recipient],
/// [messageController]); this widget only shows them and runs the lookup.
/// The sender never sees more than the recipient's nickname and a masked
/// email.
class GiftSection extends ConsumerStatefulWidget {
  const GiftSection({
    super.key,
    required this.enabled,
    required this.recipient,
    required this.messageController,
    required this.onEnabledChanged,
    required this.onRecipientChanged,
  });

  final bool enabled;
  final GiftRecipient? recipient;
  final TextEditingController messageController;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<GiftRecipient?> onRecipientChanged;

  @override
  ConsumerState<GiftSection> createState() => _GiftSectionState();
}

class _GiftSectionState extends ConsumerState<GiftSection> {
  final _email = TextEditingController();
  bool _finding = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final email = _email.text.trim();
    if (email.isEmpty || _finding) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _finding = true;
      _error = null;
    });
    try {
      final result = await ref.read(giftRepositoryProvider).lookup(email);
      if (!mounted) return;
      switch (result) {
        case GiftLookupFound(:final recipient):
          widget.onRecipientChanged(recipient);
        case GiftLookupFailed():
          setState(() => _error = result.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = AppErrorMapper.map(e));
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  void _change() {
    widget.onRecipientChanged(null);
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.recipient;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('gift-switch'),
          contentPadding: EdgeInsets.zero,
          secondary:
              const Icon(Icons.card_giftcard_outlined, color: AppColors.orange),
          title: Text('Send as a gift', style: theme.textTheme.titleSmall),
          subtitle: const Text(
              'Another student gets this food. You pay and can cancel.'),
          value: widget.enabled,
          onChanged: widget.onEnabledChanged,
        ),
        if (widget.enabled) ...[
          const SizedBox(height: AppSpacing.sm),
          if (r == null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _email,
                    label: "Recipient's email",
                    hint: 'The email they signed up with',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.search,
                    errorText: _error,
                    onSubmitted: (_) => _find(),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton(
                    key: const ValueKey('gift-find'),
                    onPressed: _finding ? null : _find,
                    child: _finding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Find'),
                  ),
                ),
              ],
            ),
          ] else
            Container(
              key: const ValueKey('gift-recipient'),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.emerald.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border:
                    Border.all(color: AppColors.emerald.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: AppColors.emerald, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Sending to: ',
                        children: [
                          TextSpan(
                            text: r.nickname,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: ' (${r.maskedEmail})'),
                        ],
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('gift-change'),
                    onPressed: _change,
                    child: const Text('Change'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: widget.messageController,
            label: 'Gift message (optional)',
            hint: 'e.g. Happy birthday!',
            maxLength: kGiftMessageMax,
            maxLines: 3,
            minLines: 1,
          ),
        ],
      ],
    );
  }
}
