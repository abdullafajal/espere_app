/// One category budget as a row: icon, name, what is left (or how much over) and how
/// it repeats, the amount spent of the limit on the right, a progress bar underneath
/// and a "⋮" menu. Rows sit together in one card on the Budgets screen ([grouped]).
/// Swipe right to delete, left to edit; tap to open the budget.
library;

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

  /// Spent this month counted on the phone (fresher than the server's number).
  final double? spent;

  /// Drawn flat, as one row of a shared card (no own card, shadow or margin).
  final bool grouped;

  const BudgetTile({
    super.key,
    required this.budget,
    required this.currencySymbol,
    this.onEdit,
    this.onDelete,
    this.onTap,
    this.spent,
    this.grouped = false,
  });

  @override
  State<BudgetTile> createState() => _BudgetTileState();
}

class _BudgetTileState extends State<BudgetTile> {
  String _m(double d) {
    final f = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: d == d.roundToDouble() ? 0 : 2);
    return '${widget.currencySymbol}${f.format(d)}';
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.budget;
    final id = b['id'];
    final category = b['category'] is Map ? b['category'] as Map : const {};
    final limit = double.tryParse(b['amount'].toString()) ?? 0;
    final spent = widget.spent ?? (double.tryParse(b['spent']?.toString() ?? '') ?? 0);
    final fraction = limit <= 0 ? 0.0 : spent / limit;
    final over = spent > limit && limit > 0;
    final repeat = b['repeat'] != false;
    final carried = double.tryParse(b['carried']?.toString() ?? '') ?? 0;

    final status = over ? '${_m((spent - limit).roundToDouble())} over' : '${_m((limit - spent).roundToDouble())} left';
    final sub = [
      repeat ? 'Every month' : 'This month only',
      if (carried > 0) '+${_m(carried)} carried',
    ].join(' · ');

    Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 14),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: over ? AppColors.dark : AppColors.categoryFill,
                  shape: BoxShape.circle,
                ),
                child: MorphIcon(
                  id: id,
                  IconMapper.map(category['icon']?.toString() ?? 'category'),
                  color: over ? AppColors.accent : AppColors.categoryInk,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MorphText(
                      id: id,
                      category['name']?.toString() ?? 'Category',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowTitle,
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: status,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: over ? AppColors.text : AppColors.muted,
                          ),
                        ),
                        TextSpan(text: ' · $sub'),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowSub,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MorphText(id: id, _m(spent.roundToDouble()), style: AppText.amount),
                  const SizedBox(height: 2),
                  MorphText(id: id, 'of ${_m(limit)}', style: AppText.rowSub.copyWith(fontSize: 11)),
                ],
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
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: fraction.clamp(0.0, 1.0)),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: 8,
                        backgroundColor: AppColors.surface,
                        // Under 80% the bar is the app colour; near or over the limit it turns dark.
                        color: fraction >= 0.8 ? AppColors.dark : AppColors.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 38,
                  child: Text(
                    '${(fraction * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: fraction >= 0.8 ? AppColors.text : AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    content = Material(
      color: AppColors.card,
      child: InkWell(onTap: widget.onTap, child: content),
    );

    content = EspereSwipeAction(
      dismissKey: ValueKey(id),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          widget.onDelete?.call();
        } else if (direction == DismissDirection.endToStart) {
          widget.onEdit?.call();
        }
        return false;
      },
      bgIcon: Icons.delete_outline_rounded,
      bgColor: AppColors.dark,
      bgIconColor: AppColors.accent,
      secBgIcon: Icons.edit_rounded,
      secBgColor: AppColors.accent,
      secBgIconColor: AppColors.dark,
      borderRadius: widget.grouped ? BorderRadius.zero : BorderRadius.circular(AppRadius.xxl),
      child: content,
    );

    if (widget.grouped) return content;
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
