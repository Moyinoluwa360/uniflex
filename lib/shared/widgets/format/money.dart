import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Naira formatting. **Formatting only — it never changes an amount.**
///
/// ```
/// Money.format(39210)      →  ₦39,210
/// Money.format(39210.5)    →  ₦39,210.50     (kobo shown only when present)
/// Money.hero(39210)        →  ₦39,210.00
/// Money.minus(2000)        →  −₦2,000        (real minus sign U+2212)
/// Money.plus(10000)        →  +₦10,000
/// Money.signed(-2000)      →  −₦2,000
/// ```
abstract final class Money {
  static const String symbol = '₦';
  static const String minusSign = '−';

  /// Rounds to kobo and splits into whole naira + kobo (both non-negative)
  /// plus the sign.
  static ({bool negative, int naira, int kobo}) _split(num amount) {
    final totalKobo = (amount.abs() * 100).round();
    return (
      negative: amount < 0 && totalKobo != 0,
      naira: totalKobo ~/ 100,
      kobo: totalKobo % 100,
    );
  }

  static String _commas(int n) {
    final s = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  /// `₦39,210` — with `.50` only when there are kobo. Negative amounts get a
  /// real minus sign.
  static String format(num amount) {
    final p = _split(amount);
    final kobo = p.kobo == 0 ? '' : '.${p.kobo.toString().padLeft(2, '0')}';
    return '${p.negative ? minusSign : ''}$symbol${_commas(p.naira)}$kobo';
  }

  /// `₦39,210.00` — always two decimals (balance hero).
  static String hero(num amount) {
    final p = heroParts(amount);
    return '${p.whole}${p.decimals}';
  }

  /// The hero split for rendering the decimals smaller: whole = `₦39,210`,
  /// decimals = `.00`.
  static ({String whole, String decimals}) heroParts(num amount) {
    final p = _split(amount);
    return (
      whole: '${p.negative ? minusSign : ''}$symbol${_commas(p.naira)}',
      decimals: '.${p.kobo.toString().padLeft(2, '0')}',
    );
  }

  /// `−₦2,000` for the magnitude of [amount] (money going out).
  static String minus(num amount) => '$minusSign${format(amount.abs())}';

  /// `+₦10,000` for the magnitude of [amount] (money coming in).
  static String plus(num amount) => '+${format(amount.abs())}';

  /// `+` / `−` chosen from the sign of [amount]; zero has no sign.
  static String signed(num amount) {
    if (_split(amount).naira == 0 && _split(amount).kobo == 0) return format(0);
    return amount < 0 ? minus(amount) : plus(amount);
  }
}

/// Where the money is going, which decides its colour: spending and plain
/// amounts are neutral (`textPrimary`), money in is `brandText`. Orange is
/// never used for amounts.
enum MoneyTone { neutral, positive }

/// A formatted amount in tabular figures.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.tone = MoneyTone.neutral,
    this.style,
    this.signed = false,
    this.textAlign,
  });

  final num amount;
  final MoneyTone tone;

  /// Base style (defaults to Body). Colour comes from [tone] unless the style
  /// already sets one.
  final TextStyle? style;

  /// Show `+`/`−` from the sign of [amount].
  final bool signed;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = style ?? AppTypography.body(c);
    final color = tone == MoneyTone.positive ? c.brandText : c.textPrimary;
    return Text(
      signed ? Money.signed(amount) : Money.format(amount),
      textAlign: textAlign,
      style: AppTypography.tabular(base.copyWith(color: style?.color ?? color)),
    );
  }
}

/// The big balance: `₦39,210` at 40/700 with `.00` at 22/600.
class MoneyHero extends StatelessWidget {
  const MoneyHero(this.amount, {super.key, this.color});

  final num amount;

  /// Text colour. Defaults to `textPrimary`; the wallet card passes white.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final parts = Money.heroParts(amount);
    final ink = color ?? c.textPrimary;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: parts.whole, style: AppTypography.balanceHero(ink)),
          TextSpan(
            text: parts.decimals,
            style: AppTypography.balanceDecimals(ink),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
