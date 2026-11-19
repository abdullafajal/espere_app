/// Adds and removes transactions the same way the transaction form does: the cache and
/// the dashboard update at once, and the change is queued for sync (works offline).
library;

import '../models/category.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';
import 'sync_service.dart';
import 'widget_service.dart';

class TransactionStore {
  TransactionStore._();

  static const _methodDisplay = {
    'cash': 'Cash',
    'card': 'Credit/Debit Card',
    'bank': 'Bank Transfer',
    'upi': 'UPI / Mobile Payment',
    'other': 'Other',
  };

  /// Creates a transaction and returns its local (temporary) id.
  static Future<int> create({
    required double amount,
    required String type,
    required CategoryModel? category,
    DateTime? date,
    String paymentMethod = 'upi',
    String notes = '',
  }) async {
    final when = date ?? DateTime.now();
    final tempId = DateTime.now().millisecondsSinceEpoch;
    final amountText = amount.toStringAsFixed(2);

    final full = {
      'id': tempId,
      'amount': amountText,
      'type': type,
      'category': category?.toJson() ?? {'name': 'Other', 'icon': 'category'},
      'date': when.toUtc().toIso8601String(),
      'payment_method': paymentMethod,
      'payment_method_display': _methodDisplay[paymentMethod] ?? 'Other',
      'notes': notes,
    };

    await CacheService.addTransactionToCache(full);
    await CacheService.updateDashboardOptimistically(type, amount, full);
    if (type == 'expense' && category != null) {
      await CacheService.updateBudgetOptimistically(category.id, amount);
    }
    await SyncService.queueOperation(
      action: 'create',
      entity: 'transaction',
      entityId: tempId,
      data: {
        'amount': amountText,
        'type': type,
        'category_id': category?.id,
        'date': when.toUtc().toIso8601String(),
        'payment_method': paymentMethod,
        'notes': notes,
      },
    );
    if (ConnectivityService.isOnline) SyncService.syncAll();
    WidgetService.refreshAllWidgets();
    return tempId;
  }

  /// Removes a transaction created a moment ago (Undo). Follows its id if a sync has
  /// already replaced the temporary id with the server's.
  static Future<void> remove(int id) async {
    final current = SyncService.transactionIdRemap[id] ?? id;
    final cached = await CacheService.getCachedTransactions();
    final list = List<Map<String, dynamic>>.from(cached?['transactions'] ?? const []);
    final idx = list.indexWhere((t) => t['id'] == current);
    if (idx >= 0) {
      final t = list[idx];
      final amount = double.tryParse(t['amount'].toString()) ?? 0.0;
      final category = t['category'] as Map?;
      await CacheService.reverseDashboardImpact(
        (t['type'] ?? 'expense').toString(),
        amount,
        current,
        categoryName: category?['name']?.toString(),
      );
      if (t['type'] == 'expense' && category?['id'] is int) {
        await CacheService.updateBudgetOptimistically(category!['id'] as int, amount, isDelete: true);
      }
      list.removeAt(idx);
      await CacheService.cacheTransactions(
        {'transactions': list, 'currency_symbol': cached?['currency_symbol']},
        preserveUnsynced: false,
      );
    }
    await SyncService.queueOperation(action: 'delete', entity: 'transaction', entityId: current);
    if (ConnectivityService.isOnline) SyncService.syncAll();
    WidgetService.refreshAllWidgets();
  }

  /// Categories of [type], the ones used most in the cached transactions first.
  static Future<List<CategoryModel>> categoriesByUse(String type) async {
    final cats = await CacheService.getCachedCategories();
    final all = ((cats?['categories'] as List?) ?? const [])
        .whereType<Map>()
        .map((c) => CategoryModel.fromJson(Map<String, dynamic>.from(c)))
        .where((c) => c.type == type)
        .toList();
    final txns = await CacheService.getCachedTransactions();
    final uses = <int, int>{};
    for (final t in ((txns?['transactions'] as List?) ?? const []).whereType<Map>()) {
      final id = (t['category'] as Map?)?['id'];
      if (id is int) uses[id] = (uses[id] ?? 0) + 1;
    }
    final order = {for (var i = 0; i < all.length; i++) all[i].id: i};
    all.sort((a, b) {
      final byUse = (uses[b.id] ?? 0).compareTo(uses[a.id] ?? 0);
      return byUse != 0 ? byUse : order[a.id]!.compareTo(order[b.id]!);
    });
    return all;
  }
}
