import 'package:flutter_test/flutter_test.dart';
import 'package:ganacsi_ai/models/models.dart';

void main() {
  test('Sale.due waa farqiga wadarta iyo lacagta la bixiyay', () {
    final s = Sale.fromJson({'id': 1, 'total': 30, 'paid': 10, 'payment_method': 'cash', 'created_at': '2026-10-22 10:00:00', 'items': []});
    expect(s.due, 20);
  });

  test('Product.isLow', () {
    final p = Product.fromJson({'id': 1, 'name': 'Bariis', 'price': 10, 'cost': 7, 'quantity': 3, 'low_stock_threshold': 5});
    expect(p.isLow, isTrue);
  });
}
