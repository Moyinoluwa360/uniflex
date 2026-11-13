// Pack 2 / S-15 — every wallet_transactions.source has its own label, and
// the spending budget still counts exactly the order / fee / gift debits.
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/models/wallet_transaction.dart';

void main() {
  test('server sources map to their own label', () {
    const expected = {
      'topup': 'Wallet Top-up',
      'order_payment': 'Order Payment',
      'group_order_payment': 'Order Payment',
      'commitment_fee': 'Delivery Fee',
      'gift_payment': 'Gift Payment',
      'refund': 'Refund',
      'referral_bonus': 'Referral Bonus',
      'birthday_reward': 'Birthday Reward',
      'adjustment': 'Balance Adjustment',
      'account_deleted': 'Balance Forfeited',
    };
    expected.forEach((raw, label) {
      final tx = WalletTransaction.fromMap({
        'id': 't', 'user_id': 'u', 'type': 'credit', 'amount': 100,
        'source': raw, 'balance_after': 100,
        'created_at': '2026-11-13T00:00:00Z',
      });
      expect(tx.label, label, reason: raw);
    });
  });

  test('spending budget counts the same debits as before', () {
    for (final raw in ['order_payment', 'group_order_payment', 'commitment_fee', 'gift_payment']) {
      expect(WalletTxSource.fromString(raw).isSpending, isTrue, reason: raw);
    }
    for (final raw in ['topup', 'refund', 'referral_bonus', 'birthday_reward', 'adjustment', 'account_deleted']) {
      expect(WalletTxSource.fromString(raw).isSpending, isFalse, reason: raw);
    }
  });
}
