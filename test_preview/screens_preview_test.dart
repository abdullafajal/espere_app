import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:espere_app/screens/dashboard_screen.dart';
import 'package:espere_app/screens/quick_add_screen.dart';

import 'preview_harness.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
    silencePlugins();
  });

  testWidgets('home', (t) => shot(t, 'home', const DashboardScreen()));
  testWidgets('home_long', (t) => shot(t, 'home_long', const DashboardScreen(), size: const Size(390, 2400)));
  testWidgets('quick_add', (t) => shot(t, 'quick_add', const QuickAddScreen(), scaffold: false));
}
