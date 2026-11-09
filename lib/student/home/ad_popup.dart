import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/advertisement.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';

/// Opens [uri] outside the app. Returns false when nothing could open it.
typedef AdLinkLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultLauncher(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Shows the ad in a centred, rounded dialog over a dimmed background.
/// Tapping the dimmed area or the X closes it.
Future<void> showAdPopup(
  BuildContext context,
  Advertisement ad, {
  AdLinkLauncher? launcher,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => AdPopupDialog(ad: ad, launcher: launcher),
  );
}

/// The ad popup: the WHOLE image (fit: contain, never cropped), an X in the
/// corner, and — only when the ad has a link — a "Visit" button under the
/// image that opens the link in the external browser. Never larger than
/// ~85% of the screen in either direction (so it never goes full-screen).
class AdPopupDialog extends StatelessWidget {
  const AdPopupDialog({super.key, required this.ad, this.launcher});

  final Advertisement ad;
  final AdLinkLauncher? launcher;

  Future<void> _visit(BuildContext context) async {
    final link = ad.webLink;
    if (link == null) return;
    final uri = Uri.tryParse(link);
    var opened = false;
    if (uri != null) {
      try {
        opened = await (launcher ?? _defaultLauncher)(uri);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't open the link. Try again later."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final maxW = size.width * 0.85;
    final maxH = size.height * 0.85;
    final hasImage = (ad.imageUrl ?? '').trim().isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width * 0.075,
        vertical: size.height * 0.075,
      ),
      child: ConstrainedBox(
        key: const ValueKey('ad-popup'),
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sheet),
              child: ColoredBox(
                color: theme.colorScheme.surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: hasImage
                          ? Image.network(
                              ad.imageUrl!,
                              key: const ValueKey('ad-popup-image'),
                              fit: BoxFit.contain,
                              width: double.infinity,
                              loadingBuilder: (context, child, progress) =>
                                  progress == null
                                      ? child
                                      : const SizedBox(
                                          height: 200,
                                          child: Center(
                                              child:
                                                  CircularProgressIndicator()),
                                        ),
                              errorBuilder: (_, __, ___) => _TextFace(ad: ad),
                            )
                          : _TextFace(ad: ad),
                    ),
                    if (ad.hasLink)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: FilledButton.icon(
                          key: const ValueKey('ad-popup-visit'),
                          onPressed: () => _visit(context),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Visit'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: AppColors.adDark.withValues(alpha: 0.55),
                shape: const CircleBorder(),
                child: InkWell(
                  key: const ValueKey('ad-popup-close'),
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child:
                        Icon(Icons.close, size: 20, color: AppColors.onMedia),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown for an ad that has no (or an unloadable) image: its headline and
/// subtitle on the ad's own colour.
class _TextFace extends StatelessWidget {
  const _TextFace({required this.ad});

  final Advertisement ad;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: ad.isDark ? AppColors.adDark : context.colors.promoOrangeStart,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ad.title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(color: AppColors.onMedia)),
          if (ad.subtitle.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(ad.subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onMedia.withValues(alpha: 0.9))),
          ],
        ],
      ),
    );
  }
}
