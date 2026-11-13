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
        WalletTxSource.commitmentFee => 'Delivery Fee',
        WalletTxSource.giftPayment => 'Gift Payment',
        WalletTxSource.refund => 'Refund',
        WalletTxSource.referralBonus => 'Referral Bonus',
        WalletTxSource.birthdayReward => 'Birthday Reward',
        WalletTxSource.adjustment => 'Balance Adjustment',
        WalletTxSource.accountDeleted => 'Balance Forfeited',
      };

  /// Positive for credits, negative for debits — useful for display.
  double get signedAmount => type == WalletTxType.credit ? amount : -amount;
}

enum WalletTxType {
  credit,
  debit;

  static WalletTxType fromString(String s) => s == 'credit' ? credit : debit;
}

/// `wallet_transactions.source` (Pack 2: every server value has its own
/// label; before, anything unknown — birthday rewards, referral bonuses,
/// delivery fees — was shown as "Order Payment", even money coming in).
enum WalletTxSource {
  topup,
  orderPayment,
  commitmentFee,
  giftPayment,
  refund,
  referralBonus,
  birthdayReward,
  adjustment,
  accountDeleted;

  static WalletTxSource fromString(String s) => switch (s) {
        'topup' => topup,
        'refund' => refund,
        'commitment_fee' => commitmentFee,
        'gift_payment' => giftPayment,
        'referral_bonus' => referralBonus,
        'birthday_reward' => birthdayReward,
        'adjustment' => adjustment,
        'account_deleted' => accountDeleted,
        // order_payment, group_order_payment and anything new.
        _ => orderPayment,
      };

  /// Money spent on orders — what the spending budget counts.
  bool get isSpending =>
      this == orderPayment || this == commitmentFee || this == giftPayment;
}
