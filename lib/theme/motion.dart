/// One feel for the whole app: the same spring for everything that moves or is pressed,
/// and the same few haptics, so taps feel physical and consistent everywhere.
///
/// - [AppMotion.move]: things that travel (the nav pill, selections). Slight overshoot.
/// - [AppMotion.press]: a pressed button sinking and springing back.
/// - [AppHaptics]: tap (selection), press (light), confirm (medium), warn (heavy), and
///   land (the light tick when a moving thing arrives).
/// - [SpringPress]: wrap any tappable to get the press spring + haptic.
/// - [EspereScrollBehavior]: every list in the app bounces at its ends on [AppMotion.move]
///   (the nav pill's spring), with one light tick when the end is reached (see main.dart).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

class AppMotion {
  AppMotion._();

  /// Damping ratio ≈ 0.62: arrives quickly with one soft overshoot.
  static const SpringDescription move = SpringDescription(mass: 1, stiffness: 420, damping: 25);

  /// Damping ratio ≈ 0.5: snappier, a small bounce on release.
  static const SpringDescription press = SpringDescription(mass: 1, stiffness: 900, damping: 30);

  /// How far a pressed button sinks.
  static const double pressedScale = 0.94;
}

enum HapticKind { none, tap, press, confirm, warn }

class AppHaptics {
  AppHaptics._();

  /// Android: played on the vibrator directly (Haptics.kt), because many phones ignore
  /// some of the system "touch feedback" kinds. Elsewhere: Flutter's HapticFeedback.
  static const _channel = MethodChannel('com.example.espere_app/haptics');
  static bool _native = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void _play(String kind, Future<void> Function() fallback) {
    if (_native) {
      _channel.invokeMethod('play', kind).catchError((_) {
        _native = false; // no native side (tests, older build): use the fallback from now on
        fallback();
      });
    } else {
      fallback();
    }
  }

  static void tap() => _play('tap', HapticFeedback.mediumImpact);
  static void press() => _play('press', HapticFeedback.mediumImpact);
  static void confirm() => _play('confirm', HapticFeedback.heavyImpact);
  static void warn() => _play('warn', HapticFeedback.heavyImpact);
  static void land() => _play('land', HapticFeedback.mediumImpact);

  static void of(HapticKind kind) {
    switch (kind) {
      case HapticKind.tap:
        tap();
      case HapticKind.press:
        press();
      case HapticKind.confirm:
        confirm();
      case HapticKind.warn:
        warn();
      case HapticKind.none:
        break;
    }
  }
}

/// Sinks a little while pressed and springs back (with a small bounce) on release,
/// with a haptic on tap. Works inside lists and scroll views (a scroll cancels it).
class SpringPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final HapticKind haptic;
  final double scale;

  const SpringPress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.haptic = HapticKind.tap,
    this.scale = AppMotion.pressedScale,
  });

  @override
  State<SpringPress> createState() => _SpringPressState();
}

class _SpringPressState extends State<SpringPress> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this, value: 1);

  void _to(double target) {
    _c.animateWith(SpringSimulation(AppMotion.press, _c.value, target, _c.velocity));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _to(widget.scale) : null,
      onTapUp: enabled ? (_) => _to(1) : null,
      onTapCancel: enabled ? () => _to(1) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              AppHaptics.of(widget.haptic);
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _to(1);
              AppHaptics.confirm();
              widget.onLongPress!();
            },
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.scale(scale: _c.value, child: child),
        child: widget.child,
      ),
    );
  }
}

/// Bounces past the end of a list and springs back on [AppMotion.move] (the same spring
/// as the nav pill), so the ends of lists feel like the rest of the app.
class EspereScrollPhysics extends BouncingScrollPhysics {
  const EspereScrollPhysics({super.parent});

  @override
  EspereScrollPhysics applyTo(ScrollPhysics? ancestor) => EspereScrollPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => AppMotion.move;
}

/// App-wide scrolling: [EspereScrollPhysics] everywhere, no Android glow or stretch.
class EspereScrollBehavior extends MaterialScrollBehavior {
  const EspereScrollBehavior();

  /// Not "always scrollable": something that fits (a dialog, a short sheet) must not
  /// scroll, or it steals drags from its content (the time picker's clock hand). Lists
  /// with pull-to-refresh are made always-scrollable by ListView itself.
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const EspereScrollPhysics();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}
