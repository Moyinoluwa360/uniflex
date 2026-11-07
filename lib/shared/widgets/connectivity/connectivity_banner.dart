import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/connectivity/connectivity_service.dart';

/// Riverpod provider that re-emits the connectivity stream.
final connectivityProvider = StreamProvider<bool>((ref) {
  return ConnectivityService.instance.onlineStream;
});

/// Wraps [child] in a [Stack] and overlays a slim banner at the top:
///
/// * **Offline** → red banner "No internet connection" + × dismiss button.
/// * **Back online** → green banner "Back online" that auto-hides after 3 s.
///
/// The banner sits below the status bar (safe area), never blocks taps on the
/// content below it, and re-appears on the next connectivity change.
class ConnectivityBanner extends ConsumerStatefulWidget {
  const ConnectivityBanner({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends ConsumerState<ConnectivityBanner> {
  /// null  = no banner
  /// true  = online (green, auto-hide)
  /// false = offline (red, dismissible)
  bool? _bannerOnline;
  bool _dismissed = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    // Seed from the current synchronous value so the banner is correct
    // even before the first stream event.
    final seeded = ConnectivityService.instance.isOnline;
    if (!seeded) {
      _bannerOnline = false;
      _dismissed = false;
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onConnectivityChanged(bool isOnline) {
    _hideTimer?.cancel();
    setState(() {
      _bannerOnline = isOnline;
      _dismissed = false;
    });

    if (isOnline) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _bannerOnline = null);
      });
    }
  }

  void _dismiss() {
    setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    // Listen to changes (errors/loading are silent — keep last state).
    ref.listen<AsyncValue<bool>>(connectivityProvider, (_, next) {
      next.whenData(_onConnectivityChanged);
    });

    final showBanner = _bannerOnline != null && !_dismissed;

    return Stack(
      children: [
        widget.child,
        if (showBanner)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: _BannerStrip(
                isOnline: _bannerOnline!,
                onDismiss: _bannerOnline! ? null : _dismiss,
              ),
            ),
          ),
      ],
    );
  }
}

class _BannerStrip extends StatelessWidget {
  const _BannerStrip({required this.isOnline, this.onDismiss});

  final bool isOnline;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final label = isOnline ? 'Back online' : 'No internet connection';
    final icon = isOnline ? Icons.wifi : Icons.wifi_off;

    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onDismiss != null)
              GestureDetector(
                onTap: onDismiss,
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}
