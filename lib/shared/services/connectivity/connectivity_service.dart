import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// A singleton connectivity service that combines the OS network-change
/// event from `connectivity_plus` with a real reachability probe.
///
/// Usage:
///   await ConnectivityService.instance.init();  // call once in main()
///   ConnectivityService.instance.isOnline       // synchronous current state
///   ConnectivityService.instance.onlineStream   // Stream<bool> for listeners
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final _controller = StreamController<bool>.broadcast();
  bool _isOnline = true;
  bool _initialized = false;

  bool get isOnline => _isOnline;

  /// Emits `true` when online, `false` when offline.
  Stream<bool> get onlineStream => _controller.stream;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Seed with an immediate reachability check.
    _isOnline = await _probe();

    // Listen to connectivity changes and re-probe on each change.
    Connectivity().onConnectivityChanged.listen((results) async {
      // `results` is List<ConnectivityResult> in connectivity_plus ≥ 5.
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);

      if (!hasNetwork) {
        _emit(false);
        return;
      }
      // Wi-Fi / mobile detected — confirm real reachability.
      final online = await _probe();
      _emit(online);
    });
  }

  void _emit(bool online) {
    if (online == _isOnline) return; // no change
    _isOnline = online;
    _controller.add(online);
  }

  /// Returns true when we can actually reach the internet.
  Future<bool> _probe() async {
    try {
      final result = await InternetAddress.lookup('supabase.co')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  void dispose() {
    _controller.close();
  }
}
