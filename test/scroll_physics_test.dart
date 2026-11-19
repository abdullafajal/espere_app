import 'package:espere_app/services/app_navigation.dart';
import 'package:espere_app/theme/motion.dart';
import 'package:espere_app/widgets/nav_space.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lists bounce back to their end and pull-to-refresh still works', (t) async {
    var refreshed = 0;
    final controller = ScrollController();
    await t.pumpWidget(MaterialApp(
      scrollBehavior: const EspereScrollBehavior(),
      home: Scaffold(
        body: RefreshIndicator(
          onRefresh: () async => refreshed++,
          child: ListView(
            controller: controller,
            children: [for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('row $i'))],
          ),
        ),
      ),
    ));

    // Fling hard to the end: it may go past, then must settle exactly on the end.
    await t.fling(find.byType(ListView), const Offset(0, -6000), 8000);
    await t.pumpAndSettle();
    expect(controller.offset, closeTo(controller.position.maxScrollExtent, 0.5));

    // Back to the top and pull down: refresh runs.
    controller.jumpTo(0);
    await t.pump();
    await t.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await t.pumpAndSettle();
    expect(refreshed, 1);
    expect(controller.offset, closeTo(0, 0.5));
  });

  testWidgets('space under a tab list follows the nav bar', (t) async {
    AppNavigation.navVisible.value = true;
    await t.pumpWidget(const MaterialApp(home: NavScope(child: Column(children: [NavBottomSpace()]))));
    expect(t.getSize(find.byType(AnimatedContainer)).height, 96);
    AppNavigation.navVisible.value = false;
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(AnimatedContainer)).height, 20);
    AppNavigation.navVisible.value = true;
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(AnimatedContainer)).height, 96);

    // Outside the tabs (pushed screens): just the margin.
    await t.pumpWidget(const MaterialApp(home: Column(children: [NavBottomSpace()])));
    expect(t.getSize(find.byType(SizedBox).last).height, 20);
  });
}
