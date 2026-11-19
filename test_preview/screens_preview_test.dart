import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:espere_app/theme/app_theme.dart';

import 'package:espere_app/screens/dashboard_screen.dart';
import 'package:espere_app/screens/quick_add_screen.dart';
import 'package:espere_app/screens/transaction_list_screen.dart';
import 'package:espere_app/services/receipt_service.dart';
import 'package:espere_app/screens/budgets_screen.dart';
import 'package:espere_app/screens/reports_screen.dart';
import 'package:espere_app/screens/categories_screen.dart';
import 'package:espere_app/screens/split_groups_screen.dart';
import 'package:espere_app/screens/split_group_detail_screen.dart';
import 'package:espere_app/screens/friends_screen.dart';

import 'preview_harness.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
    silencePlugins();
  });

  testWidgets('home', (t) => shot(t, 'home', const DashboardScreen()));
  testWidgets('home_sky', (t) async {
    AppAccent.debugIndex = 2;
    try {
      await shot(t, 'home_sky', const DashboardScreen());
    } finally {
      AppAccent.debugIndex = 0;
    }
  });
  testWidgets('home_long', (t) => shot(t, 'home_long', const DashboardScreen(), size: const Size(390, 2400)));
  testWidgets('quick_add', (t) => shot(t, 'quick_add', const QuickAddScreen(), scaffold: false));
  testWidgets('activity', (t) => shot(t, 'activity', const TransactionListScreen()));
  testWidgets('form_new', (t) => shot(t, 'form_new', const QuickAddScreen(prefill: TransactionPrefill(amount: 249, notes: 'Swiggy')), scaffold: false));
  testWidgets('form_edit', (t) => shot(t, 'form_edit', const QuickAddScreen(editId: 101), scaffold: false));
  testWidgets('budgets', (t) => shot(t, 'budgets', const BudgetsScreen()));
  testWidgets('reports', (t) => shot(t, 'reports', const ReportsScreen(), scaffold: false, size: const Size(390, 1800)));
  testWidgets('categories', (t) => shot(t, 'categories', const CategoriesScreen(), scaffold: false));
  testWidgets('split', (t) => shot(t, 'split', SplitGroupsScreen(onBack: () {}), scaffold: false));
  testWidgets('group_detail', (t) => shot(t, 'group_detail', const SplitGroupDetailScreen(groupId: 1, groupName: 'Goa Trip'), scaffold: false));
  testWidgets('friends', (t) => shot(t, 'friends', FriendsScreen(onBack: () {}), scaffold: false));
  testWidgets('group_balances', (t) => shot(t, 'group_balances', const SplitGroupDetailScreen(groupId: 1, groupName: 'Goa Trip'),
      scaffold: false, act: (t) => t.tap(find.text('Balances'))));
  testWidgets('group_settle', (t) => shot(t, 'group_settle', const SplitGroupDetailScreen(groupId: 1, groupName: 'Goa Trip'),
      scaffold: false, act: (t) => t.tap(find.text('Settle Up').last)));
  testWidgets('sheet_group_expense', (t) => shot(t, 'sheet_group_expense', const SplitGroupDetailScreen(groupId: 1, groupName: 'Goa Trip'),
      scaffold: false, act: (t) => t.tap(find.text('Add Expense'))));
  testWidgets('sheet_new_group', (t) => shot(t, 'sheet_new_group', SplitGroupsScreen(onBack: () {}),
      scaffold: false, act: (t) => t.tap(find.byTooltip('New group'))));
  testWidgets('sheet_budget', (t) => shot(t, 'sheet_budget', const BudgetsScreen(),
      act: (t) => t.tap(find.byTooltip('New budget'))));
}
