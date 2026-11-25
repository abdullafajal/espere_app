/// Segmented tabs that look and move exactly like the bottom nav bar: a dark track, the
/// accent pill widens the selected tab and shows its icon and label side by side, the
/// others show a muted icon over a small label. The pill flows on [AppMotion.move] with a
/// soft overshoot (one vibration per change). Swiping the pages moves the pill with the
/// finger.
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';

class SpringTabs extends StatefulWidget {
  final TabController controller;
  final List<String> labels;

  /// One icon per tab, as in the nav bar. Without icons the tabs show labels only.
  final List<IconData>? icons;

  /// Kept for older call sites; the track is always the nav bar's dark pill now.
  final Color? background;
  final double height;

  const SpringTabs({
    super.key,
    required this.controller,
    required this.labels,
    this.icons,
    this.background,
    this.height = 60,
  });

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
      AppHaptics.tap();
    }
  }

  void _checkLanding() {
    if (_landed) return;
    if ((_pos.value - _target).abs() < 0.06) {
      _landed = true; // no second buzz on landing: one tap, one vibration
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
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppShadows.soft,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.1,
        child: AnimatedBuilder(
          animation: _pos,
          builder: (context, _) => Row(
            // Every slot is full height, so the pill always fills the track like the nav bar.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (var i = 0; i < n; i++) _slot(i)],
          ),
        ),
      ),
    );
  }

  /// One tab, built like a nav bar slot. `a` (0-1) is how much of the pill is on it: it
  /// widens the slot, grows and fades in the pill, and cross-fades the two looks.
  Widget _slot(int i) {
    final a = (1 - (_pos.value - i).abs()).clamp(0.0, 1.0);
    final icon = widget.icons != null && i < widget.icons!.length ? widget.icons![i] : null;
    final label = widget.labels[i];
    return Expanded(
      flex: (1000 + 800 * a).round(),
      child: Semantics(
        button: true,
        selected: widget.controller.index == i,
        label: label,
        excludeSemantics: true,
        child: SpringPress(
          haptic: HapticKind.none,
          onTap: () => _tap(i),
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
                  child: icon == null
                      ? _label(label, AppColors.darkMuted, 13)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, size: 21, color: AppColors.darkMuted),
                            const SizedBox(height: 1),
                            _label(label, AppColors.darkMuted, 10, weight: FontWeight.w600),
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
                          if (icon != null) ...[
                            Icon(icon, size: 21, color: AppColors.dark),
                            const SizedBox(width: 5),
                          ],
                          _label(label, AppColors.dark, 13),
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

  Widget _label(String text, Color color, double size, {FontWeight weight = FontWeight.w700}) => Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: TextStyle(fontSize: size, fontWeight: weight, letterSpacing: size < 12 ? -0.2 : 0, color: color),
      );
}
