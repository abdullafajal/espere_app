import 'morph_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import 'spring_menu.dart';
import 'espere_swipe_action.dart';
import '../utils/icon_mapper.dart';

class BudgetTile extends StatefulWidget {
  final Map<String, dynamic> budget;
  final String currencySymbol;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Opens the budget (its entries this month).
  final VoidCallback? onTap;

  const BudgetTile({
    super.key,
    required this.budget,
    required this.currencySymbol,
    this.onEdit,
    this.onDelete,
    this.onTap,
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

  /// "Every month · +₹500 carried" or "This month only".
  String _repeatLine() {
    final repeat = widget.budget['repeat'] != false;
    final carried = double.tryParse(widget.budget['carried']?.toString() ?? '') ?? 0;
    return [
      repeat ? 'Every month' : 'This month only',
      if (carried > 0) '+${_m(carried)} carried',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final isExceeded = widget.budget['is_exceeded'] == true;
    final pct = double.tryParse(widget.budget['percentage'].toString()) ?? 0;
    final category = widget.budget['category'];

    Widget content = Container(
      padding: const EdgeInsets.all(16),
      // Transparent when tappable, so the press ripple shows.
      decoration: BoxDecoration(
        color: widget.onTap != null ? null : AppColors.card,
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
                child: MorphIcon(
                  id: widget.budget['id'],
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
                    MorphText(id: widget.budget['id'], 
                      category['name'] ?? 'Category',
                      style: AppText.rowTitle,
                    ),
                    MorphText(id: widget.budget['id'],
                      _repeatLine(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowSub,
                    ),
                  ],
                ),
              ),
              SpringMenuButton<String>(
                items: SpringMenuButton.editDelete(),
                onSelected: (v) {
                  if (v == 'edit') widget.onEdit?.call();
                  if (v == 'delete') widget.onDelete?.call();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              MorphText(id: widget.budget['id'], 
                '${_m(widget.budget['spent'])} spent',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              MorphText(id: widget.budget['id'], 
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
              MorphText(id: widget.budget['id'], 
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
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MorphText(id: widget.budget['id'], 
                      'Budget exceeded by ${_m(double.parse(widget.budget['spent'].toString()) - double.parse(widget.budget['amount'].toString()))}',
                      style: TextStyle(
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

    if (widget.onTap != null) {
      content = Material(
        color: AppColors.card,
        child: InkWell(onTap: widget.onTap, child: content),
      );
    }

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
