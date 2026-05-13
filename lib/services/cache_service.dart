/// Cache service — JSON read/write for offline-first data using SharedPreferences.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  // ─── Cache Keys ──────────────────────────────────────────────────────
  static const _dashboardKey = 'cache_dashboard';
  static const _transactionsKey = 'cache_transactions';
  static const _categoriesKey = 'cache_categories';
  static const _budgetsKey = 'cache_budgets';
  static const _savingsKey = 'cache_savings';
  static const _splitGroupsKey = 'cache_split_groups';
  static const _userKey = 'cache_user';
  static const _reportsKey = 'cache_reports';
  static const _syncQueueKey = 'sync_queue';

  // ─── Generic Helpers ─────────────────────────────────────────────────

  /// Write raw JSON map to cache
  static Future<void> _write(String key, Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(data));
  }

  /// Read raw JSON map from cache
  static Future<Map<String, dynamic>?> _read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Clear a specific cache key
  static Future<void> _clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  // ─── Dashboard ───────────────────────────────────────────────────────

  static Future<void> cacheDashboard(Map<String, dynamic> data) async {
    await _write(_dashboardKey, data);
  }

  static Future<Map<String, dynamic>?> getCachedDashboard() async {
    return await _read(_dashboardKey);
  }

  // ─── Transactions ────────────────────────────────────────────────────

  static Future<void> cacheTransactions(Map<String, dynamic> data) async {
    await _write(_transactionsKey, data);
  }

  static Future<Map<String, dynamic>?> getCachedTransactions() async {
    return await _read(_transactionsKey);
  }

  // ─── Categories ──────────────────────────────────────────────────────

  static Future<void> cacheCategories(Map<String, dynamic> data) async {
    await _write(_categoriesKey, data);
  }

  static Future<Map<String, dynamic>?> getCachedCategories() async {
    return await _read(_categoriesKey);
  }

  // ─── Budgets ─────────────────────────────────────────────────────────

  static Future<void> cacheBudgets(Map<String, dynamic> data) async {
    await _write(_budgetsKey, data);
  }

  static Future<Map<String, dynamic>?> getCachedBudgets() async {
    return await _read(_budgetsKey);
  }

  // ─── Savings ─────────────────────────────────────────────────────────

  static Future<void> cacheSavings(Map<String, dynamic> data) async {
    await _write(_savingsKey, data);
  }

  static Future<Map<String, dynamic>?> getCachedSavings() async {
    return await _read(_savingsKey);
  }

  // ─── Split Groups ────────────────────────────────────────────────────

  static Future<void> cacheSplitGroups(List<Map<String, dynamic>> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_splitGroupsKey, jsonEncode(data));
  }

  static Future<List<Map<String, dynamic>>?> getCachedSplitGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_splitGroupsKey);
    if (raw == null) return null;
    try {
      final List decoded = jsonDecode(raw);
      return decoded.map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {
      return null;
    }
  }

  // ─── User Profile ────────────────────────────────────────────────────

  static Future<void> cacheUser(Map<String, dynamic> data) async {
    await _write(_userKey, data);
  }

  static Future<Map<String, dynamic>?> getCachedUser() async {
    return await _read(_userKey);
  }

  // ─── Reports ─────────────────────────────────────────────────────────

  static Future<void> cacheReports(Map<String, dynamic> data) async {
    await _write(_reportsKey, data);
  }

  static Future<Map<String, dynamic>?> getCachedReports() async {
    return await _read(_reportsKey);
  }

  // ─── Optimistic Updates ──────────────────────────────────────────────

  /// Add a transaction to the local cache immediately (offline-first)
  static Future<void> addTransactionToCache(Map<String, dynamic> txnJson) async {
    final cached = await getCachedTransactions();
    if (cached == null) return;
    final list = List<Map<String, dynamic>>.from(cached['transactions'] ?? []);
    list.insert(0, txnJson);
    await cacheTransactions({
      'transactions': list,
      'currency_symbol': cached['currency_symbol'],
    });
  }

  /// Update an existing transaction in the local cache
  static Future<void> updateTransactionInCache(
      int id, Map<String, dynamic> txnJson) async {
    final cached = await getCachedTransactions();
    if (cached == null) return;
    final list = List<Map<String, dynamic>>.from(cached['transactions'] ?? []);
    final idx = list.indexWhere((t) => t['id'] == id);
    if (idx != -1) {
      list[idx] = txnJson;
      await cacheTransactions({
        'transactions': list,
        'currency_symbol': cached['currency_symbol'],
      });
    }
  }

  /// Add a category to the local cache immediately
  static Future<void> addCategoryToCache(Map<String, dynamic> catJson) async {
    final cached = await getCachedCategories();
    if (cached == null) return;
    final list = List<Map<String, dynamic>>.from(cached['categories'] ?? []);
    list.add(catJson);
    await cacheCategories({
      'categories': list,
      'currency_symbol': cached['currency_symbol'],
    });
  }

  /// Add a budget to the local cache immediately
  static Future<void> addBudgetToCache(Map<String, dynamic> budgetJson) async {
    final cached = await getCachedBudgets();
    if (cached == null) return;
    final list = List<Map<String, dynamic>>.from(cached['budgets'] ?? []);
    list.add(budgetJson);
    await cacheBudgets({
      'budgets': list,
      'currency_symbol': cached['currency_symbol'],
    });
  }

  /// Add a saving goal to the local cache immediately
  static Future<void> addSavingToCache(Map<String, dynamic> goalJson) async {
    final cached = await getCachedSavings();
    if (cached == null) return;
    final list = List<Map<String, dynamic>>.from(cached['goals'] ?? []);
    list.insert(0, goalJson);
    await cacheSavings({
      'goals': list,
      'currency_symbol': cached['currency_symbol'],
    });
  }

  /// Update dashboard totals and recent transactions optimistically
  static Future<void> updateDashboardOptimistically(
      String type, double amount, Map<String, dynamic> txnJson) async {
    final cached = await getCachedDashboard();
    if (cached == null) return;

    double total = double.tryParse(cached['total_balance'].toString()) ?? 0;
    double income = double.tryParse(cached['monthly_income'].toString()) ?? 0;
    double expense = double.tryParse(cached['monthly_expenses'].toString()) ?? 0;
    double savings = double.tryParse(cached['monthly_savings'].toString()) ?? 0;

    if (type == 'income') {
      total += amount;
      income += amount;
    } else if (type == 'savings') {
      total -= amount;
      savings += amount;
    } else {
      total -= amount;
      expense += amount;
    }

    cached['total_balance'] = total.toStringAsFixed(2);
    cached['monthly_income'] = income.toStringAsFixed(2);
    cached['monthly_expenses'] = expense.toStringAsFixed(2);
    cached['monthly_savings'] = savings.toStringAsFixed(2);

    // Update recent transactions list in dashboard and sort by date
    final recent =
        List<Map<String, dynamic>>.from(cached['recent_transactions'] ?? []);
    recent.add(txnJson);
    recent.sort((a, b) => DateTime.parse(b['date'].toString())
        .compareTo(DateTime.parse(a['date'].toString())));
    if (recent.length > 5) recent.removeRange(5, recent.length);
    cached['recent_transactions'] = recent;

    // Update charts (Pie Chart)
    if (type == 'expense') {
      final categoryName = txnJson['category']?['name'] ?? 'Other';
      final categoryColor = txnJson['category']?['color'] ?? '#CCCCCC';
      final labels = List<String>.from(cached['pie_labels'] ?? []);
      final values = List<double>.from(
          (cached['pie_values'] as List? ?? []).map((v) => (v as num).toDouble()));
      final colors = List<String>.from(cached['pie_colors'] ?? []);

      int idx = labels.indexOf(categoryName);
      if (idx != -1) {
        values[idx] += amount;
      } else {
        labels.add(categoryName);
        values.add(amount);
        colors.add(categoryColor);
      }
      cached['pie_labels'] = labels;
      cached['pie_values'] = values;
      cached['pie_colors'] = colors;
    }

    // Update Bar Chart (Monthly Income vs Expense)
    final monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final currentMonth = monthNames[DateTime.now().month - 1];
    final barLabels = List<String>.from(cached['bar_labels'] ?? []);
    int barIdx = barLabels.indexOf(currentMonth);
    if (barIdx != -1) {
      if (type == 'income') {
        final incomeValues = List<double>.from(
            (cached['bar_income'] as List? ?? []).map((v) => (v as num).toDouble()));
        if (barIdx < incomeValues.length) {
          incomeValues[barIdx] += amount;
          cached['bar_income'] = incomeValues;
        }
      } else if (type == 'expense') {
        final expenseValues = List<double>.from(
            (cached['bar_expense'] as List? ?? []).map((v) => (v as num).toDouble()));
        if (barIdx < expenseValues.length) {
          expenseValues[barIdx] += amount;
          cached['bar_expense'] = expenseValues;
        }
      }
    }

    // Update Line Chart (30-Day Spending Trend)
    if (type == 'expense') {
      final lineLabels = List<String>.from(cached['line_labels'] ?? []);
      final day = DateTime.now().day.toString().padLeft(2, '0');
      final dayShort = DateTime.now().day.toString();
      final dayFull = "$day $currentMonth";

      int lineIdx = lineLabels.indexOf(day);
      if (lineIdx == -1) lineIdx = lineLabels.indexOf(dayShort);
      if (lineIdx == -1) lineIdx = lineLabels.indexOf(dayFull);

      if (lineIdx != -1) {
        final lineValues = List<double>.from(
            (cached['line_values'] as List? ?? []).map((v) => (v as num).toDouble()));
        if (lineIdx < lineValues.length) {
          lineValues[lineIdx] += amount;
          cached['line_values'] = lineValues;
        }
      }
    }

    // Update Savings Chart (If also present as line chart)
    if (type == 'savings') {
      final lineLabels = List<String>.from(cached['line_labels'] ?? []);
      int lineIdx = lineLabels.indexOf(currentMonth);
      if (lineIdx != -1) {
        final lineValues = List<double>.from(
            (cached['line_values'] as List? ?? []).map((v) => (v as num).toDouble()));
        if (lineIdx < lineValues.length) {
          lineValues[lineIdx] += amount;
          cached['line_values'] = lineValues;
        }
      }
    }

    await cacheDashboard(cached);
  }

  /// Update budget spent amount optimistically
  static Future<void> updateBudgetOptimistically(int categoryId, double amount,
      {bool isDelete = false}) async {
    final cached = await getCachedBudgets();
    if (cached == null) return;

    final budgets = List<Map<String, dynamic>>.from(cached['budgets'] ?? []);
    bool updated = false;
    for (var i = 0; i < budgets.length; i++) {
      final budgetCatId = budgets[i]['category']?['id'] ?? budgets[i]['category_id'];
      if (budgetCatId?.toString() == categoryId.toString()) {
        double spent = double.tryParse(budgets[i]['spent'].toString()) ?? 0;
        double total = double.tryParse(budgets[i]['amount'].toString()) ?? 0;

        if (isDelete) {
          spent -= amount;
        } else {
          spent += amount;
        }

        budgets[i]['spent'] = spent;
        budgets[i]['remaining'] = total - spent;
        budgets[i]['percentage'] =
            total > 0 ? (spent / total * 100).clamp(0, 100) : 0;
        updated = true;
        break;
      }
    }

    if (updated) {
      await cacheBudgets({
        'budgets': budgets,
        'currency_symbol': cached['currency_symbol'],
      });
    }
  }

  /// Reverse a transaction's impact on dashboard totals (used when deleting offline)
  static Future<void> reverseDashboardImpact(
      String type, double amount, int txnId,
      {String? categoryName}) async {
    final cached = await getCachedDashboard();
    if (cached == null) return;

    double total = double.tryParse(cached['total_balance'].toString()) ?? 0;
    double income = double.tryParse(cached['monthly_income'].toString()) ?? 0;
    double expense = double.tryParse(cached['monthly_expenses'].toString()) ?? 0;

    if (type == 'income') {
      total -= amount;
      income -= amount;
    } else {
      total += amount;
      expense -= amount;
    }

    cached['total_balance'] = total.toStringAsFixed(2);
    cached['monthly_income'] = income.toStringAsFixed(2);
    cached['monthly_expenses'] = expense.toStringAsFixed(2);

    // Remove from recent transactions if present
    final recent =
        List<Map<String, dynamic>>.from(cached['recent_transactions'] ?? []);

    // Find the transaction to get category name before removing
    final txnToDelete =
        recent.firstWhere((t) => t['id'] == txnId, orElse: () => {});
    recent.removeWhere((t) => t['id'] == txnId);
    cached['recent_transactions'] = recent;

    // Reverse Pie Chart values if it was an expense
    if (type == 'expense') {
      String? finalCatName = categoryName;
      if (finalCatName == null && txnToDelete.isNotEmpty) {
        final cat = txnToDelete['category'];
        if (cat is Map) {
          finalCatName = cat['name']?.toString();
        }
      }
      
      if (finalCatName != null) {
        final labels = List<String>.from(cached['pie_labels'] ?? []);
        final values = List<double>.from((cached['pie_values'] as List? ?? [])
            .map((v) => (v as num).toDouble()));

        int idx = labels.indexOf(finalCatName);
        if (idx != -1) {
          values[idx] -= amount;
          if (values[idx] < 0) values[idx] = 0;
        }
        cached['pie_labels'] = labels;
        cached['pie_values'] = values;
      }
    }

    // Reverse Bar/Line Chart values
    final monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    // Use transaction date if available, else current month
    final txnDateRaw = txnToDelete['date'];
    final txnMonth = txnDateRaw != null 
        ? monthNames[DateTime.parse(txnDateRaw.toString()).month - 1]
        : monthNames[DateTime.now().month - 1];
    
    final barLabels = List<String>.from(cached['bar_labels'] ?? []);
    int barIdx = barLabels.indexOf(txnMonth);
    if (barIdx != -1) {
      if (type == 'income') {
        final incomeValues = List<double>.from((cached['bar_income'] as List? ?? []).map((v) => (v as num).toDouble()));
        if (barIdx < incomeValues.length) {
          incomeValues[barIdx] -= amount;
          if (incomeValues[barIdx] < 0) incomeValues[barIdx] = 0;
          cached['bar_income'] = incomeValues;
        }
      } else if (type == 'expense') {
        final expenseValues = List<double>.from((cached['bar_expense'] as List? ?? []).map((v) => (v as num).toDouble()));
        if (barIdx < expenseValues.length) {
          expenseValues[barIdx] -= amount;
          if (expenseValues[barIdx] < 0) expenseValues[barIdx] = 0;
          cached['bar_expense'] = expenseValues;
        }
      }
    }

    if (type == 'expense') {
      final lineLabels = List<String>.from(cached['line_labels'] ?? []);
      final day = txnDateRaw != null 
          ? DateTime.parse(txnDateRaw.toString()).day.toString().padLeft(2, '0')
          : DateTime.now().day.toString().padLeft(2, '0');
      final dayShort = txnDateRaw != null 
          ? DateTime.parse(txnDateRaw.toString()).day.toString()
          : DateTime.now().day.toString();
      final dayFull = "$day $txnMonth";

      int lineIdx = lineLabels.indexOf(day);
      if (lineIdx == -1) lineIdx = lineLabels.indexOf(dayShort);
      if (lineIdx == -1) lineIdx = lineLabels.indexOf(dayFull);

      if (lineIdx != -1) {
        final lineValues = List<double>.from((cached['line_values'] as List? ?? []).map((v) => (v as num).toDouble()));
        if (lineIdx < lineValues.length) {
          lineValues[lineIdx] -= amount;
          if (lineValues[lineIdx] < 0) lineValues[lineIdx] = 0;
          cached['line_values'] = lineValues;
        }
      }
    }

    if (type == 'savings') {
      final lineLabels = List<String>.from(cached['line_labels'] ?? []);
      int lineIdx = lineLabels.indexOf(txnMonth);
      if (lineIdx != -1) {
        final lineValues = List<double>.from((cached['line_values'] as List? ?? []).map((v) => (v as num).toDouble()));
        if (lineIdx < lineValues.length) {
          lineValues[lineIdx] -= amount;
          if (lineValues[lineIdx] < 0) lineValues[lineIdx] = 0;
          cached['line_values'] = lineValues;
        }
      }
    }

    await cacheDashboard(cached);
  }


  /// Update an existing saving goal in cache
  static Future<void> updateSavingInCache(int id, Map<String, dynamic> updatedData) async {
    final cached = await getCachedSavings();
    if (cached == null) return;

    final goals = List<Map<String, dynamic>>.from(cached['goals'] ?? []);
    bool updated = false;

    for (int i = 0; i < goals.length; i++) {
      if (goals[i]['id']?.toString() == id.toString()) {
        final curr = double.tryParse((updatedData['current_amount'] ?? goals[i]['current_amount']).toString()) ?? 0.0;
        final targ = double.tryParse((updatedData['target_amount'] ?? goals[i]['target_amount']).toString()) ?? 1.0;
        goals[i] = {
          ...goals[i],
          ...updatedData,
          // Recalculate percentage if amounts changed
          'saved_percentage': (curr / targ * 100).clamp(0, 100),
          'is_completed': curr >= targ,
        };
        updated = true;
        break;
      }
    }

    if (updated) {
      await cacheSavings({
        'goals': goals,
        'currency_symbol': cached['currency_symbol'],
      });
    }
  }

  /// Add money to a saving goal in cache
  static Future<void> addMoneyToSavingInCache(int id, double amount, {String? notes}) async {
    final cached = await getCachedSavings();
    if (cached == null) return;

    final goals = List<Map<String, dynamic>>.from(cached['goals'] ?? []);
    bool updated = false;

    for (int i = 0; i < goals.length; i++) {
      if (goals[i]['id']?.toString() == id.toString()) {
        final current = double.tryParse(goals[i]['current_amount'].toString()) ?? 0.0;
        final target = double.tryParse(goals[i]['target_amount'].toString()) ?? 1.0;
        final newCurrent = current + amount;
        
        goals[i]['current_amount'] = newCurrent;
        goals[i]['saved_percentage'] = (newCurrent / target * 100).clamp(0, 100);
        goals[i]['is_completed'] = newCurrent >= target;
        
        // Add to history logs
        final history = List<Map<String, dynamic>>.from(goals[i]['history'] ?? []);
        history.insert(0, {
          'amount': amount.toStringAsFixed(2),
          'date': DateTime.now().toIso8601String(),
          'notes': notes ?? 'Added money',
        });
        goals[i]['history'] = history;
        
        updated = true;
        break;
      }
    }

    if (updated) {
      await cacheSavings({
        'goals': goals,
        'currency_symbol': cached['currency_symbol'],
      });
    }
  }

  // ─── Sync Queue ──────────────────────────────────────────────────────

  /// Get pending sync operations
  static Future<List<Map<String, dynamic>>> getSyncQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_syncQueueKey);
    if (raw == null) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  /// Add an operation to the sync queue
  static Future<void> addToSyncQueue(Map<String, dynamic> operation) async {
    final queue = await getSyncQueue();
    queue.add(operation);
    await saveSyncQueue(queue);
  }

  /// Save the entire sync queue (overwrites)
  static Future<void> saveSyncQueue(List<Map<String, dynamic>> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_syncQueueKey, jsonEncode(queue));
  }

  /// Remove a processed operation from queue by its id
  static Future<void> removeFromSyncQueue(String operationId) async {
    final queue = await getSyncQueue();
    queue.removeWhere((op) => op['id'] == operationId);
    await saveSyncQueue(queue);
  }

  /// Clear the entire sync queue
  static Future<void> clearSyncQueue() async {
    await _clear(_syncQueueKey);
  }

  // ─── Clear All ───────────────────────────────────────────────────────

  /// Clear all cached data (used on logout)
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dashboardKey);
    await prefs.remove(_transactionsKey);
    await prefs.remove(_categoriesKey);
    await prefs.remove(_budgetsKey);
    await prefs.remove(_savingsKey);
    await prefs.remove(_splitGroupsKey);
    await prefs.remove(_syncQueueKey);
  }
}
