import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../widgets/espere_input.dart';
import '../utils/app_toast.dart';
import '../utils/icon_mapper.dart';
import '../models/category.dart';

class BudgetsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const BudgetsScreen({super.key, this.onBack});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  List<Map<String, dynamic>> _budgets = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;
  bool _isLoadingCats = true;
  String? _error;
  String _currencySymbol = '₹';

  @override
  void initState() {
    super.initState();
    _loadBudgets();
    _loadCategories();
  }

  Future<void> _loadBudgets() async {
    setState(() => _isLoading = true);
    final result = await ApiService.getBudgets();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.isSuccess) {
        final Map<String, dynamic> data = result.data!;
        _budgets =
            List<Map<String, dynamic>>.from(data['budgets'] as Iterable? ?? []);
        _currencySymbol = (data['currency_symbol'] as String?) ?? '₹';
      } else {
        _error = result.error;
      }
    });
  }

  Future<void> _loadCategories() async {
    final result = await ApiService.getCategories();
    if (mounted) {
      setState(() {
        _isLoadingCats = false;
        if (result.isSuccess && result.data != null) {
          final cats = result.data!['categories'] as List<CategoryModel>;
          _categories = cats
              .map<Map<String, dynamic>>((c) => {
                    'id': c.id,
                    'name': c.name,
                    'icon': c.icon,
                    'color': c.color,
                  })
              .toList();
        }
      });
    }
  }

  void _showBudgetForm([Map<String, dynamic>? budget]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BudgetFormSheet(
        budget: budget,
        currencySymbol: _currencySymbol,
        categories: _categories,
        onSuccess: _loadBudgets,
      ),
    );
  }

  Future<void> _deleteBudget(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Delete Budget',
            style: TextStyle(color: AppColors.text)),
        content: const Text('Are you sure you want to delete this budget?',
            style: TextStyle(color: AppColors.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final result = await ApiService.deleteBudget(id);
      if (mounted) {
        if (result.isSuccess) {
          HapticFeedback.heavyImpact();
          AppToast.success(context, 'Budget deleted.');
          _loadBudgets();
        } else {
          AppToast.error(context, result.error ?? 'Failed to delete.');
        }
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

        // Content
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.accent))
              : _error != null
                  ? Center(
                      child: Text(_error!,
                          style: const TextStyle(color: AppColors.muted)))
                  : _budgets.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.account_balance_wallet_outlined,
                                  size: 64,
                                  color: AppColors.muted.withOpacity(0.3)),
                              const SizedBox(height: 16),
                              const Text('No budgets found.',
                                  style: TextStyle(color: AppColors.muted)),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: () => _showBudgetForm(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: AppColors.dark,
                                ),
                                child: const Text('Create First Budget'),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadBudgets,
                          color: AppColors.accent,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                            itemCount: _budgets.length,
                            itemBuilder: (context, index) {
                              final budget = _budgets[index];
                              final isExceeded = budget['is_exceeded'] == true;
                              final pct = double.tryParse(
                                      budget['percentage'].toString()) ??
                                  0;
                              final category = budget['category'];
                              final categoryColor = _parseColor(category['color']);

                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.xxl),
                                  boxShadow: AppShadows.card,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header row
                                    Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: categoryColor,
                                            borderRadius: BorderRadius.circular(
                                                AppRadius.md),
                                          ),
                                          child: Icon(
                                            IconMapper.map(category['icon']),
                                            color: AppColors.dark,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                category['name'] ?? 'Category',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: AppColors.text,
                                                ),
                                              ),
                                              Text(
                                                DateFormat('MMMM yyyy').format(
                                                    DateTime.parse(
                                                        budget['month'])),
                                                style: const TextStyle(
                                                  color: AppColors.muted,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            GestureDetector(
                                              onTap: () => _showBudgetForm(budget),
                                              child: const Icon(Icons.edit_outlined,
                                                  size: 18,
                                                  color: AppColors.muted),
                                            ),
                                            const SizedBox(width: 12),
                                            GestureDetector(
                                              onTap: () => _deleteBudget(budget['id']),
                                              child: const Icon(Icons.delete_outline,
                                                  size: 18,
                                                  color: AppColors.muted),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Progress info
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '$_currencySymbol${budget['spent']} spent',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600),
                                        ),
                                        Text(
                                          '${pct.toStringAsFixed(0)}%',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: isExceeded
                                                ? categoryColor
                                                : AppColors.accent,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    LinearProgressIndicator(
                                      value: (pct / 100).clamp(0.0, 1.0),
                                      backgroundColor: AppColors.surface,
                                      color: isExceeded
                                          ? categoryColor
                                          : AppColors.accent,
                                      minHeight: 10,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Spent so far',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: AppColors.muted)),
                                        Text(
                                            'Limit: $_currencySymbol${budget['amount']}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.muted)),
                                      ],
                                    ),

                                    // Warning message
                                    if (isExceeded) ...[
                                      const SizedBox(height: 16),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: AppColors.dark,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.warning_amber_rounded,
                                                size: 16,
                                                color: categoryColor),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                "You've exceeded your budget limit!",
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: categoryColor),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ]
                                  ],
                                ),
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
  final VoidCallback onSuccess;

  const _BudgetFormSheet({
    this.budget,
    required this.currencySymbol,
    required this.categories,
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
      _selectedCategoryId = widget.budget!['category']['id'];
      _selectedCategoryName = widget.budget!['category']['name'];
      _selectedCategoryIcon = widget.budget!['category']['icon'];
      _selectedCategoryColor = widget.budget!['category']['color'];
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

    setState(() => _isSaving = true);
    final result = await ApiService.createBudget({
      'category_id': _selectedCategoryId,
      'amount': _amountController.text,
      'month': DateFormat('yyyy-MM-dd').format(DateTime.now()),
    });

    if (mounted) {
      setState(() => _isSaving = false);
      if (result.isSuccess) {
        HapticFeedback.mediumImpact();
        AppToast.success(context,
            widget.budget == null ? 'Budget created.' : 'Budget updated.');
        widget.onSuccess();
        Navigator.pop(context);
      } else {
        AppToast.error(context, result.error ?? 'Failed to save budget.');
      }
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
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
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
            const Text('Category',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _showCategoryPicker,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                                color: _selectedCategoryId != null
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
                        color: AppColors.text),
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
              child: _isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          color: AppColors.dark, strokeWidth: 2))
                  : Text(widget.budget == null
                      ? 'Create Budget'
                      : 'Update Budget'),
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
        _filtered = widget.categories
            .where((c) =>
                c['name'].toString().toLowerCase().contains(query.toLowerCase()))
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
                prefixIcon:
                    const Icon(Icons.search, size: 18, color: AppColors.muted),
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
              child: _filtered.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No categories found',
                          style: TextStyle(color: AppColors.muted, fontSize: 14),
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
                                horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.accent.withOpacity(0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(AppRadius.md),
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
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
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
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
