import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppToast {
  static void success(BuildContext context, String message) {
    _show(context, message, Icons.check_circle, AppColors.accent);
  }

  static void error(BuildContext context, String message) {
    _show(context, message, Icons.error, AppColors.error);
  }

  static void info(BuildContext context, String message) {
    _show(context, message, Icons.info, AppColors.accent);
  }

  static void _show(
    BuildContext context,
    String message,
    IconData icon,
    Color color,
  ) {
    final overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;

    final animationController = AnimationController(
      vsync: overlayState,
      duration: const Duration(milliseconds: 300),
    );

    final animation = CurvedAnimation(
      parent: animationController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, (1.0 - animation.value) * -50),
                  child: Opacity(
                    opacity: animation.value.clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.dark,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlayState.insert(overlayEntry);
    animationController.forward();

    Timer(const Duration(seconds: 4), () {
      if (overlayEntry.mounted) {
        animationController.reverse().then((_) {
          if (overlayEntry.mounted) overlayEntry.remove();
        });
      }
    });
  }
}
