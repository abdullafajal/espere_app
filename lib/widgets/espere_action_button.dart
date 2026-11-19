import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';

/// Round 44 px header action button. Pair with [EspereHeader.trailing] so every
/// screen's header buttons share the same size and look.
class EspereActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  /// The screen's main action (such as "add"): a firmer haptic. Every header button
  /// looks the same, white with an ink icon, in any app colour.
  final bool primary;

  /// Shows a small lime dot in the top-right corner.
  final bool showBadge;

  /// Read out by screen readers; describe what the button does.
  final String? tooltip;

  const EspereActionButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.primary = false,
    this.showBadge = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    const bg = AppColors.card;
    final button = SpringPress(
      haptic: primary ? HapticKind.press : HapticKind.tap,
      onTap: onPressed,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                boxShadow: AppShadows.soft,
              ),
              child: Icon(icon, color: AppColors.dark, size: 22),
            ),
            if (showBadge)
              Positioned(
                right: 9,
                top: 9,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.dark, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
