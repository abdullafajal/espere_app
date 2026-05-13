/// Transaction Form Screen — matches transaction_form.html.
///
/// Card with type/amount/category/date/payment/notes fields.
/// Used for both create and edit.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import '../utils/icon_mapper.dart';
import '../widgets/espere_input.dart';

class TransactionFormScreen extends StatefulWidget {
  /// If null, it's a create screen. If set, it's an edit screen.
  final int? transactionId;
  /// Pre-set type (from dashboard quick-add): 'income' or 'expense'
  final String? presetType;

  const TransactionFormScreen({
    super.key,
    this.transactionId,
    this.presetType,
  });

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  String _type = 'expense';
  int? _categoryId;
  DateTime _date = DateTime.now();
  String _paymentMethod = 'cash';

  List<CategoryModel> _categories = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String _currencySymbol = '₹';

  // Track old state for offline updates
  String? _oldAmount;
  String? _oldType;
  int? _oldCategoryId;

  bool get isEdit => widget.transactionId != null;

  /// Returns the currently selected category or null.
  CategoryModel? get _selectedCategory {
    if (_categoryId == null) return null;
    return _categories.where((c) => c.id == _categoryId).firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    if (widget.presetType != null) {
      _type = widget.presetType!;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    // 1. Load categories from cache first
    final cachedCats = await CacheService.getCachedCategories();
    if (cachedCats != null) {
      setState(() {
        _categories = (cachedCats['categories'] as List)
            .map((c) => CategoryModel.fromJson(c as Map<String, dynamic>))
            .toList();
        _currencySymbol = cachedCats['currency_symbol'] as String? ?? '₹';
        _isLoading = false; // HIDE LOADER IMMEDIATELY
      });
    }

    // 2. Fetch fresh categories from API ONLY IF ONLINE
    if (ConnectivityService.isOnline) {
      ApiService.getCategories().then((catResult) {
        if (catResult.isSuccess && mounted) {
          setState(() {
            _categories = catResult.data!['categories'] as List<CategoryModel>;
            _currencySymbol = catResult.data!['currency_symbol'] as String? ?? '₹';
            _isLoading = false;
          });

          // Update cache
          CacheService.cacheCategories({
            'categories': _categories.map((c) => c.toJson()).toList(),
            'currency_symbol': _currencySymbol,
          });
        }
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }

    // 3. If edit, load existing transaction
    if (isEdit) {
      TransactionModel? initialData;

      // Try cache first (Main Transaction List)
      final cachedTxns = await CacheService.getCachedTransactions();
      if (cachedTxns != null) {
        final list = List<Map<String, dynamic>>.from(cachedTxns['transactions'] ?? []);
        final found = list.firstWhere(
          (t) => t['id']?.toString() == widget.transactionId?.toString(), 
          orElse: () => {}
        );
        if (found.isNotEmpty) {
          initialData = TransactionModel.fromJson(found);
        }
      }

      // If still not found, try Dashboard cache (Recent Transactions)
      if (initialData == null) {
        final cachedDashboard = await CacheService.getCachedDashboard();
        if (cachedDashboard != null) {
          final recent = List<Map<String, dynamic>>.from(cachedDashboard['recent_transactions'] ?? []);
          final found = recent.firstWhere(
            (t) => t['id']?.toString() == widget.transactionId?.toString(), 
            orElse: () => {}
          );
          if (found.isNotEmpty) {
            initialData = TransactionModel.fromJson(found);
          }
        }
      }

      if (initialData != null) {
        setState(() {
          _amountController.text = initialData!.amount;
          _notesController.text = initialData!.notes;
          _type = initialData!.type;
          _categoryId = initialData!.category.id;
          _date = initialData!.date;
          _paymentMethod = initialData!.paymentMethod;

          // Store old values for offline update reversal
          _oldAmount = initialData!.amount;
          _oldType = initialData!.type;
          _oldCategoryId = initialData!.category.id;
          
          _isLoading = false;
        });
      }

      // Then try API in background if online
      if (ConnectivityService.isOnline) {
        _getBaseUrl().then((baseUrl) {
          _fetchTransaction(baseUrl).then((response) {
            if (response != null && mounted) {
              setState(() {
                _amountController.text = response.amount;
                _notesController.text = response.notes;
                _type = response.type;
                _categoryId = response.category.id;
                _date = response.date;
                _paymentMethod = response.paymentMethod;

                _oldAmount = response.amount;
                _oldType = response.type;
                _oldCategoryId = response.category.id;
                
                _isLoading = false;
              });
            }
          });
        });
      }
    }
  }

  Future<String> _getBaseUrl() async {
    return await (await _loadAuthService()).toString();
  }

  // Simplified: use API service directly
  Future<TransactionModel?> _fetchTransaction(String _) async {
    // Re-fetch via getTransactions with all=1
    final result = await ApiService.getTransactions(showAll: true);
    if (result.isSuccess) {
      final list = result.data!['transactions'] as List<TransactionModel>;
      return list
          .where((t) => t.id == widget.transactionId)
          .firstOrNull;
    }
    return null;
  }

  Future<dynamic> _loadAuthService() async {
    final service = await ApiService.getCategories();
    return service;
  }

  Future<void> _save() async {
    final amount = _amountController.text.trim();
    if (amount.isEmpty) {
      setState(() => _error = 'Amount is required.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final txnData = {
      'amount': amount,
      'type': _type,
      'category_id': _categoryId,
      'date': _date.toIso8601String(),
      'payment_method': _paymentMethod,
      'notes': _notesController.text.trim(),
    };

    ApiResult result;
    if (ConnectivityService.isOnline) {
      result = isEdit
          ? await ApiService.updateTransaction(widget.transactionId!, txnData)
          : await ApiService.createTransaction(txnData);
    } else {
      // Offline mode: queue the operation
      await SyncService.queueOperation(
        action: isEdit ? 'update' : 'create',
        entity: 'transaction',
        data: txnData,
        entityId: isEdit ? widget.transactionId : null,
      );

      // ─── Optimistic Update ──────────────────────────────────────────
      // To show the transaction in the list immediately, we inject it into the cache
      final selectedCat = _selectedCategory;
      final fullTxnJson = {
        'id': isEdit ? widget.transactionId : DateTime.now().millisecondsSinceEpoch, // Temp ID
        'amount': amount,
        'type': _type,
        'category': selectedCat?.toJson() ?? {'name': 'Other', 'icon': 'category'},
        'date': _date.toIso8601String(),
        'payment_method': _paymentMethod,
        'payment_method_display': _paymentMethods.firstWhere((m) => m.$1 == _paymentMethod).$2,
        'notes': _notesController.text.trim(),
      };

      if (!isEdit) {
        await CacheService.addTransactionToCache(fullTxnJson);
        // Also update dashboard totals
        await CacheService.updateDashboardOptimistically(
          _type, 
          double.tryParse(amount) ?? 0.0, 
          fullTxnJson
        );
        // Update budget if it's an expense
        if (_type == 'expense' && _categoryId != null) {
          await CacheService.updateBudgetOptimistically(
            _categoryId!, 
            double.tryParse(amount) ?? 0.0
          );
        }
      } else {
        // Optimistic Update for Edit
        await CacheService.updateTransactionInCache(widget.transactionId!, fullTxnJson);
        
        // Reverse old impact and add new impact to dashboard/budgets
        if (_oldAmount != null && _oldType != null) {
          final oldCatName = _categories.firstWhere((c) => c.id == _oldCategoryId, orElse: () => CategoryModel(id: 0, name: 'Other', icon: 'category', color: '#000000', isSystem: true)).name;
          
          await CacheService.reverseDashboardImpact(
            _oldType!, 
            double.tryParse(_oldAmount!) ?? 0.0, 
            widget.transactionId!,
            categoryName: oldCatName,
          );
          await CacheService.updateDashboardOptimistically(
            _type, 
            double.tryParse(amount) ?? 0.0, 
            fullTxnJson
          );

          // Budgets
          if (_oldType == 'expense' && _oldCategoryId != null) {
            await CacheService.updateBudgetOptimistically(
              _oldCategoryId!, 
              double.tryParse(_oldAmount!) ?? 0.0, 
              isDelete: true
            );
          }
          if (_type == 'expense' && _categoryId != null) {
            await CacheService.updateBudgetOptimistically(
              _categoryId!, 
              double.tryParse(amount) ?? 0.0
            );
          }
        }
      }
      // ───────────────────────────────────────────────────────────────
      
      // We don't have the server response, but we notify success to close the screen
      result = ApiResult(data: null); 
      
      // Provide immediate feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Offline: Transaction saved locally and will sync later.',
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

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.isSuccess) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context, true);
    } else {
      setState(() => _error = result.error ?? 'Failed to save.');
    }
  }

  /// Opens a searchable bottom sheet to pick a category.
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
          categories: _categories,
          selectedId: _categoryId,
          onSelected: (cat) {
            setState(() => _categoryId = cat.id);
            Navigator.pop(ctx);
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  static const _paymentMethods = [
    ('cash', 'Cash'),
    ('card', 'Credit/Debit Card'),
    ('bank', 'Bank Transfer'),
    ('upi', 'UPI / Mobile Payment'),
    ('other', 'Other'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Top Bar ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius:
                            BorderRadius.circular(AppRadius.md),
                        boxShadow: AppShadows.soft,
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: AppColors.text),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEdit ? 'Edit Transaction' : 'Add Transaction',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  const Spacer(),
                  // Type badge
                  if (widget.presetType != null && !isEdit)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _type == 'income'
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 14,
                            color: AppColors.dark,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _type == 'income' ? 'Income' : 'Expense',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.dark,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // ─── Form ──────────────────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Error
                          if (_error != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.dark,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.xl),
                                boxShadow: AppShadows.soft,
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error,
                                      size: 18, color: AppColors.accent),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Form card — mn-card p-5 space-y-4
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.xxl),
                              boxShadow: AppShadows.card,
                            ),
                            child: Column(
                              children: [
                                // Type selector (if no preset)
                                if (widget.presetType == null || isEdit) ...[
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Type',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.text,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      GestureDetector(
                                        onTap: () {
                                          showModalBottomSheet(
                                            context: context,
                                            backgroundColor: AppColors.card,
                                            shape: const RoundedRectangleBorder(
                                              borderRadius: BorderRadius.vertical(
                                                  top: Radius.circular(24)),
                                            ),
                                            builder: (ctx) =>
                                                _TransactionTypePickerSheet(
                                              selectedType: _type,
                                              onSelected: (type) {
                                                setState(() => _type = type);
                                                Navigator.pop(ctx);
                                              },
                                            ),
                                          );
                                        },
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 14),
                                          decoration: BoxDecoration(
                                            color: AppColors.surface,
                                            borderRadius:
                                                BorderRadius.circular(AppRadius.lg),
                                            border: Border.all(
                                                color: AppColors.border,
                                                width: 1.5),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: AppColors.accent,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Icon(
                                                  _type == 'income'
                                                      ? Icons.arrow_upward
                                                      : Icons.arrow_downward,
                                                  size: 18,
                                                  color: AppColors.dark,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  _type == 'income'
                                                      ? 'Income'
                                                      : 'Expense',
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    color: AppColors.text,
                                                  ),
                                                ),
                                              ),
                                              const Icon(Icons.arrow_drop_down,
                                                  color: AppColors.muted),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                ],

                                // Amount
                                EspereInput(
                                  label: 'Amount',
                                  hint: '0.00',
                                  controller: _amountController,
                                  prefixText: _currencySymbol,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                ),
                                const SizedBox(height: 16),

                                // Category
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Category',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.text,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    GestureDetector(
                                      onTap: _showCategoryPicker,
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 14),
                                        decoration: BoxDecoration(
                                          color: AppColors.surface,
                                          borderRadius:
                                              BorderRadius.circular(AppRadius.lg),
                                          border: Border.all(
                                              color: AppColors.border,
                                              width: 1.5),
                                        ),
                                        child: Row(
                                          children: [
                                            if (_selectedCategory != null) ...[
                                              Container(
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  color: _selectedCategory!.colorValue,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Icon(
                                                  IconMapper.map(
                                                      _selectedCategory!.icon),
                                                  size: 16,
                                                  color: AppColors.dark,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                            ],
                                            Expanded(
                                              child: Text(
                                                _selectedCategory?.name ??
                                                    'Select category',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: _selectedCategory != null
                                                      ? AppColors.text
                                                      : AppColors.muted,
                                                ),
                                              ),
                                            ),
                                            const Icon(Icons.arrow_drop_down,
                                                color: AppColors.muted),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Date & Time
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Date & Time',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.text,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    GestureDetector(
                                      onTap: () async {
                                        final pickedDate =
                                            await showDatePicker(
                                          context: context,
                                          initialDate: _date,
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime.now()
                                              .add(const Duration(
                                                  days: 365)),
                                        );
                                        if (pickedDate != null) {
                                          if (!mounted) return;
                                          final pickedTime =
                                              await showTimePicker(
                                            context: context,
                                            initialTime:
                                                TimeOfDay.fromDateTime(
                                                    _date),
                                          );
                                          if (pickedTime != null) {
                                            setState(() {
                                              _date = DateTime(
                                                pickedDate.year,
                                                pickedDate.month,
                                                pickedDate.day,
                                                pickedTime.hour,
                                                pickedTime.minute,
                                              );
                                            });
                                          }
                                        }
                                      },
                                      child: Container(
                                        width: double.infinity,
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 14),
                                        decoration: BoxDecoration(
                                          color: AppColors.surface,
                                          borderRadius:
                                              BorderRadius.circular(
                                                  AppRadius.lg),
                                          border: Border.all(
                                              color: AppColors.border,
                                              width: 1.5),
                                        ),
                                        child: Text(
                                          DateFormat('MMM dd, yyyy · hh:mm a')
                                              .format(_date.toLocal()),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: AppColors.text,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Payment method
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Payment Method',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.text,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    GestureDetector(
                                      onTap: () {
                                        showModalBottomSheet(
                                          context: context,
                                          backgroundColor: AppColors.card,
                                          shape: const RoundedRectangleBorder(
                                            borderRadius: BorderRadius.vertical(
                                                top: Radius.circular(24)),
                                          ),
                                          builder: (ctx) =>
                                              _PaymentMethodPickerSheet(
                                            selectedMethod: _paymentMethod,
                                            onSelected: (method) {
                                              setState(() =>
                                                  _paymentMethod = method);
                                              Navigator.pop(ctx);
                                            },
                                          ),
                                        );
                                      },
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 14),
                                        decoration: BoxDecoration(
                                          color: AppColors.surface,
                                          borderRadius:
                                              BorderRadius.circular(
                                                  AppRadius.lg),
                                          border: Border.all(
                                              color: AppColors.border,
                                              width: 1.5),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color: AppColors.accent,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                IconMapper.map(_paymentMethod),
                                                size: 18,
                                                color: AppColors.dark,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                _paymentMethods
                                                    .firstWhere((m) =>
                                                        m.$1 == _paymentMethod)
                                                    .$2,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: AppColors.text,
                                                ),
                                              ),
                                            ),
                                            const Icon(Icons.arrow_drop_down,
                                                color: AppColors.muted),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Notes
                                EspereInput(
                                  label: 'Notes',
                                  hint: 'Add a note...',
                                  controller: _notesController,
                                  maxLines: 3,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Submit button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _save,
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.accent,
                                      ),
                                    )
                                  : Text(
                                      isEdit
                                          ? 'Update Transaction'
                                          : 'Add ${_type == 'income' ? 'Income' : _type == 'expense' ? 'Expense' : 'Transaction'}',
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Searchable bottom sheet for picking a category with icons.
class _CategoryPickerSheet extends StatefulWidget {
  final List<CategoryModel> categories;
  final int? selectedId;
  final ValueChanged<CategoryModel> onSelected;

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
  List<CategoryModel> _filtered = [];

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
        _filtered = widget.categories
            .where(
                (c) => c.name.toLowerCase().contains(query.toLowerCase()))
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
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            const Text(
              'Select Category',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 12),

            // Search bar
            TextField(
              controller: _searchController,
              onChanged: _filter,
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
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 12),

            // Category list
            Flexible(
              child: _filtered.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No categories found',
                          style: TextStyle(
                              color: AppColors.muted, fontSize: 14),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final cat = _filtered[i];
                        final isSelected =
                            widget.selectedId == cat.id;

                        return GestureDetector(
                          onTap: () => widget.onSelected(cat),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.accent.withValues(alpha: 0.15)
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.accent
                                    : AppColors.border,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Icon badge
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: cat.colorValue,
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    IconMapper.map(cat.icon),
                                    size: 18,
                                    color: AppColors.dark,
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Name
                                Expanded(
                                  child: Text(
                                    cat.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: AppColors.text,
                                    ),
                                  ),
                                ),

                                // Check mark
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

/// Bottom sheet for picking a payment method with icons.
class _TransactionTypePickerSheet extends StatelessWidget {
  final String selectedType;
  final ValueChanged<String> onSelected;

  const _TransactionTypePickerSheet({
    required this.selectedType,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
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
            'Select Type',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          _buildItem(
            context,
            'income',
            'Income',
            Icons.arrow_upward,
            AppColors.income,
          ),
          _buildItem(
            context,
            'expense',
            'Expense',
            Icons.arrow_downward,
            AppColors.expense,
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, String value, String label,
      IconData icon, Color color) {
    final isSelected = selectedType == value;
    return GestureDetector(
      onTap: () => onSelected(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.15)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: AppColors.dark),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: AppColors.text,
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

class _PaymentMethodPickerSheet extends StatelessWidget {
  final String selectedMethod;
  final ValueChanged<String> onSelected;

  const _PaymentMethodPickerSheet({
    required this.selectedMethod,
    required this.onSelected,
  });

  static const _methods = [
    ('cash', 'Cash'),
    ('card', 'Credit/Debit Card'),
    ('bank', 'Bank Transfer'),
    ('upi', 'UPI / Mobile Payment'),
    ('other', 'Other'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
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
            'Payment Method',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),

          ..._methods.map((method) {
            final isSelected = selectedMethod == method.$1;
            return GestureDetector(
              onTap: () => onSelected(method.$1),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: isSelected ? AppColors.accent : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        IconMapper.map(method.$1),
                        size: 18,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        method.$2,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle,
                          size: 20, color: AppColors.accent),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String value;
  final List<(String, String)> items;
  final ValueChanged<String> onChanged;

  const _DropdownField({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.any((item) => item.$1 == value) ? value : null,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, color: AppColors.muted),
          style: const TextStyle(fontSize: 14, color: AppColors.text),
          dropdownColor: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          items: items
              .map((item) => DropdownMenuItem<String>(
                    value: item.$1,
                    child: Text(item.$2),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
