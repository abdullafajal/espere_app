import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import '../theme/motion.dart';
import '../services/app_navigation.dart';
import '../theme/app_theme.dart';

/// "Groups | Friends" switch at the top of the Split tab. Friends lives inside Split, so
/// both screens show it; tapping the other side switches the home shell's tab.
///
/// The dark pill moves on the app's spring ([AppMotion.move], like the nav bar): a tick
/// on tap, the pill flows to the other side with a soft overshoot, a light tick when it
/// lands, and then the screen changes.
class SplitSwitcher extends StatefulWidget {
  /// 'groups' or 'friends'.
  final String current;

  const SplitSwitcher({super.key, required this.current});

  static const groupsTab = 4;
  static const friendsTab = 3;

  @override
  State<SplitSwitcher> createState() => _SplitSwitcherState();
}

class _SplitSwitcherState extends State<SplitSwitcher> with SingleTickerProviderStateMixin {
  double get _home => widget.current == 'groups' ? 0 : 1;

  /// 0 = pill on Groups, 1 = pill on Friends.
  late final AnimationController _pos = AnimationController.unbounded(vsync: this, value: _home);
  bool _switching = false;

  void _go(double target, int tab) {
    if (_switching) return;
    _switching = true;
    AppHaptics.tap();
    void onTick() {
      if ((_pos.value - target).abs() < 0.06) {
        _pos.removeListener(onTick);
        AppHaptics.land();
        AppNavigation.openTab(tab);
        // This screen is now hidden: put the pill back home for when it shows again.
        Future.delayed(const Duration(milliseconds: 60), () {
          if (!mounted) return;
          _pos.stop();
          _pos.value = _home;
          _switching = false;
        });
      }
    }

    _pos.addListener(onTick);
    _pos.animateWith(SpringSimulation(AppMotion.move, _pos.value, target, _pos.velocity));
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppShadows.soft,
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final half = box.maxWidth / 2;
            return AnimatedBuilder(
              animation: _pos,
              builder: (context, _) {
                final p = _pos.value;
                return Stack(
                  children: [
                    Positioned(
                      left: p * half,
                      top: 0,
                      bottom: 0,
                      width: half,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.dark,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        _item('Groups', Icons.groups_rounded, 1 - (p.clamp(0.0, 1.0)), 0, SplitSwitcher.groupsTab),
                        _item('Friends', Icons.person_rounded, p.clamp(0.0, 1.0), 1, SplitSwitcher.friendsTab),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// `on` (0-1): how much of the pill is behind this side, for the colour cross-fade.
  Widget _item(String label, IconData icon, double on, double side, int tab) {
    final selected = _home == side;
    final fg = Color.lerp(AppColors.text, Colors.white, on)!;
    final iconColor = Color.lerp(AppColors.muted, AppColors.accent, on)!;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: SpringPress(
          haptic: HapticKind.none,
          onTap: selected ? null : () => _go(side, tab),
          child: SizedBox.expand(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: on > 0.5 ? FontWeight.w800 : FontWeight.w600,
                    color: fg,
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
