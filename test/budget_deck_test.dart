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

  testWidgets('press and slide on the strip shows that day, and the card stays', (t) async {
    final now = DateTime.now();
    final items = [
      BudgetInfo(categoryId: 1, name: 'Food', limit: 1000, spent: 300, daily: {now.day: 300}),
      BudgetInfo(categoryId: 2, name: 'Fun', limit: 1000, spent: 0),
    ];
    var index = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: StatefulBuilder(
              builder: (context, set) => BudgetDeck(
                items: items,
                index: index,
                onIndex: (i) => set(() => index = i),
                month: now,
                symbol: '₹',
                onOpen: (_) {},
                onEdit: (_) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    final dayLine = find.textContaining(RegExp(r'^\w{3}, \d'));
    expect(dayLine, findsNothing);
    final g = await t.startGesture(t.getTopLeft(find.byType(BudgetDeck)) + const Offset(40, 170));
    await t.pump(const Duration(milliseconds: 700));
    await g.moveBy(const Offset(30, 0));
    await t.pump();
    expect(dayLine, findsOneWidget);
    await g.up();
    await t.pumpAndSettle();
    expect(dayLine, findsNothing);
    expect(index, 0);
  });
}
