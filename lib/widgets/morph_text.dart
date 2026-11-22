/// Text that shows an edit. When [text] changes, only the characters that differ break
/// into dust (the same left-to-right drift as the delete animation in
/// [ThanosSnapWidget]); then the new characters gather from dust into place. The parts
/// that stayed the same (common start and end) do not move.
///
/// Use it in place of [Text] wherever saved data is shown. Pass [id] (e.g. the record's id)
/// so a row that is reused for a different record just switches, without animating.
///
/// Settings → Look → "Edit animation" turns it off ([EditAnimation.enabled]).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/motion.dart';

class EditAnimation {
  EditAnimation._();

  static const prefKey = 'enable_edit_anim';

  /// Cached so text can decide synchronously whether to animate.
  static bool enabled = true;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool(prefKey) ?? true;
  }

  static Future<void> set(bool on) async {
    enabled = on;
    final p = await SharedPreferences.getInstance();
    await p.setBool(prefKey, on);
  }

  /// The same buzz as the delete animation: a tick every 50 ms while dust moves. Shared by
  /// every changing text, so several fields changing together still buzz as one.
  static DateTime _lastTick = DateTime(0);
  static void _tick() {
    final now = DateTime.now();
    if (now.difference(_lastTick).inMilliseconds < 50) return;
    _lastTick = now;
    AppHaptics.tap();
  }
}

class MorphText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;

  /// What this text belongs to. A change of [id] never animates.
  final Object? id;

  const MorphText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
    this.id,
  });

  @override
  State<MorphText> createState() => _MorphTextState();
}

class _MorphTextState extends State<MorphText> with SingleTickerProviderStateMixin {
  static const _out = Duration(milliseconds: 760);
  static const _in = Duration(milliseconds: 720);

  AnimationController? _c;
  String? _from; // text being dusted away (phase 1)
  _Grains? _grains;

  @override
  void didUpdateWidget(MorphText old) {
    super.didUpdateWidget(old);
    if (old.text == widget.text) return;
    if (old.id != widget.id || !EditAnimation.enabled || !TickerMode.valuesOf(context).enabled) {
      _stop();
      return;
    }
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) return;
    _from = old.text;
    _grains = null;
    _c ??= AnimationController(vsync: this)..addListener(_onTick);
    // First tick right away, with the first frame of dust (not after the first frame lands).
    EditAnimation._tick();
    _c!
      ..duration = _out + _in
      ..forward(from: 0).whenComplete(() {
        if (!mounted) return;
        setState(() {
          _from = null;
          _grains = null;
        });
      });
  }

  // Buzz only while grains are actually moving: dust leaving (most of phase one) and dust
  // gathering (most of phase two), so the feel stops when the new text has formed.
  void _onTick() {
    final c = _c!;
    if (!c.isAnimating) return;
    final split = _out.inMilliseconds / (_out + _in).inMilliseconds;
    final v = c.value;
    final moving = v < split * .92 || (v > split && v < split + (1 - split) * .9);
    if (moving) EditAnimation._tick();
  }

  void _stop() {
    _c?.stop();
    _from = null;
    _grains = null;
  }

  @override
  void dispose() {
    _c?.dispose();
    _grains?.dispose();
    super.dispose();
  }

  TextStyle _style(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    return base.merge(widget.style);
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textAlign: widget.textAlign,
      softWrap: widget.softWrap,
    );
    final c = _c;
    final from = _from;
    if (c == null || from == null) return text;

    final style = _style(context);
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final split = _out.inMilliseconds / (_out + _in).inMilliseconds;

    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final outPhase = c.value < split;
        // Lay out with the text on screen for this phase, so the row sizes as it would.
        final shown = Text(
          outPhase ? from : widget.text,
          style: widget.style,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
          textAlign: widget.textAlign,
          softWrap: widget.softWrap,
        );
        return CustomPaint(
          foregroundPainter: _MorphPainter(
            state: this,
            from: from,
            to: widget.text,
            style: style,
            scaler: scaler,
            dir: dir,
            dpr: dpr,
            align: widget.textAlign ?? TextAlign.start,
            maxLines: widget.maxLines,
            ellipsis: widget.overflow == TextOverflow.ellipsis ? '…' : null,
            out: outPhase,
            t: outPhase ? c.value / split : (c.value - split) / (1 - split),
          ),
          child: Opacity(opacity: 0, child: shown),
        );
      },
    );
  }
}

/// Which characters differ: everything between the common start and the common end.
class _Diff {
  final int start; // code-unit offset where the change begins
  final int endOld; // code-unit offset where the changed part of the old text ends
  final int endNew;
  const _Diff(this.start, this.endOld, this.endNew);

  factory _Diff.of(String a, String b) {
    final A = a.characters.toList(), B = b.characters.toList();
    var p = 0;
    while (p < A.length && p < B.length && A[p] == B[p]) {
      p++;
    }
    var s = 0;
    while (s < A.length - p && s < B.length - p && A[A.length - 1 - s] == B[B.length - 1 - s]) {
      s++;
    }
    int units(List<String> l, int n) => l.take(n).fold(0, (sum, c) => sum + c.length);
    return _Diff(units(A, p), units(A, A.length - s), units(B, B.length - s));
  }
}

/// One phase's picture of the text and the dust cells cut from its changed part.
class _Grains {
  final ui.Image image;
  final Path changed; // where the changed characters are (logical px)
  final List<Rect> src; // cell in image pixels
  final List<Offset> at; // cell's resting place (logical px)
  final List<Offset> away; // where it drifts to / comes from
  final List<double> delay, len, spin;
  final bool out;
  final Size size;

  _Grains(this.image, this.changed, this.src, this.at, this.away, this.delay, this.len, this.spin, this.out, this.size);

  void dispose() => image.dispose();
}

class _MorphPainter extends CustomPainter {
  final _MorphTextState state;
  final String from, to;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection dir;
  final double dpr;
  final TextAlign align;
  final int? maxLines;
  final String? ellipsis;
  final bool out;
  final double t;

  _MorphPainter({
    required this.state,
    required this.from,
    required this.to,
    required this.style,
    required this.scaler,
    required this.dir,
    required this.dpr,
    required this.align,
    required this.maxLines,
    required this.ellipsis,
    required this.out,
    required this.t,
  });

  _Grains _build(Size size) {
    final text = out ? from : to;
    final d = _Diff.of(from, to);
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: dir,
      textAlign: align,
      textScaler: scaler,
      maxLines: maxLines,
      ellipsis: ellipsis,
    )..layout(minWidth: size.width, maxWidth: size.width);

    final w = math.max(1, (size.width * dpr).ceil()), h = math.max(1, (size.height * dpr).ceil());
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(dpr);
    final dy = (size.height - tp.height) / 2;
    tp.paint(canvas, Offset(0, dy));
    final image = rec.endRecording().toImageSync(w, h);

    final boxes = tp.getBoxesForSelection(TextSelection(baseOffset: d.start, extentOffset: out ? d.endOld : d.endNew));
    final changed = Path();
    final src = <Rect>[], at = <Offset>[], away = <Offset>[];
    final delay = <double>[], len = <double>[], spin = <double>[];
    final rnd = math.Random();
    const cell = 2.0; // logical px per grain
    if (boxes.isNotEmpty) {
      final left = boxes.map((b) => b.left).reduce(math.min);
      final right = boxes.map((b) => b.right).reduce(math.max);
      final span = math.max(1.0, right - left);
      for (final b in boxes) {
        final r = Rect.fromLTRB(b.left - 1, b.top + dy - 1, b.right + 1, b.bottom + dy + 1);
        changed.addRect(r);
        for (var y = r.top; y < r.bottom; y += cell) {
          for (var x = r.left; x < r.right; x += cell) {
            src.add(Rect.fromLTWH(x * dpr, y * dpr, cell * dpr, cell * dpr));
            at.add(Offset(x, y));
            final f = (x - left) / span;
            if (out) {
              // like the delete: later to the right, drifts up and to the right
              delay.add(f * .55 + rnd.nextDouble() * .12);
              len.add(.3 + rnd.nextDouble() * .3);
              away.add(Offset(x + 14 + rnd.nextDouble() * 30, y - 8 - rnd.nextDouble() * 26));
            } else {
              // gathers in from below-left, left to right
              delay.add(f * .45 + rnd.nextDouble() * .12);
              len.add(.35 + rnd.nextDouble() * .2);
              away.add(Offset(x - 12 - rnd.nextDouble() * 28, y + 6 + rnd.nextDouble() * 22));
            }
            spin.add((rnd.nextDouble() - .5) * 6);
          }
        }
      }
    }
    tp.dispose();
    return _Grains(image, changed, src, at, away, delay, len, spin, out, size);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    var g = state._grains;
    if (g == null || g.out != out || g.size != size) {
      g?.dispose();
      g = state._grains = _build(size);
    }
    final full = Offset.zero & size;
    final img = Rect.fromLTWH(0, 0, g.image.width.toDouble(), g.image.height.toDouble());
    final paint = Paint()..filterQuality = FilterQuality.medium;

    // The unchanged part, drawn as it is.
    canvas.save();
    canvas.clipPath(Path.combine(PathOperation.difference, Path()..addRect(full), g.changed));
    canvas.drawImageRect(g.image, img, full, paint);
    canvas.restore();

    final n = g.src.length;
    if (n == 0) return;
    final xforms = <RSTransform>[], rects = <Rect>[], colors = <Color>[];
    for (var i = 0; i < n; i++) {
      final k = ((t - g.delay[i]) / g.len[i]).clamp(0.0, 1.0);
      final double alpha;
      final double e;
      final double scale;
      final double rot;
      if (out) {
        if (k >= 1) continue;
        e = k * k;
        alpha = 1 - k;
        scale = 1 - k * .5;
        rot = g.spin[i] * k;
        final p = Offset.lerp(g.at[i], g.away[i], e)!;
        _add(xforms, rects, colors, g.src[i], p, scale, rot, alpha);
      } else {
        if (k <= 0) continue;
        e = 1 - math.pow(1 - k, 3).toDouble();
        alpha = k;
        scale = .5 + k * .5;
        rot = g.spin[i] * (1 - k);
        final p = Offset.lerp(g.away[i], g.at[i], e)!;
        _add(xforms, rects, colors, g.src[i], p, scale, rot, alpha);
      }
    }
    if (xforms.isEmpty) return;
    canvas.drawAtlas(g.image, xforms, rects, colors, BlendMode.modulate, null, paint);
  }

  void _add(List<RSTransform> x, List<Rect> r, List<Color> c, Rect src, Offset p, double scale, double rot, double a) {
    final s = scale / dpr;
    final half = src.width / 2;
    x.add(RSTransform.fromComponents(
      rotation: rot,
      scale: s,
      anchorX: half,
      anchorY: half,
      translateX: p.dx + half / dpr,
      translateY: p.dy + half / dpr,
    ));
    r.add(src);
    c.add(Colors.white.withValues(alpha: a.clamp(0.0, 1.0)));
  }

  @override
  bool shouldRepaint(_MorphPainter old) => old.t != t || old.out != out || old.to != to;
}

/// An icon that shows an edit the same way: the old icon turns to dust and the new one
/// gathers in its place. Icons are font glyphs, so this is [MorphText] with one character.
class MorphIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;
  final Object? id;

  const MorphIcon(this.icon, {super.key, this.size = 24, this.color, this.id});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: MorphText(
          String.fromCharCode(icon.codePoint),
          id: id,
          softWrap: false,
          style: TextStyle(
            inherit: false,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontFamilyFallback: icon.fontFamilyFallback,
            fontSize: size,
            height: 1,
            color: color ?? IconTheme.of(context).color,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
      ),
    );
  }
}
