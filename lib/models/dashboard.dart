/// Dashboard data model — aggregated response from /api/dashboard/
import 'user.dart';
import 'transaction.dart';

class DashboardData {
  final String greeting;
  final UserModel user;
  final String totalBalance;
  final String monthlyIncome;
  final String monthlyExpenses;
  final String monthlySavings;
  final String currencySymbol;
  final List<TransactionModel> recentTransactions;
  final List<String> pieLabels;
  final List<double> pieValues;
  final List<String> pieColors;
  final List<String> barLabels;
  final List<double> barIncome;
  final List<double> barExpense;
  final List<String> lineLabels;
  final List<double> lineValues;
  final List<Map<String, String>> budgetWarnings;
  final List<String> insights;

  DashboardData({
    required this.greeting,
    required this.user,
    required this.totalBalance,
    required this.monthlyIncome,
    required this.monthlyExpenses,
    required this.monthlySavings,
    required this.currencySymbol,
    required this.recentTransactions,
    required this.pieLabels,
    required this.pieValues,
    required this.pieColors,
    required this.barLabels,
    required this.barIncome,
    required this.barExpense,
    required this.lineLabels,
    required this.lineValues,
    required this.budgetWarnings,
    required this.insights,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    return DashboardData(
      greeting: json['greeting'] ?? 'Morning',
      user: UserModel.fromJson(json['user'] ?? {}),
      totalBalance: json['total_balance'] ?? '0.00',
      monthlyIncome: json['monthly_income'] ?? '0.00',
      monthlyExpenses: json['monthly_expenses'] ?? '0.00',
      monthlySavings: json['monthly_savings'] ?? '0.00',
      currencySymbol: json['currency_symbol'] ?? '₹',
      recentTransactions: () {
        final rawList = (json['recent_transactions'] as List? ?? [])
            .map((t) => TransactionModel.fromJson(t))
            .toList();
        
        final seenKeys = <String>{};
        final uniqueList = <TransactionModel>[];
        for (var t in rawList) {
          final amt = double.tryParse(t.amount.toString()) ?? 0;
          final key = "${amt.toStringAsFixed(2)}_${t.category.name}_${t.date.toUtc().toIso8601String().substring(0, 16)}";
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            uniqueList.add(t);
          }
        }
        return uniqueList..sort((a, b) {
          int cmp = b.date.compareTo(a.date);
          if (cmp != 0) return cmp;
          return b.id.compareTo(a.id);
        });
      }(),
      pieLabels: List<String>.from(json['pie_labels'] ?? []),
      pieValues: (json['pie_values'] as List? ?? [])
          .map((v) => (v as num).toDouble())
          .toList(),
      pieColors: List<String>.from(json['pie_colors'] ?? []),
      barLabels: List<String>.from(json['bar_labels'] ?? []),
      barIncome: (json['bar_income'] as List? ?? [])
          .map((v) => (v as num).toDouble())
          .toList(),
      barExpense: (json['bar_expense'] as List? ?? [])
          .map((v) => (v as num).toDouble())
          .toList(),
      lineLabels: List<String>.from(json['line_labels'] ?? []),
      lineValues: (json['line_values'] as List? ?? [])
          .map((v) => (v as num).toDouble())
          .toList(),
      budgetWarnings: (json['budget_warnings'] as List? ?? [])
          .map((w) => Map<String, String>.from(w.map(
              (key, value) => MapEntry(key.toString(), value.toString()))))
          .toList(),
      insights: List<String>.from(json['insights'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
        'greeting': greeting,
        'user': user.toJson(),
        'total_balance': totalBalance,
        'monthly_income': monthlyIncome,
        'monthly_expenses': monthlyExpenses,
        'monthly_savings': monthlySavings,
        'currency_symbol': currencySymbol,
        'recent_transactions':
            recentTransactions.map((t) => t.toJson()).toList(),
        'pie_labels': pieLabels,
        'pie_values': pieValues,
        'pie_colors': pieColors,
        'bar_labels': barLabels,
        'bar_income': barIncome,
        'bar_expense': barExpense,
        'line_labels': lineLabels,
        'line_values': lineValues,
        'budget_warnings': budgetWarnings,
        'insights': insights,
      };
}
