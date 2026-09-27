import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../services/admin_providers.dart';
import '../services/admin_service.dart';

/// Everyone who signed up using one referral code.
class ReferralCodeUsesScreen extends ConsumerWidget {
  const ReferralCodeUsesScreen({super.key, required this.row});

  final ReferralCodeRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final usesAsync = ref.watch(adminReferralCodeUsesProvider(row.id));

    return Scaffold(
      appBar: UniflexAppBar(title: row.code),
      body: usesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load signups.',
          onRetry: () => ref.invalidate(adminReferralCodeUsesProvider(row.id)),
        ),
        data: (uses) {
          if (uses.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'Nobody has signed up with ${row.code} yet.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            itemCount: uses.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(
                    'Allocated to ${row.allocatedTo} · ${uses.length} signup'
                    '${uses.length == 1 ? '' : 's'}',
                    style: theme.textTheme.titleSmall,
                  ),
                );
              }
              final use = uses[i - 1];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(use.referredName),
                subtitle: Text(use.matricNumber ?? '—'),
                trailing: Text(
                  '${use.usedAt.day}/${use.usedAt.month}/${use.usedAt.year}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
