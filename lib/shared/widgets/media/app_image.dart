import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// A network image with a branded, on-theme fallback — used for vendor and
/// meal photography across the app.
///
/// The design handoff renders all food/vendor imagery as labelled striped
/// placeholders ("send me photos and I'll drop them in"). Until real vendor
/// photos are attached, [AppImage] fills those slots with context-appropriate
/// random photography from LoremFlickr (keyword-seeded, so the same [seed]
/// always yields the same picture), falling back to a soft branded tile if
/// the network image is missing or fails to load. Pass an explicit [url]
/// (e.g. `vendor.imageUrl`) to use a real photo when one exists.
class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    this.url,
    this.keywords = 'food',
    this.seed = 1,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.icon = Icons.restaurant,
  });

  /// A real image URL, when the data has one. Falls back to a seeded random
  /// context photo when null/empty.
  final String? url;

  /// Comma-separated LoremFlickr keywords for the random fallback photo,
  /// e.g. `'jollof,rice'` or `'storefront'`.
  final String keywords;

  /// Stable seed so a given card always shows the same random photo.
  final int seed;

  final BorderRadius? borderRadius;
  final BoxFit fit;
  final IconData icon;

  String get _effectiveUrl {
    final u = url;
    if (u != null && u.trim().isNotEmpty) return u;
    return 'https://loremflickr.com/400/300/$keywords?lock=$seed';
  }

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.card);
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        _effectiveUrl,
        fit: fit,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _Placeholder(icon: icon, shimmer: true);
        },
        errorBuilder: (context, _, __) => _Placeholder(icon: icon),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, this.shimmer = false});

  final IconData icon;
  final bool shimmer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      color: isDark ? AppColors.darkSurface : AppColors.softGrey,
      alignment: Alignment.center,
      child: Icon(
        icon,
        color: theme.colorScheme.onSurface.withValues(alpha: shimmer ? 0.12 : 0.2),
        size: 28,
      ),
    );
  }
}
