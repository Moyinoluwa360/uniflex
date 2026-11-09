import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Membership tier colours (UI Polish 1). The Profile header takes the tier's
/// colour as a soft metallic wash — never a loud solid card.
///
/// The pack specified Bronze, Silver and Platinum. The app also has **Gold**
/// (`Profile.membershipTier` is 'Bronze' | 'Silver' | 'Gold' | 'Platinum'), so
/// Gold is added in the same pattern (values are mine — see the report).
///
/// An unknown or missing tier returns `null`: the header falls back to a plain
/// surface with no tint.
@immutable
class TierStyle {
  const TierStyle({
    required this.washStart,
    required this.washMid,
    required this.washEnd,
    required this.border,
    required this.ring,
    required this.text,
  });

  /// Gradient colours, 150°. Dark: start → mid → transparent. Light:
  /// start → mid → white.
  final Color washStart;
  final Color washMid;
  final Color washEnd;
  final Color border;
  final Color ring;
  final Color text;

  /// The wash gradient: tier colour fading out by ~58% of the card.
  LinearGradient get gradient => AppColors.cssLinear(
        150,
        [washStart, washMid, washEnd],
        const [0, 0.58, 1],
      );
}

abstract final class TierTokens {
  /// 1px inner top highlight for tier/header cards: white 14% in dark,
  /// white 85% in light.
  static Color highlight(Brightness b) => b == Brightness.dark
      ? const Color(0x24FFFFFF)
      : const Color(0xD9FFFFFF);

  /// Tier names the app knows, in ladder order.
  static const List<String> known = ['Bronze', 'Silver', 'Gold', 'Platinum'];

  /// Style for [tier] in the given brightness, or `null` for an unknown or
  /// missing tier. Case-insensitive.
  static TierStyle? of(String? tier, Brightness brightness) {
    final key = (tier ?? '').trim().toLowerCase();
    final dark = brightness == Brightness.dark;
    return switch (key) {
      'bronze' => dark ? _bronzeDark : _bronzeLight,
      'silver' => dark ? _silverDark : _silverLight,
      'gold' => dark ? _goldDark : _goldLight,
      'platinum' => dark ? _platinumDark : _platinumLight,
      _ => null,
    };
  }

  // Bronze
  static const _bronzeDark = TierStyle(
    washStart: Color(0x52CD7F32), // .32
    washMid: Color(0x17CD7F32), // .09
    washEnd: Color(0x00CD7F32),
    border: Color(0x66CD7F32), // .40
    ring: Color(0xFFCD8B4B),
    text: Color(0xFFE6B07A),
  );
  static const _bronzeLight = TierStyle(
    washStart: Color(0xFFF3D9BF),
    washMid: Color(0xFFFAEBDD),
    washEnd: Color(0xFFFFFFFF),
    border: Color(0x6BB87333), // .42
    ring: Color(0xFFB87333),
    text: Color(0xFF8A4F1D),
  );

  // Silver
  static const _silverDark = TierStyle(
    washStart: Color(0x47C4CCD4), // .28
    washMid: Color(0x14C4CCD4), // .08
    washEnd: Color(0x00C4CCD4),
    border: Color(0x57C4CCD4), // .34
    ring: Color(0xFFB7C0C9),
    text: Color(0xFFD3D9DF),
  );
  static const _silverLight = TierStyle(
    washStart: Color(0xFFDDE2E7),
    washMid: Color(0xFFEEF1F4),
    washEnd: Color(0xFFFFFFFF),
    border: Color(0x666B7783), // .40
    ring: Color(0xFF8D98A3),
    text: Color(0xFF46515C),
  );

  // Gold (added — not in the original spec)
  static const _goldDark = TierStyle(
    washStart: Color(0x52D4A432), // .32
    washMid: Color(0x17D4A432), // .09
    washEnd: Color(0x00D4A432),
    border: Color(0x66D4A432), // .40
    ring: Color(0xFFD4A432),
    text: Color(0xFFEBCB7C),
  );
  static const _goldLight = TierStyle(
    washStart: Color(0xFFF6E6B8),
    washMid: Color(0xFFFBF2D9),
    washEnd: Color(0xFFFFFFFF),
    border: Color(0x6BB88A14), // .42
    ring: Color(0xFFB88A14),
    text: Color(0xFF6E5005),
  );

  // Platinum
  static const _platinumDark = TierStyle(
    washStart: Color(0x5C8A94D6), // .36
    washMid: Color(0x1A8A94D6), // .10
    washEnd: Color(0x008A94D6),
    border: Color(0x6B96A0E2), // .42
    ring: Color(0xFF9AA3E6),
    text: Color(0xFFC3C9F5),
  );
  static const _platinumLight = TierStyle(
    washStart: Color(0xFFDDE0F7),
    washMid: Color(0xFFEDEFFB),
    washEnd: Color(0xFFFFFFFF),
    border: Color(0x6B636BBE), // .42
    ring: Color(0xFF7C86D6),
    text: Color(0xFF4348A0),
  );
}
