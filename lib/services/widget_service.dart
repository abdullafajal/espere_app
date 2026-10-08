import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import 'package:flutter/foundation.dart';
import '../models/category.dart';

class WidgetService {
  static const String _dashboardWidgetName = 'DashboardWidgetProvider';
  static const String _quickAddWidgetName = 'QuickAddWidgetProvider';

  /// Updates financial summary in the Dashboard Home-Screen Widget
  static Future<void> updateDashboard({
    required double totalBalance,
    required double totalIncome,
    required double totalExpense,
    String currencySymbol = '₹',
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>('currency_symbol', currencySymbol);
      await HomeWidget.saveWidgetData<String>('total_balance', '$currencySymbol${totalBalance.toStringAsFixed(2)}');
      await HomeWidget.saveWidgetData<String>('total_income', '$currencySymbol${totalIncome.toInt()}');
      await HomeWidget.saveWidgetData<String>('total_expense', '$currencySymbol${totalExpense.toInt()}');
      
      double savings = totalIncome - totalExpense;
      await HomeWidget.saveWidgetData<String>('total_savings', '$currencySymbol${savings.toStringAsFixed(2)}');

      await HomeWidget.updateWidget(
        name: _dashboardWidgetName,
        iOSName: 'DashboardWidget',
      );
      debugPrint('[Widget] Dashboard widget updated successfully');
    } catch (e) {
      debugPrint('[Widget] Dashboard update failed: $e');
    }
  }

  /// Syncs app categories and currency symbol to the Quick Add Home-Screen Widget
  static Future<void> syncQuickAddCategories(
    List<CategoryModel> categories, {
    String currencySymbol = '₹',
  }) async {
    try {
      final expenseCategories = categories.where((c) => c.type == 'expense').toList();
      final serializedList = expenseCategories.map((c) => c.toJson()).toList();
      
      await HomeWidget.saveWidgetData<String>('currency_symbol', currencySymbol);
      await HomeWidget.saveWidgetData<String>('cached_categories_json', jsonEncode(serializedList));

      await HomeWidget.updateWidget(
        name: _quickAddWidgetName,
      );
      debugPrint('[Widget] Quick Add categories synced successfully (${expenseCategories.length} items)');
    } catch (e) {
      debugPrint('[Widget] Quick Add categories sync failed: $e');
    }
  }

  /// Syncs 2x2 financial metrics to the Quick Add Home-Screen Widget
  static Future<void> syncQuickAddFinancialMetrics({
    required double totalSpend,
    required double totalIncome,
    required double todaySpend,
    required double avgDaily,
    String currencySymbol = '₹',
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>('currency_symbol', currencySymbol);
      await HomeWidget.saveWidgetData<String>('widget_total_spend', '$currencySymbol${totalSpend.toStringAsFixed(2)}');
      await HomeWidget.saveWidgetData<String>('widget_total_income', '$currencySymbol${totalIncome.toStringAsFixed(2)}');
      await HomeWidget.saveWidgetData<String>('widget_today_spend', '$currencySymbol${todaySpend.toStringAsFixed(2)}');
      await HomeWidget.saveWidgetData<String>('widget_avg_daily', '$currencySymbol${avgDaily.toStringAsFixed(2)}');

      await HomeWidget.updateWidget(
        name: _quickAddWidgetName,
      );
      debugPrint('[Widget] Quick Add 2x2 financial metrics synced successfully');
    } catch (e) {
      debugPrint('[Widget] Quick Add financial metrics sync failed: $e');
    }
  }

  /// Refreshes all widgets on the home screen
  static Future<void> refreshAllWidgets() async {
    try {
      await HomeWidget.updateWidget(name: _dashboardWidgetName);
      await HomeWidget.updateWidget(name: _quickAddWidgetName);
    } catch (e) {
      debugPrint('[Widget] Refresh all failed: $e');
    }
  }
}
