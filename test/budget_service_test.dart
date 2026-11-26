import 'dart:convert';

import 'package:espere_app/services/budget_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.now();
  final month = BudgetService.monthKey(now);

  Map<String, dynamic> txn(int id, String amount, int catId, DateTime at) => {
        'id': id,
        'amount': amount,
        'type': 'expense',
        'category': {'id': catId, 'name': 'Food', 'icon': 'restaurant'},
        'date': at.toUtc().toIso8601String(),
      };

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'cache_transactions': jsonEncode({
        'transactions': [
          txn(1, '500', 1, now),
          txn(2, '1100', 1, now),
          txn(3, '300', 2, now),
          txn(4, '900', 1, DateTime(now.year, now.month - 1, 10)),
        ],
      }),
      'cache_budgets': jsonEncode({
        'budgets': [
          {'id': 9, 'category': {'id': 1, 'name': 'Food', 'icon': 'restaurant'}, 'amount': '2000', 'month': '$month-01'},
        ],
        'overall': {'amount': '10000.00'},
        'currency_symbol': '₹',
      }),
    });
  });

  test('category spending is counted from this month on the phone', () async {
    final b = (await BudgetService.byCategory())[1]!;
    expect(b.spent, 1600);
    expect(b.left, 400);
    expect(b.percent, 80);
    final o = await BudgetService.overall();
    expect(o.limit, 10000);
    expect(o.spent, 1900);
  });

  test('suggested amounts round to friendly steps', () {
    expect(BudgetService.suggestedChoices(6200), [5500, 6000, 6500]);
    expect(BudgetService.suggestedChoices(840), [700, 800, 900]);
    expect(BudgetService.suggestedChoices(0), isEmpty);
  });

  test('crossing 80% alerts once a month', () async {
    final first = await BudgetService.checkAfterSave(categoryId: 1);
    expect(first, 'Food budget 80% used');
    final again = await BudgetService.checkAfterSave(categoryId: 1);
    expect(again, isNull);
  });
}
