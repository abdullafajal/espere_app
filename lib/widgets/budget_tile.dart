import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../utils/icon_mapper.dart';

class BudgetTile extends StatefulWidget {
  final Map<String, dynamic> budget;
  final String currencySymbol;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const BudgetTile({
    super.key,
    required this.budget,
    required this.currencySymbol,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<BudgetTile> createState() => _BudgetTileState();
}

class _BudgetTileState extends State<BudgetTile> {
  double _swipeProgress = 0.0;

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
    final isExceeded = widget.budget['is_exceeded'] == true;
    final pct = double.tryParse(widget.budget['percentage'].toString()) ?? 0;
    final category = widget.budget['category'];
    final categoryColor = _parseColor(category['color']);

    Widget content = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
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
                  borderRadius: BorderRadius.circular(AppRadius.md),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                        DateTime.parse(widget.budget['month']),
                      ),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${widget.currencySymbol}${widget.budget['spent']} spent',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isExceeded ? AppColors.accent : AppColors.text,
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
            borderRadius: BorderRadius.circular(5),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Spent so far',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                ),
              ),
              Text(
                'Limit: ${widget.currencySymbol}${widget.budget['amount']}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
          
          if (isExceeded) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppColors.dark,
                borderRadius: BorderRadius.circular(
                  AppRadius.md,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Budget exceeded by ${widget.currencySymbol}${double.parse(widget.budget['spent'].toString()) - double.parse(widget.budget['amount'].toString())}',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    // Calculate dynamic scale based on swipe progress.
    final double iconScale = (_swipeProgress * 4.0).clamp(0.8, 1.8);

    content = Dismissible(
      key: ValueKey(widget.budget['id']),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (widget.onDelete != null) widget.onDelete!();
          return false;
        } else if (direction == DismissDirection.endToStart) {
          if (widget.onEdit != null) widget.onEdit!();
          return false;
        }
        return false;
      },
      onUpdate: (details) {
        if (details.reached && !details.previousReached) {
          HapticFeedback.vibrate();
        }
        setState(() {
          _swipeProgress = details.progress;
        });
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: AppColors.dark,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Transform.scale(
          scale: iconScale,
          child: Icon(Icons.delete, color: categoryColor),
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: categoryColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Transform.scale(
          scale: iconScale,
          child: const Icon(Icons.edit, color: AppColors.dark),
        ),
      ),
      child: content,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: content,
      ),
    );
  }
}
