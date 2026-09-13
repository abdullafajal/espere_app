import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// A universal, fully customizable swipe action widget with haptic feedback
/// and smooth scale animations.
class EspereSwipeAction extends StatefulWidget {
  final Key dismissKey;
  final DismissDirection direction;
  final Future<bool?> Function(DismissDirection) confirmDismiss;
  final Widget child;

  final IconData? bgIcon;
  final Color? bgColor;
  final Color? bgIconColor;
  final Alignment? bgAlignment;

  final IconData? secBgIcon;
  final Color? secBgColor;
  final Color? secBgIconColor;
  final Alignment? secBgAlignment;
  final BorderRadius? borderRadius;

  const EspereSwipeAction({
    super.key,
    required this.dismissKey,
    required this.direction,
    required this.confirmDismiss,
    required this.child,
    this.bgIcon,
    this.bgColor,
    this.bgIconColor,
    this.bgAlignment,
    this.secBgIcon,
    this.secBgColor,
    this.secBgIconColor,
    this.secBgAlignment,
    this.borderRadius,
  });

  @override
  State<EspereSwipeAction> createState() => _EspereSwipeActionState();
}

class _EspereSwipeActionState extends State<EspereSwipeAction> {
  double _swipeProgress = 0.0;
  DateTime? _lastVibration;

  @override
  Widget build(BuildContext context) {
    final double iconScale = (_swipeProgress * 4.0).clamp(0.8, 1.8);

    Widget? bg;
    if (widget.bgIcon != null) {
      bg = Container(
        decoration: BoxDecoration(
          color: widget.bgColor,
        ),
        alignment: widget.bgAlignment ?? Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Transform.scale(
          scale: iconScale,
          child: Icon(widget.bgIcon, color: widget.bgIconColor),
        ),
      );
    }

    Widget? secBg;
    if (widget.secBgIcon != null) {
      secBg = Container(
        decoration: BoxDecoration(
          color: widget.secBgColor,
        ),
        alignment: widget.secBgAlignment ?? Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Transform.scale(
          scale: iconScale,
          child: Icon(widget.secBgIcon, color: widget.secBgIconColor),
        ),
      );
    }

    return Dismissible(
      key: widget.dismissKey,
      direction: widget.direction,
      onUpdate: (details) {
        if (details.reached) {
          final now = DateTime.now();
          // Vibrate continuously every 50 milliseconds while held past threshold
          if (_lastVibration == null || now.difference(_lastVibration!).inMilliseconds > 50) {
            HapticFeedback.lightImpact();
            _lastVibration = now;
          }
        } else {
          _lastVibration = null; // Reset when pulled back
        }
        setState(() => _swipeProgress = details.progress);
      },
      confirmDismiss: widget.confirmDismiss,
      background: bg,
      secondaryBackground: secBg,
      child: widget.child,
    );
  }
}

/// A pre-configured swipe-to-delete widget (Swipes Right to Left)
class EspereSwipeToDelete extends StatelessWidget {
  final Key dismissKey;
  final Future<bool?> Function() onConfirmDelete;
  final Widget child;
  final BorderRadius? borderRadius;

  const EspereSwipeToDelete({
    super.key,
    required this.dismissKey,
    required this.onConfirmDelete,
    required this.child,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return EspereSwipeAction(
      dismissKey: dismissKey,
      direction: DismissDirection.endToStart,
      confirmDismiss: (dir) => onConfirmDelete(),
      secBgIcon: Icons.delete,
      secBgColor: AppColors.error.withOpacity(0.15),
      secBgIconColor: AppColors.error,
      borderRadius: borderRadius,
      child: child,
    );
  }
}

/// A pre-configured swipe-to-edit widget (Swipes Left to Right)
class EspereSwipeToEdit extends StatelessWidget {
  final Key dismissKey;
  final Future<bool?> Function() onConfirmEdit;
  final Widget child;

  const EspereSwipeToEdit({
    super.key,
    required this.dismissKey,
    required this.onConfirmEdit,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return EspereSwipeAction(
      dismissKey: dismissKey,
      direction: DismissDirection.startToEnd,
      confirmDismiss: (dir) => onConfirmEdit(),
      bgIcon: Icons.edit,
      bgColor: AppColors.accent.withOpacity(0.15),
      bgIconColor: AppColors.accent,
      child: child,
    );
  }
}
