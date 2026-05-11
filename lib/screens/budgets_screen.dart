import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  List<Map<String, dynamic>> _budgets = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBudgets();
  }

  Future<void> _loadBudgets() async {
    final result = await ApiService.getBudgets();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.isSuccess) {
        _budgets = result.data!;
      } else {
        _error = result.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Text(
            'Budgets',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
        ),
        
        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.muted)))
                  : _budgets.isEmpty
                      ? const Center(
                          child: Text('No budgets found. Create one on the website.',
                              style: TextStyle(color: AppColors.muted)))
                      : RefreshIndicator(
                          onRefresh: _loadBudgets,
                          color: AppColors.accent,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: _budgets.length,
                            itemBuilder: (context, index) {
                              final budget = _budgets[index];
                              final isExceeded = budget['is_exceeded'] == true;
                              final pct = double.tryParse(budget['percentage'].toString()) ?? 0;
                              
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(AppRadius.xxl),
                                  boxShadow: AppShadows.card,
                                  border: Border.all(
                                    color: isExceeded ? AppColors.error : Colors.transparent,
                                    width: 1,
                                  ),
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
                                            color: AppColors.accent,
                                            borderRadius: BorderRadius.circular(AppRadius.md),
                                          ),
                                          child: Icon(
                                            Icons.category, // You can map budget['category']['icon'] here later
                                            color: AppColors.dark,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                budget['category']['name'] ?? 'Category',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: AppColors.text,
                                                ),
                                              ),
                                              Text(
                                                // Simplified month string
                                                'This Month', 
                                                style: const TextStyle(
                                                  color: AppColors.muted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Icon(Icons.edit, size: 16, color: AppColors.muted),
                                            const SizedBox(width: 12),
                                            Icon(Icons.delete, size: 16, color: AppColors.muted),
                                          ],
                                        )
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    
                                    // Progress info
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '₹${budget['spent']} spent',
                                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                        ),
                                        Text(
                                          '${pct.toStringAsFixed(0)}%',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: isExceeded ? AppColors.error : AppColors.text,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(
                                      value: pct / 100,
                                      backgroundColor: AppColors.surface,
                                      color: isExceeded ? AppColors.error : (pct > 75 ? AppColors.warning : AppColors.accent),
                                      minHeight: 10,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('₹0', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                        Text('₹${budget['amount']}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                      ],
                                    ),
                                    
                                    // Warning message
                                    if (isExceeded) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: AppColors.dark,
                                          borderRadius: BorderRadius.circular(AppRadius.md),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.warning, size: 16, color: AppColors.accent),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Budget exceeded',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: AppColors.accent,
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
