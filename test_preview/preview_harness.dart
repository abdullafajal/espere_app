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

/// Shared preferences the app reads its offline cache from.
Map<String, Object> baseCache() => {
      'cache_dashboard': jsonEncode(dashboard),
      'cache_user': jsonEncode(user),
      'cache_transactions': jsonEncode({'transactions': transactions, 'currency_symbol': '₹'}),
      'cache_categories': jsonEncode({'categories': categories, 'currency_symbol': '₹'}),
      'cache_budgets': jsonEncode({'budgets': budgets, 'currency_symbol': '₹'}),
      'cache_reports': jsonEncode(reports),
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
    {Map<String, Object>? prefs, Size size = const Size(390, 844), bool scaffold = true}) async {
  debugDisableShadows = false;
  SharedPreferences.setMockInitialValues(prefs ?? baseCache());
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size(size.width * 2, size.height * 2);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
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
  try {
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  } finally {
    debugDisableShadows = true;
  }
}
