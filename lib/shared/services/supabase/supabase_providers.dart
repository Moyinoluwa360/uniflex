import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The single [SupabaseClient] instance the whole app shares. Requires
/// `Supabase.initialize` to have already run in `main()` before
/// `runApp` — see main.dart.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
