import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import '../widgets/espere_input.dart';
import 'package:intl/intl.dart';

class SavingsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const SavingsScreen({super.key, this.onBack});

  @override
  State<SavingsScreen> createState() => SavingsScreenState();
}

class SavingsScreenState extends State<SavingsScreen> {
  List<Map<String, dynamic>> _goals = [];
  bool _isLoading = true;
  String? _error;
  int? _expandedGoalId;
  String _currencySymbol = '₹';

  @override
  void initState() {
    super.initState();
    _loadSavings();
  }

  void reload() => _loadSavings();

  Future<void> _loadSavings() async {
    // 1. Always check cache first to show optimistic updates
    final cached = await CacheService.getCachedSavings();
    if (cached != null && mounted) {
      setState(() {
        _goals = List<Map<String, dynamic>>.from(
            cached['goals'] as Iterable? ?? []);
        _currencySymbol =
            (cached['currency_symbol'] as String?) ?? '₹';
        _isLoading = false;
      });
    }

    // 2. Fetch fresh from API ONLY if online
    if (!ConnectivityService.isOnline) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final result = await ApiService.getSavings();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.isSuccess) {
        final Map<String, dynamic> data = result.data!;
        _goals = List<Map<String, dynamic>>.from(
          data['goals'] as Iterable? ?? [],
        );
        _currencySymbol = (data['currency_symbol'] as String?) ?? '₹';
        CacheService.cacheSavings(data);
      } else if (_goals.isEmpty) {
        _error = result.error;
      }
    });
  }

  void _showAddMoney(Map<String, dynamic> goal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _AddMoneySheet(
        goal: goal,
        currencySymbol: _currencySymbol,
        onSuccess: () {
          _loadSavings();
        },
      ),
    );
  }

  void _deleteGoal(Map<String, dynamic> goal) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('Delete Goal'),
            content: Text('Are you sure you want to delete "${goal['name']}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
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
        final res = await ApiService.deleteSavingGoal(goal['id']);
        if (res.isSuccess) {
          HapticFeedback.heavyImpact();
          _loadSavings();
        }
      } else {
        // Offline mode: queue deletion
        await SyncService.queueOperation(
          action: 'delete',
          entity: 'saving',
          entityId: goal['id'],
        );
        
        setState(() {
          _goals.removeWhere((g) => g['id'] == goal['id']);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Offline: Goal will be deleted when online.',
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

  void _showGoalForm({Map<String, dynamic>? goal}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => _GoalFormSheet(
            goal: goal,
            currencySymbol: _currencySymbol,
            onSaved: () {
              Navigator.pop(ctx);
              _loadSavings();
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
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
                      child: const Icon(
                        Icons.arrow_back,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Savings Goals',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _showGoalForm(),
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
              child:
                  _isLoading
                      ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accent,
                        ),
                      )
                      : _error != null
                      ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      )
                      : _goals.isEmpty
                      ? const Center(
                        child: Text(
                          'No savings goals found.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      )
                      : RefreshIndicator(
                        onRefresh: _loadSavings,
                        color: AppColors.accent,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                          itemCount: _goals.length,
                          itemBuilder: (context, index) {
                            final goal = _goals[index];
                            final id = goal['id'] as int;
                            final isExpanded = _expandedGoalId == id;
                            final currentAmount = double.tryParse(goal['current_amount'].toString()) ?? 0;
                            final targetAmount = double.tryParse(goal['target_amount'].toString()) ?? 1;
                            final pct = (currentAmount / targetAmount * 100).clamp(0, 100);
                            final isCompleted = currentAmount >= targetAmount;
                            final history = goal['history'] as List? ?? [];

                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.xxl,
                                ),
                                boxShadow: AppShadows.card,
                              ),
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Opacity(
                                      opacity: isCompleted ? 0.7 : 1.0,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Header Row
                                          Row(
                                            children: [
                                              Container(
                                                width: 44,
                                                height: 44,
                                                decoration: BoxDecoration(
                                                  color: AppColors.accent,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        AppRadius.md,
                                                      ),
                                                ),
                                                child: const Icon(
                                                  Icons.savings_outlined,
                                                  color: AppColors.dark,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      goal['name'] ?? 'Goal',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                    if (goal['deadline'] !=
                                                        null)
                                                      Text(
                                                        'Deadline: ${goal['deadline'].toString().split('T')[0]}',
                                                        style: const TextStyle(
                                                          color:
                                                              AppColors.muted,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap:
                                                    () => _showGoalForm(
                                                      goal: goal,
                                                    ),
                                                child: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 18,
                                                  color: AppColors.muted,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              GestureDetector(
                                                onTap: () => _deleteGoal(goal),
                                                child: const Icon(
                                                  Icons.delete_outline,
                                                  size: 18,
                                                  color: AppColors.muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 20),

                                          // Progress
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                '$_currencySymbol${goal['current_amount']} saved',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                '${pct.toStringAsFixed(0)}%',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                  color: AppColors.text,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          LinearProgressIndicator(
                                            value: (pct / 100).clamp(0.0, 1.0),
                                            backgroundColor: AppColors.surface,
                                            color: AppColors.accent,
                                            minHeight: 10,
                                            borderRadius: BorderRadius.circular(
                                              5,
                                            ),
                                          ),

                                          const SizedBox(height: 20),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              // History Button
                                              GestureDetector(
                                                onTap: () {
                                                  setState(() {
                                                    _expandedGoalId =
                                                        isExpanded ? null : id;
                                                  });
                                                },
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                        vertical: 10,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.surface,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    border: Border.all(
                                                      color: AppColors.border,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        isExpanded
                                                            ? Icons
                                                                .keyboard_arrow_up
                                                            : Icons.history,
                                                        size: 16,
                                                        color: AppColors.text,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        isExpanded
                                                            ? 'Hide History'
                                                            : 'History',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: AppColors.text,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),

                                              // Add Money Button
                                              if (!isCompleted) ...[
                                                const Spacer(),
                                                GestureDetector(
                                                  onTap:
                                                      () => _showAddMoney(goal),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 16,
                                                          vertical: 10,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.dark,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                      boxShadow:
                                                          AppShadows.soft,
                                                    ),
                                                    child: Text(
                                                      '+ Add Money',
                                                      style: const TextStyle(
                                                        color: AppColors.accent,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ] else
                                                const Text(
                                                  'Completed',
                                                  style: TextStyle(
                                                    color: AppColors.text,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Expanded History
                                  if (isExpanded)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.fromLTRB(
                                        20,
                                        0,
                                        20,
                                        20,
                                      ),
                                      child:
                                          history.isEmpty
                                              ? const Padding(
                                                padding: EdgeInsets.only(
                                                  top: 8,
                                                ),
                                                child: Text(
                                                  'No history found.',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: AppColors.muted,
                                                  ),
                                                ),
                                              )
                                              : Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Divider(
                                                    color: AppColors.border,
                                                  ),
                                                  const SizedBox(height: 12),
                                                  ...history.map((t) {
                                                    final date = DateTime.parse(
                                                      t['date'],
                                                    );
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            bottom: 12,
                                                          ),
                                                      child: Row(
                                                        children: [
                                                          Container(
                                                            width: 6,
                                                            height: 6,
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color:
                                                                      AppColors
                                                                          .accent,
                                                                  shape:
                                                                      BoxShape
                                                                          .circle,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            width: 12,
                                                          ),
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  t['notes'] !=
                                                                              null &&
                                                                          t['notes']
                                                                              .isNotEmpty
                                                                      ? t['notes']
                                                                      : 'Saved money',
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        13,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500,
                                                                  ),
                                                                ),
                                                                Text(
                                                                  DateFormat(
                                                                    'MMM dd, yyyy',
                                                                  ).format(
                                                                    date,
                                                                  ),
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    color:
                                                                        AppColors
                                                                            .muted,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          Text(
                                                            '+$_currencySymbol${t['amount']}',
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color:
                                                                      AppColors
                                                                          .text,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  }).toList(),
                                                ],
                                              ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalFormSheet extends StatefulWidget {
  final Map<String, dynamic>? goal;
  final String currencySymbol;
  final VoidCallback onSaved;

  const _GoalFormSheet({
    this.goal,
    required this.currencySymbol,
    required this.onSaved,
  });

  @override
  State<_GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends State<_GoalFormSheet> {
  late TextEditingController _nameController;
  late TextEditingController _targetController;
  late TextEditingController _currentController;
  DateTime? _deadline;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.goal?['name'] ?? '');
    _targetController = TextEditingController(
      text: widget.goal?['target_amount']?.toString() ?? '',
    );
    _currentController = TextEditingController(
      text: widget.goal?['current_amount']?.toString() ?? '0',
    );
    if (widget.goal?['deadline'] != null) {
      _deadline = DateTime.parse(widget.goal!['deadline']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.goal == null ? 'New Goal' : 'Edit Goal',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              labelText: 'Goal Name',
              hintText: 'e.g. New Laptop',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _targetController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.text),
                  decoration: InputDecoration(
                    labelText: 'Target Amount',
                    prefixText: widget.currencySymbol,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _currentController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.text),
                  decoration: InputDecoration(
                    labelText: 'Initial Amount',
                    prefixText: widget.currencySymbol,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Deadline (Optional)',
              style: TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              _deadline == null
                  ? 'Not set'
                  : DateFormat('yyyy-MM-dd').format(_deadline!),
            ),
            trailing: const Icon(
              Icons.calendar_today,
              size: 18,
              color: AppColors.muted,
            ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    _deadline ?? DateTime.now().add(const Duration(days: 30)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (picked != null) setState(() => _deadline = picked);
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child:
                  _isSaving
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : Text(
                        widget.goal == null ? 'Create Goal' : 'Update Goal',
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final target = double.tryParse(_targetController.text) ?? 0;
    final current = double.tryParse(_currentController.text) ?? 0;

    if (name.isEmpty || target <= 0) return;

    setState(() => _isSaving = true);
    final data = {
      'name': name,
      'target_amount': target,
      'current_amount': current,
      if (_deadline != null)
        'deadline': DateFormat('yyyy-MM-dd').format(_deadline!),
    };
    ApiResult result;
    if (ConnectivityService.isOnline) {
      result = widget.goal == null
          ? await ApiService.createSavingGoal(data)
          : await ApiService.updateSavingGoal(widget.goal!['id'], data);
    } else {
      // Offline mode: queue operation
      await SyncService.queueOperation(
        action: widget.goal == null ? 'create' : 'update',
        entity: 'saving',
        data: data,
        entityId: widget.goal?['id'],
      );

      // ─── Optimistic Update ──────────────────────────────────────────
      if (widget.goal == null) {
        final newGoalJson = {
          'id': DateTime.now().millisecondsSinceEpoch,
          'name': name,
          'target_amount': target,
          'current_amount': current,
          'deadline': data['deadline'],
          'saved_percentage': (current / target * 100).clamp(0, 100),
          'history': [],
        };
        await CacheService.addSavingToCache(newGoalJson);
      } else {
        await CacheService.updateSavingInCache(widget.goal!['id'], {
          'name': name,
          'target_amount': target,
          'current_amount': current,
          'deadline': data['deadline'],
        });
      }
      // ───────────────────────────────────────────────────────────────
      
      result = ApiResult(data: null);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Offline: Goal saved locally and will sync later.',
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

    if (mounted) {
      setState(() => _isSaving = false);
      if (result.isSuccess) {
        HapticFeedback.mediumImpact();
        widget.onSaved();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? 'Error saving goal')),
        );
      }
    }
  }
}
class _AddMoneySheet extends StatefulWidget {
  final Map<String, dynamic> goal;
  final String currencySymbol;
  final VoidCallback onSuccess;

  const _AddMoneySheet({
    required this.goal,
    required this.currencySymbol,
    required this.onSuccess,
  });

  @override
  State<_AddMoneySheet> createState() => _AddMoneySheetState();
}

class _AddMoneySheetState extends State<_AddMoneySheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
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
          Text(
            'Add to ${widget.goal['name']}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 24),
          EspereInput(
            label: 'Amount',
            hint: '0.00',
            controller: _amountController,
            prefixText: widget.currencySymbol,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          EspereInput(
            label: 'Notes (Optional)',
            hint: 'e.g. Monthly contribution',
            controller: _noteController,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isSaving
                  ? null
                  : () async {
                      final amount = double.tryParse(_amountController.text) ?? 0;
                      if (amount <= 0) return;

                      final current = double.tryParse(widget.goal['current_amount'].toString()) ?? 0;
                      final target = double.tryParse(widget.goal['target_amount'].toString()) ?? 0;
                      if (current + amount > target) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Contribution exceeds target amount.')),
                        );
                        return;
                      }

                      setState(() => _isSaving = true);
                      ApiResult res;
                      if (ConnectivityService.isOnline) {
                        res = await ApiService.addMoneyToSavingGoal(
                          widget.goal['id'],
                          amount,
                          notes: _noteController.text.trim(),
                        );
                      } else {
                        // Offline mode: queue "add money" operation
                        await SyncService.queueOperation(
                          action: 'add_money',
                          entity: 'saving_add_money',
                          data: {
                            'amount': amount,
                            'notes': _noteController.text.trim(),
                          },
                          entityId: widget.goal['id'],
                        );
                        // ─── Optimistic Update ──────────────────────────────────────────
                        // Update dashboard totals
                        await CacheService.updateDashboardOptimistically(
                          'savings', 
                          amount, 
                          {
                            'id': DateTime.now().millisecondsSinceEpoch,
                            'amount': amount.toString(),
                            'type': 'expense', // Savings count as expense from balance
                            'category': {'name': 'Savings', 'icon': 'savings', 'color': '#C8E64A'},
                            'date': DateTime.now().toIso8601String(),
                            'notes': _noteController.text.trim(),
                            'payment_method_display': 'Internal',
                          }
                        );
                        // Update saving goal progress
                        await CacheService.addMoneyToSavingInCache(
                          widget.goal['id'], 
                          amount, 
                          notes: _noteController.text.trim()
                        );
                        // ───────────────────────────────────────────────────────────────

                        res = ApiResult(data: null);
                        
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Offline: Contribution saved locally and will sync later.',
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
                      
                      setState(() => _isSaving = false);

                      if (res.isSuccess) {
                        HapticFeedback.mediumImpact();
                        if (!mounted) return;
                        Navigator.pop(context);
                        widget.onSuccess();
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.dark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.dark,
                      ),
                    )
                  : const Text(
                      'Add Money',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
