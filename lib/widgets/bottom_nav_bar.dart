/// Floating bottom navigation: a dark pill with labelled tabs and the Add button in the
/// middle.
///
/// Tabs map to the home shell's screen indexes: Home 0, Activity 1, Budgets 2, Split 4.
/// Friends (index 3) lives inside Split, so Split stays highlighted there too.
///
/// The accent pill moves on the app's spring ([AppMotion.move]): it flows from the old
/// tab to the new one, overshoots a touch and settles, with a selection tick on tap and a
/// light tick when it lands. Slots share the width, so the bar fits any screen.
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';

class EspereBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onAdd;
  final bool isVisible;

  const EspereBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onAdd,
    this.isVisible = true,
  });

  @override
  State<EspereBottomNav> createState() => _EspereBottomNavState();
}

class _NavItem {
  final int index;
  final IconData icon;
  final String label;
  const _NavItem(this.index, this.icon, this.label);
}

class _EspereBottomNavState extends State<EspereBottomNav> with SingleTickerProviderStateMixin {
  static const _items = [
    _NavItem(0, Icons.home_rounded, 'Home'),
    _NavItem(1, Icons.receipt_long_rounded, 'Activity'),
    _NavItem(2, Icons.donut_large_rounded, 'Budgets'),
    _NavItem(4, Icons.group_rounded, 'Split'),
  ];

  /// Slot (0-3) of a screen index. Friends (3) shows as Split.
  static double _slotOf(int index) => switch (index) {
        0 => 0,
        1 => 1,
        2 => 2,
        _ => 3,
      };

  /// Position of the pill in slot units; follows the spring between slots.
  late final AnimationController _pos =
      AnimationController.unbounded(vsync: this, value: _slotOf(widget.currentIndex));
  double _target = 0;
  bool _landed = true;

  @override
  void initState() {
    super.initState();
    _target = _slotOf(widget.currentIndex);
    _pos.addListener(_checkLanding);
  }

  @override
  void didUpdateWidget(EspereBottomNav old) {
    super.didUpdateWidget(old);
    final t = _slotOf(widget.currentIndex);
    if (t != _target) {
      _target = t;
      _landed = false;
      _pos.animateWith(SpringSimulation(AppMotion.move, _pos.value, t, _pos.velocity));
    }
  }

  /// Light tick the first time the pill reaches its new tab.
  void _checkLanding() {
    if (_landed) return;
    if ((_pos.value - _target).abs() < 0.08) {
      _landed = true;
      AppHaptics.land();
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: widget.isVisible ? Offset.zero : const Offset(0, 1.2),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        child: SafeArea(
          top: false,
          child: Container(
            height: 68,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: AppColors.dark,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: AppShadows.nav,
            ),
            // Large system font sizes would push the tabs off a small screen.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.1,
              child: AnimatedBuilder(
                animation: _pos,
                builder: (context, _) => Row(
                  children: [
                    _slot(0),
                    _slot(1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: SpringPress(
                        haptic: HapticKind.confirm,
                        scale: 0.88,
                        onTap: widget.onAdd,
                        child: Semantics(
                          button: true,
                          label: 'Add transaction',
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.add_rounded, size: 28, color: AppColors.dark),
                          ),
                        ),
                      ),
                    ),
                    _slot(2),
                    _slot(3),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One tab. `a` (0-1) is how much of the pill is on it right now: it sets the slot's
  /// width, the pill's size and opacity, and cross-fades the two looks of the tab.
  Widget _slot(int slot) {
    final item = _items[slot];
    final a = (1 - (_pos.value - slot).abs()).clamp(0.0, 1.0);
    final selected = _slotOf(widget.currentIndex) == slot;
    return Expanded(
      flex: (1000 + 800 * a).round(),
      child: Semantics(
        selected: selected,
        button: true,
        label: item.label,
        excludeSemantics: true,
        child: SpringPress(
          haptic: HapticKind.tap,
          onTap: () => widget.onTap(item.index),
          child: SizedBox(
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (a > 0)
                  Opacity(
                    opacity: a,
                    child: Transform.scale(
                      scale: 0.82 + 0.18 * a,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                    ),
                  ),
                if (a < 1)
                  Opacity(
                    opacity: 1 - a,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(item.icon, size: 22, color: AppColors.darkMuted),
                        const SizedBox(height: 1),
                        Text(
                          item.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: AppColors.darkMuted),
                        ),
                      ],
                    ),
                  ),
                if (a > 0)
                  Opacity(
                    opacity: a,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(item.icon, size: 22, color: AppColors.dark),
                            const SizedBox(width: 5),
                            Text(item.label,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.dark)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
