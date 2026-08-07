/// Transaction tile — displays a single transaction row.
///
/// Matches the Django template:
///   mn-card p-4 with icon badge, category name, date, amount
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/transaction.dart';
import '../utils/icon_mapper.dart';

class TransactionTile extends StatefulWidget {
  final TransactionModel transaction;
  final String currencySymbol;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool showActions;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.currencySymbol = '₹',
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.showActions = false,
  });

  @override
  State<TransactionTile> createState() => _TransactionTileState();
}

class _TransactionTileState extends State<TransactionTile> {
  double _swipeProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d');
    final timeFormat = DateFormat('h:mm a');

    final catColorStr = widget.transaction.category.color.replaceFirst('#', '');
    final catColor = Color(int.parse('FF$catColorStr', radix: 16));

    Widget content = GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        color: AppColors.card,
        child: Row(
          children: [
            // Category icon badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: catColor,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                IconMapper.map(widget.transaction.category.icon),
                size: 22,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(width: 12),

            // Name + Date + Notes
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.transaction.category.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${dateFormat.format(widget.transaction.date.toLocal())} · ${timeFormat.format(widget.transaction.date.toLocal())}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.transaction.paymentMethodDisplay,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                    ),
                  ),
                  if (widget.transaction.notes.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.transaction.notes,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.muted.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  widget.transaction.formattedAmount(widget.currencySymbol),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: widget.transaction.isIncome
                        ? const Color(0xFFA7C431)
                        : AppColors.text,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (widget.showActions) {
      final catColorStr = widget.transaction.category.color.replaceFirst('#', '');
      final catColor = Color(int.parse('FF$catColorStr', radix: 16));

      // Calculate dynamic scale based on swipe progress.
      // Starts at 0.8, reaches 1.8 scale.
      final double iconScale = (_swipeProgress * 4.0).clamp(0.8, 1.8);

      content = Dismissible(
        key: ValueKey(widget.transaction.id),
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
          color: AppColors.dark,
          child: Transform.scale(
            scale: iconScale,
            child: Icon(Icons.delete, color: catColor),
          ),
        ),
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: catColor,
          child: Transform.scale(
            scale: iconScale,
            child: const Icon(Icons.edit, color: AppColors.dark),
          ),
        ),
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        child: content,
      ),
    );
  }
}
