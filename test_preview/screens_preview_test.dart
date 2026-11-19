import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:espere_app/theme/app_theme.dart';

import 'package:espere_app/screens/dashboard_screen.dart';
import 'package:espere_app/screens/notifications_screen.dart';
import 'package:espere_app/screens/group_invite_screen.dart';
import 'package:espere_app/widgets/bottom_nav_bar.dart';
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
  testWidgets('nav_small', (t) => shot(t, 'nav_small', MediaQuery(
        data: const MediaQueryData(size: Size(320, 200), textScaler: TextScaler.linear(1.3)),
        child: Column(children: [
          for (final i in [0, 2, 4])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: EspereBottomNav(currentIndex: i, onTap: (_) {}, onAdd: () {}),
            ),
        ]),
      ), size: const Size(320, 300)));
  testWidgets('notifications', (t) => shot(t, 'notifications', const NotificationsScreen(), scaffold: false));
  testWidgets('date_picker', (t) async {
    AppAccent.debugIndex = 4;
    try {
      await shot(t, 'date_picker', const QuickAddScreen(), scaffold: false, act: (t) async {
        await t.tap(find.text('Now'));
        for (var k = 0; k < 8; k++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      });
    } finally {
      AppAccent.debugIndex = 0;
    }
  });
  testWidgets('time_picker', (t) async {
    AppAccent.debugIndex = 4;
    try {
      await shot(t, 'time_picker', const QuickAddScreen(), scaffold: false, act: (t) async {
        await t.tap(find.text('Now'));
        for (var k = 0; k < 8; k++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.tap(find.text('OK'));
        for (var k = 0; k < 8; k++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      });
    } finally {
      AppAccent.debugIndex = 0;
    }
  });
  testWidgets('menu_open', (t) => shot(t, 'menu_open', const TransactionListScreen(), act: (t) async {
        await t.tap(find.byIcon(Icons.more_vert_rounded).first);
        await t.pumpAndSettle();
      }));
  testWidgets('notifications_delete', (t) => shot(t, 'notifications_delete', const NotificationsScreen(), scaffold: false,
          act: (t) async {
        await t.drag(find.text('Goa Trip: new expense'), const Offset(-300, 0));
        await t.pumpAndSettle();
      }));
  testWidgets('home_past_month', (t) => shot(t, 'home_past_month', const DashboardScreen(), act: (t) async {
        await t.tap(find.byIcon(Icons.expand_more_rounded).first);
        await t.pumpAndSettle();
        final last = DateTime(DateTime.now().year, DateTime.now().month - 1);
        await t.tap(find.text(last.year == DateTime.now().year
            ? DateFormat('MMMM').format(last)
            : DateFormat('MMM yyyy').format(last)));
        await t.pumpAndSettle();
      }));
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
  testWidgets('form_edit', (t) => shot(t, 'form_edit',
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844), padding: EdgeInsets.only(top: 40, bottom: 24)),
        child: const QuickAddScreen(editId: 101),
      ),
      scaffold: false));
  testWidgets('budgets', (t) => shot(t, 'budgets', const BudgetsScreen()));
  testWidgets('reports', (t) => shot(t, 'reports', const ReportsScreen(), scaffold: false, size: const Size(390, 1800)));
  testWidgets('categories', (t) => shot(t, 'categories', const CategoriesScreen(), scaffold: false));
  testWidgets('split', (t) => shot(t, 'split', SplitGroupsScreen(onBack: () {}), scaffold: false));
  testWidgets('group_detail', (t) => shot(t, 'group_detail', const SplitGroupDetailScreen(groupId: 1, groupName: 'Goa Trip'), scaffold: false));
  testWidgets('group_members', (t) => shot(t, 'group_members',
      const SplitGroupDetailScreen(groupId: 1, groupName: 'Goa Trip'), scaffold: false, size: const Size(390, 1200), act: (t) async {
        await t.tap(find.text('Members').first);
        await t.pump(const Duration(milliseconds: 900));
      }));
  testWidgets('group_balances', (t) => shot(t, 'group_balances',
      const SplitGroupDetailScreen(groupId: 1, groupName: 'Goa Trip'), scaffold: false, act: (t) async {
        await t.tap(find.text('Balances').first);
        await t.pump(const Duration(milliseconds: 900));
      }));
  testWidgets('group_invite', (t) => shot(t, 'group_invite',
      GroupInviteScreen(
        groupId: 1,
        groupName: 'Goa Trip',
        inviteToken: 'abc',
        myUsername: 'abdulla',
        members: List<Map<String, dynamic>>.from(groupDetail['members'] as List),
        pendingInvites: List<Map<String, dynamic>>.from(groupDetail['pending_invites'] as List),
      ),
      scaffold: false, size: const Size(390, 1000)));
  testWidgets('group_detail_scrolled', (t) => shot(t, 'group_detail_scrolled',
      const SplitGroupDetailScreen(groupId: 1, groupName: 'Goa Trip'), scaffold: false, act: (t) async {
        await t.drag(find.text('Activity').last, const Offset(0, -500));
        await t.pump(const Duration(milliseconds: 800));
      }));
  testWidgets('friends', (t) => shot(t, 'friends', FriendsScreen(onBack: () {}), scaffold: false));
  testWidgets('group_balances', (t) => shot(t, 'group_balances', const SplitGroupDetailScreen(groupId: 1, groupName: 'Goa Trip'),
      scaffold: false, act: (t) => t.tap(find.text('Balances'))));
  testWidgets('group_settle', (t) => shot(t, 'group_settle', const SplitGroupDetailScreen(groupId: 1, groupName: 'Goa Trip'),
      scaffold: false, act: (t) => t.tap(find.text('Settle up').first)));
  testWidgets('sheet_group_expense', (t) => shot(t, 'sheet_group_expense', const SplitGroupDetailScreen(groupId: 1, groupName: 'Goa Trip'),
      scaffold: false, act: (t) => t.tap(find.text('Add expense'))));
  testWidgets('sheet_new_group', (t) => shot(t, 'sheet_new_group', SplitGroupsScreen(onBack: () {}),
      scaffold: false, act: (t) => t.tap(find.byTooltip('New group'))));
  testWidgets('sheet_budget', (t) => shot(t, 'sheet_budget', const BudgetsScreen(),
      act: (t) => t.tap(find.byTooltip('New budget'))));
}
