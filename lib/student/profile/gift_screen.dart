import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../services/student_providers.dart';

/// Gift screen — two tabs: Send a gift and Gift history.
class GiftScreen extends ConsumerStatefulWidget {
  const GiftScreen({super.key});

  @override
  ConsumerState<GiftScreen> createState() => _GiftScreenState();
}

class _GiftScreenState extends ConsumerState<GiftScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Food Gifts'),
          bottom: TabBar(
            controller: _tabs,
            indicatorColor: AppColors.emerald,
            tabs: const [
            Tab(text: 'Send Gift'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _SendGiftTab(),
          _GiftHistoryTab(),
        ],
      ),
    );
  }
}

/// Send-a-gift tab — matric number lookup + message.
class _SendGiftTab extends ConsumerStatefulWidget {
  const _SendGiftTab();

  @override
  ConsumerState<_SendGiftTab> createState() => _SendGiftTabState();
}

class _SendGiftTabState extends ConsumerState<_SendGiftTab> {
  final _formKey = GlobalKey<FormState>();
  final _matricController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _matricController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero icon
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.card_giftcard,
                    color: AppColors.emerald, size: 36),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Text(
                'Send food to a friend',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            Center(
              child: Text(
                'Enter their matric number to find them.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            Text("Recipient's matric number",
                style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              controller: _matricController,
              hint: 'e.g. RUN/CIS/21/1234',
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Enter a matric number'
                  : null,
            ),

            const SizedBox(height: AppSpacing.md),

            Text('Message (optional)', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              controller: _messageController,
              hint: 'Add a personal message…',
              maxLines: 3,
            ),

            const SizedBox(height: AppSpacing.xl),

            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border:
                    Border.all(color: AppColors.info.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.info, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'After finding your friend, you\'ll choose items from '
                      'any vendor and pay from your wallet.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.info),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.pureWhite),
                      )
                    : const Icon(Icons.search),
                label: Text(_isSending ? 'Looking up…' : 'Find Recipient'),
                onPressed: _isSending ? null : _lookup,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _lookup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSending = true);
    try {
      // Navigate to vendor selection with context carrying the matric + msg
      // For now: show a placeholder snack explaining the flow is vendor-first.
      // Full integration requires a vendor picker that pre-populates the cart
      // for the recipient — wired up in the "Send Gift" cart flow extension.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Gift flow: choose a vendor from the Home tab, '
              'add items to cart, then select "Send as Gift" at checkout.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }
}

/// Gift history tab.
class _GiftHistoryTab extends ConsumerWidget {
  const _GiftHistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final giftsAsync = ref.watch(giftsProvider);

    return giftsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load: $e')),
      data: (gifts) {
        if (gifts.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.card_giftcard_outlined,
                    size: 56,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.3)),
                const SizedBox(height: AppSpacing.md),
                Text('No gifts yet',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Sent or received gifts will appear here.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          itemCount: gifts.length,
          itemBuilder: (ctx, i) {
            final g = gifts[i];
            return Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: g.isSent
                      ? AppColors.orange.withValues(alpha: 0.12)
                      : AppColors.emerald.withValues(alpha: 0.12),
                  child: Icon(
                    g.isSent
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    color: g.isSent
                        ? AppColors.orange
                        : AppColors.emerald,
                    size: 18,
                  ),
                ),
                title: Text(
                  g.isSent
                      ? 'To ${g.otherPartyName}'
                      : 'From ${g.otherPartyName}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: g.message != null
                    ? Text(g.message!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall)
                    : null,
                trailing: Text(
                  '₦${g.totalAmount.toStringAsFixed(0)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
