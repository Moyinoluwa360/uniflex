import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';

/// Reads a number out of a stats map (the database returns numeric as
/// int or double or even a string); anything missing counts as 0.
num statNum(Map<String, dynamic> stats, String key) {
  final v = stats[key];
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

String naira(num amount) {
  final n = amount.round();
  final digits = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '${n < 0 ? '-' : ''}₦$buf';
}

/// One money number split over today / this week / this month.
///
/// The dashboard shows TWO of these — "Fees collected" and "Food payments" —
/// side by side and never adds them together: fees are Uniflex's own money
/// (delivery / commitment fees and service charges), food payments are what
/// students paid for the food itself.
class PeriodMoneyCard extends StatelessWidget {
  const PeriodMoneyCard({
    super.key,
    required this.title,
    required this.caption,
    required this.today,
    required this.week,
    required this.month,
    required this.color,
    required this.icon,
  });

  final String title;
  final String caption;
  final num today;
  final num week;
  final num month;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    Widget row(String label, num v, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
              ),
              Text(
                naira(v),
                style: (strong
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.bodyLarge)
                    ?.copyWith(
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                  color: strong ? color : null,
                ),
              ),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 2),
          Text(caption,
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: AppSpacing.sm),
          row('Today', today, strong: true),
          row('This week', week),
          row('This month', month),
        ],
      ),
    );
  }
}

/// A small label/value tile used for the dashboard counts.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The footnote that explains the money split and the clock the numbers use.
class StatsFootnote extends StatelessWidget {
  const StatsFootnote({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Fees and food payments are separate and never added together. '
      'Only paid orders count. Days and weeks use Nigerian time; '
      'a week starts on Monday.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
      ),
    );
  }
}

const Color kFeesColor = AppColors.emerald;
const Color kFoodColor = AppColors.orange;
