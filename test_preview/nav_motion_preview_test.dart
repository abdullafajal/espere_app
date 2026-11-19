import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:espere_app/widgets/bottom_nav_bar.dart';
import 'preview_harness.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
    silencePlugins();
  });

  testWidgets('nav_motion', (t) async {
    t.view.devicePixelRatio = 2;
    t.view.physicalSize = const Size(780, 200);
    addTearDown(t.view.reset);
    final index = ValueNotifier(0);
    Widget bar() => ValueListenableBuilder<int>(
          valueListenable: index,
          builder: (_, i, __) => EspereBottomNav(currentIndex: i, onTap: (_) {}, onAdd: () {}),
        );
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F6F2),
        body: Column(children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: bar()),
        ]),
      ),
    ));
    index.value = 2; // Home -> Budgets
    await t.pump();
    await t.pump(const Duration(milliseconds: 70));
    expect(t.takeException(), isNull);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/nav_motion_mid.png'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
