part of '../buttons/app_button.dart';

/// The one dialog. Surface, radius 24, title 18/700, body 14 secondary, two
/// equal-width actions: [secondaryLabel] on the left (an outlined button) and
/// the confirm action on the right — `primary`, or **solid red** when
/// [destructive] is true (the only place in the app solid red is allowed).
///
/// ```dart
/// final ok = await AppDialog.show(
///   context,
///   title: 'Cancel order?',
///   body: 'This cannot be undone.',
///   secondaryLabel: 'Keep order',
///   confirmLabel: 'Cancel order',
///   destructive: true,
/// );
/// if (ok == true) { ... }
/// ```
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.body,
    this.content,
    required this.secondaryLabel,
    required this.confirmLabel,
    this.destructive = false,
    this.onConfirm,
  });

  final String title;
  final String? body;

  /// Extra widget under the body (a field, a list...).
  final Widget? content;
  final String secondaryLabel;
  final String confirmLabel;

  /// Solid red confirm button — final confirmations only.
  final bool destructive;

  /// Called when the confirm button is pressed, before the dialog pops with
  /// `true`. Leave null to just pop.
  final VoidCallback? onConfirm;

  /// Shows the dialog. Resolves `true` on confirm, `false` on the left
  /// button, `null` if dismissed.
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    String? body,
    Widget? content,
    required String secondaryLabel,
    required String confirmLabel,
    bool destructive = false,
    VoidCallback? onConfirm,
    bool barrierDismissible = true,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: AppColors.barrier, // black 50%
      builder: (_) => AppDialog(
        title: title,
        body: body,
        content: content,
        secondaryLabel: secondaryLabel,
        confirmLabel: confirmLabel,
        destructive: destructive,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nav = Navigator.of(context);

    final confirm = destructive
        ? AppButton._dialogDanger(
            label: confirmLabel,
            onPressed: () {
              onConfirm?.call();
              nav.pop(true);
            },
          )
        : AppButton(
            label: confirmLabel,
            onPressed: () {
              onConfirm?.call();
              nav.pop(true);
            },
          );

    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        side: BorderSide(color: c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.title(c)),
              if (body != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  body!,
                  style: AppTypography.meta(c).copyWith(height: 1.45),
                ),
              ],
              if (content != null) ...[
                const SizedBox(height: AppSpacing.md),
                content!,
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: secondaryLabel,
                      variant: AppButtonVariant.secondary,
                      onPressed: () => nav.pop(false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: confirm),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
