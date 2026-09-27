import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../services/admin_providers.dart';
import '../services/admin_service.dart';
import 'referral_code_form_screen.dart';
import 'referral_code_uses_screen.dart';

/// Admin management of referral codes (Phase 10). Codes are minted here and
/// allocated to a person; students no longer generate their own at signup.
/// Each row shows how many signups the code has brought in.
class ReferralCodesScreen extends ConsumerWidget {
  const ReferralCodesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final codesAsync = ref.watch(adminReferralCodesProvider);

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Referral Codes'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, null),
        icon: const Icon(Icons.add),
        label: const Text('New Code'),
      ),
      body: codesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load referral codes.',
          onRetry: () => ref.invalidate(adminReferralCodesProvider),
        ),
        data: (codes) {
          if (codes.isEmpty) return const _EmptyCodes();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md,
              AppSpacing.screenGutter,
              AppSpacing.xl + 72,
            ),
            itemCount: codes.length,
            itemBuilder: (context, i) {
              final row = codes[i];
              return _CodeCard(
                row: row,
                onEdit: () => _openForm(context, row),
                onViewUses: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReferralCodeUsesScreen(row: row),
                  ),
                ),
                onToggle: (active) => _toggle(context, ref, row, active),
                onDelete: () => _confirmDelete(context, ref, row),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openForm(BuildContext context, ReferralCodeRow? row) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReferralCodeFormScreen(existing: row)),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    ReferralCodeRow row,
    bool active,
  ) async {
    try {
      await ref.read(adminServiceProvider).updateReferralCode(
            codeId: row.id,
            ownerId: row.ownerId,
            ownerLabel: row.ownerLabel,
            note: row.note,
            isActive: active,
          );
      ref.invalidate(adminReferralCodesProvider);
    } on AdminException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ReferralCodeRow row,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete code?'),
        content: Text(
          row.useCount > 0
              ? '${row.code} has ${row.useCount} signup'
                  '${row.useCount == 1 ? '' : 's'} attributed to it, so it '
                  'cannot be deleted — the attribution has to survive. '
                  'Pause it instead.'
              : 'Delete ${row.code}? Nobody has used it, so nothing is lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          if (row.useCount == 0)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(adminServiceProvider).deleteReferralCode(row.id);
      ref.invalidate(adminReferralCodesProvider);
    } on AdminException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _EmptyCodes extends StatelessWidget {
  const _EmptyCodes();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.emerald.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.confirmation_number_outlined,
                  size: 36, color: AppColors.emerald),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('No codes yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Mint a code and allocate it to a student or a promoter. '
              'Every signup that uses it is counted here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.row,
    required this.onEdit,
    required this.onViewUses,
    required this.onToggle,
    required this.onDelete,
  });

  final ReferralCodeRow row;
  final VoidCallback onEdit;
  final VoidCallback onViewUses;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: row.useCount > 0 ? onViewUses : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          row.code,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          tooltip: 'Copy code',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: row.code));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${row.code} copied')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: row.isActive,
                    onChanged: onToggle,
                    activeThumbColor: AppColors.emerald,
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'uses') onViewUses();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'uses', child: Text('View signups')),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete',
                            style: TextStyle(color: AppColors.error)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    row.earnsNobodyBonus
                        ? Icons.campaign_outlined
                        : Icons.person_outline,
                    size: 14,
                    color: muted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      row.allocatedTo,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '${row.useCount} used',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.emerald),
                    ),
                  ),
                ],
              ),
              if (row.earnsNobodyBonus) ...[
                const SizedBox(height: 4),
                Text(
                  'No app user attached — signups are tracked but no ₦500 '
                  'bonus is paid.',
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ],
              if (row.note != null && row.note!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  row.note!,
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
