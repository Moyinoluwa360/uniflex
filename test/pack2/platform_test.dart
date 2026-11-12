// Pack 2 — platform configuration and app-hardening guards (no device).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/theme/app_theme.dart';
import 'package:uniflex/shared/widgets/inputs/app_text_field.dart';
import 'package:uniflex/student/wallet/paystack_checkout_native.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  group('Android', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    test('no location, storage or photo permission is requested', () {
      for (final p in [
        'ACCESS_FINE_LOCATION',
        'ACCESS_COARSE_LOCATION',
        'ACCESS_BACKGROUND_LOCATION',
        'READ_MEDIA_IMAGES',
        'READ_EXTERNAL_STORAGE',
        'READ_CONTACTS',
        'SCHEDULE_EXACT_ALARM',
        'USE_EXACT_ALARM',
        'NEARBY_WIFI_DEVICES',
        'RECORD_AUDIO',
      ]) {
        expect(manifest.contains('android.permission.$p'), isFalse, reason: p);
      }
    });
    test('backups are off and no cleartext traffic is allowed', () {
      expect(manifest.contains('android:allowBackup="false"'), isTrue);
      expect(manifest.contains('@xml/data_extraction_rules'), isTrue);
      expect(
          File('android/app/src/main/res/xml/data_extraction_rules.xml')
              .existsSync(),
          isTrue);
      expect(manifest.contains('usesCleartextTraffic="true"'), isFalse);
    });
  });

  group('iOS', () {
    final plist = _read('ios/Runner/Info.plist');
    test('no location / tracking / contacts / microphone purpose strings', () {
      for (final k in [
        'NSLocationWhenInUseUsageDescription',
        'NSLocationAlwaysUsageDescription',
        'NSLocationAlwaysAndWhenInUseUsageDescription',
        'NSUserTrackingUsageDescription',
        'NSContactsUsageDescription',
        'NSMicrophoneUsageDescription',
        'NSBluetoothAlwaysUsageDescription',
        'NSPhotoLibraryAddUsageDescription',
      ]) {
        expect(plist.contains(k), isFalse, reason: k);
      }
    });
    test('export compliance answered; no arbitrary loads', () {
      expect(
          RegExp(r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>')
              .hasMatch(plist),
          isTrue);
      expect(plist.contains('NSAllowsArbitraryLoads'), isFalse);
    });
    test('privacy manifest exists and is bundled (Resources build phase)', () {
      final manifest = _read('ios/Runner/PrivacyInfo.xcprivacy');
      expect(manifest.contains('<key>NSPrivacyTracking</key>\n\t<false/>'),
          isTrue);
      final pbx = _read('ios/Runner.xcodeproj/project.pbxproj');
      expect(
          RegExp(r'PrivacyInfo\.xcprivacy in Resources').allMatches(pbx).length,
          2);
    });
  });

  test('no location plugin is a dependency', () {
    final pubspec = _read('pubspec.yaml');
    expect(pubspec.contains('geolocator'), isFalse);
    expect(pubspec.contains('location:'), isFalse);
    expect(pubspec.contains('permission_handler'), isFalse);
  });

  test('release builds print nothing to the device log', () {
    final main = _read('lib/main.dart');
    expect(main.contains('if (kReleaseMode) debugPrint ='), isTrue);
  });

  group('Paystack WebView', () {
    test('only https pages (and the inline page) may load', () {
      expect(isAllowedCheckoutUrl('about:blank'), isTrue);
      expect(isAllowedCheckoutUrl('https://checkout.paystack.com/x'), isTrue);
      expect(isAllowedCheckoutUrl('https://bank.example/3ds'), isTrue);
      expect(isAllowedCheckoutUrl('http://evil.example'), isFalse);
      expect(isAllowedCheckoutUrl('javascript:alert(1)'), isFalse);
      expect(isAllowedCheckoutUrl('file:///etc/passwd'), isFalse);
      expect(isAllowedCheckoutUrl('intent://x'), isFalse);
    });
    test('values are escaped for an inline script', () {
      final out = escapeJsLiteral("a'b\\c</script>\nx");
      expect(out.contains("'"), isTrue); // only as \'
      expect(out.contains(r"\'"), isTrue);
      expect(out.contains('</script>'), isFalse);
      expect(out.contains('\n'), isFalse);
    });
  });

  testWidgets('obscured fields (PIN / password) turn keyboard learning off',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: Column(children: [
          AppTextField(obscureText: true),
          AppTextField(),
        ]),
      ),
    ));
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].enableSuggestions, isFalse);
    expect(fields[0].autocorrect, isFalse);
    expect(fields[0].enableIMEPersonalizedLearning, isFalse);
    expect(fields[1].enableSuggestions, isTrue);
  });
}
