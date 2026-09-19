import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/wallet_transaction.dart';
import '../supabase/supabase_providers.dart';
import 'wallet_service.dart';

// ---------------------------------------------------------------------------
// Service provider
// ---------------------------------------------------------------------------

final walletServiceProvider = Provider<WalletService>((ref) {
  return WalletService(ref.watch(supabaseClientProvider));
});

// ---------------------------------------------------------------------------
// Read providers
// ---------------------------------------------------------------------------

/// The signed-in student's wallet balance (₦), or null if not loaded.
/// Still used by the Home screen header and the Profile screen.
/// Refreshed by calling `ref.invalidate(walletBalanceProvider)`.
final walletBalanceProvider = FutureProvider<double?>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return null;

  final row = await client
      .from('wallets')
      .select('balance')
      .eq('user_id', user.id)
      .maybeSingle();

  if (row == null) return null;
  return (row['balance'] as num).toDouble();
});

/// Full wallet row: balance, virtual_account_number, tier.
/// Used by the Wallet screen — includes the VAN so we only need one call.
/// Refreshed by calling `ref.invalidate(walletInfoProvider)`.
final walletInfoProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final service = ref.watch(walletServiceProvider);
  return service.getWalletInfo();
});

/// Transaction history for the signed-in student, newest first.
/// Refreshed by calling `ref.invalidate(walletTransactionsProvider)`.
final walletTransactionsProvider =
    FutureProvider<List<WalletTransaction>>((ref) async {
  final service = ref.watch(walletServiceProvider);
  return service.getTransactions();
});
