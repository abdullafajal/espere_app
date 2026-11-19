/// Transaction Form Screen — matches transaction_form.html.
///
/// Card with type/amount/category/date/payment/notes fields.
/// Used for both create and edit.
import 'package:flutter/material.dart';
import '../theme/motion.dart';
import '../utils/app_toast.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'quick_add_screen.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../services/api_service.dart';
import '../services/auto_expense_service.dart';
import '../services/receipt_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import '../services/widget_service.dart';
import '../utils/icon_mapper.dart';
import '../widgets/espere_input.dart';

class TransactionFormScreen extends StatefulWidget {
  /// If null, it's a create screen. If set, it's an edit screen.
  final int? transactionId;

  /// Pre-set type (from dashboard quick-add): 'income' or 'expense'
  final String? presetType;

  /// Callback when transaction is saved
  final VoidCallback? onSaved;

  /// Starting values for a new entry (from a shared / scanned payment receipt).
  final TransactionPrefill? prefill;

  const TransactionFormScreen({
    super.key,
    this.transactionId,
    this.presetType,
    this.onSaved,
    this.prefill,
  });

  /// Helper to show this form as a bottom sheet
  /// Edits / adds a transaction. Uses the Quick add screen (keypad + categories), so
  /// adding and editing look the same.
  static void show(
    BuildContext context, {
    int? transactionId,
    String? presetType,
    VoidCallback? onSaved,
    TransactionPrefill? prefill,
  }) {
    final Future<bool> done = transactionId != null
        ? QuickAddScreen.edit(context, transactionId)
        : prefill != null
            ? QuickAddScreen.prefilled(context, prefill)
            : QuickAddScreen.open(context, type: presetType ?? 'expense');
    done.then((saved) {
      if (saved) onSaved?.call();
    });
  }

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
  bool _isScanning = false;

  /// Text read from a shared / scanned receipt, so the user can check what was read
  /// (and copy it when a field was filled wrong).
  String? _receiptText;
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
    if (widget.prefill != null && !isEdit) _applyPrefill(widget.prefill!);
    _loadData();
  }

  void _applyPrefill(TransactionPrefill p) {
    if (p.amount != null) {
      _amountController.text =
          p.amount == p.amount!.roundToDouble() ? p.amount!.toStringAsFixed(0) : p.amount!.toStringAsFixed(2);
    }
    if (p.notes != null && p.notes!.trim().isNotEmpty) _notesController.text = p.notes!.trim();
    _receiptText = p.sourceText;
    if (widget.presetType == null) _type = p.type;
    if (p.date != null) _date = p.date!;
    _paymentMethod = p.paymentMethod;
    if (p.categoryId != null && (widget.presetType == null || widget.presetType == p.type)) {
      _categoryId = p.categoryId;
    }
  }

  void _showReceiptText() {
    final text = _receiptText ?? '';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Text read from receipt'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              AppToast.success(context, 'Copied');
            },
            child: const Text('Copy'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  /// "Scan receipt": pick a payment screenshot, read it on device and fill the form.
  Future<void> _scanReceipt() async {
    if (_isScanning) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => _isScanning = true);
    try {
      final scan = await ReceiptService.recognize(picked.path);
      if (!mounted) return;
      if (scan == null) {
        AppToast.error(context, 'Could not read text from this image.');
        return;
      }
      final data = ReceiptService.read(scan: scan);
      final text = ReceiptService.sourceTextOf(scan: scan);
      if (data.notCompleted) {
        AppToast.error(context, 'This payment failed or is still pending.');
        return;
      }
      if (data.isEmpty) {
        AppToast.error(context, 'No payment details found in this image.');
        return;
      }
      final p = await ReceiptService.prefillFrom(data, sourceText: text);
      if (!mounted) return;
      setState(() {
        final keepType = widget.presetType != null && widget.presetType != p.type;
        if (!keepType && _type != p.type) _categoryId = null;
        _applyPrefill(p);
      });
      if (p.amount == null) {
        AppToast.info(context, 'Could not find the amount. Please enter it.');
      } else {
        AppToast.success(context, 'Filled from receipt. Please check and save.');
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _loadData() async {
    // 1. Load categories from cache first
    final cachedCats = await CacheService.getCachedCategories();
    if (cachedCats != null) {
      setState(() {
        _categories =
            (cachedCats['categories'] as List)
                .map((c) => CategoryModel.fromJson(c as Map<String, dynamic>))
                .toList();
        _currencySymbol = cachedCats['currency_symbol'] as String? ?? '₹';
        _isLoading = false; // HIDE LOADER IMMEDIATELY
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
        final list = List<Map<String, dynamic>>.from(
          cachedTxns['transactions'] ?? [],
        );
        final found = list.firstWhere(
          (t) => t['id']?.toString() == widget.transactionId?.toString(),
          orElse: () => {},
        );
        if (found.isNotEmpty) {
          initialData = TransactionModel.fromJson(found);
        }
      }

      // If still not found, try Dashboard cache (Recent Transactions)
      if (initialData == null) {
        final cachedDashboard = await CacheService.getCachedDashboard();
        if (cachedDashboard != null) {
          final recent = List<Map<String, dynamic>>.from(
            cachedDashboard['recent_transactions'] ?? [],
          );
          final found = recent.firstWhere(
            (t) => t['id']?.toString() == widget.transactionId?.toString(),
            orElse: () => {},
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
    }
  }

  Future<void> _save() async {
    final amount = _amountController.text.trim();
    if (amount.isEmpty) {
      AppToast.error(context, 'Amount is required.');
      return;
    }

    setState(() {
      _isSaving = true;
    });
    AppHaptics.confirm();

    final txnData = {
      'amount': amount,
      'type': _type,
      'category_id': _categoryId,
      'date': _date.toUtc().toIso8601String(),
      'payment_method': _paymentMethod,
      'notes': _notesController.text.trim(),
    };
    int? tempId;
    if (!isEdit) {
      tempId = DateTime.now().millisecondsSinceEpoch;
    }

    // ─── Prepare Optimistic Data ──────────────────────────────────────
    final selectedCat = _selectedCategory;
    final fullTxnJson = {
      'id': isEdit ? widget.transactionId : tempId, // Temp ID for new, real ID for edit
      'amount': (double.tryParse(amount) ?? 0.0).toStringAsFixed(2),
      'type': _type,
      'category': selectedCat?.toJson() ?? {'name': 'Other', 'icon': 'category'},
      'date': _date.toUtc().toIso8601String(),
      'payment_method': _paymentMethod,
      'payment_method_display': _paymentMethods.firstWhere((m) => m.$1 == _paymentMethod).$2,
      'notes': _notesController.text.trim(),
    };

    // ─── Apply Optimistic Updates (Immediate Reflection) ─────────────
    if (!isEdit) {
      await CacheService.addTransactionToCache(fullTxnJson);
      await CacheService.updateDashboardOptimistically(
        _type,
        double.tryParse(amount) ?? 0.0,
        fullTxnJson,
      );
      if (_type == 'expense' && _categoryId != null) {
        await CacheService.updateBudgetOptimistically(
          _categoryId!,
          double.tryParse(amount) ?? 0.0,
        );
      }
    } else {
      await CacheService.updateTransactionInCache(widget.transactionId!, fullTxnJson);
      if (_oldAmount != null && _oldType != null) {
        final oldCatName = _categories
            .firstWhere((c) => c.id == _oldCategoryId,
                orElse: () => CategoryModel(
                    id: 0,
                    name: 'Other',
                    icon: 'category',
                    color: '#000000',
                    isSystem: true))
            .name;

        await CacheService.reverseDashboardImpact(
          _oldType!,
          double.tryParse(_oldAmount!) ?? 0.0,
          widget.transactionId!,
          categoryName: oldCatName,
        );
        await CacheService.updateDashboardOptimistically(
          _type,
          double.tryParse(amount) ?? 0.0,
          fullTxnJson,
        );

        if (_oldType == 'expense' && _oldCategoryId != null) {
          await CacheService.updateBudgetOptimistically(_oldCategoryId!,
              double.tryParse(_oldAmount!) ?? 0.0,
              isDelete: true);
        }
        if (_type == 'expense' && _categoryId != null) {
          await CacheService.updateBudgetOptimistically(
              _categoryId!, double.tryParse(amount) ?? 0.0);
        }
      }
    }

    // Always queue the operation for background sync
    await SyncService.queueOperation(
      action: isEdit ? 'update' : 'create',
      entity: 'transaction',
      data: txnData,
      entityId: isEdit ? widget.transactionId : tempId,
    );
    
    // Trigger sync if online
    if (ConnectivityService.isOnline) {
      SyncService.syncAll();
    }

    // Refresh home screen widgets
    WidgetService.refreshAllWidgets();

    // Editing the category of an auto-tracked entry teaches the per-payee category.
    if (isEdit) {
      AutoExpenseService.learnFromEdit(txnId: widget.transactionId, categoryId: _categoryId);
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    AppHaptics.confirm();
    widget.onSaved?.call();
    Navigator.pop(context, true);
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
          categories: _categories.where((c) => c.type == _type).toList(),
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
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
            
            // ─── Top Bar ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  if (!isEdit && ReceiptService.isSupported)
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: _isScanning
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.text,
                              ),
                            )
                          : IconButton(
                              padding: EdgeInsets.zero,
                              tooltip: 'Scan receipt',
                              icon: const Icon(Icons.document_scanner_outlined,
                                  color: AppColors.text),
                              onPressed: _scanReceipt,
                            ),
                    )
                  else
                    const SizedBox(width: 40), // Spacer for balance
                  const Spacer(),
                  Text(
                    isEdit ? 'Edit Transaction' : 'Add Transaction',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  const Spacer(),
                  // Type badge or placeholder
                  if (widget.presetType != null && !isEdit)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _type == 'income'
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
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
                    )
                  else
                    const SizedBox(width: 40),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ─── Form ──────────────────────────────────────
            Flexible(
              child:
                  _isLoading
                      ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.dark,
                        ),
                      )
                      : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Error
                            

                            // Form container without card border
                            Container(
                              padding: const EdgeInsets.only(top: 8),
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
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.text,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        GestureDetector(
                                          onTap: () {
                                            showModalBottomSheet(
                                              context: context,
                                              backgroundColor: AppColors.card,
                                              shape:
                                                  const RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.vertical(
                                                          top: Radius.circular(
                                                            24,
                                                          ),
                                                        ),
                                                  ),
                                              builder:
                                                  (ctx) =>
                                                      _TransactionTypePickerSheet(
                                                        selectedType: _type,
                                                        onSelected: (type) {
                                                          setState(() {
                                                            if (_type != type) {
                                                              _categoryId = null;
                                                            }
                                                            _type = type;
                                                          });
                                                          Navigator.pop(ctx);
                                                        },
                                                      ),
                                            );
                                          },
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 14,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.surface,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppRadius.lg,
                                                  ),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 32,
                                                  height: 32,
                                                  decoration: BoxDecoration(
                                                    color: AppColors.card,
                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    _type == 'income'
                                                        ? Icons.south_west_rounded
                                                        : Icons.north_east_rounded,
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
                                                const Icon(
                                                  Icons.expand_more_rounded,
                                                  color: AppColors.muted,
                                                ),
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
                                          decimal: true,
                                        ),
                                  ),
                                  if (_receiptText != null &&
                                      _receiptText!.trim().isNotEmpty)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: _showReceiptText,
                                        icon: const Icon(Icons.text_snippet_outlined,
                                            size: 16, color: AppColors.muted),
                                        label: const Text(
                                          'See text read from receipt',
                                          style: TextStyle(
                                              fontSize: 13, color: AppColors.muted),
                                        ),
                                      ),
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
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.text,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
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
                                            borderRadius: BorderRadius.circular(
                                              AppRadius.lg,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              if (_selectedCategory !=
                                                  null) ...[
                                                Container(
                                                  width: 28,
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                    color: AppColors.card,
                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    IconMapper.map(
                                                      _selectedCategory!.icon,
                                                    ),
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
                                                    color:
                                                        _selectedCategory !=
                                                                null
                                                            ? AppColors.text
                                                            : AppColors.muted,
                                                  ),
                                                ),
                                              ),
                                              const Icon(
                                                Icons.expand_more_rounded,
                                                color: AppColors.muted,
                                              ),
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
                                          fontWeight: FontWeight.w700,
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
                                                lastDate: DateTime.now().add(
                                                  const Duration(days: 365),
                                                ),
                                              );
                                          if (pickedDate != null) {
                                            if (!mounted) return;
                                            final pickedTime =
                                                await showTimePicker(
                                                  context: context,
                                                  initialTime:
                                                      TimeOfDay.fromDateTime(
                                                        _date,
                                                      ),
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
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.surface,
                                            borderRadius: BorderRadius.circular(
                                              AppRadius.lg,
                                            ),
                                          ),
                                          child: Text(
                                            DateFormat(
                                              'MMM dd, yyyy · hh:mm a',
                                            ).format(_date.toLocal()),
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
                                          fontWeight: FontWeight.w700,
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
                                              borderRadius:
                                                  BorderRadius.vertical(
                                                    top: Radius.circular(24),
                                                  ),
                                            ),
                                            builder:
                                                (ctx) =>
                                                    _PaymentMethodPickerSheet(
                                                      selectedMethod:
                                                          _paymentMethod,
                                                      onSelected: (method) {
                                                        setState(
                                                          () =>
                                                              _paymentMethod =
                                                                  method,
                                                        );
                                                        Navigator.pop(ctx);
                                                      },
                                                    ),
                                          );
                                        },
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.surface,
                                            borderRadius: BorderRadius.circular(
                                              AppRadius.lg,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: AppColors.card,
                    shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  IconMapper.map(
                                                    _paymentMethod,
                                                  ),
                                                  size: 18,
                                                  color: AppColors.dark,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  _paymentMethods
                                                      .firstWhere(
                                                        (m) =>
                                                            m.$1 ==
                                                            _paymentMethod,
                                                      )
                                                      .$2,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    color: AppColors.text,
                                                  ),
                                                ),
                                              ),
                                              const Icon(
                                                Icons.expand_more_rounded,
                                                color: AppColors.muted,
                                              ),
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
                                child:
                                    _isSaving
                                        ? SizedBox(
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
                                              : 'Add ${_type == 'income'
                                                  ? 'Income'
                                                  : _type == 'expense'
                                                  ? 'Expense'
                                                  : 'Transaction'}',
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
        _filtered =
            widget.categories
                .where(
                  (c) => c.name.toLowerCase().contains(query.toLowerCase()),
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

            // Category list
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
                          final isSelected = widget.selectedId == cat.id;

                          return GestureDetector(
                            onTap: () => widget.onSelected(cat),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    isSelected
                                        ? AppColors.accentSoft
                                        : AppColors.surface,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.lg,
                                ),
                                border: Border.all(
                                  color: isSelected ? AppColors.dark : Colors.transparent,
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
                                      color: AppColors.card,
                                      shape: BoxShape.circle,
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
                                        fontWeight:
                                            isSelected
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ),

                                  // Check mark
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
            Icons.south_west_rounded,
            AppColors.income,
          ),
          _buildItem(
            context,
            'expense',
            'Expense',
            Icons.north_east_rounded,
            AppColors.expense,
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    final isSelected = selectedType == value;
    return GestureDetector(
      onTap: () => onSelected(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? AppColors.accentSoft
                  : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isSelected ? AppColors.dark : Colors.transparent,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.card,
                    shape: BoxShape.circle,
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
              const Icon(Icons.check_circle_rounded, color: AppColors.dark, size: 20),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color:
                      isSelected
                          ? AppColors.accentSoft
                          : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: isSelected ? AppColors.dark : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                    shape: BoxShape.circle,
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
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: AppColors.dark,
                      ),
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
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.any((item) => item.$1 == value) ? value : null,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded, color: AppColors.muted),
          style: const TextStyle(fontSize: 14, color: AppColors.text),
          dropdownColor: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          items:
              items
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item.$1,
                      child: Text(item.$2),
                    ),
                  )
                  .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
