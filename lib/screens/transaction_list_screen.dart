/// Transaction List Screen — matches transaction_list.html.
///
/// Features: search bar, type/category filter chips, month navigator,
/// grouped transaction list with edit/delete actions
import 'dart:async';
import '../theme/motion.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/espere_action_button.dart';
import '../widgets/export_sheet.dart';
import '../services/auto_expense_service.dart';
import 'auto_track_review_screen.dart';
import '../widgets/espere_header.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import '../services/widget_service.dart';
import '../widgets/transaction_tile.dart';
import '../widgets/espere_filter_chip.dart';
import '../widgets/thanos_snap_widget.dart';
import 'transaction_form_screen.dart';
import '../utils/icon_mapper.dart';

class TransactionListScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const TransactionListScreen({super.key, this.onBack});

  @override
  State<TransactionListScreen> createState() => TransactionListScreenState();
}

class TransactionListScreenState extends State<TransactionListScreen> {
  List<TransactionModel> _transactions = [];
  List<CategoryModel> _categories = [];
  bool _isLoading = true;
  String _currencySymbol = '₹';
  StreamSubscription<void>? _syncSub;
  final Map<int, GlobalKey<ThanosSnapWidgetState>> _snapKeys = {};

  // Filters
  String _searchQuery = '';
  String _typeFilter = '';
  int? _categoryFilter;
  DateTime _currentMonth = DateTime.now();
  bool _showAll = false;

  final _searchController = TextEditingController();

  List<ReviewItem> _reviews = const [];
  StreamSubscription<void>? _autoSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadReviews();
    _autoSub = AutoExpenseService.changes.listen((_) => _loadReviews());

    // Listen for background sync completions
    _syncSub = SyncService.onSyncComplete.listen((_) {
      debugPrint('[TxnList] Background sync detected — refreshing data...');
      _loadTransactions();
    });
  }

  /// Public method for parent to trigger a data reload.
  void reload() {
    _loadTransactions();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    final items = await AutoExpenseService.reviewItems();
    if (mounted) setState(() => _reviews = items);
  }

  Future<void> _openReview() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AutoTrackReviewScreen()));
    _loadReviews();
    _loadTransactions();
  }

  Future<void> _confirmReview(ReviewItem item) async {
    AppHaptics.confirm();
    await AutoExpenseService.confirmReview(item, categoryId: item.txn.categoryId);
    await _loadReviews();
    await _loadTransactions();
  }

  Future<void> _ignoreReview(ReviewItem item) async {
    AppHaptics.tap();
    await AutoExpenseService.discardReview(item);
    await _loadReviews();
  }

  Future<void> _loadData() async {
    // 1. Load from cache instantly
    final cachedCats = await CacheService.getCachedCategories();
    final cachedTxns = await CacheService.getCachedTransactions();
    if (mounted && (cachedCats != null || cachedTxns != null)) {
      setState(() {
        if (cachedCats != null) {
          _categories = (cachedCats['categories'] as List)
              .map((c) => CategoryModel.fromJson(c as Map<String, dynamic>))
              .toList();
          _currencySymbol =
              (cachedCats['currency_symbol'] as String?) ?? '₹';
        }
        if (cachedTxns != null) {
          _transactions = (cachedTxns['transactions'] as List)
              .map((t) => TransactionModel.fromJson(t as Map<String, dynamic>))
              .toList();
          _currencySymbol =
              (cachedTxns['currency_symbol'] as String?) ?? _currencySymbol;
        }
      });
    }

    _loadTransactions();
  }

  Future<void> _handleRefresh() async {
    await SyncService.syncAll();
    await _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    // 1. Always check cache first to show optimistic updates
    final cached = await CacheService.getCachedTransactions();
    if (cached != null && mounted) {
      var list = (cached['transactions'] as List)
          .map((t) => TransactionModel.fromJson(t as Map<String, dynamic>))
          .toList();

      // UI-level De-duplication: 
      // Prevents showing duplicates if sync race conditions occurred in the past.
      final seenKeys = <String>{};
      final uniqueList = <TransactionModel>[];
      for (var t in list) {
        // Create a unique key based on Amount + Category + Date (minute precision)
        final amt = double.tryParse(t.amount.toString()) ?? 0;
        final key = "${amt.toStringAsFixed(2)}_${t.category.name}_${t.date.toUtc().toIso8601String().substring(0, 16)}";
        if (!seenKeys.contains(key)) {
          seenKeys.add(key);
          uniqueList.add(t);
        }
      }
      list = uniqueList;

      // Apply Filters Locally
      if (_typeFilter.isNotEmpty) {
        list = list.where((t) => t.type == _typeFilter).toList();
      }
      if (_categoryFilter != null) {
        list = list.where((t) => t.category.id == _categoryFilter).toList();
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        list = list.where((t) {
          return t.notes.toLowerCase().contains(query) ||
              t.category.name.toLowerCase().contains(query) ||
              t.amount.toString().contains(query);
        }).toList();
      }
      if (!_showAll) {
        final monthStr = DateFormat('yyyy-MM').format(_currentMonth);
        list = list.where((t) {
          return DateFormat('yyyy-MM').format(t.date) == monthStr;
        }).toList();
      }

      // Sort by date (descending) + ID (descending) for deterministic order
      list.sort((a, b) {
        int cmp = b.date.compareTo(a.date);
        if (cmp != 0) return cmp;
        return b.id.compareTo(a.id);
      });

      setState(() {
        _transactions = list;
        _currencySymbol = (cached['currency_symbol'] as String?) ?? '₹';
        _isLoading = false;
      });

      // Sync 2x2 financial metrics for current month to home-screen widget
      if (!_showAll && _currentMonth.year == DateTime.now().year && _currentMonth.month == DateTime.now().month) {
        final expenses = list.where((t) => t.type == 'expense');
        final incomes = list.where((t) => t.type == 'income');
        final totalSpend = expenses.fold(0.0, (sum, t) => sum + (double.tryParse(t.amount.toString()) ?? 0));
        final totalIncome = incomes.fold(0.0, (sum, t) => sum + (double.tryParse(t.amount.toString()) ?? 0));
        final now = DateTime.now();
        final todaySpend = expenses.where((t) {
          final d = t.date.toLocal();
          return d.year == now.year && d.month == now.month && d.day == now.day;
        }).fold(0.0, (sum, t) => sum + (double.tryParse(t.amount.toString()) ?? 0));
        final avgDaily = totalSpend / (now.day > 0 ? now.day : 1);

        WidgetService.syncQuickAddFinancialMetrics(
          totalSpend: totalSpend,
          totalIncome: totalIncome,
          todaySpend: todaySpend,
          avgDaily: avgDaily,
          currencySymbol: _currencySymbol,
        );
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
      _showAll = false;
      _isLoading = true;
      _transactions = [];
    });
    _loadTransactions();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
      _showAll = false;
      _isLoading = true;
      _transactions = [];
    });
    _loadTransactions();
  }

  void _toggleAll() {
    setState(() {
      _showAll = !_showAll;
      if (!_showAll) {
        _currentMonth = DateTime.now();
      }
      _isLoading = true;
      _transactions = [];
    });
    _loadTransactions();
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
      
      AppHaptics.confirm();
      
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

        // ─── Optimistic Update ──────────────────────────────────────────
        final txn = _transactions.firstWhere((t) => t.id == id);
        await CacheService.reverseDashboardImpact(
          txn.type, 
          double.tryParse(txn.amount) ?? 0.0, 
          id,
          categoryName: txn.category.name,
        );
        // Reverse budget impact if expense
        if (txn.type == 'expense') {
          await CacheService.updateBudgetOptimistically(
            txn.category.id, 
            double.tryParse(txn.amount) ?? 0.0, 
            isDelete: true
          );
        }
        // Also remove from transaction cache
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
        // ───────────────────────────────────────────────────────────────

      // Update local UI immediately
      setState(() {
        _transactions.removeWhere((t) => t.id == id);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _syncSub?.cancel();
    _autoSub?.cancel();
    super.dispose();
  }

  void _setType(String type) {
    if (_typeFilter == type) return;
    AppHaptics.tap();
    setState(() => _typeFilter = type);
    _loadTransactions();
  }

  String _dayLabel(DateTime d) {
    final today = DateUtils.dateOnly(DateTime.now());
    final day = DateUtils.dateOnly(d);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    return DateFormat(day.year == today.year ? 'EEE, d MMM' : 'EEE, d MMM yyyy').format(day).toUpperCase();
  }

  String _signed(double v) {
    final f = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: v == v.roundToDouble() ? 0 : 2);
    return '${v >= 0 ? '+' : '−'}$_currencySymbol${f.format(v.abs())}';
  }

  Widget _typeChip(String type, String label) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: EspereFilterChip(
          label: label,
          active: _typeFilter == type,
          dropdown: false,
          onTap: () => _setType(type),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Day sections, newest first (the list is already sorted by date).
    final sections = <(DateTime, List<TransactionModel>)>[];
    for (final t in _transactions) {
      final day = DateUtils.dateOnly(t.date.toLocal());
      if (sections.isEmpty || sections.last.$1 != day) {
        sections.add((day, [t]));
      } else {
        sections.last.$2.add(t);
      }
    }

    return Column(
      children: [
        EspereHeader(
          title: 'Activity',
          showBack: widget.onBack == null,
          onBack: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              widget.onBack?.call();
            }
          },
          trailing: EspereActionButton(
            icon: Icons.ios_share_rounded,
            tooltip: 'Export to CSV',
            onPressed: () => showExportSheet(context),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _handleRefresh,
            color: AppColors.dark,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              children: [
                _buildTopCard(),
                const SizedBox(height: 14),
                _searchRow(),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Row(
                    children: [
                      _typeChip('', 'All'),
                      _typeChip('expense', 'Spent'),
                      _typeChip('income', 'Received'),
                      EspereFilterChip(
                        label: _reviews.isEmpty ? 'To review' : 'To review · ${_reviews.length}',
                        icon: Icons.bolt_rounded,
                        active: false,
                        dropdown: false,
                        onTap: _openReview,
                      ),
                    ],
                  ),
                ),
                if (_filterSummary != null) ...[
                  const SizedBox(height: 10),
                  _filterBar(_filterSummary!),
                ],
                const SizedBox(height: 14),
                if (_reviews.isNotEmpty) ...[
                  _reviewCard(_reviews.first),
                  const SizedBox(height: 14),
                ],
                if (_isLoading && _transactions.isEmpty)
                  SizedBox(height: 360, child: _buildSkeleton())
                else if (_transactions.isEmpty)
                  SizedBox(height: 380, child: _buildEmpty())
                else
                  for (final (day, items) in sections) _daySection(day, items),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// "November 2026 · Food" when a filter other than this month is on.
  String? get _filterSummary {
    final now = DateTime.now();
    final thisMonth = !_showAll && _currentMonth.year == now.year && _currentMonth.month == now.month;
    final cat = _categoryFilter == null ? null : _categories.where((c) => c.id == _categoryFilter).firstOrNull?.name;
    if (thisMonth && cat == null) return null;
    return [
      _showAll ? 'All time' : DateFormat('MMMM yyyy').format(_currentMonth),
      if (cat != null) cat,
    ].join(' · ');
  }

  Widget _filterBar(String text) => Row(
        children: [
          const Icon(Icons.tune_rounded, size: 16, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: AppText.rowSub.copyWith(fontWeight: FontWeight.w600))),
          TextButton(
            onPressed: () {
              setState(() {
                _categoryFilter = null;
                _showAll = false;
                _currentMonth = DateTime.now();
              });
              _loadTransactions();
            },
            child: const Text('Clear'),
          ),
        ],
      );

  Widget _searchRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(23),
              boxShadow: AppShadows.soft,
            ),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (value) {
                _searchQuery = value.trim();
                _loadTransactions();
              },
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.muted),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _searchQuery = '';
                          _loadTransactions();
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(23), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(23), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(23),
                  borderSide: const BorderSide(color: AppColors.dark, width: 1.5),
                ),
                filled: true,
                fillColor: AppColors.card,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: 'Filters',
          child: GestureDetector(
            onTap: _showFilters,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: AppColors.card, shape: BoxShape.circle, boxShadow: AppShadows.soft),
              child: const Icon(Icons.tune_rounded, size: 22, color: AppColors.dark),
            ),
          ),
        ),
      ],
    );
  }

  /// Month (or all time) and category.
  void _showFilters() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Filters', style: AppText.section),
              const SizedBox(height: 14),
              const Text('PERIOD', style: AppText.label),
              const SizedBox(height: 8),
              StatefulBuilder(builder: (ctx, ss) {
                void go(VoidCallback f) {
                  f();
                  ss(() {});
                }

                return Container(
                  height: 48,
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: () => go(_prevMonth),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: Text(
                          _showAll ? 'All time' : DateFormat('MMMM yyyy').format(_currentMonth),
                          textAlign: TextAlign.center,
                          style: AppText.rowTitle,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: () => go(_nextMonth),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: EspereFilterChip(
                          label: 'All time',
                          active: _showAll,
                          dropdown: false,
                          onTap: () => go(_toggleAll),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
              const Text('CATEGORY', style: AppText.label),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                  child: Icon(IconMapper.map(_categories.where((c) => c.id == _categoryFilter).firstOrNull?.icon ?? 'category'),
                      size: 20, color: AppColors.dark),
                ),
                title: Text(
                  _categories.where((c) => c.id == _categoryFilter).firstOrNull?.name ?? 'All categories',
                  style: AppText.rowTitle,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCategoryPicker();
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reviewCard(ReviewItem item) {
    final t = item.txn;
    final cat = _categories.where((c) => c.id == t.categoryId).firstOrNull;
    final f = NumberFormat.decimalPatternDigits(
        locale: 'en_IN', decimalDigits: t.amount == t.amount.roundToDouble() ? 0 : 2);
    final source = t.sourceApp.isEmpty ? 'a notification' : t.sourceApp;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                child: Icon(IconMapper.map(cat?.icon ?? 'category'), size: 22, color: AppColors.dark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.payee ?? cat?.name ?? 'Payment', style: AppText.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 1),
                    Text(
                      'Auto-tracked from $source · ${DateFormat('h:mm a').format(t.time.toLocal())}',
                      style: AppText.rowSub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('${t.type == 'income' ? '+' : '−'}$_currencySymbol${f.format(t.amount)}',
                  style: AppText.amount.copyWith(fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _pillButton('Ignore', AppColors.surface, AppColors.text, () => _ignoreReview(item)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _pillButton(
                  t.type == 'income' ? 'Add income' : 'Add expense',
                  AppColors.dark,
                  Colors.white,
                  () => _confirmReview(item),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pillButton(String label, Color bg, Color fg, VoidCallback onTap) => SpringPress(
        haptic: HapticKind.none,
        onTap: onTap,
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(21)),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
        ),
      );

  Widget _daySection(DateTime day, List<TransactionModel> items) {
    final net = items.fold<double>(0, (sum, t) {
      final v = double.tryParse(t.amount) ?? 0;
      return sum + (t.isIncome ? v : -v);
    });
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
            child: Row(
              children: [
                Expanded(child: Text(_dayLabel(day), style: AppText.label)),
                Text(_signed(net), style: AppText.label.copyWith(letterSpacing: 0, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.soft,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final txn in items)
                  Builder(builder: (context) {
                    final snapKey = _snapKeys.putIfAbsent(txn.id, () => GlobalKey<ThanosSnapWidgetState>());
                    return ThanosSnapWidget(
                      key: snapKey,
                      child: TransactionTile(
                        transaction: txn,
                        currencySymbol: _currencySymbol,
                        showActions: true,
                        card: false,
                        onTap: () => TransactionFormScreen.show(context, transactionId: txn.id, onSaved: _loadTransactions),
                        onEdit: () => TransactionFormScreen.show(context, transactionId: txn.id, onSaved: _loadTransactions),
                        onDelete: () => _deleteTransaction(txn.id, snapKey: snapKey),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCategoryPicker() {
    final searchCtrl = TextEditingController();
    List<CategoryModel> filtered = _categories;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, ss) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  24, 16, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Select Category',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Search bar
                  TextField(
                    controller: searchCtrl,
                    onChanged: (v) {
                      ss(() {
                        filtered = _categories
                            .where((c) =>
                                c.name.toLowerCase().contains(v.toLowerCase()))
                            .toList();
                      });
                    },
                    style: const TextStyle(fontSize: 14, color: AppColors.text),
                    decoration: InputDecoration(
                      hintText: 'Search categories...',
                      prefixIcon: const Icon(Icons.search,
                          size: 18, color: AppColors.muted),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // All categories option (only if search is empty)
                  if (searchCtrl.text.isEmpty)
                    ListTile(
                      leading: Icon(
                        Icons.all_inclusive,
                        color: AppColors.accent,
                      ),
                      title: const Text('All Categories'),
                      onTap: () {
                        setState(() => _categoryFilter = null);
                        Navigator.pop(ctx);
                        _loadTransactions();
                      },
                    ),
                  if (searchCtrl.text.isEmpty)
                    const Divider(color: AppColors.border),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.6,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final cat = filtered[i];
                          return ListTile(
                            leading: Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: AppColors.categoryFill,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                IconMapper.map(cat.icon),
                                size: 19,
                                color: AppColors.categoryInk,
                              ),
                            ),
                            title: Text(cat.name),
                            selected: _categoryFilter == cat.id,
                            onTap: () {
                              setState(() => _categoryFilter = cat.id);
                              Navigator.pop(ctx);
                              _loadTransactions();
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: 15, // Increased to fill entire screen
      itemBuilder: (_, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: AppColors.dark,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                boxShadow: AppShadows.soft,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.muted.withValues(alpha: 0.2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(width: 60, height: 12, color: AppColors.muted.withValues(alpha: 0.2)),
                          const SizedBox(height: 6),
                          Container(width: 80, height: 16, color: AppColors.muted.withValues(alpha: 0.2)),
                        ],
                      ),
                    ],
                  ),
                  Container(width: 1, height: 40, color: AppColors.borderDark),
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.muted.withValues(alpha: 0.2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(width: 60, height: 12, color: AppColors.muted.withValues(alpha: 0.2)),
                          const SizedBox(height: 6),
                          Container(width: 80, height: 16, color: AppColors.muted.withValues(alpha: 0.2)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            boxShadow: AppShadows.soft,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.muted.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.muted.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.muted.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 60,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.muted.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopCard() {
    double spent = 0, received = 0;
    for (final t in _transactions) {
      final v = double.tryParse(t.amount) ?? 0;
      if (t.isIncome) {
        received += v;
      } else {
        spent += v;
      }
    }
    String money(double v) =>
        '$_currencySymbol${NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: v == v.roundToDouble() ? 0 : 2).format(v)}';
    final period = _showAll ? 'all time' : 'in ${DateFormat('MMM').format(_currentMonth)}';

    Widget stat(IconData icon, String label, String value, Color color) => Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: AppColors.darkMuted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(label,
                        style: const TextStyle(fontSize: 12, color: AppColors.darkMuted), overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(24)),
      child: Row(
        children: [
          Expanded(child: stat(Icons.arrow_upward_rounded, 'Spent $period', money(spent), Colors.white)),
          const SizedBox(width: 8),
          Expanded(child: stat(Icons.arrow_downward_rounded, 'Received', money(received), AppColors.accent)),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(left: 32, right: 32, bottom: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.receipt_long_rounded,
              size: 80,
              color: AppColors.muted,
            ),
            const SizedBox(height: 24),
            const Text(
              'No Transactions Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You have not added any transactions for this period. Add one to see it here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 220,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  TransactionFormScreen.show(
                    context,
                    onSaved: _loadTransactions,
                  );
                },
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text(
                  'Add Transaction',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.dark,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xxl),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
