import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_navigation.dart';
import '../theme/app_theme.dart';

/// "Groups | Friends" switch at the top of the Split tab. Friends lives inside Split, so
/// both screens show it; tapping the other side switches the home shell's tab.
class SplitSwitcher extends StatelessWidget {
  /// 'groups' or 'friends'.
  final String current;

  const SplitSwitcher({super.key, required this.current});

  static const groupsTab = 4;
  static const friendsTab = 3;

  @override
  Widget build(BuildContext context) {
    Widget item(String id, String label, IconData icon, int tab) {
      final on = current == id;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            onTap: on
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    AppNavigation.openTab(tab);
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 40,
              decoration: BoxDecoration(
                color: on ? AppColors.dark : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: on ? AppColors.accent : AppColors.muted),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                      color: on ? Colors.white : AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppShadows.soft,
        ),
        child: Row(
          children: [
            item('groups', 'Groups', Icons.groups_rounded, groupsTab),
            item('friends', 'Friends', Icons.person_rounded, friendsTab),
          ],
        ),
      ),
    );
  }
}
