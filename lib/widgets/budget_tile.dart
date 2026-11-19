import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import 'espere_swipe_action.dart';
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
  String _m(dynamic v) {
    final d = double.tryParse(v.toString()) ?? 0;
    final f = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: d == d.roundToDouble() ? 0 : 2);
    return '${widget.currencySymbol}${f.format(d)}';
  }

  @override
  Widget build(BuildContext context) {
    final isExceeded = widget.budget['is_exceeded'] == true;
    final pct = double.tryParse(widget.budget['percentage'].toString()) ?? 0;
    final category = widget.budget['category'];

    Widget content = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(color: AppColors.categoryFill, shape: BoxShape.circle),
                child: Icon(
                  IconMapper.map(category['icon']),
                  color: AppColors.categoryInk,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category['name'] ?? 'Category',
                      style: AppText.rowTitle,
                    ),
                    Text(
                      DateFormat('MMMM yyyy').format(
                        DateTime.parse(widget.budget['month']),
                      ),
                      style: AppText.rowSub,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.muted),
                onSelected: (v) {
                  if (v == 'edit') widget.onEdit?.call();
                  if (v == 'delete') widget.onDelete?.call();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 20), SizedBox(width: 10), Text('Edit')])),
                  PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 20), SizedBox(width: 10), Text('Delete')])),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_m(widget.budget['spent'])} spent',
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
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            backgroundColor: AppColors.surface,
            color: AppColors.dark,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
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
                'Limit: ${_m(widget.budget['amount'])}',
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
                      'Budget exceeded by ${_m(double.parse(widget.budget['spent'].toString()) - double.parse(widget.budget['amount'].toString()))}',
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

    content = EspereSwipeAction(
      dismissKey: ValueKey(widget.budget['id']),
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
      bgIcon: Icons.delete_outline_rounded,
      bgColor: AppColors.dark,
      bgIconColor: AppColors.accent,
      secBgIcon: Icons.edit_rounded,
      secBgColor: AppColors.accent,
      secBgIconColor: AppColors.dark,
      borderRadius: BorderRadius.circular(AppRadius.xxl),
      child: content,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: AppShadows.soft,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        child: content,
      ),
    );
  }
}
