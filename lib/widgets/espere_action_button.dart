import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Round 44 px header action button. Pair with [EspereHeader.trailing] so every
/// screen's header buttons share the same size and look.
class EspereActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  /// Filled lime (the screen's main action, such as "add").
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
    final bg = primary ? AppColors.accent : AppColors.card;
    final button = GestureDetector(
      onTap: onPressed == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onPressed!();
            },
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
                boxShadow: primary ? AppShadows.accent : AppShadows.soft,
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
                    color: primary ? AppColors.dark : AppColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: bg, width: 2),
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
