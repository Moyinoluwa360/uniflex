import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../widgets/format/money.dart';

/// Show / hide the wallet balance (Pack 1 / 1.3).
///
/// ONE in-memory flag shared by the Home wallet panel and the Wallet tab:
/// showing it on one shows it on the other. It is never persisted and never
/// sent anywhere. Hidden is the default on every cold start (a fresh process
/// starts at `false`) and after logout ([reset] runs when the student shell
/// is created and disposed, i.e. on every sign-in and sign-out).
abstract final class BalanceVisibility {
  static final ValueNotifier<bool> visible = ValueNotifier<bool>(false);

  static void toggle() => visible.value = !visible.value;

  static void reset() => visible.value = false;

  /// Naira sign + thin space (U+2009). The four bullets follow in
  /// [HiddenBalanceText].
  static const String prefix = '${Money.symbol}\u2009';

  /// Exactly four bullets (U+2022), whatever the amount.
  static const String dots = '\u2022\u2022\u2022\u2022';

  /// Plain text form, for tests and semantics checks: `₦ ••••`.
  static const String hiddenText = '$prefix$dots';

  /// Positive tracking so the bullets read as separate dots.
  static const double dotSpacing = 2;
}

/// The hidden amount: always `₦ ••••` (four dots, no decimals) in the SAME
/// style as the real amount, so the line keeps its height when toggling.
/// Screen readers hear "Balance hidden".
class HiddenBalanceText extends StatelessWidget {
  const HiddenBalanceText({super.key, required this.style});

  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Balance hidden',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: BalanceVisibility.prefix, style: style),
            TextSpan(
              text: BalanceVisibility.dots,
              style:
                  style.copyWith(letterSpacing: BalanceVisibility.dotSpacing),
            ),
          ],
        ),
        key: const ValueKey('balance-hidden'),
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}

/// The eye toggle: hidden shows `eye` (tap to show), visible shows `eyeOff`
/// (tap to hide). 32×32 visual inside a 44×44 hit area.
class BalanceEyeButton extends StatelessWidget {
  const BalanceEyeButton({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: BalanceVisibility.visible,
      builder: (context, visible, _) => Semantics(
        button: true,
        label: visible ? 'Hide balance' : 'Show balance',
        excludeSemantics: true,
        child: SizedBox(
          key: const ValueKey('balance-eye'),
          width: 44,
          height: 44,
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              highlightColor: context.colors.pressOverlay,
              onTap: BalanceVisibility.toggle,
              child: Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    visible ? AppIcons.eyeOff : AppIcons.eye,
                    size: 20,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
