import 'package:home_widget/home_widget.dart';
import 'package:flutter/foundation.dart';

class WidgetService {
  static const String _groupId = 'group.com.example.espere_app'; // Optional for iOS
  static const String _androidWidgetName = 'DashboardWidgetProvider';

  static Future<void> updateDashboard({
    required double totalBalance,
    required double totalIncome,
    required double totalExpense,
    String currencySymbol = '₹',
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>('total_balance', '$currencySymbol${totalBalance.toStringAsFixed(2)}');
      await HomeWidget.saveWidgetData<String>('total_income', '$currencySymbol${totalIncome.toInt()}');
      await HomeWidget.saveWidgetData<String>('total_expense', '$currencySymbol${totalExpense.toInt()}');
      
      double savings = totalIncome - totalExpense;
      await HomeWidget.saveWidgetData<String>('total_savings', '$currencySymbol${savings.toStringAsFixed(2)}');

      await HomeWidget.updateWidget(
        name: _androidWidgetName,
        iOSName: 'DashboardWidget', // Not implemented yet but good to have
      );
      debugPrint('[Widget] Dashboard updated successfully');
    } catch (e) {
      debugPrint('[Widget] Update failed: $e');
    }
  }
}
