/// Floating bottom navigation bar — the dark pill from base.html.
///
/// Matches the Django template:
///   bg-mn-dark rounded-[28px] px-3 py-3 with 5 icon tabs
///   Active: bg-mn-accent text-mn-dark
///   Inactive: text-gray-400
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class EspereBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isVisible;

  const EspereBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.isVisible = true,
  });

  static const _items = [
    _NavItem(Icons.home_outlined, Icons.home_outlined, 'Home'),
    _NavItem(Icons.swap_horiz, Icons.swap_horiz, 'Activity'),
    _NavItem(Icons.wallet_outlined, Icons.wallet, 'Budgets'),
    _NavItem(Icons.track_changes, Icons.track_changes, 'Savings'),
    _NavItem(Icons.call_split, Icons.call_split, 'Split'),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: isVisible ? Offset.zero : const Offset(0, 1.0),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutQuart,
        child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.dark,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_items.length, (index) {
              final item = _items[index];
              final isActive = index == currentIndex;
              
              return GestureDetector(
                onTap: () => onTap(index),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.accent : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isActive ? item.activeIcon : item.icon,
                        size: 24,
                        color: isActive ? AppColors.dark : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    ),
  );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}
