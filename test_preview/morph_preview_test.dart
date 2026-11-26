// Edit animation: renders a transaction row mid-way through an edit (Chai ₹20 → Coffee ₹45).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:espere_app/models/transaction.dart';
import 'package:espere_app/theme/app_theme.dart';
import 'package:espere_app/widgets/transaction_tile.dart';
import 'package:espere_app/widgets/morph_text.dart';
import 'preview_harness.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
    silencePlugins();
  });
  testWidgets('morph', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390 * 2, 120 * 2);
    addTearDown(tester.view.reset);
    final d = DateTime(2026, 11, 22, 6, 56).toUtc().toIso8601String();
    final d2 = DateTime(2026, 11, 22, 8, 30).toUtc().toIso8601String();
    final a = TransactionModel.fromJson(txn(7, '20', 'expense', categories[0], 'Chai', d));
    final b = TransactionModel.fromJson(txn(7, '45', 'expense', categories[2], 'Coffee', d2));
    final n = ValueNotifier(a);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ValueListenableBuilder(valueListenable: n, builder: (_, t, __) => TransactionTile(transaction: t)),
        ),
      ),
    ));
    EditAnimation.arm();
    n.value = b;
    var prev = 0;
    for (final ms in [0, 250, 450, 700, 950, 1150, 1600]) {
      await tester.pump(Duration(milliseconds: ms - prev));
      prev = ms;
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/morph_$ms.png'));
    }
  });
}
