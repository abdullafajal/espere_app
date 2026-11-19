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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ..._left.map(_tab),
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
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.add_rounded, size: 28, color: AppColors.dark),
                    ),
                  ),
                ),
                ..._right.map(_tab),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Active tab: lime pill with icon and label side by side. Others: icon over a small
  /// grey label.
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 52,
          width: active ? null : 56,
          padding: EdgeInsets.symmetric(horizontal: active ? 14 : 0),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
          ),
          child: active
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(item.icon, size: 22, color: AppColors.dark),
                    const SizedBox(width: 6),
                    Text(item.label,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.dark)),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.icon, size: 22, color: AppColors.darkMuted),
                    const SizedBox(height: 1),
                    Text(item.label,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.darkMuted)),
                  ],
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
