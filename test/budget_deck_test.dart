import 'package:espere_app/services/budget_service.dart';
import 'package:espere_app/widgets/budget_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a short drag springs back, a long one moves to the next budget', (t) async {
    final items = [
      for (final n in ['Food', 'Fun', 'Fuel'])
        BudgetInfo(categoryId: n.length, name: n, limit: 1000, spent: 500),
    ];
    var index = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => Padding(
            padding: const EdgeInsets.all(20),
            child: BudgetDeck(
              items: items,
              index: index,
              onIndex: (i) => set(() => index = i),
              month: DateTime.now(),
              symbol: '₹',
              onOpen: (_) {},
              onEdit: (_) {},
              onDelete: (_) {},
            ),
          ),
        ),
      ),
    ));
    // Let the one-time swipe hint play first.
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();

    await t.dragFrom(t.getTopLeft(find.byType(BudgetDeck)) + const Offset(200, 120), const Offset(-40, 0));
    await t.pumpAndSettle();
    expect(index, 0);

    await t.dragFrom(t.getTopLeft(find.byType(BudgetDeck)) + const Offset(200, 120), const Offset(-320, 0));
    await t.pumpAndSettle();
    expect(index, 1);

    await t.dragFrom(t.getTopLeft(find.byType(BudgetDeck)) + const Offset(200, 120), const Offset(320, 0));
    await t.pumpAndSettle();
    expect(index, 0);
  });
}
