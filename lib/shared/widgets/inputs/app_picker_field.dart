import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../sheets/app_sheet.dart';
import 'app_text_field.dart';

/// A tappable box that looks exactly like a large [AppTextField] but opens
/// something else (a date picker, a sheet) instead of the keyboard.
/// [valueText] null ⇒ the [placeholder] is shown in the hint colour.
class AppPickerField extends StatelessWidget {
  const AppPickerField({
    super.key,
    required this.placeholder,
    required this.onTap,
    this.valueText,
    this.leadingIcon,
    this.trailingIcon = AppIcons.chevronDown,
    this.errorText,
    this.enabled = true,
  });

  final String placeholder;
  final String? valueText;
  final VoidCallback? onTap;
  final IconData? leadingIcon;
  final IconData trailingIcon;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasValue = valueText != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: placeholder,
      value: valueText,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.input),
          onTap: enabled ? onTap : null,
          child: InputDecorator(
            isEmpty: !hasValue,
            decoration: appLargeInputDecoration(
              context,
              errorText: errorText,
              leadingIcon: leadingIcon,
              trailing: Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Icon(trailingIcon, size: 20, color: c.textSecondary),
              ),
              locked: !enabled,
            ),
            child: Text(
              hasValue ? valueText! : placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body(c).copyWith(
                fontSize: 15.5,
                color: hasValue ? c.textPrimary : c.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppDropdownItem<T> {
  const AppDropdownItem(this.value, this.label);
  final T value;
  final String label;
}

/// A dropdown: the [AppPickerField] box with a chevron-down; tapping opens an
/// [AppSheet] with 56 px rows, the selected one marked with a `brandText`
/// check. Same options, same selection behaviour as the menu it replaces.
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    this.leadingIcon,
    this.errorText,
  });

  /// Shown as the box's placeholder and as the sheet's title.
  final String label;
  final List<AppDropdownItem<T>> items;
  final T? value;
  final ValueChanged<T> onChanged;
  final IconData? leadingIcon;
  final String? errorText;

  String? get _valueText {
    for (final i in items) {
      if (i.value == value) return i.label;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    final picked = await AppSheet.show<T>(
      context,
      builder: (ctx) {
        final c = ctx.colors;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(label, style: AppTypography.title(c)),
            ),
            for (final i in items)
              InkWell(
                key: ValueKey('dropdown-row-${i.label}'),
                onTap: () => Navigator.of(ctx).pop(i.value),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          i.label,
                          style: AppTypography.body(c),
                        ),
                      ),
                      if (i.value == value)
                        Icon(AppIcons.check, size: 22, color: c.brandText),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return AppPickerField(
      placeholder: label,
      valueText: _valueText,
      leadingIcon: leadingIcon,
      errorText: errorText,
      onTap: () => _open(context),
    );
  }
}
