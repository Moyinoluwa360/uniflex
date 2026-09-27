import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/advertisement.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/media/app_image.dart';
import '../services/admin_providers.dart';
import 'advertisement_form_screen.dart';

/// Admin management of the advertisement banners on the student home page.
/// Replaces the hardcoded promo list that used to live in the Flutter app.
class AdvertisementsScreen extends ConsumerWidget {
  const AdvertisementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adsAsync = ref.watch(adminAdvertisementsProvider);

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Advertisements'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, null),
        icon: const Icon(Icons.add),
        label: const Text('New Ad'),
      ),
      body: adsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load advertisements.',
          onRetry: () => ref.invalidate(adminAdvertisementsProvider),
        ),
        data: (ads) {
          if (ads.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'No advertisements yet. Tap + to add one — it appears in '
                  'the carousel on the student home page.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md,
              AppSpacing.screenGutter,
              AppSpacing.xl + 72,
            ),
            itemCount: ads.length,
            itemBuilder: (context, i) => _AdCard(
              ad: ads[i],
              onEdit: () => _openForm(context, ads[i]),
              onToggle: (active) => _toggle(ref, ads[i], active),
              onDelete: () => _confirmDelete(context, ref, ads[i]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openForm(BuildContext context, Advertisement? ad) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdvertisementFormScreen(existing: ad)),
    );
  }

  Future<void> _toggle(WidgetRef ref, Advertisement ad, bool active) async {
    await ref.read(adminServiceProvider).upsertAdvertisement(
          id: ad.id,
          title: ad.title,
          subtitle: ad.subtitle,
          isDark: ad.isDark,
          isActive: active,
          sortOrder: ad.sortOrder,
          imageUrl: ad.imageUrl,
          linkType: ad.linkType,
          linkValue: ad.linkValue,
          startsAt: ad.startsAt,
          endsAt: ad.endsAt,
        );
    ref.invalidate(adminAdvertisementsProvider);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Advertisement ad,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete advertisement?'),
        content: Text('Remove "${ad.title}" from the home carousel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(adminServiceProvider).deleteAdvertisement(ad.id);
    ref.invalidate(adminAdvertisementsProvider);
  }
}

class _AdCard extends StatelessWidget {
  const _AdCard({
    required this.ad,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final Advertisement ad;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  Color _statusColor() => switch (ad.statusLabel) {
        'Live' => AppColors.emerald,
        'Scheduled' => AppColors.info,
        'Ended' => AppColors.mediumGrey,
        _ => AppColors.orange,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final statusColor = _statusColor();

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control - 4),
              child: SizedBox(
                width: 56,
                height: 56,
                child: ad.imageUrl != null && ad.imageUrl!.isNotEmpty
                    ? AppImage(url: ad.imageUrl, fit: BoxFit.cover)
                    : ColoredBox(
                        color: ad.isDark
                            ? AppColors.matteBlack
                            : AppColors.orange,
                        child: const Icon(Icons.campaign_outlined,
                            color: AppColors.pureWhite, size: 20),
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ad.title,
                      style: theme.textTheme.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (ad.subtitle.isNotEmpty)
                    Text(
                      ad.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          ad.statusLabel,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: statusColor),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text('#${ad.sortOrder}',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: muted)),
                      if (ad.linkType != AdLinkType.none) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Icon(Icons.link, size: 12, color: muted),
                        const SizedBox(width: 2),
                        Text(ad.linkType.name,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: muted)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Switch(
              value: ad.isActive,
              onChanged: onToggle,
              activeThumbColor: AppColors.emerald,
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                  value: 'delete',
                  child:
                      Text('Delete', style: TextStyle(color: AppColors.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
