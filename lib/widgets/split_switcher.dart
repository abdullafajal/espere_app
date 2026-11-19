import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import '../theme/motion.dart';
import '../services/app_navigation.dart';
import '../theme/app_theme.dart';

/// "Groups | Friends" switch at the top of the Split tab. Friends lives inside Split, so
/// both screens show it; tapping the other side switches the home shell's tab.
///
/// The pill moves exactly like the nav bar's: tick on tap, it flows on [AppMotion.move]
/// with a soft overshoot, light tick when it lands. The screen switches at once; the pill's
/// position is shared ([SplitPill]) and driven by [SplitPillDriver] in the home shell, so
/// the new screen's switch shows the same pill still moving and bouncing.
class SplitSwitcher extends StatelessWidget {
  /// 'groups' or 'friends'.
  final String current;

  const SplitSwitcher({super.key, required this.current});

  static const groupsTab = 4;
  static const friendsTab = 3;

  double get _home => current == 'groups' ? 0 : 1;

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
            return ValueListenableBuilder<double?>(
              valueListenable: SplitPill.position,
              builder: (context, moving, _) {
                // While the pill is not moving, it sits on this screen's side.
                final p = moving ?? _home;
                return Stack(
                  children: [
                    Positioned(
                      left: p * half,
                      top: 0,
                      bottom: 0,
                      width: half,
                      child: Container(
                        decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                    Row(
                      children: [
                        _item('Groups', Icons.groups_rounded, 1 - p.clamp(0.0, 1.0), 0, groupsTab),
                        _item('Friends', Icons.person_rounded, p.clamp(0.0, 1.0), 1, friendsTab),
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
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: SpringPress(
          haptic: HapticKind.none,
          onTap: selected
              ? null
              : () {
                  AppHaptics.tap();
                  SplitPill.moveTo(from: _home, to: side);
                  AppNavigation.openTab(tab);
                },
          child: SizedBox.expand(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: Color.lerp(AppColors.muted, AppColors.accent, on)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: on > 0.5 ? FontWeight.w800 : FontWeight.w600,
                    color: Color.lerp(AppColors.text, Colors.white, on),
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

/// The Groups | Friends pill's shared position: null when at rest.
class SplitPill {
  SplitPill._();

  static final ValueNotifier<double?> position = ValueNotifier<double?>(null);
  static _SplitPillDriverState? _driver;

  static void moveTo({required double from, required double to}) {
    final d = _driver;
    if (d == null) return;
    d._move(from, to);
  }
}

/// Runs the Groups | Friends pill's spring. Lives in the home shell (always on screen), so
/// the motion keeps going while the Split screens swap.
class SplitPillDriver extends StatefulWidget {
  const SplitPillDriver({super.key});

  @override
  State<SplitPillDriver> createState() => _SplitPillDriverState();
}

class _SplitPillDriverState extends State<SplitPillDriver> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this);
  double _target = 0;
  bool _landed = true;

  @override
  void initState() {
    super.initState();
    SplitPill._driver = this;
    _c.addListener(() {
      SplitPill.position.value = _c.value;
      if (!_landed && (_c.value - _target).abs() < 0.06) {
        _landed = true;
        AppHaptics.land();
      }
    });
  }

  void _move(double from, double to) {
    _target = to;
    _landed = false;
    final start = SplitPill.position.value ?? from;
    _c.value = start;
    _c
        .animateWith(SpringSimulation(AppMotion.move, start, to, _c.velocity))
        .whenComplete(() => SplitPill.position.value = null);
  }

  @override
  void dispose() {
    if (SplitPill._driver == this) SplitPill._driver = null;
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
