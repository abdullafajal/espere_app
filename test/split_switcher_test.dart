import 'package:espere_app/services/app_navigation.dart';
import 'package:espere_app/widgets/split_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pill springs to Friends, then the tab switches and the pill resets', (t) async {
    AppNavigation.requestedTab.value = null;
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: SplitSwitcher(current: 'groups'))));
    final pill = find.byType(Positioned);
    final startLeft = t.getTopLeft(pill).dx;

    await t.tap(find.text('Friends'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    // Moving, tab not switched yet.
    expect(t.getTopLeft(pill).dx, greaterThan(startLeft));
    expect(AppNavigation.requestedTab.value, isNull);

    await t.pumpAndSettle();
    expect(AppNavigation.requestedTab.value, SplitSwitcher.friendsTab);
    // Back on Groups for when this screen shows again.
    expect(t.getTopLeft(pill).dx, closeTo(startLeft, 0.5));
  });
}
