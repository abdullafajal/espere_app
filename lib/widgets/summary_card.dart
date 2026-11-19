/// Summary card (Income / Expenses / Savings) on the dashboard.
///
/// Matches the Django template:
///   mn-card p-4 text-center with icon badge, label, value
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const SummaryCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        children: [
          // Icon badge — w-9 h-9 bg-mn-accent rounded-xl
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
            child: Icon(icon, size: 19, color: AppColors.dark),
          ),
          const SizedBox(height: 8),
          // Label — text-xs text-mn-muted
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 2),
          // Value — text-sm font-bold
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
