import 'package:url_launcher/url_launcher.dart';

/// Public pages on the Uniflex website (repo `uniflex-website`). The same
/// URLs go into App Store Connect and Play Console (docs/store-requirements.md).
abstract final class LegalLinks {
  static const String website = 'https://uniflex.live';
  static const String privacyPolicy = 'https://uniflex.live/privacy';
  static const String terms = 'https://uniflex.live/terms';

  /// Google Play's "delete your account without the app" page.
  static const String deleteAccount = 'https://uniflex.live/delete-account';

  /// Support page (contact details) for the stores' "Support URL".
  static const String support = 'https://uniflex.live/#contact';

  /// Opens [url] in the browser. Returns false if nothing could open it.
  static Future<bool> open(String url) async {
    try {
      return await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
