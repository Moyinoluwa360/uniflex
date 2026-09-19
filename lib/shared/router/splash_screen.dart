import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/wordmark/uniflex_wordmark.dart';

/// Full-screen branded splash, per the design handoff's "Splash — brand
/// gradient, wordmark only" screen: a diagonal emerald gradient fills the
/// whole screen, with the white wordmark bottom-left rather than
/// centred. Fade + scale entrance, no buttons or text. [AuthGate] shows
/// this while it resolves whether there's a valid session, then swaps it
/// out — this widget itself does no auth logic and does not navigate
/// anywhere.
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
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.emerald, AppColors.darkEmerald],
          ),
        ),
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: FadeTransition(
                opacity: _opacity,
                child: ScaleTransition(
                  scale: _scale,
                  alignment: Alignment.bottomLeft,
                  child: const UniflexWordmark(
                    fontSize: 40,
                    color: AppColors.pureWhite,
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
