import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/wallet_transaction.dart';

/// Service wrapping all Supabase calls for the student wallet.
///
/// Balance updates and transaction writes are done exclusively through
/// SECURITY DEFINER RPCs; this service only reads from the client side
/// and delegates writes to the appropriate RPC or Edge Function.
class WalletService {
  const WalletService(this._client);

  final SupabaseClient _client;

  /// Returns the wallet row (balance, virtual_account_number, tier) for
  /// the signed-in student via the `get_wallet_info` RPC.
  Future<Map<String, dynamic>?> getWalletInfo() async {
    final result = await _client.rpc('get_wallet_info');
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  /// Returns up to [limit] wallet transactions for the signed-in student,
  /// newest first.
  Future<List<WalletTransaction>> getTransactions({int limit = 50}) async {
    final data = await _client
        .from('wallet_transactions')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);

    return data
        .map((m) => WalletTransaction.fromMap(m))
        .toList();
  }

  /// Calls the `verify-paystack-payment` Edge Function with the given
  /// [reference]. Returns the updated wallet balance on success.
  ///
  /// Throws a [WalletException] if the Edge Function reports an error.
  Future<double> verifyPaystackPayment(String reference) async {
    final response = await _client.functions.invoke(
      'verify-paystack-payment',
      body: {'reference': reference},
    );

    final data = response.data as Map<String, dynamic>?;
    if (data == null) {
      throw const WalletException('Empty response from payment service');
    }

    // 409 duplicate reference is treated as success — the money was
    // already credited on a previous call.
    if (data.containsKey('error') && data['error'] != null) {
      throw WalletException(data['error'] as String);
    }

    return (data['balance'] as num).toDouble();
  }

  /// Calls the `create-virtual-account` Edge Function to attempt issuing
  /// a Paystack Dedicated Virtual Account. Always returns a result map
  /// (may be the placeholder VAN with `is_real_account: false` if
  /// Paystack business verification is not yet complete).
  Future<VirtualAccountResult> createVirtualAccount() async {
    final response = await _client.functions.invoke(
      'create-virtual-account',
      body: <String, dynamic>{},
    );

    final data = response.data as Map<String, dynamic>?;
    if (data == null) {
      return const VirtualAccountResult(
        accountNumber: '',
        bankName: 'Uniflex (Pending)',
        isRealAccount: false,
      );
    }

    return VirtualAccountResult(
      accountNumber: data['account_number'] as String? ?? '',
      bankName: data['bank_name'] as String? ?? 'Unknown',
      isRealAccount: data['is_real_account'] as bool? ?? false,
    );
  }
}

class WalletException implements Exception {
  const WalletException(this.message);
  final String message;
  @override
  String toString() => 'WalletException: $message';
}

/// Result of a Virtual Account creation attempt.
class VirtualAccountResult {
  const VirtualAccountResult({
    required this.accountNumber,
    required this.bankName,
    required this.isRealAccount,
  });

  final String accountNumber;
  final String bankName;

  /// `true` if this is a real Paystack NUBAN, `false` if it is the
  /// Phase 1 placeholder (UFX-...) pending Paystack business verification.
  final bool isRealAccount;
}
