import 'dart:async';
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
  bool _reached = false;
  Timer? _zigzag;
  int _zigTick = 0;

  /// Zig-zag haptics while the action is armed: strong / light / strong ...
  void _startZigzag() {
    _zigzag?.cancel();
    _zigTick = 0;
    _zigzag = Timer.periodic(const Duration(milliseconds: 70), (_) {
      _zigTick++;
      _zigTick.isEven
          ? HapticFeedback.heavyImpact()
          : HapticFeedback.selectionClick();
      if (_zigTick > 40) _stopZigzag(); // safety stop
    });
  }

  void _stopZigzag() {
    _zigzag?.cancel();
    _zigzag = null;
  }

  @override
  void dispose() {
    _stopZigzag();
    super.dispose();
  }

  /// Icon fades in while dragging and "pops" once the action is armed.
  Widget _icon(IconData icon, Color? color) {
    return AnimatedScale(
      scale: _reached ? 1.4 : 1.0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      child: Opacity(
        opacity: (0.35 + _swipeProgress * 3.0).clamp(0.35, 1.0),
        child: Icon(icon, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget? bg;
    if (widget.bgIcon != null) {
      bg = Container(
        decoration: BoxDecoration(
          color: widget.bgColor,
        ),
        alignment: widget.bgAlignment ?? Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: _icon(widget.bgIcon!, widget.bgIconColor),
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
        child: _icon(widget.secBgIcon!, widget.secBgIconColor),
      );
    }

    final dismissible = Dismissible(
      key: widget.dismissKey,
      direction: widget.direction,
      onUpdate: (details) {
        // One firm tick the moment the action is armed (and a light one when
        // the user pulls back), instead of buzzing continuously.
        if (details.reached != _reached) {
          if (details.reached) {
            HapticFeedback.mediumImpact();
            _startZigzag();
          } else {
            _stopZigzag();
            HapticFeedback.selectionClick();
          }
        }
        setState(() {
          _reached = details.reached;
          _swipeProgress = details.progress;
        });
      },
      confirmDismiss: (direction) {
        _stopZigzag(); // finger released
        return widget.confirmDismiss(direction);
      },
      background: bg,
      secondaryBackground: secBg,
      child: widget.child,
    );

    // Clip the action backgrounds with the card's own radius so their corners
    // always match the card, whatever the parent does.
    if (widget.borderRadius == null) return dismissible;
    return ClipRRect(borderRadius: widget.borderRadius!, child: dismissible);
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
