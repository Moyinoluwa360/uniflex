import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../shared/models/profile.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../services/student_providers.dart';

/// Referral screen — shows the student's code, share button, and the
/// top-10 leaderboard.
class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final leaderboardAsync = ref.watch(referralLeaderboardProvider);
    final code = profile.referralCode ?? '—';

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Refer a Friend'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero card ──────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.emerald, AppColors.splashGradientMid],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Column(
                children: [
                  const Icon(Icons.people, color: AppColors.pureWhite, size: 40),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Earn ₦500 for every friend',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.pureWhite,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'They place their first order, you both win.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.pureWhite.withValues(alpha: 0.8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Code block ─────────────────────────────────────────────
            Text('Your referral code', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      code,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                        color: theme.colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined),
                    tooltip: 'Copy',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied')),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share my code'),
                onPressed: () => Share.share(
                  'Use my Uniflex referral code $code when you sign up '
                  'and we both earn ₦500! Download Uniflex for campus food ordering.',
                  subject: 'Join me on Uniflex',
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── Leaderboard ────────────────────────────────────────────
            Text('Referral Leaderboard', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            leaderboardAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Could not load: $e'),
              data: (rows) {
                if (rows.isEmpty) {
                  return Text(
                    'No referrals yet — be the first!',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  );
                }
                return Column(
                  children: rows.asMap().entries.map((entry) {
                    final i = entry.key;
                    final row = entry.value;
                    final rank = row['rank'] as int? ?? i + 1;
                    final name =
                        row['display_name'] as String? ?? '—';
                    final count = row['referral_count'] as int? ?? 0;
                    return _LeaderboardRow(
                      rank: rank,
                      name: name,
                      count: count,
                      theme: theme,
                      isTop3: rank <= 3,
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.rank,
    required this.name,
    required this.count,
    required this.theme,
    required this.isTop3,
  });
  final int rank;
  final String name;
  final int count;
  final ThemeData theme;
  final bool isTop3;

  @override
  Widget build(BuildContext context) {
    final medal = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => '$rank.',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              medal,
              style: isTop3
                  ? const TextStyle(fontSize: 18)
                  : theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(name, style: theme.textTheme.bodyMedium),
          ),
          Text(
            '$count referrals',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.emerald,
            ),
          ),
        ],
      ),
    );
  }
}
