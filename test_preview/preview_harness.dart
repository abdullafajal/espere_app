/// Renders app screens with made-up data into PNG files, so the redesign can be checked
/// without a phone: `flutter test test_preview --update-goldens` writes
/// test_preview/goldens/*.png (git-ignored). Not part of the CI test run.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:espere_app/theme/app_theme.dart';

final _now = DateTime.now();
String _ago({int days = 0, int hours = 0}) =>
    _now.subtract(Duration(days: days, hours: hours)).toUtc().toIso8601String();

Map<String, dynamic> cat(int id, String name, String icon, [String type = 'expense']) =>
    {'id': id, 'name': name, 'icon': icon, 'color': '#FF6B6B', 'is_system': true, 'type': type};

final categories = [
  cat(1, 'Food', 'restaurant'),
  cat(2, 'Groceries', 'shopping_cart'),
  cat(3, 'Travel', 'directions_bus'),
  cat(4, 'Shopping', 'shopping_bag'),
  cat(5, 'Bills', 'receipt_long'),
  cat(6, 'Health', 'favorite'),
  cat(7, 'Fun', 'movie'),
  cat(8, 'Rent', 'home'),
  cat(9, 'Education', 'school'),
  cat(10, 'Fuel', 'local_gas_station'),
  cat(11, 'Other', 'category'),
  cat(20, 'Salary', 'work', 'income'),
  cat(21, 'Gift', 'redeem', 'income'),
];

Map<String, dynamic> txn(int id, String amount, String type, Map<String, dynamic> category,
        String notes, String date, {String method = 'upi'}) =>
    {
      'id': id,
      'amount': amount,
      'type': type,
      'category': category,
      'date': date,
      'payment_method': method,
      'payment_method_display': method == 'upi' ? 'UPI / Mobile Payment' : 'Cash',
      'notes': notes,
    };

final transactions = [
  txn(101, '60.00', 'expense', categories[0], 'LITE CAFE', _ago(hours: 2)),
  txn(102, '249.00', 'expense', categories[2], 'Metro card', _ago(hours: 7)),
  txn(103, '20.00', 'expense', categories[0], 'Chai', _ago(days: 1)),
  txn(104, '140.00', 'expense', categories[10], 'TALIB', _ago(days: 2)),
  txn(105, '1232.00', 'expense', categories[3], 'Flipkart', _ago(days: 3)),
  txn(106, '20.00', 'expense', categories[0], 'Chai', _ago(days: 3)),
  txn(107, '42000.00', 'income', categories[11], 'Salary', _ago(days: 5), method: 'bank'),
  txn(108, '899.00', 'expense', categories[4], 'Airtel', _ago(days: 5)),
  txn(109, '60.00', 'expense', categories[0], 'LITE CAFE', _ago(days: 6)),
  txn(110, '20.00', 'expense', categories[0], 'Chai', _ago(days: 6)),
];

final user = {
  'id': 1,
  'username': 'abdulla',
  'email': 'user@example.com',
  'first_name': 'Abdulla',
  'last_name': 'Fajal',
  'avatar': '',
  'currency': 'INR',
  'currency_symbol': '₹',
};

final dashboard = {
  'greeting': 'Evening',
  'user': user,
  'total_balance': '33580.00',
  'monthly_income': '42000.00',
  'monthly_expenses': '8420.00',
  'monthly_savings': '33580.00',
  'total_friends': 4,
  'monthly_budget_limit': '15000',
  'monthly_budget_spent': '8420',
  'currency_symbol': '₹',
  'recent_transactions': transactions,
  'pie_labels': ['Food', 'Shopping', 'Bills', 'Travel'],
  'pie_values': [2400, 1232, 899, 600],
  'pie_colors': ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4'],
  'bar_labels': ['Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov'],
  'bar_income': [40000, 41000, 42000, 42000, 42000, 42000],
  'bar_expense': [9000, 12000, 8000, 15000, 11000, 8420],
  'line_labels': ['1', '5', '10', '15', '18'],
  'line_values': [1200, 3000, 5200, 7100, 8420],
  'budget_warnings': [
    {'category': 'Food', 'spent': '2400', 'limit': '2000', 'icon': 'restaurant'}
  ],
  'insights': ['You spent 18% less on food than last month.'],
};

final _month = '${_now.year}-${_now.month.toString().padLeft(2, '0')}-01';

Map<String, dynamic> budget(int id, Map<String, dynamic> category, String amount, String spent) {
  final pct = double.parse(spent) / double.parse(amount) * 100;
  return {
    'id': id,
    'name': category['name'],
    'category': category,
    'amount': amount,
    'spent': spent,
    'percentage': pct.toStringAsFixed(1),
    'is_exceeded': pct > 100,
    'month': _month,
  };
}

final budgets = [
  budget(1, categories[0], '2000', '2400'),
  budget(2, categories[3], '3000', '1232'),
  budget(3, categories[4], '1500', '899'),
];

final reports = {
  'currency_symbol': '₹',
  'annual_income': '504000',
  'annual_expenses': '128400',
  'annual_net': '375600',
  'bar_labels': ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov'],
  'bar_income': [42000, 42000, 42000, 42000, 42000, 42000, 42000, 42000, 42000, 42000, 42000],
  'bar_expense': [9000, 12000, 8000, 15000, 11000, 9500, 12500, 8000, 15000, 11000, 8420],
  'savings_trend': [33000, 63000, 97000, 124000, 155000, 187500, 217000, 251000, 278000, 309000, 342580],
  'top_categories': [
    {'name': 'Food', 'total': '24000', 'color': '#FF6B6B', 'icon': 'restaurant'},
    {'name': 'Shopping', 'total': '18000', 'color': '#4ECDC4', 'icon': 'shopping_bag'},
    {'name': 'Bills', 'total': '12000', 'color': '#45B7D1', 'icon': 'receipt_long'},
    {'name': 'Travel', 'total': '8000', 'color': '#96CEB4', 'icon': 'directions_bus'},
  ],
  'monthly_summary': [
    {'month': 'Nov', 'income': '42000', 'expense': '8420', 'net': '33580'},
    {'month': 'Oct', 'income': '42000', 'expense': '11000', 'net': '31000'},
  ],
};

Map<String, dynamic> member(int id, String name, double net) => {
      'id': id,
      'display_name': name,
      'username': name.toLowerCase(),
      'initial': name[0],
      'avatar_url': '',
      'email': '${name.toLowerCase()}@example.com',
      'net_balance': net.toStringAsFixed(2),
    };

final splitGroups = [
  {'id': 1, 'name': 'Goa Trip', 'icon': 'flight', 'color': '#FF6B6B', 'total_members': 4, 'net_balance': '1250.00', 'is_accepted': true, 'created_by_id': 1},
  {'id': 2, 'name': 'Flatmates', 'icon': 'home', 'color': '#4ECDC4', 'total_members': 3, 'net_balance': '-480.00', 'is_accepted': true, 'created_by_id': 2},
  {'id': 3, 'name': 'Office Lunch', 'icon': 'restaurant', 'color': '#45B7D1', 'total_members': 6, 'net_balance': '0', 'is_accepted': true, 'created_by_id': 1},
  {'id': 4, 'name': 'Cricket Team', 'icon': 'sports_soccer', 'color': '#96CEB4', 'total_members': 11, 'net_balance': '0', 'is_accepted': false, 'created_by_id': 3},
];

final groupDetail = {
  ...splitGroups[0],
  'members': [
    {...member(1, 'Abdulla', 1250), 'is_accepted': true, 'is_creator': true},
    {...member(2, 'Talib', -500), 'is_accepted': true},
    {...member(3, 'Rahul', -450), 'is_accepted': true},
    {...member(4, 'Neha', -300), 'is_accepted': true},
    {...member(5, 'Imran', 0), 'is_accepted': false},
  ],
  'pending_invites': [
    {'email': 'sam@gmail.com', 'invited_by': 'Abdulla', 'created_at': _ago(days: 2)},
  ],
  'recent_expenses': [
    {'id': 11, 'description': 'Hotel booking', 'amount': '6000.00', 'date': _ago(days: 1), 'paid_by': member(1, 'Abdulla', 0), 'splits': [
      {'user_id': 1, 'amount': '1500.00'}, {'user_id': 2, 'amount': '1500.00'}, {'user_id': 3, 'amount': '1500.00'}, {'user_id': 4, 'amount': '1500.00'},
    ], 'split_type': 'equal', 'created_by_id': 1},
    {'id': 12, 'description': 'Dinner at beach shack', 'amount': '2400.00', 'date': _ago(days: 2), 'paid_by': member(2, 'Talib', 0), 'splits': [
      {'user_id': 1, 'amount': '600.00'}, {'user_id': 2, 'amount': '600.00'}, {'user_id': 3, 'amount': '600.00'}, {'user_id': 4, 'amount': '600.00'},
    ], 'split_type': 'equal', 'created_by_id': 2},
    {'id': 13, 'description': 'Scooter rent', 'amount': '1200.00', 'date': _ago(days: 3), 'paid_by': member(3, 'Rahul', 0), 'splits': [], 'split_type': 'equal', 'created_by_id': 3},
  ],
  'balances': [],
  'simplified_debts': [
    {'from_user': 'Talib', 'from_user_id': 2, 'to_user': 'Abdulla', 'to_user_id': 1, 'amount': '500.00'},
    {'from_user': 'Rahul', 'from_user_id': 3, 'to_user': 'Abdulla', 'to_user_id': 1, 'amount': '450.00'},
    {'from_user': 'Neha', 'from_user_id': 4, 'to_user': 'Abdulla', 'to_user_id': 1, 'amount': '300.00'},
  ],
  'settlement_history': [],
  'members_can_invite': true,
  'invite_token': 'abc',
};

final friends = {
  'friends': [member(2, 'Talib', 0), member(3, 'Rahul', 0), member(4, 'Neha', 0), member(5, 'Imran', 0)],
  'pending_received': [member(6, 'Asha', 0)],
  'pending_sent': [member(7, 'Karan', 0)],
};

/// Shared preferences the app reads its offline cache from.
Map<String, Object> baseCache() => {
      'cache_dashboard': jsonEncode(dashboard),
      'cache_user': jsonEncode(user),
      'cache_transactions': jsonEncode({'transactions': transactions, 'currency_symbol': '₹'}),
      'cache_categories': jsonEncode({'categories': categories, 'currency_symbol': '₹'}),
      'cache_budgets': jsonEncode({'budgets': budgets, 'overall': {'amount': '20000.00', 'spent': '0'}, 'currency_symbol': '₹'}),
      'cache_reports': jsonEncode(reports),
      'cache_split_groups': jsonEncode(splitGroups),
      'cache_split_group_detail_1': jsonEncode(groupDetail),
      'cache_friends': jsonEncode(friends),
      'cache_notifications': jsonEncode([
        {
          'id': 3,
          'title': 'Today: ₹309 spent',
          'message': '2 entries logged so far. Anything else to add? Tap to log it.',
          'data': {'action': 'open_dashboard', 'kind': 'daily_reminder'},
          'is_read': false,
          'created_at': DateTime.now().subtract(const Duration(minutes: 25)).toUtc().toIso8601String(),
        },
        {
          'id': 2,
          'title': 'Goa Trip: new expense',
          'message': 'Rahul added Dinner ₹2,400. Your share is ₹600.',
          'data': {'action': 'open_split_group', 'group_id': '1', 'kind': 'split_expense'},
          'is_read': false,
          'created_at': DateTime.now().subtract(const Duration(hours: 5)).toUtc().toIso8601String(),
        },
        {
          'id': 1,
          'title': "Log today's expenses",
          'message': "You haven't added anything today. It takes 5 seconds to keep your budget on track.",
          'data': {'action': 'open_dashboard', 'kind': 'daily_reminder'},
          'is_read': true,
          'created_at': DateTime.now().subtract(const Duration(days: 1, hours: 2)).toUtc().toIso8601String(),
        },
      ]),
    };

Future<void> loadFonts() async {
  final jakarta = FontLoader('PlusJakartaSans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    jakarta.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$w.ttf'));
  }
  await jakarta.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter-347/flutter';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final bytes = await icons.readAsBytes();
  final mi = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(bytes.buffer)));
  await mi.load();
}

void silencePlugins() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in [
    'home_widget',
    'plugins.flutter.io/connectivity',
    'dev.fluttercommunity.plus/connectivity',
    'com.example.espere_app/auto_capture',
    'com.example.espere_app/receipt',
    'plugins.flutter.io/firebase_messaging',
    'dev.fluttercommunity.plus/package_info',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }
}

/// Renders [screen] at phone size and writes goldens/[name].png.
Future<void> shot(WidgetTester tester, String name, Widget screen,
    {Map<String, Object>? prefs, Size size = const Size(390, 844), bool scaffold = true,
    double textScale = 1,
    Future<void> Function(WidgetTester t)? act}) async {
  debugDisableShadows = false;
  // flutter test --dart-define=ACCENT=4 renders every screen in that app colour into
  // goldens/accent_4/ (used for the website's colour picker).
  const accent = int.fromEnvironment('ACCENT', defaultValue: -1);
  if (accent >= 0) AppAccent.debugIndex = accent;
  final path = accent >= 0 ? 'goldens/accent_$accent/$name.png' : 'goldens/$name.png';
  SharedPreferences.setMockInitialValues(prefs ?? baseCache());
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size(size.width * 2, size.height * 2);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    builder: textScale == 1
        ? null
        : (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
    routes: {'/categories': (_) => const SizedBox(), '/profile': (_) => const SizedBox()},
    home: scaffold ? Scaffold(body: SafeArea(child: screen)) : screen,
  ));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  if (act != null) {
    await act(tester);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }
  try {
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(path));
  } finally {
    debugDisableShadows = true;
  }
}
