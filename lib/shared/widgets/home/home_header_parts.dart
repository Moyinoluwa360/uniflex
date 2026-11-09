import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../buttons/tap_guard.dart';
import '../format/money.dart';

/// 40×40 glass button that sits ON the green Home header: radius 12,
/// header-glass fill and border, 22px outline icon in the header text colour.
/// [showDot] draws the 10px unread dot (`notifyDot`, 2px border in the header
/// colour). It carries no count.
class HeaderGlassButton extends StatefulWidget {
  const HeaderGlassButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.showDot = false,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool showDot;
  final String? semanticLabel;

  @override
  State<HeaderGlassButton> createState() => _HeaderGlassButtonState();
}

class _HeaderGlassButtonState extends State<HeaderGlassButton> {
  final _guard = TapGuard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.iconButton);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Material(
                color: c.headerPanelFill,
                shape: RoundedRectangleBorder(
                  borderRadius: radius,
                  side: BorderSide(color: c.headerPanelBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _guard.run(widget.onTap),
                  child: Center(
                    child: Icon(widget.icon,
                        size: AppIconSize.regular, color: c.headerText),
                  ),
                ),
              ),
            ),
            if (widget.showDot)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  key: const ValueKey('notify-dot'),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.notifyDot,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.headerSolid, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 40px circle, header-glass fill and border, bold initial 16/700.
class HeaderAvatar extends StatelessWidget {
  const HeaderAvatar({super.key, required this.initial, required this.onTap});

  final String initial;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Profile',
      child: Material(
        color: c.headerPanelFill,
        shape: CircleBorder(side: BorderSide(color: c.headerPanelBorder)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Text(
                initial,
                style: AppTypography.button(c.headerText)
                    .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The compact wallet panel inside the Home header: label + balance on the
/// left, a **Top up** pill on the right. Header-glass fill and border, radius
/// 20, padding 10/12/10/16. No blur (it sits on a flat gradient).
class HeaderWalletPanel extends StatefulWidget {
  const HeaderWalletPanel({
    super.key,
    required this.label,
    required this.balance,
    required this.onTopUp,
  });

  /// The existing label text (e.g. WALLET BALANCE).
  final String label;

  /// `null` while loading or on error: shown as `₦--`, as before.
  final double? balance;
  final VoidCallback onTopUp;

  @override
  State<HeaderWalletPanel> createState() => _HeaderWalletPanelState();
}

class _HeaderWalletPanelState extends State<HeaderWalletPanel> {
  final _guard = TapGuard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      key: const ValueKey('header-wallet-panel'),
      decoration: BoxDecoration(
        color: c.headerPanelFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.headerPanelBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.sectionLabel(c).copyWith(
                      fontSize: 11.5,
                      color: c.headerTextSecondary,
                      letterSpacing: 11.5 * 0.06,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.balance != null
                        ? Money.format(widget.balance!)
                        : '${Money.symbol}--',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.tabular(
                      AppTypography.greetingName(c.headerText)
                          .copyWith(fontSize: 24, height: 1.15),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Material(
              color: c.topUpFill,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _guard.run(widget.onTopUp),
                child: SizedBox(
                  height: 40,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.add, size: 18, color: c.topUpLabel),
                        const SizedBox(width: 4),
                        Text(
                          'Top up',
                          style: AppTypography.buttonSmall(c.topUpLabel)
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
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
