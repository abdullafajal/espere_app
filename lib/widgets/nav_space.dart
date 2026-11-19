/// Space at the end of a tab's list for the floating nav bar, which the home shell always
/// shows at the end of a list, so the last card is never hidden and no empty band is
/// left. Outside the tabs (pushed screens) it is just a margin.
library;

import 'package:flutter/material.dart';


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

  /// Fixed height: changing it while a list bounces at its end made the bounce jerk.
  /// The home shell brings the nav bar back at the end of a list, so this space is never
  /// left empty there.
  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return SizedBox(height: (NavScope.isIn(context) ? _withNav : _margin) + inset);
  }
}
