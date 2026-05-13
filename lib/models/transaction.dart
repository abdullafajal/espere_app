/// Transaction model matching Django's Transaction model.
import 'category.dart';

class TransactionModel {
  final int id;
  final String amount;
  final String type; // 'income' or 'expense'
  final CategoryModel category;
  final DateTime date;
  final String paymentMethod;
  final String paymentMethodDisplay;
  final String notes;

  TransactionModel({
    required this.id,
    required this.amount,
    required this.type,
    required this.category,
    required this.date,
    this.paymentMethod = 'cash',
    this.paymentMethodDisplay = 'Cash',
    this.notes = '',
  });

  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';

  /// Formatted amount with sign
  String formattedAmount(String currencySymbol) {
    final sign = isIncome ? '+' : '-';
    return '$sign$currencySymbol$amount';
  }

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'] ?? 0,
      amount: json['amount'] ?? '0.00',
      type: json['type'] ?? 'expense',
      category: CategoryModel.fromJson(json['category'] ?? {}),
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      paymentMethod: json['payment_method'] ?? 'cash',
      paymentMethodDisplay: json['payment_method_display'] ?? 'Cash',
      notes: json['notes'] ?? '',
    );
  }

  /// Full serialization for caching (round-trips with fromJson)
  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'type': type,
        'category': category.toJson(),
        'date': date.toIso8601String(),
        'payment_method': paymentMethod,
        'payment_method_display': paymentMethodDisplay,
        'notes': notes,
      };

  /// Slim payload for API create/update
  Map<String, dynamic> toApiJson() => {
        'amount': amount,
        'type': type,
        'category_id': category.id,
        'date': date.toIso8601String(),
        'payment_method': paymentMethod,
        'notes': notes,
      };
}
