/// Home: greeting → spend hero card (this month, last 7 days) → Add expense / Scan →
/// one-tap repeats → payments to review → recent → budget, insights, charts → shortcuts.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import '../models/dashboard.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../widgets/transaction_tile.dart';
import '../widgets/thanos_snap_widget.dart';
import '../utils/icon_mapper.dart';
import '../utils/app_toast.dart';
import '../services/connectivity_service.dart';
import 'reports_screen.dart';
import '../services/sync_service.dart';
import '../services/widget_service.dart';
import 'transaction_form_screen.dart';
import 'quick_add_screen.dart';
import 'auto_track_review_screen.dart';
import '../models/category.dart';
import '../services/auto_expense_service.dart';
import '../services/receipt_service.dart';
import '../services/transaction_store.dart';
import 'package:image_picker/image_picker.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int)? onTabChange;

  const DashboardScreen({super.key, this.onTabChange});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  DashboardData? _data;
  bool _isLoading = true;
  StreamSubscription<void>? _syncSub;
  final Map<int, GlobalKey<ThanosSnapWidgetState>> _snapKeys = {};

  /// Spending of the last 7 days (oldest first) and their weekday letters.
  List<double> _week = List.filled(7, 0);
  List<String> _weekDays = List.filled(7, '');

  /// Frequent expenses offered as one-tap repeats.
  List<_Again> _again = const [];
  int _reviewCount = 0;
  StreamSubscription<void>? _autoSub;

  void initState() {
    super.initState();
    _loadDashboard();

    // Listen for background sync completions to refresh UI immediately
    _syncSub = SyncService.onSyncComplete.listen((_) {
      debugPrint('[Dashboard] Background sync detected — refreshing data...');
      _loadDashboard();
    });
    _autoSub = AutoExpenseService.changes.listen((_) => _loadExtras());
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _autoSub?.cancel();
    super.dispose();
  }

  /// Public method for parent to trigger a data reload.
  void reload() => _loadDashboard();

  Future<void> _loadDashboard() async {
    final cached = await CacheService.getCachedDashboard();
    final cachedUser = await CacheService.getCachedUser();
    
    if (cached != null && mounted) {
      if (cachedUser != null) {
        cached['user'] = cachedUser;
      }
      final d = DashboardData.fromJson(cached);
      setState(() {
        _data = d;
        _isLoading = false;
        
      });

      _loadExtras();

      // Update home screen widget
      WidgetService.updateDashboard(
        totalBalance: double.tryParse(d.totalBalance.replaceAll(',', '')) ?? 0,
        totalIncome: double.tryParse(d.monthlyIncome.replaceAll(',', '')) ?? 0,
        totalExpense: double.tryParse(d.monthlyExpenses.replaceAll(',', '')) ?? 0,
        currencySymbol: d.currencySymbol,
      );
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Week bars, one-tap repeats and the review count, all from local data.
  Future<void> _loadExtras() async {
    final cached = await CacheService.getCachedTransactions();
    final txns = ((cached?['transactions'] as List?) ?? const []).whereType<Map>().toList();
    final today = DateUtils.dateOnly(DateTime.now());
    final week = List<double>.filled(7, 0);
    final days = List.generate(7, (i) => DateFormat('E').format(today.subtract(Duration(days: 6 - i)))[0]);
    final counts = <String, _Again>{};
    for (final t in txns) {
      if (t['type'] != 'expense') continue;
      final date = DateTime.tryParse(t['date']?.toString() ?? '')?.toLocal();
      final amount = double.tryParse(t['amount']?.toString() ?? '') ?? 0;
      if (date == null || amount <= 0) continue;
      final age = today.difference(DateUtils.dateOnly(date)).inDays;
      if (age >= 0 && age < 7) week[6 - age] += amount;
      if (age < 0 || age > 60) continue;
      final cat = t['category'] is Map ? Map<String, dynamic>.from(t['category'] as Map) : null;
      final note = (t['notes'] ?? '').toString().trim();
      final key = '${note.toLowerCase()}|${cat?['id']}|${amount.toStringAsFixed(2)}';
      final prev = counts[key];
      counts[key] = _Again(
        label: note.isNotEmpty ? note : (cat?['name']?.toString() ?? 'Other'),
        amount: amount,
        note: note,
        category: cat == null ? null : CategoryModel.fromJson(cat),
        count: (prev?.count ?? 0) + 1,
      );
    }
    final again = counts.values.where((a) => a.count >= 2).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    var review = 0;
    if (await AutoExpenseService.isAvailable()) review = await AutoExpenseService.reviewCount();
    if (!mounted) return;
    setState(() {
      _week = week;
      _weekDays = days;
      _again = again.take(4).toList();
      _reviewCount = review;
    });
  }

  String _money(num v, String symbol) {
    final whole = v == v.roundToDouble();
    final f = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: whole ? 0 : 2);
    return '$symbol${f.format(v)}';
  }

  double _num(String s) => double.tryParse(s.replaceAll(',', '')) ?? 0;

  Future<void> _openQuickAdd({String type = 'expense'}) async {
    final added = await QuickAddScreen.open(context, type: type);
    if (added && mounted) _loadDashboard();
  }

  Future<void> _scanReceipt() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final scan = await ReceiptService.recognize(picked.path);
    if (!mounted) return;
    if (scan == null) {
      AppToast.error(context, 'Could not read text from this image.');
      return;
    }
    await ReceiptService.openForm(context, scan: scan);
    if (mounted) _loadDashboard();
  }

  Future<void> _addAgain(_Again a, String symbol) async {
    HapticFeedback.mediumImpact();
    final id = await TransactionStore.create(
      amount: a.amount,
      type: 'expense',
      category: a.category,
      notes: a.note,
    );
    if (!mounted) return;
    await _loadDashboard();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('−${_money(a.amount, symbol)} added · ${a.label}'),
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await TransactionStore.remove(id);
            if (mounted) _loadDashboard();
          },
        ),
      ));
  }

  Future<void> _openReview() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AutoTrackReviewScreen()));
    if (mounted) _loadDashboard();
  }

  // ─── Home: top part ──────────────────────────────────────────────────────

  Widget _header(DashboardData d) {
    final initial = d.user.displayName.trim().isEmpty ? '?' : d.user.displayName.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 16),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Semantics(
              button: true,
              label: 'Profile and settings',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () async {
                  await Navigator.pushNamed(context, '/profile');
                  if (mounted) _loadDashboard();
                },
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.dark, shape: BoxShape.circle),
                  child: Text(initial, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Good ${d.greeting.toLowerCase()}', style: AppText.rowSub),
                  Text(
                    d.user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: 'Settings',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () async {
                  await Navigator.pushNamed(context, '/profile');
                  if (mounted) _loadDashboard();
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: AppColors.card, shape: BoxShape.circle, boxShadow: AppShadows.soft),
                  child: const Icon(Icons.settings_rounded, size: 22, color: AppColors.dark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(DashboardData d) {
    final spent = _num(d.monthlyExpenses);
    final income = _num(d.monthlyIncome);
    final limit = d.monthlyBudgetLimit;
    final maxDay = _week.fold<double>(0, math.max);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(AppRadius.xxxl),
        boxShadow: AppShadows.elevated,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Spent this month', style: TextStyle(fontSize: 13, color: AppColors.darkMuted)),
              ),
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.darkCard, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  DateFormat('MMMM').format(DateTime.now()),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(_money(spent, d.currencySymbol), style: AppText.hero.copyWith(color: Colors.white)),
                if (limit > 0) ...[
                  const SizedBox(width: 8),
                  Text('of ${_money(limit, d.currencySymbol)}',
                      style: const TextStyle(fontSize: 13, color: AppColors.darkMuted)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 74,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final today = i == 6;
                final h = maxDay <= 0 ? 6.0 : math.max(6.0, 52 * (_week[i] / maxDay));
                return Expanded(
                  child: Tooltip(
                    message: _money(_week[i], d.currencySymbol),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                            height: h,
                            decoration: BoxDecoration(
                              color: today ? AppColors.accent : AppColors.darkCardRaised,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _weekDays[i],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: today ? AppColors.accent : AppColors.darkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _heroStat(
                  limit > 0 ? 'Left to spend' : 'Balance',
                  limit > 0 ? _money(math.max(0, limit - spent), d.currencySymbol) : _money(_num(d.totalBalance), d.currencySymbol),
                  Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _heroStat('Money in', '+${_money(income, d.currencySymbol)}', AppColors.accent)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.darkCard, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.darkMuted)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            ),
          ],
        ),
      );

  Widget _actions() {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Add expense',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                _openQuickAdd();
              },
              child: Container(
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: AppShadows.accent,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(color: AppColors.dark, shape: BoxShape.circle),
                      child: const Icon(Icons.add_rounded, size: 20, color: AppColors.accent),
                    ),
                    const SizedBox(width: 10),
                    const Text('Add expense', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.dark)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          label: 'Scan receipt',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: _scanReceipt,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(AppRadius.xl), boxShadow: AppShadows.soft),
              child: const Icon(Icons.document_scanner_rounded, size: 24, color: AppColors.dark),
            ),
          ),
        ),
      ],
    );
  }

  Widget _againRow(DashboardData d) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Add again in one tap', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: _again.map((a) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Semantics(
                    button: true,
                    label: 'Add ${a.label} ${_money(a.amount, d.currencySymbol)} again',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => _addAgain(a, d.currencySymbol),
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.only(left: 6, right: 14),
                        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(21), boxShadow: AppShadows.soft),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: const BoxDecoration(color: AppColors.categoryFill, shape: BoxShape.circle),
                              child: Icon(IconMapper.map(a.category?.icon ?? 'category'), size: 17, color: AppColors.categoryInk),
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 120),
                              child: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
                            ),
                            Text(' ${_money(a.amount, d.currencySymbol)}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.text)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          onTap: _openReview,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.bolt_rounded, size: 22, color: AppColors.dark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _reviewCount == 1 ? '1 payment to review' : '$_reviewCount payments to review',
                        style: AppText.rowTitle,
                      ),
                      const Text('Found in your payment notifications', style: AppText.rowSub),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _recent(DashboardData d) {
    final list = d.recentTransactions.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: Row(
            children: [
              const Expanded(child: Text('Recent', style: AppText.section)),
              TextButton(
                onPressed: () => widget.onTabChange?.call(1),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                child: const Text('See all', style: TextStyle(decoration: TextDecoration.underline)),
              ),
            ],
          ),
        ),
        if (list.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(AppRadius.xxl)),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                  child: const Icon(Icons.receipt_long_rounded, color: AppColors.dark),
                ),
                const SizedBox(height: 10),
                const Text('No transactions yet', style: AppText.rowTitle),
                const SizedBox(height: 4),
                const Text('Tap “Add expense” to log your first one.', style: AppText.rowSub, textAlign: TextAlign.center),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.xxl),
              boxShadow: AppShadows.soft,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 68, endIndent: 14),
                  Builder(builder: (_) {
                    final txn = list[i];
                    final snapKey = _snapKeys.putIfAbsent(txn.id, () => GlobalKey<ThanosSnapWidgetState>());
                    return ThanosSnapWidget(
                      key: snapKey,
                      child: TransactionTile(
                        transaction: txn,
                        currencySymbol: d.currencySymbol,
                        showActions: true,
                        card: false,
                        onTap: () => TransactionFormScreen.show(context, transactionId: txn.id, onSaved: _loadDashboard),
                        onEdit: () => TransactionFormScreen.show(context, transactionId: txn.id, onSaved: _loadDashboard),
                        onDelete: () => _deleteTransaction(txn.id, snapKey: snapKey),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _handleRefresh() async {
    await SyncService.syncAll();
    await _loadDashboard();
  }

  /// Calculates a "nice" interval for chart axes (like Chart.js/Django)
  double _getNiceInterval(double max) {
    if (max <= 0) return 1000;
    // Aim for 4-5 ticks
    double rawInterval = max / 4;
    double exponent = (math.log(rawInterval) / math.ln10).floorToDouble();
    double fraction = rawInterval / math.pow(10, exponent);
    
    double niceFraction;
    if (fraction < 1.5) niceFraction = 1;
    else if (fraction < 3) niceFraction = 2;
    else if (fraction < 7) niceFraction = 5;
    else niceFraction = 10;
    
    return niceFraction * math.pow(10, exponent);
  }

  double _getNiceMax(double max, double interval) {
    if (max <= 0) return 4000;
    return (math.max(max, 1.0) / interval).ceil() * interval;
  }

  Future<void> _deleteTransaction(int id, {GlobalKey<ThanosSnapWidgetState>? snapKey}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.xxl),
            ),
            title: const Text('Delete Transaction'),
            content: const Text(
              'Are you sure you want to delete this transaction?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      if (snapKey != null) {
        await snapKey.currentState?.startSnap();
      }
      
      HapticFeedback.mediumImpact();
      
      // Offline mode: queue deletion
      await SyncService.queueOperation(
        action: 'delete',
        entity: 'transaction',
        entityId: id,
      );

      // Trigger sync if online
      if (ConnectivityService.isOnline) {
        SyncService.syncAll();
      }

      // Optimistic Update
      if (_data != null) {
        final txn = _data!.recentTransactions.firstWhere((t) => t.id == id);
        await CacheService.reverseDashboardImpact(
          txn.type, 
          double.tryParse(txn.amount) ?? 0.0, 
          id,
          categoryName: txn.category.name,
        );
        if (txn.type == 'expense') {
          await CacheService.updateBudgetOptimistically(
            txn.category.id, 
            double.tryParse(txn.amount) ?? 0.0, 
            isDelete: true
          );
        }
        final cachedTxns = await CacheService.getCachedTransactions();
        if (cachedTxns != null) {
          final list = List<Map<String, dynamic>>.from(cachedTxns['transactions'] ?? []);
          list.removeWhere((t) => t['id'] == id);
          // The list already holds every unsynced entry; re-adding "unsynced" items
          // here would bring back a deleted offline-created transaction.
          await CacheService.cacheTransactions({
            'transactions': list,
            'currency_symbol': cachedTxns['currency_symbol'],
          }, preserveUnsynced: false);
        }
      }

      // Reload dashboard data
      await _loadDashboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildSkeleton();
    if (_data == null) return _buildEmpty();

    final d = _data!;

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: AppColors.dark,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(d),
            _hero(d),
            const SizedBox(height: 16),
            _actions(),
            if (_again.isNotEmpty) _againRow(d),
            if (_reviewCount > 0) _reviewRow(),
            _recent(d),
            const SizedBox(height: 24),

            // ─── Overall Monthly Budget ─────────────────────────────
            if (d.monthlyBudgetLimit > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadius.xxl),
                  boxShadow: AppShadows.card,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                          child: const Icon(
                            Icons.track_changes_rounded,
                            size: 18,
                            color: AppColors.dark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Current Month Budget',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${d.currencySymbol}${d.monthlyBudgetSpent.toStringAsFixed(0)} spent',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        Text(
                          '${((d.monthlyBudgetSpent / d.monthlyBudgetLimit) * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: d.monthlyBudgetSpent > d.monthlyBudgetLimit ? AppColors.error : AppColors.text,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: (d.monthlyBudgetLimit > 0 ? (d.monthlyBudgetSpent / d.monthlyBudgetLimit) : 0.0).clamp(0.0, 1.0),
                      backgroundColor: AppColors.surface,
                      color: AppColors.dark,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Spent so far',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                        Text(
                          'Limit: ${d.currencySymbol}${d.monthlyBudgetLimit.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // ─── Budget Warnings ────────────────────────────────
            if (d.budgetWarnings.isNotEmpty)
              ...d.budgetWarnings.map((w) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding:
                      const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(AppRadius.xxl),
                    boxShadow: AppShadows.card,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          IconMapper.map(w['icon'] ?? 'category'),
                          size: 18,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${w['category']} budget exceeded!',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),

            // ─── Insights ───────────────────────────────────────
            if (d.insights.isNotEmpty)
              ...d.insights.map(
                (insight) => Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(AppRadius.xxl),
                    boxShadow: AppShadows.card,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lightbulb_outline, size: 18, color: AppColors.dark),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          insight,
                          style: const TextStyle(fontSize: 14, color: AppColors.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ─── Charts ─────────────────────────────────────────

            // Spending by Category (horizontal bar)
            if (d.pieLabels.isNotEmpty) ...[
              Builder(builder: (context) {
                final max = d.pieValues.isEmpty ? 0.0 : d.pieValues.fold(0.0, math.max);
                final interval = _getNiceInterval(max);
                final chartMax = _getNiceMax(max, interval);

                return _ChartCard(
                  icon: Icons.bar_chart,
                  title: 'Spending by Category',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      height: 220,
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: BarChart(
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOutQuart,
                          BarChartData(
                            maxY: chartMax,
                            alignment: BarChartAlignment.spaceAround,
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipColor: (_) => AppColors.dark,
                                tooltipPadding: const EdgeInsets.all(8),
                                tooltipMargin: 8,
                                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                  return BarTooltipItem(
                                    '${d.pieLabels[group.x.toInt()]}\n${d.currencySymbol}${rod.toY.toStringAsFixed(0)}',
                                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  );
                                },
                              ),
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 80,
                                  getTitlesWidget: (value, meta) {
                                    final idx = value.toInt();
                                    if (idx >= 0 && idx < d.pieLabels.length) {
                                      return RotatedBox(
                                        quarterTurns: -1,
                                        child: Padding(
                                          padding: const EdgeInsets.only(right: 8),
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              d.pieLabels[idx],
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                color: AppColors.text,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),
                              rightTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  interval: interval,
                                  reservedSize: 32,
                                  getTitlesWidget: (value, meta) {
                                    if (value > chartMax) return const SizedBox.shrink();
                                    return RotatedBox(
                                      quarterTurns: -1,
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          NumberFormat.decimalPattern().format(value),
                                          style: const TextStyle(fontSize: 10, color: AppColors.muted),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              drawHorizontalLine: true,
                              horizontalInterval: interval,
                              getDrawingHorizontalLine: (_) => FlLine(
                                color: Colors.black.withOpacity(0.04),
                                strokeWidth: 1,
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            barGroups: List.generate(d.pieLabels.length, (i) {
                              final value = i < d.pieValues.length ? d.pieValues[i] : 0.0;
                              
                              return BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: value,
                                    color: AppColors.dark,
                                    width: d.pieLabels.length <= 3 ? 28 : 14,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],

            // Income vs Expenses (bar chart)
            if (d.barLabels.isNotEmpty) ...[
              Builder(builder: (context) {
                final max = [...d.barIncome, ...d.barExpense].fold(0.0, math.max);
                final interval = _getNiceInterval(max);
                final chartMax = _getNiceMax(max, interval);

                return _ChartCard(
                  icon: Icons.insert_chart_outlined,
                  title: 'Income vs Expenses',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 200,
                          child: BarChart(
                            duration: const Duration(milliseconds: 800),
                            curve: Curves.easeOutQuart,
                            BarChartData(
                              maxY: chartMax,
                              alignment: BarChartAlignment.spaceAround,
                              barTouchData: BarTouchData(
                                enabled: true,
                                touchTooltipData: BarTouchTooltipData(
                                  getTooltipColor: (_) => AppColors.dark,
                                  tooltipPadding: const EdgeInsets.all(8),
                                  tooltipMargin: 8,
                                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                    final isIncome = rodIndex == 0;
                                    final label = isIncome ? 'Income' : 'Expense';
                                    return BarTooltipItem(
                                      '$label\n${d.currencySymbol}${rod.toY.toStringAsFixed(0)}',
                                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                    );
                                  },
                                ),
                              ),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final idx = value.toInt();
                                      if (idx >= 0 && idx < d.barLabels.length) {
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Text(
                                            d.barLabels[idx],
                                            style: const TextStyle(fontSize: 10, color: AppColors.muted),
                                          ),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    interval: interval,
                                    reservedSize: 48,
                                    getTitlesWidget: (value, meta) {
                                      if (value > chartMax) return const SizedBox.shrink();
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: Text(
                                          NumberFormat.decimalPattern().format(value),
                                          style: const TextStyle(fontSize: 10, color: AppColors.muted),
                                          textAlign: TextAlign.right,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                horizontalInterval: interval,
                                getDrawingHorizontalLine: (_) => FlLine(
                                  color: Colors.black.withOpacity(0.04),
                                  strokeWidth: 1,
                                ),
                              ),
                              borderData: FlBorderData(show: false),
                              barGroups: List.generate(d.barLabels.length, (i) {
                                return BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: d.barIncome[i],
                                      color: AppColors.accent,
                                      width: 10,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    BarChartRodData(
                                      toY: d.barExpense[i],
                                      color: AppColors.dark,
                                      width: 10,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ],
                                );
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _LegendItem(color: AppColors.accent, label: 'Income'),
                            SizedBox(width: 20),
                            _LegendItem(color: AppColors.dark, label: 'Expenses'),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],

            // 30-Day Spending Trend (line chart)
            if (d.lineValues.isNotEmpty) ...[
              Builder(builder: (context) {
                final max = d.lineValues.isEmpty ? 0.0 : d.lineValues.fold(0.0, math.max);
                final interval = _getNiceInterval(max);
                final chartMax = _getNiceMax(max, interval);

                return _ChartCard(
                  icon: Icons.show_chart,
                  title: '30-Day Spending Trend',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      height: 160,
                      child: LineChart(
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOutQuart,
                        LineChartData(
                          maxY: chartMax,
                          lineTouchData: LineTouchData(
                            enabled: true,
                            handleBuiltInTouches: true,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (_) => AppColors.dark,
                              tooltipPadding: const EdgeInsets.all(8),
                              getTooltipItems: (touchedSpots) {
                                return touchedSpots.map((spot) {
                                  return LineTooltipItem(
                                    '${d.lineLabels[spot.x.toInt()]}\n${d.currencySymbol}${spot.y.toStringAsFixed(0)}',
                                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  );
                                }).toList();
                              },
                            ),
                          ),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: interval,
                            getDrawingHorizontalLine: (_) => FlLine(
                              color: Colors.black.withValues(alpha: 0.1),
                              strokeWidth: 1,
                              dashArray: [4, 4],
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 5,
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  if (idx >= 0 && idx < d.lineLabels.length) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        d.lineLabels[idx],
                                        style: const TextStyle(fontSize: 10, color: AppColors.muted),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: interval,
                                reservedSize: 48,
                                getTitlesWidget: (value, meta) {
                                  if (value > chartMax) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Text(
                                      NumberFormat.decimalPattern().format(value),
                                      style: const TextStyle(fontSize: 10, color: AppColors.muted),
                                      textAlign: TextAlign.right,
                                    ),
                                  );
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: List.generate(
                                d.lineValues.length,
                                (i) => FlSpot(i.toDouble(), d.lineValues[i]),
                              ),
                              isCurved: false,
                              isStepLineChart: true,
                              lineChartStepData: const LineChartStepData(stepDirection: 0),
                              color: AppColors.dark,
                              barWidth: 2.5,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: AppColors.accent.withValues(alpha: 0.15),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],

            // ─── Shortcuts ──────────────────────────────────────
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 10),
              child: Text('Shortcuts', style: AppText.section),
            ),
            GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _QuickLink(
                  icon: Icons.donut_large_rounded,
                  label: 'Budgets',
                  subtitle: 'Set spending limits',
                  onTap: () => widget.onTabChange?.call(2),
                ),
                _QuickLink(
                  icon: Icons.group_rounded,
                  label: 'Friends',
                  subtitle: 'Manage friends',
                  onTap: () => widget.onTabChange?.call(3),
                ),
                _QuickLink(
                  icon: Icons.category_rounded,
                  label: 'Categories',
                  subtitle: 'Organize spending',
                  onTap: () => Navigator.pushNamed(context, '/categories'),
                ),
                _QuickLink(
                  icon: Icons.pie_chart_rounded,
                  label: 'Reports',
                  subtitle: 'Analyze spending',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())),
                ),
                _QuickLink(
                  icon: Icons.groups_rounded,
                  label: 'Split Groups',
                  subtitle: 'Share expenses',
                  onTap: () => widget.onTabChange?.call(4),
                ),
                _QuickLink(
                  icon: Icons.ios_share_rounded,
                  label: 'Export',
                  subtitle: 'Download CSV',
                  onTap: () => _showExportDialog(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const _ExportBottomSheet(),
    );
  }

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _shimmer(96, 12),
                  const SizedBox(height: 8),
                  _shimmer(192, 32),
                ],
              ),
              _shimmer(48, 48, radius: AppRadius.xl),
            ],
          ),
          const SizedBox(height: 16),
          _shimmer(double.infinity, 200, radius: AppRadius.xxxl),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _shimmer(double.infinity, 100, radius: AppRadius.xxl)),
              const SizedBox(width: 12),
              Expanded(child: _shimmer(double.infinity, 100, radius: AppRadius.xxl)),
              const SizedBox(width: 12),
              Expanded(child: _shimmer(double.infinity, 100, radius: AppRadius.xxl)),
            ],
          ),
          const SizedBox(height: 16),
          _shimmer(double.infinity, 220, radius: AppRadius.xxl),
          const SizedBox(height: 16),
          _shimmer(double.infinity, 200, radius: AppRadius.xxl),
          const SizedBox(height: 16),
          ...List.generate(
            3,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _shimmer(double.infinity, 72, radius: AppRadius.xxl),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shimmer(double width, double height, {double radius = 8}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(radius)),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          const Text('Something went wrong', style: TextStyle(color: AppColors.muted), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadDashboard, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(child: Text('No data available', style: TextStyle(color: AppColors.muted)));
  }
}

class _ChartCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _ChartCard({required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                child: Icon(icon, size: 16, color: AppColors.dark),
              ),
              const SizedBox(width: 10),
              Text(title, style: AppText.section.copyWith(fontSize: 15)),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;

  const _QuickLink({required this.icon, required this.label, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, $subtitle',
      excludeSemantics: true,
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                  child: Icon(icon, size: 21, color: AppColors.dark),
                ),
                const SizedBox(height: 8),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text)),
                const SizedBox(height: 2),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ],
    );
  }
}

class _ExportBottomSheet extends StatefulWidget {
  const _ExportBottomSheet();

  @override
  State<_ExportBottomSheet> createState() => _ExportBottomSheetState();
}

class _ExportBottomSheetState extends State<_ExportBottomSheet> {
  String _selectedPeriod = 'current_month';
  DateTime? _startDate;
  DateTime? _endDate;

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              onPrimary: AppColors.dark,
              surface: AppColors.card,
              onSurface: AppColors.text,
            ),
          ),
          child: child!,
        );
      },
    );
    if (range != null) {
      setState(() {
        _selectedPeriod = 'custom';
        _startDate = range.start;
        _endDate = range.end;
      });
    }
  }

  bool _isExporting = false;

  Future<void> _export() async {
    setState(() => _isExporting = true);
    
    final result = await ApiService.downloadCSV(
      _selectedPeriod,
      startDate: _startDate?.toIso8601String().split('T')[0],
      endDate: _endDate?.toIso8601String().split('T')[0],
    );

    if (!mounted) return;
    setState(() => _isExporting = false);

    if (result.isSuccess && result.data != null) {
      try {
        String? finalPath;
        final fileName = 'espere_transactions_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
        
        if (Platform.isAndroid) {
          var status = await Permission.storage.request();
          
          // On Android 11+ (SDK 30+), storage permission often returns denied even if we can write to app-specific dirs.
          // To write to public /Download, we try MANAGE_EXTERNAL_STORAGE as a fallback.
          if (status.isDenied) {
            status = await Permission.manageExternalStorage.request();
          }

          if (status.isGranted) {
            final dirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
            if (dirs != null && dirs.isNotEmpty) {
              finalPath = '${dirs.first.path}/$fileName';
            } else {
              // Direct path attempt if dirs is empty
              finalPath = '/storage/emulated/0/Download/$fileName';
            }
          }
        }
        
        if (finalPath == null) {
          final directory = await getApplicationDocumentsDirectory();
          finalPath = '${directory.path}/$fileName';
        }

        final file = File(finalPath);
        await file.writeAsString(result.data!);
        
        if (mounted) {
          AppToast.success(context, 'Exported: $fileName');
        }
        
        // Also share it for convenience
        await Share.shareXFiles(
          [XFile(finalPath)],
          subject: 'Espere Transactions Export',
          text: 'Here is your exported transaction history from Espere.',
        );
        
        if (mounted) Navigator.pop(context);
      } catch (e) {
        debugPrint('Export Save Error: $e');
        if (mounted) AppToast.error(context, 'Failed to save file locally.');
      }
    } else {
      if (mounted) {
        AppToast.error(context, result.error ?? 'Export failed.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Export Transactions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Select a period to download your CSV report.',
            style: TextStyle(fontSize: 14, color: AppColors.muted),
          ),
          const SizedBox(height: 16),

          _buildOption('current_month', 'Current Month', Icons.calendar_today),
          _buildOption('last_month', 'Last Month', Icons.history),
          _buildOption('3m', 'Last 3 Months', Icons.query_builder),
          _buildOption('6m', 'Last 6 Months', Icons.timelapse),
          _buildOption('all', 'All Time', Icons.all_inclusive),
          
          GestureDetector(
            onTap: _pickDateRange,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _selectedPeriod == 'custom' ? AppColors.accent.withOpacity(0.1) : AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _selectedPeriod == 'custom' ? AppColors.accent : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.date_range,
                    color: _selectedPeriod == 'custom' ? AppColors.accent : AppColors.muted,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Custom Date Range',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _selectedPeriod == 'custom' ? AppColors.accent : AppColors.text,
                          ),
                        ),
                        if (_startDate != null && _endDate != null)
                          Text(
                            '${DateFormat('MMM d').format(_startDate!)} - ${DateFormat('MMM d').format(_endDate!)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                      ],
                    ),
                  ),
                  if (_selectedPeriod == 'custom')
                    const Icon(Icons.check_circle, color: AppColors.accent, size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isExporting ? null : _export,
              child: _isExporting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: AppColors.dark,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Export CSV'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(String period, String label, IconData icon) {
    final isSelected = _selectedPeriod == period;
    return GestureDetector(
      onTap: () => setState(() => _selectedPeriod = period),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent.withOpacity(0.1) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.accent : AppColors.muted,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isSelected ? AppColors.accent : AppColors.text,
              ),
            ),
            const Spacer(),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColors.accent, size: 20),
          ],
        ),
      ),
    );
  }
}

/// A frequent expense offered as a one-tap repeat on Home.
class _Again {
  final String label;
  final double amount;
  final String note;
  final CategoryModel? category;
  final int count;
  const _Again({required this.label, required this.amount, required this.note, required this.category, required this.count});
}
