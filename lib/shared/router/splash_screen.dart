import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Full-screen branded splash, per the Design Board's "01 — Splash, brand
/// gradient, wordmark only": layered brand gradient (emerald range melting
/// into a warm orange hint at the far corner) with a soft top highlight,
/// and a single centered white wordmark. Fade + scale entrance, no buttons
/// or text. [AuthGate] shows this while it resolves whether there's a
/// valid session, then swaps it out — this widget itself does no auth
/// logic and does not navigate anywhere.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            // 155deg on the board ≈ top-left → bottom-right diagonal.
            begin: Alignment(-0.4, -1.0),
            end: Alignment(0.9, 1.0),
            stops: [0.0, 0.34, 0.62, 1.0],
            colors: [
              AppColors.splashGradientTop,
              AppColors.emerald,
              AppColors.splashGradientMid,
              AppColors.orange,
            ],
          ),
        ),
        child: Stack(
          children: [
            // Soft top highlight, per the board's radial white overlay.
            Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.2, -0.9),
                  radius: 1.1,
                  stops: [0.0, 0.55],
                  colors: [
                    Color.fromRGBO(255, 255, 255, 0.34),
                    Color.fromRGBO(255, 255, 255, 0.0),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: FadeTransition(
                  opacity: _opacity,
                  child: ScaleTransition(
                    scale: _scale,
                    child: Text(
                      'Uniflex',
                      style: AppTypography.wordmark(
                        fontSize: 52,
                        color: AppColors.pureWhite,
                      ).copyWith(
                        shadows: const [
                          Shadow(
                            offset: Offset(0, 2),
                            blurRadius: 24,
                            color: Color.fromRGBO(6, 46, 35, 0.18),
                          ),
                        ],
                      ),
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
