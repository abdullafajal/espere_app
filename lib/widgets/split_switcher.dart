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
    // Same look as the bottom nav bar (and the group tabs): dark track, the accent pill
    // widens the selected side and shows icon + label in a row, the other side shows a
    // muted icon over a small label.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        height: 60,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.dark,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: AppShadows.soft,
        ),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.1,
          child: ValueListenableBuilder<double?>(
            valueListenable: SplitPill.position,
            builder: (context, moving, _) {
              // While the pill is not moving, it sits on this screen's side.
              final p = moving ?? _home;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _item('Groups', Icons.groups_rounded, (1 - (p - 0).abs()).clamp(0.0, 1.0), 0, groupsTab),
                  _item('Friends', Icons.person_rounded, (1 - (p - 1).abs()).clamp(0.0, 1.0), 1, friendsTab),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// `a` (0-1): how much of the pill is on this side. It widens the side, grows and fades
  /// in the pill, and cross-fades the two looks, exactly like a nav bar slot.
  Widget _item(String label, IconData icon, double a, double side, int tab) {
    final selected = _home == side;
    return Expanded(
      flex: (1000 + 800 * a).round(),
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
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (a > 0)
                Positioned.fill(
                  child: Opacity(
                    opacity: a,
                    child: Transform.scale(
                      scale: 0.82 + 0.18 * a,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
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
                      Icon(icon, size: 21, color: AppColors.darkMuted),
                      const SizedBox(height: 1),
                      Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
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
                          Icon(icon, size: 21, color: AppColors.dark),
                          const SizedBox(width: 5),
                          Text(label,
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
