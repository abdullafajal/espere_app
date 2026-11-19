import 'package:espere_app/widgets/spring_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping a tab springs the pill there with an overshoot', (t) async {
    late TabController tc;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DefaultTabController(
          length: 3,
          child: Builder(builder: (context) {
            tc = DefaultTabController.of(context);
            return Column(children: [
              SpringTabs(controller: tc, labels: const ['Expenses', 'Balances', 'Settle Up']),
              const Expanded(child: TabBarView(children: [Text('a'), Text('b'), Text('c')])),
            ]);
          }),
        ),
      ),
    ));
    final pill = find.descendant(of: find.byType(SpringTabs), matching: find.byType(Positioned));
    final w = t.getSize(pill).width;
    final x0 = t.getTopLeft(pill).dx;

    await t.tap(find.text('Balances'));
    var maxX = x0;
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 16));
      final x = t.getTopLeft(pill).dx;
      if (x > maxX) maxX = x;
    }
    expect(maxX, greaterThan(x0 + w + 1)); // went past Balances: the bounce
    await t.pumpAndSettle();
    expect(t.getTopLeft(pill).dx, closeTo(x0 + w, 0.5));
    expect(tc.index, 1);

    // Swiping the pages moves the pill with them.
    await t.fling(find.text('b'), const Offset(-300, 0), 1000);
    await t.pumpAndSettle();
    expect(tc.index, 2);
    expect(t.getTopLeft(pill).dx, closeTo(x0 + 2 * w, 0.5));
  });
}
