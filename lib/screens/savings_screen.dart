import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});

  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  List<Map<String, dynamic>> _goals = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavings();
  }

  Future<void> _loadSavings() async {
    final result = await ApiService.getSavings();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.isSuccess) {
        _goals = result.data!;
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
            'Savings Goals',
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
                  : _goals.isEmpty
                      ? const Center(
                          child: Text('No savings goals found. Create one on the website.',
                              style: TextStyle(color: AppColors.muted)))
                      : RefreshIndicator(
                          onRefresh: _loadSavings,
                          color: AppColors.accent,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: _goals.length,
                            itemBuilder: (context, index) {
                              final goal = _goals[index];
                              final pct = double.tryParse(goal['percentage'].toString()) ?? 0;
                              final isCompleted = goal['is_completed'] == true;
                              
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(AppRadius.xxl),
                                  boxShadow: AppShadows.card,
                                ),
                                child: Opacity(
                                  opacity: isCompleted ? 0.75 : 1.0,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Header
                                      Row(
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: AppColors.accent,
                                              borderRadius: BorderRadius.circular(AppRadius.md),
                                            ),
                                            child: const Icon(Icons.flag, color: AppColors.dark),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  goal['name'] ?? 'Goal',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                if (goal['deadline'] != null)
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.event, size: 12, color: AppColors.muted),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        goal['deadline'].toString().split('T')[0], // Simplified
                                                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                                      ),
                                                    ],
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
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      
                                      // Progress
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '₹${goal['current_amount']} saved',
                                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.accent,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '${pct.toStringAsFixed(0)}%',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10,
                                                color: AppColors.dark,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      LinearProgressIndicator(
                                        value: pct / 100,
                                        backgroundColor: AppColors.surface,
                                        color: isCompleted ? AppColors.accent : (pct > 75 ? AppColors.warning : AppColors.accent),
                                        minHeight: 10,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('₹0', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                                          Text('₹${goal['target_amount']}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                        ],
                                      ),
                                      
                                      // Bottom Section
                                      if (!isCompleted) ...[
                                        const SizedBox(height: 16),
                                        const Divider(color: AppColors.border, height: 1),
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text.rich(
                                              TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: '₹${goal['remaining'] ?? '0'}',
                                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.text, fontSize: 12),
                                                  ),
                                                  const TextSpan(
                                                    text: ' remaining',
                                                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: AppColors.dark,
                                                borderRadius: BorderRadius.circular(AppRadius.md),
                                                boxShadow: AppShadows.soft,
                                              ),
                                              child: const Text(
                                                '+ Add',
                                                style: TextStyle(
                                                  color: AppColors.accent,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
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
