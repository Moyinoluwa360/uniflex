/// A row from the `wallet_transactions` table.
///
/// All transaction rows are written by SECURITY DEFINER Postgres RPCs —
/// the client only ever reads them. [type] tells you the direction:
/// [WalletTxType.credit] for money coming in, [WalletTxType.debit] for
/// money going out.
class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.source,
    required this.balanceAfter,
    required this.createdAt,
    this.orderId,
    this.reference,
  });

  factory WalletTransaction.fromMap(Map<String, dynamic> map) {
    return WalletTransaction(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      type: WalletTxType.fromString(map['type'] as String),
      amount: (map['amount'] as num).toDouble(),
      source: WalletTxSource.fromString(map['source'] as String),
      balanceAfter: (map['balance_after'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      orderId: map['order_id'] as String?,
      reference: map['reference'] as String?,
    );
  }

  final String id;
  final String userId;
  final WalletTxType type;
  final double amount;
  final WalletTxSource source;
  final double balanceAfter;
  final DateTime createdAt;
  final String? orderId;
  final String? reference;

  /// Display label shown in the transaction history list.
  String get label => switch (source) {
        WalletTxSource.topup => 'Wallet Top-up',
        WalletTxSource.orderPayment => 'Order Payment',
        WalletTxSource.refund => 'Refund',
      };

  /// Positive for credits, negative for debits — useful for display.
  double get signedAmount =>
      type == WalletTxType.credit ? amount : -amount;
}

enum WalletTxType {
  credit,
  debit;

  static WalletTxType fromString(String s) =>
      s == 'credit' ? credit : debit;
}

enum WalletTxSource {
  topup,
  orderPayment,
  refund;

  static WalletTxSource fromString(String s) => switch (s) {
        'topup' => topup,
        'refund' => refund,
        _ => orderPayment,
      };
}
