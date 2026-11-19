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
    final groupsPill = find.descendant(of: find.byKey(const Key('groups')), matching: find.byType(Positioned));
    final friendsPill = find.descendant(of: find.byKey(const Key('friends')), matching: find.byType(Positioned));
    final left = t.getTopLeft(groupsPill).dx;
    final right = t.getTopLeft(friendsPill).dx;

    await t.tap(find.descendant(of: find.byKey(const Key('groups')), matching: find.text('Friends')));
    expect(AppNavigation.requestedTab.value, SplitSwitcher.friendsTab); // switched at once
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
    final mid = t.getTopLeft(friendsPill).dx;
    expect(mid, greaterThan(left));
    expect(mid, lessThan(right)); // the new screen shows the pill still on its way

    var maxX = mid;
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 16));
      final x = t.getTopLeft(friendsPill).dx;
      if (x > maxX) maxX = x;
    }
    expect(maxX, greaterThan(right + 1)); // overshoot (the bounce)
    await t.pumpAndSettle();
    expect(t.getTopLeft(friendsPill).dx, closeTo(right, 0.5));
    expect(SplitPill.position.value, isNull); // at rest
  });
}
