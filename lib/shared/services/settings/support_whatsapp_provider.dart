import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase/supabase_providers.dart';

/// The support WhatsApp number as international digits (e.g.
/// `2348031234567`), or null when Admin has not set one. Read through
/// `get_support_whatsapp()`; Admin edits it under Manage → Support settings.
final supportWhatsappProvider =
    FutureProvider.autoDispose<String?>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final result = await client.rpc('get_support_whatsapp');
  final text = (result as String?)?.trim();
  return (text == null || text.isEmpty) ? null : text;
});
