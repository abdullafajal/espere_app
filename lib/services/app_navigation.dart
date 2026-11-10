import 'package:flutter/foundation.dart';

/// Lets code outside the widget tree (deep links, the home-screen widget)
/// ask the home screen to switch tabs.
class AppNavigation {
  AppNavigation._();

  /// Tab indexes: 0 dashboard, 1 transactions, 2 budgets, 3 friends, 4 split groups.
  static const int tabTransactions = 1;

  /// Set by [openTab]; consumed (and reset) by HomeScreen.
  static final ValueNotifier<int?> requestedTab = ValueNotifier<int?>(null);

  static void openTab(int index) => requestedTab.value = index;
}
