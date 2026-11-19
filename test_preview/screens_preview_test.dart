import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:espere_app/screens/dashboard_screen.dart';
import 'package:espere_app/screens/quick_add_screen.dart';
import 'package:espere_app/screens/transaction_list_screen.dart';
import 'package:espere_app/screens/transaction_form_screen.dart';
import 'package:espere_app/screens/budgets_screen.dart';
import 'package:espere_app/screens/reports_screen.dart';
import 'package:espere_app/screens/categories_screen.dart';

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
  testWidgets('activity', (t) => shot(t, 'activity', const TransactionListScreen()));
  testWidgets('form_new', (t) => shot(t, 'form_new', const TransactionFormScreen(presetType: 'expense')));
  testWidgets('form_edit', (t) => shot(t, 'form_edit', const TransactionFormScreen(transactionId: 101)));
  testWidgets('budgets', (t) => shot(t, 'budgets', const BudgetsScreen()));
  testWidgets('reports', (t) => shot(t, 'reports', const ReportsScreen(), scaffold: false, size: const Size(390, 1800)));
  testWidgets('categories', (t) => shot(t, 'categories', const CategoriesScreen(), scaffold: false));
}
