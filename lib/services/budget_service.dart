/// Budgets, read the same way everywhere (Budgets screen, Add expense, Home, alerts).
///
/// - What is spent is counted from the transactions saved on this phone, so a new or
///   edited entry shows up at once, online or not.
/// - The whole-month budget ("overall") is kept with the budgets cache and saved to the
///   server through the sync queue.
/// - [checkAfterSave] posts an alert when a save takes a budget past 80% or 100%.
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cache_service.dart';
import 'connectivity_service.dart';
import 'notification_inbox.dart';
import 'sync_service.dart';

class BudgetInfo {
  final int? id;
  final int? categoryId;
  final String name;
  final String icon;
  final double limit;
  final double spent;
  final bool repeat;
  final bool carryOver;
  final double carried;

  /// Day of the month the spending went past the limit (null if it has not).
  final int? ranOutDay;

  const BudgetInfo({
    this.id,
    this.categoryId,
    required this.name,
    this.icon = 'category',
    required this.limit,
    required this.spent,
    this.repeat = true,
    this.carryOver = false,
    this.carried = 0,
    this.ranOutDay,
  });

  double get left => math.max(0, limit - spent);
  double get fraction => limit <= 0 ? 0 : spent / limit;
  int get percent => (fraction * 100).round();
}

class BudgetService {
  BudgetService._();

  static const alertsPrefKey = 'enable_budget_alerts';
  static const _alertedKey = 'budget_alerted';
  static const _channel = MethodChannel('com.example.espere_app/reminders');

  static String monthKey(DateTime m) => '${m.year}-${m.month.toString().padLeft(2, '0')}';

  static double _num(Object? v) => double.tryParse(v?.toString() ?? '') ?? 0;

  /// Expenses of [month] per category and day of the month (category id → day → amount).
  static Future<Map<int, Map<int, double>>> _daily(DateTime month) async {
    final cached = await CacheService.getCachedTransactions();
    final list = ((cached?['transactions'] as List?) ?? const []).whereType<Map>();
    final out = <int, Map<int, double>>{};
    for (final t in list) {
      if (t['type'] != 'expense') continue;
      final at = DateTime.tryParse(t['date']?.toString() ?? '')?.toLocal();
      if (at == null || at.year != month.year || at.month != month.month) continue;
      final cat = t['category'];
      final id = cat is Map ? int.tryParse(cat['id']?.toString() ?? '') : null;
      if (id == null) continue;
      final days = out.putIfAbsent(id, () => {});
      days[at.day] = (days[at.day] ?? 0) + _num(t['amount']);
    }
    return out;
  }

  /// Expenses of [month] from the phone's copy: total and per category id.
  static Future<(double, Map<int, double>)> _spent(DateTime month) async {
    final cached = await CacheService.getCachedTransactions();
    final list = ((cached?['transactions'] as List?) ?? const []).whereType<Map>();
    var total = 0.0;
    final byCat = <int, double>{};
    for (final t in list) {
      if (t['type'] != 'expense') continue;
      final at = DateTime.tryParse(t['date']?.toString() ?? '')?.toLocal();
      if (at == null || at.year != month.year || at.month != month.month) continue;
      final v = _num(t['amount']);
      total += v;
      final cat = t['category'];
      final id = cat is Map ? int.tryParse(cat['id']?.toString() ?? '') : null;
      if (id != null) byCat[id] = (byCat[id] ?? 0) + v;
    }
    return (total, byCat);
  }

  /// The category budgets of [month] (this month when null), keyed by category id.
  static Future<Map<int, BudgetInfo>> byCategory([DateTime? month]) async {
    final m = month ?? DateTime.now();
    final cached = await CacheService.getCachedBudgets();
    final list = ((cached?['budgets'] as List?) ?? const []).whereType<Map>();
    final (_, spent) = await _spent(m);
    final daily = await _daily(m);
    int? ranOut(int catId, double limit) {
      final days = daily[catId];
      if (days == null || limit <= 0) return null;
      var sum = 0.0;
      for (var d = 1; d <= 31; d++) {
        sum += days[d] ?? 0;
        if (sum > limit) return d;
      }
      return null;
    }
    final out = <int, BudgetInfo>{};
    for (final b in list) {
      if (!(b['month']?.toString() ?? monthKey(m)).startsWith(monthKey(m))) continue;
      final cat = b['category'] is Map ? b['category'] as Map : const {};
      final catId = int.tryParse((cat['id'] ?? b['category_id'])?.toString() ?? '');
      if (catId == null) continue;
      out[catId] = BudgetInfo(
        id: int.tryParse(b['id']?.toString() ?? ''),
        categoryId: catId,
        name: cat['name']?.toString() ?? 'Category',
        icon: cat['icon']?.toString() ?? 'category',
        limit: _num(b['amount']),
        spent: spent[catId] ?? 0,
        repeat: b['repeat'] != false,
        carryOver: b['carry_over'] == true,
        carried: _num(b['carried']),
        ranOutDay: ranOut(catId, _num(b['amount'])),
      );
    }
    return out;
  }

  /// The whole-month budget (limit 0 when none is set) and the month's spending.
  static Future<BudgetInfo> overall([DateTime? month]) async {
    final m = month ?? DateTime.now();
    final cached = await CacheService.getCachedBudgets();
    final o = cached?['overall'];
    final (total, _) = await _spent(m);
    return BudgetInfo(name: 'Month', limit: o is Map ? _num(o['amount']) : 0, spent: total);
  }

  /// Saves the whole-month budget (0 removes it): at once on the phone, then on the server.
  static Future<void> setOverall(double amount) async {
    final cached = Map<String, dynamic>.from(await CacheService.getCachedBudgets() ?? {});
    final o = Map<String, dynamic>.from((cached['overall'] as Map?) ?? {});
    o['amount'] = amount.toStringAsFixed(2);
    cached['overall'] = o;
    await CacheService.cacheBudgets(cached);
    await SyncService.queueOperation(action: 'update', entity: 'budget_overall', data: {'amount': amount.toStringAsFixed(2)});
    if (ConnectivityService.isOnline) SyncService.syncAll();
  }

  /// What a category usually costs a month: the last three full months that had any
  /// spending in it, averaged. Returns the average and those monthly totals (oldest first).
  static Future<(double, List<double>)> suggestion(int categoryId) async {
    final now = DateTime.now();
    final months = <double>[];
    for (var k = 3; k >= 1; k--) {
      final m = DateTime(now.year, now.month - k);
      final (_, byCat) = await _spent(m);
      final v = byCat[categoryId] ?? 0;
      if (v > 0) months.add(v);
    }
    if (months.isEmpty) return (0.0, months);
    return (months.reduce((a, b) => a + b) / months.length, months);
  }

  /// Rounds a suggested amount to something people type (₹6,200 → ₹6,000 / ₹6,500).
  static List<double> suggestedChoices(double avg) {
    if (avg <= 0) return const [];
    final step = avg >= 20000 ? 1000.0 : (avg >= 2000 ? 500.0 : 100.0);
    final mid = (avg / step).round() * step;
    return {math.max(step, mid - step), mid, mid + step}.toList();
  }

  // ─── Alerts ──────────────────────────────────────────────────────────────

  static Future<bool> alertsOn() async =>
      (await SharedPreferences.getInstance()).getBool(alertsPrefKey) ?? true;

  static Future<void> setAlerts(bool on) async =>
      (await SharedPreferences.getInstance()).setBool(alertsPrefKey, on);

  /// After a save: if [categoryId]'s budget or the whole-month budget has now passed 80%
  /// or 100% for the first time this month, put an alert in the notification shade and in
  /// Notifications. Returns the message (for an in-app toast), or null.
  static Future<String?> checkAfterSave({int? categoryId, String? symbol}) async {
    final now = DateTime.now();
    symbol ??= ((await CacheService.getCachedBudgets())?['currency_symbol'] as String?) ?? '₹';
    final prefs = await SharedPreferences.getInstance();
    final sent = (prefs.getStringList(_alertedKey) ?? const []).where((k) => k.startsWith(monthKey(now))).toSet();
    String? shown;

    Future<void> consider(String key, BudgetInfo b, String label) async {
      if (b.limit <= 0) return;
      final level = b.fraction >= 1 ? 100 : (b.fraction >= 0.8 ? 80 : 0);
      if (level == 0) return;
      final id = '${monthKey(now)}|$key|$level';
      if (sent.contains(id)) return;
      sent.add(id);
      final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day + 1;
      final sym = symbol!;
      final title = level == 100 ? '$label budget is over' : '$label budget ${b.percent}% used';
      final body = level == 100
          ? '${_money(b.spent, sym)} of ${_money(b.limit, sym)} spent this month.'
          : '${_money(b.spent, sym)} of ${_money(b.limit, sym)} spent. '
              '${_money(b.left, sym)} left for $daysLeft ${daysLeft == 1 ? 'day' : 'days'}'
              ' (≈ ${_money(b.left / daysLeft, sym)}/day).';
      shown ??= title;
      if (await alertsOn()) await _post(title, body);
    }

    if (categoryId != null) {
      final cat = (await byCategory())[categoryId];
      if (cat != null) await consider('c$categoryId', cat, cat.name);
    }
    await consider('all', await overall(), 'Monthly');
    await prefs.setStringList(_alertedKey, sent.toList());
    return shown;
  }

  static Future<void> _post(String title, String body) async {
    await NotificationInbox.addLocal(title: title, message: body, kind: 'budget_alert', action: 'open_budgets');
    try {
      await _channel.invokeMethod('notify', {'title': title, 'body': body});
    } catch (_) {
      // No native side (tests, older build): the Notifications list still has it.
    }
  }

  static String _money(double v, String symbol) {
    final r = v.round();
    final s = r.abs().toString();
    // Indian grouping: 1,23,456
    final last3 = s.length > 3 ? s.substring(s.length - 3) : s;
    var rest = s.length > 3 ? s.substring(0, s.length - 3) : '';
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${r < 0 ? '−' : ''}$symbol${[...parts, last3].join(',')}';
  }
}
