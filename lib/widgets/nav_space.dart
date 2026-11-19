/// Space at the end of a tab's list for the floating nav bar: the bar's height while it
/// shows, a small margin while it is hidden (it hides when you scroll down), so there is
/// never an empty band under the last card. Outside the tabs (pushed screens) it is just
/// the margin.
library;

import 'package:flutter/material.dart';

import '../services/app_navigation.dart';

/// Marks the home tabs, where the nav bar floats over the content.
class NavScope extends InheritedWidget {
  const NavScope({super.key, required super.child});

  static bool isIn(BuildContext context) => context.getInheritedWidgetOfExactType<NavScope>() != null;

  @override
  bool updateShouldNotify(NavScope oldWidget) => false;
}

class NavBottomSpace extends StatelessWidget {
  const NavBottomSpace({super.key});

  /// Nav bar (68) + its bottom margin (12) + a gap above it (16).
  static const double _withNav = 96;
  static const double _margin = 20;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    if (!NavScope.isIn(context)) return SizedBox(height: _margin + inset);
    return ValueListenableBuilder<bool>(
      valueListenable: AppNavigation.navVisible,
      builder: (_, visible, __) => AnimatedContainer(
        duration: const Duration(milliseconds: 420),
        curve: visible ? Curves.easeOutBack : Curves.easeOutCubic,
        height: (visible ? _withNav : _margin) + inset,
      ),
    );
  }
}
