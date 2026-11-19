/// Floating bottom navigation: a dark pill with labelled tabs and the Add button in the
/// middle.
///
/// Tabs map to the home shell's screen indexes: Home 0, Activity 1, Budgets 2, Split 4.
/// Friends (index 3) lives inside the Split tab, so Split stays highlighted there too.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class EspereBottomNav extends StatelessWidget {
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

  static const _left = [
    _NavItem(0, Icons.home_rounded, 'Home'),
    _NavItem(1, Icons.receipt_long_rounded, 'Activity'),
  ];
  static const _right = [
    _NavItem(2, Icons.donut_large_rounded, 'Budgets'),
    _NavItem(4, Icons.group_rounded, 'Split'),
  ];

  bool _isActive(_NavItem item) =>
      item.index == currentIndex || (item.index == 4 && currentIndex == 3);

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: isVisible ? Offset.zero : const Offset(0, 1.2),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        child: SafeArea(
          top: false,
          child: Container(
            height: 68,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.dark,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: AppShadows.nav,
            ),
            child: Row(
              children: [
                ..._left.map((i) => Expanded(child: _tab(i))),
                Semantics(
                  button: true,
                  label: 'Add transaction',
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      onAdd();
                    },
                    child: Container(
                      width: 52,
                      height: 52,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.add_rounded, size: 28, color: AppColors.dark),
                    ),
                  ),
                ),
                ..._right.map((i) => Expanded(child: _tab(i))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(_NavItem item) {
    final active = _isActive(item);
    return Semantics(
      selected: active,
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap(item.index);
        },
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: active ? AppColors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.icon, size: 22, color: active ? AppColors.dark : AppColors.darkMuted),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active ? AppColors.dark : AppColors.darkMuted,
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

class _NavItem {
  final int index;
  final IconData icon;
  final String label;
  const _NavItem(this.index, this.icon, this.label);
}
