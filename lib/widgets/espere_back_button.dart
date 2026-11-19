import 'package:flutter/material.dart';
import '../theme/motion.dart';
import '../theme/app_theme.dart';

/// Round 44 px back button used in every screen header.
class EspereBackButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const EspereBackButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: GestureDetector(
        onTap: () {
          AppHaptics.tap();
          if (onPressed != null) {
            onPressed!();
          } else if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.card,
            shape: BoxShape.circle,
            boxShadow: AppShadows.soft,
          ),
          child: const Icon(Icons.arrow_back_rounded, color: AppColors.text, size: 22),
        ),
      ),
    );
  }
}
