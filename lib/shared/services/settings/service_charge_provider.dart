import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase/supabase_providers.dart';

/// The current service charge (₦), read from the server's `app_settings`
/// via `get_service_charge()`. Shared because the student's payment page
/// DISPLAYS it and the Admin "Service charge" screen EDITS it. The server
/// always charges whatever the setting is at the moment of payment and
/// returns the amount actually charged — a displayed value never decides
/// a price.
final serviceChargeProvider = FutureProvider<double>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final result = await client.rpc('get_service_charge');
  return (result as num).toDouble();
});
