import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_typography.dart';
import 'tap_guard.dart';

/// The orange cart button with its count badge — one of the only two places
/// orange is allowed (ads and this). 60×60, radius 20, `promoOrangeButton`;
/// badge `promoOrangeBadge` with a 2px border in the page background colour.
class PromoCartButton extends StatefulWidget {
  const PromoCartButton({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  State<PromoCartButton> createState() => _PromoCartButtonState();
}

class _PromoCartButtonState extends State<PromoCartButton> {
  final _guard = TapGuard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Cart, ${widget.count} items',
      child: SizedBox(
        width: 60,
        height: 60,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Material(
                color: c.promoOrangeButton,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _guard.run(widget.onTap),
                  child: const Center(
                    child:
                        Icon(AppIcons.cart, size: 26, color: AppColors.onMedia),
                  ),
                ),
              ),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                key: const ValueKey('cart-badge'),
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.promoOrangeBadge,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: c.background, width: 2),
                ),
                child: Text(
                  '${widget.count}',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onMedia,
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
