import 'package:flutter/material.dart';
import '../theme/motion.dart';
import '../widgets/espere_header.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/nav_space.dart';
import '../widgets/espere_action_button.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import '../widgets/thanos_snap_widget.dart';
import '../widgets/espere_input.dart';
import '../utils/app_toast.dart';
import '../utils/icon_mapper.dart';
import '../models/category.dart';
import '../widgets/espere_back_button.dart';
import '../widgets/morph_text.dart';
import '../services/budget_service.dart';
import 'budget_detail_screen.dart';
import '../widgets/budget_deck.dart';
import 'dart:async';

class BudgetsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const BudgetsScreen({super.key, this.onBack});

  @override
  State<BudgetsScreen> createState() => BudgetsScreenState();
}

class BudgetsScreenState extends State<BudgetsScreen> {
  List<Map<String, dynamic>> _budgets = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;
  bool _isLoadingCats = true;
  String _currencySymbol = '₹';
  final Map<int, GlobalKey<ThanosSnapWidgetState>> _budgetSnapKeys = {};
  DateTime _currentMonth = DateTime.now();

  /// The whole-month budget (limit 0 = none) and the month's spending.
  BudgetInfo _overall = const BudgetInfo(name: 'Month', limit: 0, spent: 0);

  /// Category budgets with what is spent counted on the phone (fresher than the server).
  Map<int, BudgetInfo> _local = const {};

  /// Which budgets the deck and grid show: all, over, near (80%+) or ok.
  String _filter = 'all';
  int _deckIndex = 0;

  StreamSubscription<void>? _syncSub;

  @override
  void initState() {
    super.initState();
    _loadBudgets();
    _loadCategories();

    // Listen for background sync completions to refresh UI immediately
    _syncSub = SyncService.onSyncComplete.listen((_) {
      debugPrint('[BudgetsScreen] Background sync detected — refreshing data...');
      if (mounted) {
        _loadBudgets();
        _loadCategories();
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  void reload() {
    _loadBudgets();
    _loadCategories();
  }

  Future<void> _loadOverall() async {
    final o = await BudgetService.overall(_currentMonth);
    final local = await BudgetService.byCategory(_currentMonth);
    if (mounted) {
      setState(() {
        _overall = o;
        _local = local;
      });
    }
  }

  /// This month's budgets with phone-counted spending, fullest first (over, then near).
  List<BudgetInfo> get _all {
    final out = <BudgetInfo>[];
    for (final b in _budgets) {
      final cat = b['category'];
      final id = int.tryParse(((cat is Map ? cat['id'] : null) ?? b['category_id'])?.toString() ?? '');
      final local = id == null ? null : _local[id];
      out.add(local ??
          BudgetInfo(
            id: int.tryParse(b['id']?.toString() ?? ''),
            categoryId: id,
            name: (cat is Map ? cat['name'] : null)?.toString() ?? 'Category',
            icon: (cat is Map ? cat['icon'] : null)?.toString() ?? 'category',
            limit: double.tryParse(b['amount'].toString()) ?? 0,
            spent: double.tryParse(b['spent']?.toString() ?? '') ?? 0,
            repeat: b['repeat'] != false,
            carried: double.tryParse(b['carried']?.toString() ?? '') ?? 0,
          ));
    }
    return out..sort((a, b) => b.fraction.compareTo(a.fraction));
  }

  static String _kind(BudgetInfo b) => b.limit <= 0
      ? 'ok'
      : b.spent > b.limit
          ? 'over'
          : (b.fraction >= 0.8 ? 'near' : 'ok');

  List<BudgetInfo> get _shown => _filter == 'all' ? _all : _all.where((b) => _kind(b) == _filter).toList();

  /// Runs [action] with the budget map behind a deck card.
  void _withBudget(BudgetInfo b, void Function(Map<String, dynamic>) action) {
    final m = _budgets.where((x) {
      final cat = x['category'];
      return ((cat is Map ? cat['id'] : null) ?? x['category_id'])?.toString() == b.categoryId?.toString();
    }).firstOrNull;
    if (m != null) action(m);
  }

  Future<void> _loadBudgets() async {
    _loadOverall();
    // 1. Always check cache first to show optimistic updates
    final cached = await CacheService.getCachedBudgets();
    if (cached != null && mounted) {
      final List list = cached['budgets'] ?? [];
      final currentMonthStr = "${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}";
      setState(() {
        _budgets = List<Map<String, dynamic>>.from(list).where((b) {
          if (b['month'] == null) return true;
          return b['month'].toString().startsWith(currentMonthStr);
        }).toList()
          ..sort((a, b) {
            int cmp = (a['name'] ?? '').compareTo(b['name'] ?? '');
            if (cmp != 0) return cmp;
            return (b['id'] ?? 0).compareTo(a['id'] ?? 0);
          });
        _currencySymbol = (cached['currency_symbol'] as String?) ?? '₹';
      });
    }
    if (mounted) setState(() => _isLoading = false);

    // 2. Fetch from API silently
    if (ConnectivityService.isOnline) {
      final res = await ApiService.getBudgets();
      // Never overwrite local changes that are still waiting to be synced.
      if (res.isSuccess && mounted && !await SyncService.hasPending('budget')) {
        final List list = res.data!['budgets'] ?? [];
        final currentMonthStr = "${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}";
        setState(() {
          _budgets = List<Map<String, dynamic>>.from(list).where((b) {
            if (b['month'] == null) return true;
            return b['month'].toString().startsWith(currentMonthStr);
          }).toList()
            ..sort((a, b) {
              int cmp = (a['name'] ?? '').compareTo(b['name'] ?? '');
              if (cmp != 0) return cmp;
              return (b['id'] ?? 0).compareTo(a['id'] ?? 0);
            });
          _currencySymbol = (res.data!['currency_symbol'] as String?) ?? '₹';
        });
        await CacheService.cacheBudgets(res.data!);
        _loadOverall();
      }
    }
  }

  Future<void> _handleRefresh() async {
    await SyncService.syncAll();
    await _loadBudgets();
  }

  Future<void> _loadCategories() async {
    // 1. Load from cache first
    final cachedCats = await CacheService.getCachedCategories();
    if (cachedCats != null && mounted) {
      setState(() {
        final List catsRaw = cachedCats['categories'] ?? [];
        _categories =
            catsRaw
                .map<Map<String, dynamic>>((c) => Map<String, dynamic>.from(c))
                .toList();
      });
    }
    if (mounted) setState(() => _isLoadingCats = false);
    
    // 2. Fetch from API silently
    if (ConnectivityService.isOnline) {
      final res = await ApiService.getCategories();
      if (res.isSuccess && mounted && !await SyncService.hasPending('category')) {
        setState(() {
          final List catsRaw = res.data!['categories'] ?? [];
          _categories =
              catsRaw
                  .map<Map<String, dynamic>>((c) => Map<String, dynamic>.from(c))
                  .toList();
        });
        CacheService.cacheCategories(res.data!);
      }
    }
  }

  void _showBudgetForm([Map<String, dynamic>? budget]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => _BudgetFormSheet(
            budget: budget,
            currencySymbol: _currencySymbol,
            categories: _categories,
            currentMonth: _currentMonth,
            onSuccess: _loadBudgets,
          ),
    );
  }

  Future<void> _deleteBudget(GlobalKey<ThanosSnapWidgetState> snapKey, int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppColors.card,
            title: const Text(
              'Delete Budget',
              style: TextStyle(color: AppColors.text),
            ),
            content: const Text(
              'Are you sure you want to delete this budget?',
              style: TextStyle(color: AppColors.muted),
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
      await snapKey.currentState?.startSnap();
      // Offline mode: queue deletion
      await SyncService.queueOperation(
        action: 'delete',
        entity: 'budget',
        entityId: id,
      );

      // Remove from cache
      await CacheService.removeBudgetFromCache(id);

      setState(() {
        _budgets.removeWhere((b) => b['id'] == id);
      });

      AppHaptics.confirm();
      AppToast.success(context, 'Budget deleted.');

      if (ConnectivityService.isOnline) {
        SyncService.syncAll();
      }
    }
  }

  bool get _isThisMonth {
    final now = DateTime.now();
    return _currentMonth.year == now.year && _currentMonth.month == now.month;
  }

  String _money(double v) {
    final f = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0);
    return '$_currencySymbol${f.format(v.round())}';
  }

  void _openBudget(Map<String, dynamic> budget) {
    AppHaptics.tap();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BudgetDetailScreen(
          budget: budget,
          month: _currentMonth,
          currencySymbol: _currencySymbol,
          onEdit: () => _showBudgetForm(budget),
        ),
      ),
    ).then((_) => _loadBudgets());
  }

  /// The month at a glance: Spent / Left / Per day, a thin bar and the budget line.
  /// Tap to set or change the whole-month budget.
  Widget _summary() {
    final o = _overall;
    final has = o.limit > 0;
    final now = DateTime.now();
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final daysLeft = _isThisMonth ? daysInMonth - now.day + 1 : 0;
    // Without a whole-month budget, the category budgets together are the limit.
    final limit = has ? o.limit : _all.fold<double>(0, (a, b) => a + b.limit);
    final left = limit - o.spent;
    return SpringPress(
      haptic: HapticKind.tap,
      onTap: _isThisMonth ? _setOverall : null,
      child: Column(
        children: [
          Row(
            children: [
              _statBox('Spent', _money(o.spent)),
              const SizedBox(width: 8),
              _statBox(left < 0 ? 'Over by' : 'Left', limit > 0 ? _money(left.abs()) : '—'),
              const SizedBox(width: 8),
              _statBox('Per day', limit > 0 && left > 0 && daysLeft > 0 ? _money(left / daysLeft) : '—'),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: limit <= 0 ? 0 : (o.spent / limit).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppColors.border,
                color: AppColors.dark,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    has
                        ? '${DateFormat('MMMM').format(_currentMonth)} · ${_money(o.limit)} budget'
                        : (_isThisMonth ? 'Tap to set one budget for the month' : 'No monthly budget'),
                    style: AppText.rowSub.copyWith(
                      fontSize: 11.5,
                      fontWeight: has ? FontWeight.w500 : FontWeight.w700,
                      color: has ? AppColors.muted : AppColors.text,
                    ),
                  ),
                ),
                if (_isThisMonth)
                  Text('$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left', style: AppText.rowSub.copyWith(fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, maxLines: 1, style: AppText.rowSub.copyWith(fontSize: 11)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MorphText(id: 'bsum-$label', value, style: AppText.amount.copyWith(fontSize: 15)),
              ),
            ],
          ),
        ),
      );

  /// All / Over / Near limit / On track, with counts.
  Widget _filters() {
    final all = _all;
    int count(String k) => all.where((b) => _kind(b) == k).length;
    final options = [
      ('all', 'All ${all.length}'),
      if (count('over') > 0) ('over', 'Over ${count('over')}'),
      if (count('near') > 0) ('near', 'Near limit ${count('near')}'),
      if (count('ok') > 0) ('ok', 'On track ${count('ok')}'),
    ];
    if (!options.any((o) => o.$1 == _filter)) _filter = 'all';
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (final (key, label) in options)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: SpringPress(
                  haptic: HapticKind.tap,
                  onTap: () => setState(() {
                    _filter = key;
                    _deckIndex = 0;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(
                      color: _filter == key ? AppColors.dark : AppColors.card,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _filter == key ? AppColors.accent : AppColors.text,
                        )),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCategories() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(AppRadius.xxl)),
        child: Column(
          children: [
            const Text('No category budgets yet', style: AppText.rowTitle),
            const SizedBox(height: 4),
            const Text(
              'Give Food, Travel or any category its own limit. It repeats every month.',
              textAlign: TextAlign.center,
              style: AppText.rowSub,
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () => _showBudgetForm(),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Create budget'),
              ),
            ),
          ],
        ),
      );

  /// Sets (or removes) the whole-month budget, with a suggestion from past months.
  Future<void> _setOverall() async {
    final now = DateTime.now();
    final past = <double>[];
    for (var k = 3; k >= 1; k--) {
      final o = await BudgetService.overall(DateTime(now.year, now.month - k));
      if (o.spent > 0) past.add(o.spent);
    }
    final avg = past.isEmpty ? 0.0 : past.reduce((a, b) => a + b) / past.length;
    if (!mounted) return;
    final amount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OverallSheet(
        current: _overall.limit,
        average: avg,
        months: past.length,
        currencySymbol: _currencySymbol,
      ),
    );
    if (amount == null) return;
    await BudgetService.setOverall(amount);
    AppHaptics.confirm();
    if (mounted) {
      AppToast.success(context, amount > 0 ? 'Monthly budget set.' : 'Monthly budget removed.');
      _loadOverall();
    }
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
    _loadBudgets();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    });
    _loadBudgets();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Custom Fixed Header
        EspereHeader(
          title: 'Budgets',
          showBack: widget.onBack == null,
          onBack: () {
            if (widget.onBack != null) {
              widget.onBack?.call();
            } else {
              Navigator.maybePop(context);
            }
          },
          trailing: EspereActionButton(
            icon: Icons.add_rounded,
            primary: true,
            tooltip: 'New budget',
            onPressed: () => _showBudgetForm(),
          ),
        ),

        // Month Navigator
        Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppShadows.soft,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _prevMonth,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.chevron_left_rounded, size: 24, color: AppColors.dark),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  DateFormat('MMMM yyyy').format(_currentMonth),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _nextMonth,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.chevron_right_rounded, size: 24, color: AppColors.dark),
                ),
              ),
            ],
          ),
        ),

        // Content: the whole-month card, then the category budgets.
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.dark))
              : RefreshIndicator(
                  onRefresh: _handleRefresh,
                  color: AppColors.dark,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    children: [
                      _summary(),
                      if (_budgets.isEmpty) ...[
                        const SizedBox(height: 18),
                        _emptyCategories(),
                      ] else ...[
                        _filters(),
                        if (_shown.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(AppRadius.xxl)),
                            child: const Text('No budgets in this group.', textAlign: TextAlign.center, style: AppText.rowSub),
                          )
                        else ...[
                          BudgetDeck(
                            items: _shown,
                            index: _deckIndex.clamp(0, _shown.length - 1),
                            onIndex: (i) => setState(() => _deckIndex = i),
                            month: _currentMonth,
                            symbol: _currencySymbol,
                            onOpen: (b) => _withBudget(b, _openBudget),
                            onEdit: (b) => _withBudget(b, _showBudgetForm),
                            snapKeyFor: (b) => _budgetSnapKeys.putIfAbsent(b.id ?? -1, () => GlobalKey<ThanosSnapWidgetState>()),
                            onDelete: (b) => _withBudget(b, (m) => _deleteBudget(
                                _budgetSnapKeys.putIfAbsent(m['id'], () => GlobalKey<ThanosSnapWidgetState>()), m['id'])),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 20, 6, 8),
                            child: Row(
                              children: [
                                Expanded(child: Text('ALL BUDGETS', style: AppText.label)),
                                Text('${_shown.length} ${_shown.length == 1 ? 'budget' : 'budgets'}',
                                    style: AppText.label.copyWith(letterSpacing: 0.4)),
                              ],
                            ),
                          ),
                          GridView.count(
                            crossAxisCount: 3,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 0.98,
                            children: [
                              for (final (i, b) in _shown.indexed)
                                BudgetGridTile(
                                  budget: b,
                                  current: i == _deckIndex.clamp(0, _shown.length - 1),
                                  symbol: _currencySymbol,
                                  onTap: () => setState(() => _deckIndex = i),
                                ),
                            ],
                          ),
                        ],
                      ],
                      const SizedBox(height: 8),
                      const NavBottomSpace(),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _BudgetFormSheet extends StatefulWidget {
  final Map<String, dynamic>? budget;
  final String currencySymbol;
  final List<Map<String, dynamic>> categories;
  final DateTime currentMonth;
  final VoidCallback onSuccess;

  const _BudgetFormSheet({
    this.budget,
    required this.currencySymbol,
    required this.categories,
    required this.currentMonth,
    required this.onSuccess,
  });

  @override
  State<_BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends State<_BudgetFormSheet> {
  final _amountController = TextEditingController();
  int? _selectedCategoryId;
  String? _selectedCategoryName;
  String? _selectedCategoryIcon;
  String? _selectedCategoryColor;

  bool _isSaving = false;

  /// Copy into next month automatically / add this month's leftover to it.
  bool _repeat = true;
  bool _carry = false;

  /// What the picked category usually costs a month, and the months behind it.
  double _avg = 0;
  int _avgMonths = 0;

  Future<void> _loadSuggestion() async {
    final id = int.tryParse(_selectedCategoryId?.toString() ?? '');
    if (id == null) return;
    final (avg, months) = await BudgetService.suggestion(id);
    if (mounted) setState(() {
      _avg = avg;
      _avgMonths = months.length;
    });
  }

  String _m(double v) =>
      '${widget.currencySymbol}${NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0).format(v.round())}';

  @override
  void initState() {
    super.initState();
    if (widget.budget != null) {
      final amt = double.tryParse(widget.budget!['amount'].toString()) ?? 0;
      final carried = double.tryParse(widget.budget!['carried']?.toString() ?? '') ?? 0;
      // Edit the budget's own amount; the carried part is added again next month.
      _amountController.text = (amt - carried) == (amt - carried).roundToDouble()
          ? (amt - carried).round().toString()
          : (amt - carried).toStringAsFixed(2);
      _repeat = widget.budget!['repeat'] != false;
      _carry = widget.budget!['carry_over'] == true;

      final cat = widget.budget!['category'];
      if (cat != null) {
        _selectedCategoryId = cat['id'];
        _selectedCategoryName = cat['name'];
        _selectedCategoryIcon = cat['icon'];
        _selectedCategoryColor = cat['color'];
      } else {
        // Fallback for older flat structure
        _selectedCategoryId = widget.budget!['category_id'];
        _selectedCategoryName = widget.budget!['category_name'];
        _selectedCategoryIcon = widget.budget!['category_icon'];
        _selectedCategoryColor = widget.budget!['category_color'];
      }
    }
    _loadSuggestion();
  }

  void _showCategoryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return _CategoryPickerSheet(
          categories: widget.categories,
          selectedId: _selectedCategoryId,
          onSelected: (cat) {
            setState(() {
              _selectedCategoryId = cat['id'];
              _selectedCategoryName = cat['name'];
              _selectedCategoryIcon = cat['icon'];
              _selectedCategoryColor = cat['color'];
            });
            _loadSuggestion();
            Navigator.pop(ctx);
          },
        );
      },
    );
  }

  Future<void> _save() async {
    if (_selectedCategoryId == null) {
      AppToast.error(context, 'Please select a category.');
      return;
    }
    if (_amountController.text.isEmpty) {
      AppToast.error(context, 'Please enter an amount.');
      return;
    }

    final isUpdate = widget.budget != null;
    
    // Prevent duplicate budgets for the same category in the current month
    if (!isUpdate) {
      final currentMonthStr = "${widget.currentMonth.year}-${widget.currentMonth.month.toString().padLeft(2, '0')}";
      final cached = await CacheService.getCachedBudgets();
      if (cached != null) {
        final List budgets = cached['budgets'] ?? [];
        final exists = budgets.any((b) {
          final bMonth = b['month']?.toString() ?? '';
          final bCatId = b['category']?['id'] ?? b['category_id'];
          return bMonth.startsWith(currentMonthStr) && bCatId.toString() == _selectedCategoryId.toString();
        });
        
        if (exists) {
          AppToast.info(context, 'A budget for this category already exists this month.');
          return;
        }
      }
    }

    setState(() => _isSaving = true);
    final data = {
      'category_id': _selectedCategoryId,
      'amount': _amountController.text,
      'month': DateFormat('yyyy-MM-dd').format(DateTime(widget.currentMonth.year, widget.currentMonth.month, 1)),
      'repeat': _repeat,
      'carry_over': _carry,
    };

    // Always queue creation/update
    int? tempId;
    if (!isUpdate) {
      tempId = DateTime.now().millisecondsSinceEpoch;
    }
    
    await SyncService.queueOperation(
      action: 'create', // backend handles upsert on POST
      entity: 'budget',
      data: data,
      entityId: isUpdate ? widget.budget!['id'] : tempId,
    );

    // ─── Optimistic Update ──────────────────────────────────────────
    final cat = widget.categories.firstWhere(
      (c) => c['id'].toString() == _selectedCategoryId.toString(),
      orElse: () => {},
    );
    
    double computedSpent = 0.0;
    if (!isUpdate) {
      final cachedTxns = await CacheService.getCachedTransactions();
      if (cachedTxns != null && cachedTxns['transactions'] != null) {
        final now = DateTime.now();
        for (final t in cachedTxns['transactions']) {
          if (t['type'] == 'expense' && 
              t['category']?['id']?.toString() == _selectedCategoryId.toString()) {
            final dateStr = t['date']?.toString();
            if (dateStr != null) {
              final d = DateTime.tryParse(dateStr);
              if (d != null && d.year == now.year && d.month == now.month) {
                computedSpent += double.tryParse(t['amount'].toString()) ?? 0.0;
              }
            }
          }
        }
      }
    }
    
    final budgetAmount = double.tryParse(_amountController.text) ?? 0.0;
    final spentAmount = isUpdate ? (double.tryParse(widget.budget!['spent'].toString()) ?? 0.0) : computedSpent;
    final remainingAmount = budgetAmount - spentAmount;
    final percentage = budgetAmount > 0 ? (spentAmount / budgetAmount * 100).clamp(0.0, 100.0) : 0.0;
    final isExceeded = spentAmount > budgetAmount;

    final newBudgetJson = {
      'id': isUpdate ? widget.budget!['id'] : tempId,
      'category': {
        'id': _selectedCategoryId,
        'name': cat['name'] ?? 'Other',
        'icon': cat['icon'] ?? 'category',
        'color': cat['color'] ?? '#C8E64A',
      },
      'amount': _amountController.text,
      'spent': double.parse(spentAmount.toStringAsFixed(2)),
      'remaining': double.parse(remainingAmount.toStringAsFixed(2)),
      'percentage': double.parse(percentage.toStringAsFixed(2)),
      'month': data['month'],
      'is_exceeded': isExceeded,
      'repeat': _repeat,
      'carry_over': _carry,
      'carried': 0,
    };
    
    if (isUpdate) {
      await CacheService.updateBudgetInCache(widget.budget!['id'], newBudgetJson);
    } else {
      await CacheService.addBudgetToCache(newBudgetJson);
    }
    // ───────────────────────────────────────────────────────────────

    if (ConnectivityService.isOnline) {
      SyncService.syncAll();
    }

    if (mounted) {
      setState(() => _isSaving = false);
      AppHaptics.confirm();
      AppToast.success(
        context,
        widget.budget == null ? 'Budget created.' : 'Budget updated.',
      );
      widget.onSuccess();
      Navigator.pop(context);
    }
  }

  Widget _switchRow(String title, String hint, bool on, ValueChanged<bool>? onChanged) => Opacity(
        opacity: onChanged == null ? 0.45 : 1,
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.rowTitle),
                    Text(hint, style: AppText.rowSub),
                  ],
                ),
              ),
              Switch(
                value: on,
                onChanged: onChanged == null
                    ? null
                    : (v) {
                        AppHaptics.tap();
                        onChanged(v);
                      },
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Scrolls when the keyboard and the extra options do not fit.
    return SingleChildScrollView(child: Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.budget == null ? 'New Budget' : 'Edit Budget',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (widget.budget == null) ...[
            const Text(
              'Category',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _showCategoryPicker,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Row(
                  children: [
                    if (_selectedCategoryId != null) ...[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          IconMapper.map(_selectedCategoryIcon!),
                          size: 16,
                          color: AppColors.dark,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        _selectedCategoryName ?? 'Select category',
                        style: TextStyle(
                          fontSize: 14,
                          color:
                              _selectedCategoryId != null
                                  ? AppColors.text
                                  : AppColors.muted,
                        ),
                      ),
                    ),
                    const Icon(Icons.expand_more_rounded, color: AppColors.muted),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ] else ...[
            // For update mode, show a small category badge instead of input
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      IconMapper.map(_selectedCategoryIcon!),
                      size: 14,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedCategoryName ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          EspereInput(
            label: 'Monthly Limit',
            hint: '0.00',
            controller: _amountController,
            keyboardType: TextInputType.number,
            prefixText: widget.currencySymbol,
          ),
          if (_avg > 0) ...[
            const SizedBox(height: 12),
            _SuggestionBox(
              text: 'Last ${_avgMonths == 1 ? 'month' : '$_avgMonths months'} you spent about '
                  '${_m(_avg)} a month on ${_selectedCategoryName ?? 'this'}.',
              choices: BudgetService.suggestedChoices(_avg),
              selected: double.tryParse(_amountController.text),
              format: _m,
              onPick: (v) => setState(() => _amountController.text = v.round().toString()),
            ),
          ],
          const SizedBox(height: 8),
          _switchRow('Repeat every month', 'Starts again on the 1st with the same amount', _repeat,
              (v) => setState(() => _repeat = v)),
          _switchRow('Carry leftover to next month', 'Unspent money is added to next month', _carry && _repeat,
              _repeat ? (v) => setState(() => _carry = v) : null),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child:
                  _isSaving
                      ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: AppColors.dark,
                          strokeWidth: 2,
                        ),
                      )
                      : Text(
                        widget.budget == null
                            ? 'Create Budget'
                            : 'Update Budget',
                      ),
            ),
          ),
        ],
      ),
    ));
  }
}

class _CategoryPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final int? selectedId;
  final ValueChanged<Map<String, dynamic>> onSelected;

  const _CategoryPickerSheet({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.categories;
  }

  void _filter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.categories;
      } else {
        _filtered =
            widget.categories
                .where(
                  (c) => c['name'].toString().toLowerCase().contains(
                    query.toLowerCase(),
                  ),
                )
                .toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
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
            const SizedBox(height: 16),
            const Text(
              'Select Category',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: _filter,
              style: const TextStyle(fontSize: 14, color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Search categories...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: AppColors.muted,
                ),
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
            Flexible(
              child:
                  _filtered.isEmpty
                      ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            'No categories found',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                      : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final cat = _filtered[i];
                          final isSelected = widget.selectedId == cat['id'];

                          return GestureDetector(
                            onTap: () => widget.onSelected(cat),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    isSelected
                                        ? AppColors.accentSoft
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      IconMapper.map(cat['icon'].toString()),
                                      size: 18,
                                      color: AppColors.dark,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      cat['name'].toString(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight:
                                            isSelected
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      size: 20,
                                      color: AppColors.dark,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet for the whole-month budget: an amount, suggestions from past months, Save /
/// Remove. Pops with the amount (0 removes it), or null when closed.
class _OverallSheet extends StatefulWidget {
  final double current;
  final double average;
  final int months;
  final String currencySymbol;

  const _OverallSheet({
    required this.current,
    required this.average,
    required this.months,
    required this.currencySymbol,
  });

  @override
  State<_OverallSheet> createState() => _OverallSheetState();
}

class _OverallSheetState extends State<_OverallSheet> {
  late final TextEditingController _c =
      TextEditingController(text: widget.current > 0 ? widget.current.round().toString() : '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _m(double v) =>
      '${widget.currencySymbol}${NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0).format(v.round())}';

  @override
  Widget build(BuildContext context) {
    final choices = BudgetService.suggestedChoices(widget.average);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Monthly budget', style: AppText.section)),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: AppColors.muted),
              ),
            ],
          ),
          const Text('One limit for everything you spend in a month.', style: AppText.rowSub),
          const SizedBox(height: 16),
          EspereInput(
            label: 'Amount per month',
            hint: '0',
            controller: _c,
            keyboardType: TextInputType.number,
            prefixText: widget.currencySymbol,
          ),
          if (choices.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SuggestionBox(
              text: 'Last ${widget.months == 1 ? 'month' : '${widget.months} months'} you spent about '
                  '${_m(widget.average)} a month.',
              choices: choices,
              selected: double.tryParse(_c.text),
              format: _m,
              onPick: (v) => setState(() => _c.text = v.round().toString()),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              if (widget.current > 0) ...[
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, 0.0),
                      child: const Text('Remove'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      final v = double.tryParse(_c.text.replaceAll(',', '')) ?? 0;
                      if (v <= 0) {
                        AppToast.info(context, 'Enter an amount.');
                        return;
                      }
                      Navigator.pop(context, v);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Last 3 months you spent about ₹6,200" with amounts to pick in one tap.
class _SuggestionBox extends StatelessWidget {
  final String text;
  final List<double> choices;
  final double? selected;
  final String Function(double) format;
  final ValueChanged<double> onPick;

  const _SuggestionBox({
    required this.text,
    required this.choices,
    required this.selected,
    required this.format,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.dark),
              const SizedBox(width: 6),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.text))),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in choices)
                SpringPress(
                  haptic: HapticKind.tap,
                  onTap: () => onPick(v),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected == v ? AppColors.dark : AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      format(v),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected == v ? AppColors.accent : AppColors.text,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
