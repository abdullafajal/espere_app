/// The ⋮ menu used everywhere (Edit / Delete and similar): the button presses with the
/// app's spring and a haptic, and the menu grows out of the button on [AppMotion.move]
/// (one soft overshoot) with its rows following a beat behind. Picking a row ticks.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';

class SpringMenuItem<T> {
  final T value;
  final IconData icon;
  final String label;

  /// Shown last, after a divider (Delete, Leave).
  final bool destructive;

  const SpringMenuItem(this.value, this.icon, this.label, {this.destructive = false});
}

class SpringMenuButton<T> extends StatelessWidget {
  final List<SpringMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final String tooltip;

  /// The button's look; a grey ⋮ when null.
  final Widget? child;

  const SpringMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.tooltip = 'More',
    this.child,
  });

  /// The usual Edit / Delete pair.
  static List<SpringMenuItem<String>> editDelete() => const [
        SpringMenuItem('edit', Icons.edit_rounded, 'Edit'),
        SpringMenuItem('delete', Icons.delete_outline_rounded, 'Delete', destructive: true),
      ];

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    final picked = await Navigator.of(context).push<T>(_SpringMenuRoute<T>(origin: origin, items: items));
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Builder(
        builder: (ctx) => SpringPress(
          haptic: HapticKind.press,
          scale: 0.86,
          onTap: () => _open(ctx),
          child: child ??
              const SizedBox(
                width: 40,
                height: 44,
                child: Icon(Icons.more_vert_rounded, size: 20, color: AppColors.muted),
              ),
        ),
      ),
    );
  }
}

class _SpringMenuRoute<T> extends PopupRoute<T> {
  final Rect origin;
  final List<SpringMenuItem<T>> items;
  _SpringMenuRoute({required this.origin, required this.items});

  @override
  Color? get barrierColor => const Color(0x14000000);
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'Close menu';

  // Opening is driven by the spring inside the menu; closing is a quick fade.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 1);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 140);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondary, Widget child) =>
      FadeTransition(opacity: animation, child: child);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    const width = 196.0;
    final rows = items.length + (items.any((i) => i.destructive) && items.length > 1 ? 1 : 0);
    final height = items.length * 48.0 + (rows > items.length ? 9 : 0) + 12;
    // Below the button if it fits, otherwise above; right edges line up.
    final below = origin.bottom + 4 + height < screen.height - media.padding.bottom - 8;
    final top = below ? origin.bottom + 4 : origin.top - 4 - height;
    final left = (origin.right - width).clamp(12.0, screen.width - width - 12.0);
    return Stack(
      children: [
        Positioned(
          left: left,
          top: math.max(media.padding.top + 8, top),
          width: width,
          child: _SpringMenu<T>(items: items, growFrom: below ? Alignment.topRight : Alignment.bottomRight),
        ),
      ],
    );
  }
}

class _SpringMenu<T> extends StatefulWidget {
  final List<SpringMenuItem<T>> items;
  final Alignment growFrom;
  const _SpringMenu({super.key, required this.items, required this.growFrom});

  @override
  State<_SpringMenu<T>> createState() => _SpringMenuState<T>();
}

class _SpringMenuState<T> extends State<_SpringMenu<T>> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this, value: 0)
    ..animateWith(SpringSimulation(AppMotion.move, 0, 1, 0));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normal = widget.items.where((i) => !i.destructive).toList();
    final danger = widget.items.where((i) => i.destructive).toList();
    final ordered = [...normal, ...danger];
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = _c.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.55 + 0.45 * v,
            alignment: widget.growFrom,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: AppShadows.elevated,
              ),
              child: Material(
                color: AppColors.card,
                elevation: 0,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < ordered.length; i++) ...[
                        if (i == normal.length && normal.isNotEmpty && danger.isNotEmpty)
                          const Divider(height: 9, indent: 14, endIndent: 14),
                        // Rows settle a beat after the card.
                        Transform.translate(
                          offset: Offset(0, (1 - v).clamp(-1.0, 1.0) * (8.0 + i * 5)),
                          child: _row(ordered[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _row(SpringMenuItem<T> item) {
    return InkWell(
      onTap: () {
        AppHaptics.tap();
        Navigator.of(context).pop(item.value);
      },
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: item.destructive ? AppColors.dark : AppColors.surface,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(item.icon, size: 18, color: item.destructive ? AppColors.accent : AppColors.dark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(item.label,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
