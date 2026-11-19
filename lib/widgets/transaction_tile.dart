/// One transaction row: category icon in a grey circle, payee (or category), category ·
/// date · method underneath, and the amount with its "+" / "−" sign.
///
/// With [showActions] the row also has a visible "⋮" button (Edit / Delete) and keeps the
/// swipe gestures as a shortcut.
import 'package:flutter/material.dart';
import '../theme/motion.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/transaction.dart';
import '../utils/icon_mapper.dart';
import 'espere_swipe_action.dart';

class TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  final String currencySymbol;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool showActions;

  /// Draw the row on its own white card (lists) or flat (inside an existing card).
  final bool card;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.currencySymbol = '₹',
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.showActions = false,
    this.card = true,
  });

  /// "+₹42,000" / "−₹60" (true minus sign, Indian digit grouping).
  static String amountText(TransactionModel t, String symbol) {
    final v = double.tryParse(t.amount) ?? 0;
    final whole = v == v.roundToDouble();
    final f = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: whole ? 0 : 2);
    return '${t.isIncome ? '+' : '−'}$symbol${f.format(v)}';
  }

  static String _method(TransactionModel t) => switch (t.paymentMethod) {
        'upi' => 'UPI',
        'cash' => 'Cash',
        'card' => 'Card',
        'bank' => 'Bank',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final local = t.date.toLocal();
    final title = t.notes.trim().isNotEmpty ? t.notes.trim() : t.category.name;
    final sub = <String>[
      if (t.notes.trim().isNotEmpty) t.category.name,
      '${DateFormat('d MMM').format(local)}, ${DateFormat('h:mm a').format(local)}',
      if (_method(t).isNotEmpty) _method(t),
    ].join(' · ');

    Widget row = Material(
      color: card ? AppColors.card : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 10, showActions ? 2 : 14, 10),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(color: AppColors.categoryFill, shape: BoxShape.circle),
                child: Icon(IconMapper.map(t.category.icon), size: 21, color: AppColors.categoryInk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(sub, style: AppText.rowSub, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(amountText(t, currencySymbol), style: AppText.amount),
              if (showActions)
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.muted),
                  onSelected: (v) {
                    AppHaptics.tap();
                    if (v == 'edit') onEdit?.call();
                    if (v == 'delete') onDelete?.call();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [Icon(Icons.edit_rounded, size: 20), SizedBox(width: 10), Text('Edit')]),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [Icon(Icons.delete_outline_rounded, size: 20), SizedBox(width: 10), Text('Delete')]),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );

    if (showActions) {
      row = EspereSwipeAction(
        dismissKey: ValueKey(t.id),
        direction: DismissDirection.horizontal,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            onDelete?.call();
          } else if (direction == DismissDirection.endToStart) {
            onEdit?.call();
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
        child: row,
      );
    }

    if (!card) return row;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: AppShadows.soft,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.xxl), child: row),
    );
  }
}
