import 'package:espere_app/services/app_navigation.dart';
import 'package:espere_app/widgets/split_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tap switches the tab at once; the pill keeps moving and bounces on the new screen', (t) async {
    AppNavigation.requestedTab.value = null;
    // Both screens' switches are on stage here, like the home shell's two Split tabs.
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          SplitPillDriver(),
          SplitSwitcher(key: Key('groups'), current: 'groups'),
          SplitSwitcher(key: Key('friends'), current: 'friends'),
        ]),
      ),
    ));
    // Like the nav bar, the pill widens the side it is on: read the Friends side's width.
    Finder friendsSide(String screen) =>
        find.descendant(of: find.byKey(Key(screen)), matching: find.byType(Expanded)).at(1);
    final narrow = t.getSize(friendsSide('groups')).width; // pill on Groups
    final wide = t.getSize(friendsSide('friends')).width; // pill on Friends
    expect(wide, greaterThan(narrow + 10));

    await t.tap(find.descendant(of: find.byKey(const Key('groups')), matching: find.text('Friends')));
    expect(AppNavigation.requestedTab.value, SplitSwitcher.friendsTab); // switched at once
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
    final mid = t.getSize(friendsSide('friends')).width;
    expect(mid, greaterThan(narrow));
    expect(mid, lessThan(wide)); // the new screen shows the pill still on its way

    var maxP = 0.0;
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 16));
      final p = SplitPill.position.value;
      if (p != null && p > maxP) maxP = p;
    }
    expect(maxP, greaterThan(1.0)); // overshoot (the bounce)
    await t.pumpAndSettle();
    expect(t.getSize(friendsSide('friends')).width, closeTo(wide, 0.5));
    expect(SplitPill.position.value, isNull); // at rest
  });
}
