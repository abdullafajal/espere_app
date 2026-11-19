/// Segmented tabs whose dark pill moves exactly like the nav bar's: a tick on tap, the
/// pill flows to the new tab on [AppMotion.move] with a soft overshoot, and a light tick
/// when it lands. Swiping the pages moves the pill with the finger.
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';

class SpringTabs extends StatefulWidget {
  final TabController controller;
  final List<String> labels;

  const SpringTabs({super.key, required this.controller, required this.labels});

  @override
  State<SpringTabs> createState() => _SpringTabsState();
}

class _SpringTabsState extends State<SpringTabs> with SingleTickerProviderStateMixin {
  late final AnimationController _pos =
      AnimationController.unbounded(vsync: this, value: widget.controller.index.toDouble());

  /// True while our spring drives the pill (after a tap); then the page animation is
  /// ignored so the two do not fight.
  bool _springing = false;
  double _target = 0;
  bool _landed = true;

  @override
  void initState() {
    super.initState();
    _target = widget.controller.index.toDouble();
    widget.controller.animation!.addListener(_followPages);
    widget.controller.addListener(_indexChanged);
    _pos.addListener(_checkLanding);
  }

  @override
  void dispose() {
    widget.controller.animation!.removeListener(_followPages);
    widget.controller.removeListener(_indexChanged);
    _pos.dispose();
    super.dispose();
  }

  /// Swiping the pages: the pill follows the finger.
  void _followPages() {
    if (_springing) return;
    _pos.value = widget.controller.animation!.value;
  }

  /// A swipe settled on another page: tick.
  void _indexChanged() {
    if (_springing || widget.controller.indexIsChanging) return;
    if (_target != widget.controller.index.toDouble()) {
      _target = widget.controller.index.toDouble();
      AppHaptics.land();
    }
  }

  void _checkLanding() {
    if (_landed) return;
    if ((_pos.value - _target).abs() < 0.06) {
      _landed = true;
      AppHaptics.land();
    }
  }

  void _tap(int i) {
    if (i == widget.controller.index && !_springing) return;
    AppHaptics.tap();
    _target = i.toDouble();
    _landed = false;
    _springing = true;
    widget.controller.animateTo(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    _pos
        .animateWith(SpringSimulation(AppMotion.move, _pos.value, _target, _pos.velocity))
        .whenCompleteOrCancel(() => _springing = false);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.labels.length;
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(26), // fully round, like every switch
        boxShadow: AppShadows.soft,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / n;
          return AnimatedBuilder(
            animation: _pos,
            builder: (context, _) {
              final p = _pos.value;
              return Stack(
                children: [
                  Positioned(
                    left: p * w,
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: Container(
                      decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(22)),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: widget.controller.index == i,
                            label: widget.labels[i],
                            excludeSemantics: true,
                            child: SpringPress(
                              haptic: HapticKind.none,
                              onTap: () => _tap(i),
                              child: Center(
                                child: Text(
                                  widget.labels[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color.lerp(
                                      AppColors.muted,
                                      AppColors.accent,
                                      (1 - (p - i).abs()).clamp(0.0, 1.0),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
