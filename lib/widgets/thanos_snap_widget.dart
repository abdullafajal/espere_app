import 'dart:math' as math;
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ThanosSnapWidget extends StatefulWidget {
  final Widget child;

  const ThanosSnapWidget({super.key, required this.child});

  @override
  State<ThanosSnapWidget> createState() => ThanosSnapWidgetState();
}

class ThanosSnapWidgetState extends State<ThanosSnapWidget>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();
  late AnimationController _controller;
  bool _showChild = true;
  ui.Image? _image;
  List<_Particle> _particles = [];
  Float32List? _rstTransforms;
  Float32List? _rects;
  Int32List? _colors;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  /// Triggers the snap animation and completes when the animation is done.
  Future<void> startSnap() async {
    final prefs = await SharedPreferences.getInstance();
    final isAnimEnabled = prefs.getBool('enable_shredder_anim') ?? true;
    if (!isAnimEnabled) return;

    try {
      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 1.0);
      _image = image;

      _particles.clear();
      const cols = 90; // High performance density
      final rows = (cols * (image.height / image.width)).round().clamp(1, 400);
      final cellW = image.width / cols;
      final cellH = image.height / rows;

      final random = math.Random();

      for (int y = 0; y < rows; y++) {
        for (int x = 0; x < cols; x++) {
          final srcRect = Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH);

          // Stay mostly in place (just a tiny drift)
          final targetX = (x * cellW) + (random.nextDouble() - 0.5) * 20;
          final targetY = (y * cellH) - (random.nextDouble() - 0.2) * 30;

          // Dissipate from left to right smoothly
          final delay = (x / cols) * 0.6 + random.nextDouble() * 0.15;

          _particles.add(
            _Particle(
              srcRect: srcRect,
              startOffset: Offset(x * cellW, y * cellH),
              targetOffset: Offset(targetX, targetY),
              delay: delay.clamp(0.0, 1.0),
              duration: 0.3 + random.nextDouble() * 0.4,
              rotationSpin: random.nextDouble() * 2 * math.pi - math.pi, // spin
            ),
          );
        }
      }

      final count = _particles.length;
      _rstTransforms = Float32List(count * 4);
      _rects = Float32List(count * 4);
      _colors = Int32List(count);

      for (int i = 0; i < count; i++) {
        final rect = _particles[i].srcRect;
        _rects![i * 4 + 0] = rect.left;
        _rects![i * 4 + 1] = rect.top;
        _rects![i * 4 + 2] = rect.right;
        _rects![i * 4 + 3] = rect.bottom;
      }

      if (mounted) {
        setState(() {
          _showChild = false;
        });
        await _controller.forward();
      }
    } catch (e) {
      // If capture fails, just return immediately
      return;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showChild) {
      return RepaintBoundary(key: _boundaryKey, child: widget.child);
    }

    if (_image == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Collapse height during the last 30% of the animation
        final heightFactor =
            _controller.value < 0.7
                ? 1.0
                : 1.0 - ((_controller.value - 0.7) / 0.3).clamp(0.0, 1.0);

        return Align(
          alignment: Alignment.topCenter,
          heightFactor: heightFactor,
          child: CustomPaint(
            size: Size(_image!.width.toDouble(), _image!.height.toDouble()),
            painter: _ThanosSnapPainter(
              image: _image!,
              particles: _particles,
              progress: _controller.value,
              rstTransforms: _rstTransforms!,
              rects: _rects!,
              colors: _colors!,
            ),
          ),
        );
      },
    );
  }
}

class _Particle {
  final Rect srcRect;
  final Offset startOffset;
  final Offset targetOffset;
  final double delay;
  final double duration;
  final double rotationSpin;

  _Particle({
    required this.srcRect,
    required this.startOffset,
    required this.targetOffset,
    required this.delay,
    required this.duration,
    required this.rotationSpin,
  });
}

class _ThanosSnapPainter extends CustomPainter {
  final ui.Image image;
  final List<_Particle> particles;
  final double progress;
  final Float32List rstTransforms;
  final Float32List rects;
  final Int32List colors;

  _ThanosSnapPainter({
    required this.image,
    required this.particles,
    required this.progress,
    required this.rstTransforms,
    required this.rects,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (particles.isEmpty) return;

    for (int i = 0; i < particles.length; i++) {
      final p = particles[i];

      if (progress < p.delay) {
        rstTransforms[i * 4 + 0] = 1.0; // scos
        rstTransforms[i * 4 + 1] = 0.0; // ssin
        rstTransforms[i * 4 + 2] = p.startOffset.dx; // tx
        rstTransforms[i * 4 + 3] = p.startOffset.dy; // ty
        colors[i] = 0xFFFFFFFF; // Full alpha white
      } else if (progress < p.delay + p.duration) {
        final pProgress = (progress - p.delay) / p.duration;
        final eased = 1.0 - (1.0 - pProgress) * (1.0 - pProgress);

        final currentX =
            p.startOffset.dx + (p.targetOffset.dx - p.startOffset.dx) * eased;
        final currentY =
            p.startOffset.dy + (p.targetOffset.dy - p.startOffset.dy) * eased;

        final scale = (1.0 - pProgress).clamp(0.0, 1.0);
        final rotation = p.rotationSpin * eased;

        final double scos = math.cos(rotation) * scale;
        final double ssin = math.sin(rotation) * scale;

        final double anchorX = p.srcRect.width / 2;
        final double anchorY = p.srcRect.height / 2;

        final double tx = currentX + anchorX + (-scos * anchorX + ssin * anchorY);
        final double ty = currentY + anchorY + (-ssin * anchorX - scos * anchorY);

        rstTransforms[i * 4 + 0] = scos;
        rstTransforms[i * 4 + 1] = ssin;
        rstTransforms[i * 4 + 2] = tx;
        rstTransforms[i * 4 + 3] = ty;

        final int alpha = (scale * 255).clamp(0, 255).toInt();
        colors[i] = (alpha << 24) | 0x00FFFFFF;
      } else {
        // Invisible (scale 0)
        rstTransforms[i * 4 + 0] = 0.0;
        rstTransforms[i * 4 + 1] = 0.0;
        rstTransforms[i * 4 + 2] = 0.0;
        rstTransforms[i * 4 + 3] = 0.0;
        colors[i] = 0x00000000;
      }
    }

    final paint = Paint();
    canvas.drawRawAtlas(
      image,
      rstTransforms,
      rects,
      colors,
      BlendMode.modulate,
      null,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ThanosSnapPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
