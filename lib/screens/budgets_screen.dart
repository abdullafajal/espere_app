import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import '../widgets/espere_input.dart';
import '../utils/app_toast.dart';
import '../utils/icon_mapper.dart';
import '../models/category.dart';
import '../widgets/budget_tile.dart';
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
  String? _error;
  String _currencySymbol = '₹';
  DateTime _currentMonth = DateTime.now();

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

  Future<void> _loadBudgets() async {
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
      if (res.isSuccess && mounted) {
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
        CacheService.cacheBudgets(res.data!);
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
      if (res.isSuccess && mounted) {
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

  Future<void> _deleteBudget(int id) async {
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

      HapticFeedback.heavyImpact();
      AppToast.success(context, 'Budget deleted.');

      if (ConnectivityService.isOnline) {
        SyncService.syncAll();
      }
    }
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return AppColors.error;
    try {
      String cleanHex = hex.replaceFirst('#', '');
      if (cleanHex.length == 6) cleanHex = 'FF$cleanHex';
      return Color(int.parse(cleanHex, radix: 16));
    } catch (e) {
      return AppColors.error;
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  if (widget.onBack != null) {
                    widget.onBack?.call();
                  } else {
                    Navigator.maybePop(context);
                  }
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: AppShadows.soft,
                  ),
                  child: const Icon(Icons.arrow_back, color: AppColors.text),
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Budgets',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showBudgetForm(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: AppShadows.soft,
                  ),
                  child: const Icon(Icons.add, color: AppColors.dark),
                ),
              ),
            ],
          ),
        ),

        // Month Navigator
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.soft,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _prevMonth,
                child: const SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(Icons.chevron_left, size: 20, color: AppColors.muted),
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
                  width: 32,
                  height: 32,
                  child: Icon(Icons.chevron_right, size: 20, color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child:
              _isLoading
                  ? const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  )
                  : _error != null
                  ? Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  )
                  : _budgets.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 32, right: 32, bottom: 80),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.account_balance_wallet_rounded,
                              size: 80,
                              color: AppColors.muted,
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'No Budgets Yet',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'You have not set any budgets for this month. Create one to start tracking.',
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
                                onPressed: () => _showBudgetForm(),
                                icon: const Icon(Icons.add_rounded, size: 20),
                                label: const Text(
                                  'Create Budget',
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
                    )
                  : RefreshIndicator(
                    onRefresh: _handleRefresh,
                    color: AppColors.accent,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                      itemCount: _budgets.length,
                      itemBuilder: (context, index) {
                        final budget = _budgets[index];
                        return BudgetTile(
                          budget: budget,
                          currencySymbol: _currencySymbol,
                          onEdit: () => _showBudgetForm(budget),
                          onDelete: () => _deleteBudget(budget['id']),
                        );
                      },
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

  @override
  void initState() {
    super.initState();
    if (widget.budget != null) {
      _amountController.text = widget.budget!['amount'].toString();

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
      HapticFeedback.mediumImpact();
      AppToast.success(
        context,
        widget.budget == null ? 'Budget created.' : 'Budget updated.',
      );
      widget.onSuccess();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
                icon: const Icon(Icons.close, color: AppColors.muted),
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
                  border: Border.all(color: AppColors.dark, width: 1.5),
                ),
                child: Row(
                  children: [
                    if (_selectedCategoryId != null) ...[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(8),
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
                    const Icon(Icons.arrow_drop_down, color: AppColors.muted),
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
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(6),
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
          const SizedBox(height: 32),
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
    );
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
                  Icons.search,
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
                                        ? AppColors.accent.withOpacity(0.15)
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
                                      color: AppColors.accent,
                                      borderRadius: BorderRadius.circular(10),
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
                                      Icons.check_circle,
                                      size: 20,
                                      color: AppColors.accent,
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
