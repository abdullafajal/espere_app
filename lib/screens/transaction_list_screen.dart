/// Transaction List Screen — matches transaction_list.html.
///
/// Features: search bar, type/category filter chips, month navigator,
/// grouped transaction list with edit/delete actions
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import '../utils/icon_mapper.dart';
import '../widgets/transaction_tile.dart';

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
  String? _error;
  String _currencySymbol = '₹';

  // Filters
  String _searchQuery = '';
  String _typeFilter = '';
  int? _categoryFilter;
  DateTime _currentMonth = DateTime.now();
  bool _showAll = false;

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Public method for parent to trigger a data reload.
  void reload() => _loadTransactions();

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
        _isLoading = false;
      });
    }

    // 2. Fetch fresh data from API ONLY if online
    if (ConnectivityService.isOnline) {
      final catResult = await ApiService.getCategories();
      if (catResult.isSuccess) {
        _categories = catResult.data!['categories'] as List<CategoryModel>;
        // Cache categories
        CacheService.cacheCategories({
          'categories': _categories.map((c) => c.toJson()).toList(),
          'currency_symbol': catResult.data!['currency_symbol'],
        });
        if (mounted) setState(() {});
      }
      
      _loadTransactions();
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTransactions() async {
    // 1. Always check cache first to show optimistic updates
    final cached = await CacheService.getCachedTransactions();
    if (cached != null && mounted) {
      setState(() {
        _transactions = (cached['transactions'] as List)
            .map((t) => TransactionModel.fromJson(t as Map<String, dynamic>))
            .toList();
        _currencySymbol = (cached['currency_symbol'] as String?) ?? '₹';
      });
    }

    // 2. Fetch fresh from API ONLY if online
    if (!ConnectivityService.isOnline) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final monthStr = DateFormat('yyyy-M').format(_currentMonth);
    final result = await ApiService.getTransactions(
      query: _searchQuery.isNotEmpty ? _searchQuery : null,
      type: _typeFilter.isNotEmpty ? _typeFilter : null,
      categoryId: _categoryFilter,
      month: _showAll ? null : monthStr,
      showAll: _showAll,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.isSuccess) {
        _transactions = result.data!['transactions'] as List<TransactionModel>;
        _currencySymbol = result.data!['currency_symbol'] as String? ?? '₹';
        // Cache transactions
        CacheService.cacheTransactions({
          'transactions':
              _transactions.map((t) => t.toJson()).toList(),
          'currency_symbol': _currencySymbol,
        });
        _error = null;
      } else if (_transactions.isEmpty) {
        _error = result.error;
      }
    });
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
      _showAll = false;
    });
    _loadTransactions();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
      _showAll = false;
    });
    _loadTransactions();
  }

  void _toggleAll() {
    setState(() => _showAll = !_showAll);
    _loadTransactions();
  }

  Future<void> _deleteTransaction(int id) async {
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
      if (ConnectivityService.isOnline) {
        final result = await ApiService.deleteTransaction(id);
        if (result.isSuccess) {
          _loadTransactions();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result.error ?? 'Failed to delete')),
            );
          }
        }
      } else {
        // Offline mode: queue deletion
        await SyncService.queueOperation(
          action: 'delete',
          entity: 'transaction',
          entityId: id,
        );

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
          await CacheService.cacheTransactions({
            'transactions': list,
            'currency_symbol': cachedTxns['currency_symbol'],
          });
        }
        // ───────────────────────────────────────────────────────────────

        // Update local UI immediately
        setState(() {
          _transactions.removeWhere((t) => t.id == id);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Offline: Transaction will be deleted when online.',
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: AppColors.text,
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ─── Top Bar ───────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            children: [
              // Header: Title + Add button
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        widget.onBack?.call();
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
                      child: const Icon(
                        Icons.arrow_back,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Transactions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await Navigator.pushNamed(context, '/transaction/add');
                      _loadTransactions();
                    },
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
              const SizedBox(height: 16),

              // Search bar — matches the search input from transaction_list.html
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: AppShadows.soft,
                ),
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (value) {
                    _searchQuery = value;
                    _loadTransactions();
                  },
                  style: const TextStyle(fontSize: 14, color: AppColors.text),
                  decoration: InputDecoration(
                    hintText: 'Search transactions...',
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
                    fillColor: AppColors.card,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Filter chips + Month navigator
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Type filter
                    _FilterChip(
                      label:
                          _typeFilter.isEmpty
                              ? 'All Types'
                              : _typeFilter == 'income'
                              ? 'Income'
                              : 'Expense',
                      onTap: () {
                        setState(() {
                          if (_typeFilter.isEmpty) {
                            _typeFilter = 'income';
                          } else if (_typeFilter == 'income') {
                            _typeFilter = 'expense';
                          } else {
                            _typeFilter = '';
                          }
                        });
                        _loadTransactions();
                      },
                    ),
                    const SizedBox(width: 8),

                    // Category filter
                    _FilterChip(
                      label:
                          _categoryFilter == null
                              ? 'All Categories'
                              : _categories
                                      .where((c) => c.id == _categoryFilter)
                                      .firstOrNull
                                      ?.name ??
                                  'Category',
                      onTap: () => _showCategoryPicker(),
                    ),
                    const SizedBox(width: 8),

                    // Month navigator
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.border),
                        boxShadow: AppShadows.soft,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!_showAll) ...[
                            GestureDetector(
                              onTap: _prevMonth,
                              child: const SizedBox(
                                width: 24,
                                height: 24,
                                child: Icon(
                                  Icons.chevron_left,
                                  size: 18,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                          ],
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              _showAll
                                  ? 'All Time'
                                  : DateFormat(
                                    'MMMM yyyy',
                                  ).format(_currentMonth),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          if (!_showAll) ...[
                            GestureDetector(
                              onTap: _nextMonth,
                              child: const SizedBox(
                                width: 24,
                                height: 24,
                                child: Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                          ],
                          Container(
                            width: 1,
                            height: 12,
                            color: AppColors.border,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          GestureDetector(
                            onTap: _toggleAll,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _showAll ? 'Current' : 'All',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.dark,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ─── Transaction List ──────────────────────────────────
        Expanded(
          child:
              _isLoading
                  ? _buildSkeleton()
                  : _error != null
                  ? Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  )
                  : _transactions.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                    onRefresh: _loadTransactions,
                    color: AppColors.accent,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                      itemCount: _transactions.length,
                      itemBuilder: (context, index) {
                        final txn = _transactions[index];
                        // Group header — show month separator
                        bool showHeader = false;
                        if (index == 0) {
                          showHeader = true;
                        } else {
                          final prevTxn = _transactions[index - 1];
                          if (txn.date.month != prevTxn.date.month ||
                              txn.date.year != prevTxn.date.year) {
                            showHeader = true;
                          }
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showHeader)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  bottom: 8,
                                  left: 4,
                                ),
                                child: Text(
                                  DateFormat(
                                    'MMMM yyyy',
                                  ).format(txn.date.toLocal()).toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: TransactionTile(
                                transaction: txn,
                                currencySymbol: _currencySymbol,
                                showActions: true,
                                onTap: () async {
                                  await Navigator.pushNamed(
                                    context,
                                    '/transaction/edit',
                                    arguments: txn.id,
                                  );
                                  _loadTransactions();
                                },
                                onEdit: () async {
                                  await Navigator.pushNamed(
                                    context,
                                    '/transaction/edit',
                                    arguments: txn.id,
                                  );
                                  _loadTransactions();
                                },
                                onDelete: () => _deleteTransaction(txn.id),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
        ),
      ],
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
                      leading: const Icon(
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
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: cat.colorValue,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                IconMapper.map(cat.icon),
                                size: 16,
                                color: AppColors.dark,
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
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder:
          (_, __) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.xxl),
            ),
          ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long,
            size: 56,
            color: AppColors.muted.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 8),
          const Text(
            'No transactions found',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              await Navigator.pushNamed(context, '/transaction/add');
              _loadTransactions();
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Transaction'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.dark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.soft,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
