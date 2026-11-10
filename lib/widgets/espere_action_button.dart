import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Standard 36x36 header action button. Pair with [EspereHeader.trailing]
/// so every screen's header buttons share the same size, radius and shadow.
class EspereActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  /// Filled with the accent colour (primary action such as "add").
  final bool primary;

  /// Shows a small notification dot in the top-right corner.
  final bool showBadge;

  const EspereActionButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.primary = false,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = primary ? AppColors.accent : AppColors.card;
    final fg = primary ? AppColors.dark : AppColors.text;
    return GestureDetector(
      onTap: onPressed == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              onPressed!();
            },
      child: SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: AppShadows.soft,
              ),
              child: Icon(icon, color: fg, size: 20),
            ),
            if (showBadge)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.card, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
