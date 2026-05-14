/// Balance Card widget — the dark floating card on the dashboard.
///
/// Matches the Django template:
///   bg-mn-dark rounded-3xl p-6 text-white shadow-elevated
///   with gradient overlay, balance toggle, income/expense badges, action buttons
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BalanceCard extends StatefulWidget {
  final String totalBalance;
  final String monthlyIncome;
  final String monthlyExpenses;
  final String monthlySavings;
  final String currencySymbol;
  final VoidCallback? onAddIncome;
  final VoidCallback? onAddExpense;

  const BalanceCard({
    super.key,
    required this.totalBalance,
    required this.monthlyIncome,
    required this.monthlyExpenses,
    required this.monthlySavings,
    required this.currencySymbol,
    this.onAddIncome,
    this.onAddExpense,
  });

  @override
  State<BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends State<BalanceCard> {
  bool _isVisible = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(AppRadius.xxxl),
        boxShadow: AppShadows.elevated,
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Stack(
        children: [
          // Subtle gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.xxxl),
                gradient: RadialGradient(
                  center: Alignment.topRight,
                  radius: 0.6,
                  colors: [
                    AppColors.accent.withValues(alpha: 0.04),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: "Total Balance" + visibility toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Balance',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _isVisible = !_isVisible),
                      child: Icon(
                        _isVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Balance amount
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: animation,
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    _isVisible
                        ? '${widget.currencySymbol}${double.parse(widget.totalBalance.replaceAll(',', '')).toStringAsFixed(2)}'
                        : '••••••••',
                    key: ValueKey(_isVisible),
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accent,
                      letterSpacing: -1,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Monthly income/expense inline
                Row(
                  children: [
                    _StatBadge(
                      icon: Icons.arrow_upward,
                      value: '${widget.currencySymbol}${double.parse(widget.monthlyIncome.replaceAll(',', '')).toStringAsFixed(2)}',
                      color: AppColors.income,
                    ),
                    const SizedBox(width: 16),
                    _StatBadge(
                      icon: Icons.arrow_downward,
                      value: '${widget.currencySymbol}${double.parse(widget.monthlyExpenses.replaceAll(',', '')).toStringAsFixed(2)}',
                      color: AppColors.expense,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Savings badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.savings_outlined, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        'Saved ${widget.currencySymbol}${double.parse(widget.monthlySavings.replaceAll(',', '')).toStringAsFixed(2)} this month',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Action buttons — Income / Expense
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.north_east,
                        label: 'Income',
                        iconColor: AppColors.income,
                        onTap: widget.onAddIncome,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.south_west,
                        label: 'Expense',
                        iconColor: AppColors.expense,
                        onTap: widget.onAddExpense,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _StatBadge({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.2),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
