import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/media/app_image.dart';
import '../ordering/catalog_screen.dart';
import '../ordering/product_repository.dart';

/// Lists all active vendors. Tapping any card opens its [CatalogScreen].
class AllVendorsScreen extends ConsumerWidget {
  const AllVendorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vendorsAsync = ref.watch(vendorsProvider);

    return Scaffold(
      appBar: const UniflexAppBar(title: 'All Vendors'),
      body: vendorsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load vendors.',
          onRetry: () => ref.invalidate(vendorsProvider),
        ),
        data: (vendors) {
          if (vendors.isEmpty) {
            return Center(
              child: Text('No vendors available.',
                  style: theme.textTheme.bodyMedium),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            itemCount: vendors.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final v = vendors[i];
              return ListTile(
                leading: SizedBox(
                  width: 48,
                  height: 48,
                  child: AppImage(
                    url: v.imageUrl,
                    keywords: 'restaurant,food',
                    seed: i + 1,
                    borderRadius: BorderRadius.circular(8),
                    icon: Icons.storefront_outlined,
                  ),
                ),
                title: Text(v.name),
                subtitle: v.description.isNotEmpty
                    ? Text(v.description,
                        maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => CatalogScreen(vendor: v)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
