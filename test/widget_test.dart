// Widget tests. (Replaces the unused Flutter "counter" template, which tested a
// screen this app does not have and could never pass.)

import 'package:espere_app/models/category.dart';
import 'package:espere_app/models/transaction.dart';
import 'package:espere_app/widgets/transaction_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionModel _txn(String notes) => TransactionModel(
      id: 1,
      amount: '250.00',
      type: 'expense',
      category: CategoryModel(id: 3, name: 'Food', icon: 'restaurant', color: '#C8E64A'),
      date: DateTime(2026, 11, 16, 12, 30),
      paymentMethod: 'upi',
      paymentMethodDisplay: 'UPI / Mobile Payment',
      notes: notes,
    );

Future<void> _pump(WidgetTester tester, TransactionModel t) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TransactionTile(transaction: t))),
    );

void main() {
  testWidgets('an auto-tracked entry looks exactly like a manual one (no badge)', (tester) async {
    // Auto entries carry only the payee as their note, like a quick manual entry.
    await _pump(tester, _txn('Swiggy'));
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Swiggy'), findsOneWidget);
    expect(find.text('Auto'), findsNothing);
  });

  testWidgets('a manual entry shows its note', (tester) async {
    await _pump(tester, _txn('Lunch with team'));
    expect(find.text('Lunch with team'), findsOneWidget);
  });
}
