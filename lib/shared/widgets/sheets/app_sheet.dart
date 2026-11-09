import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Bottom sheet chrome: `surface`, 28px top corners, a 36×4 grab handle in
/// `borderStrong`. Visual only — it adds no behaviour to its [child].
///
/// ```dart
/// AppSheet.show(context, builder: (_) => MyContent());
/// ```
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.screenGutter,
      0,
      AppSpacing.screenGutter,
      AppSpacing.lg,
    ),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.barrier,
      builder: (ctx) => AppSheet(child: builder(ctx)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Container(
                    key: const ValueKey('sheet-handle'),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: padding,
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
