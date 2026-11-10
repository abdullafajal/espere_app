import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Standard filter chip used on every list screen so filters look identical
/// everywhere (same height, radius, text size and active state).
class EspereFilterChip extends StatelessWidget {
  static const double height = 40;

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// True when a non-default filter is applied (chip turns dark).
  final bool active;

  const EspereFilterChip({
    super.key,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active ? AppColors.dark : AppColors.card;
    final fg = active ? AppColors.accent : AppColors.text;
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      onLongPress: onLongPress,
      child: Container(
        height: height,
        padding: const EdgeInsets.only(left: 14, right: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: active ? AppColors.dark : AppColors.border),
          boxShadow: AppShadows.soft,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 22,
              color: active ? AppColors.accent : AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}
