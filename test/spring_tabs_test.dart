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
    // Like the nav bar, the pill widens the tab it is on: read the slot widths.
    final slots = find.descendant(of: find.byType(SpringTabs), matching: find.byType(Expanded));
    double width(int i) => t.getSize(slots.at(i)).width;
    expect(width(0), greaterThan(width(1)));
    final rest2 = width(2);

    await t.tap(find.text('Balances'));
    var max2 = rest2;
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 16));
      if (width(2) > max2) max2 = width(2);
    }
    expect(max2, greaterThan(rest2 + 1)); // the pill went a little past Balances: the bounce
    await t.pumpAndSettle();
    expect(tc.index, 1);
    expect(width(1), greaterThan(width(0)));
    expect(width(1), greaterThan(width(2)));
    expect(width(2), closeTo(rest2, 0.5));

    // Swiping the pages moves the pill with them.
    await t.fling(find.text('b'), const Offset(-300, 0), 1000);
    await t.pumpAndSettle();
    expect(tc.index, 2);
    expect(width(2), greaterThan(width(1)));
  });
}
