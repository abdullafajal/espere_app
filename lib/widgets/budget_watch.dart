/// Home's "Budgets": up to five budgets (over or close ones always included), as a
/// deck of dark cards to swipe through (the same springs as the Budgets screen).
///
/// Each card says how much is left, or how much was spent extra past the limit, and
/// draws the month as a chart of money left: the lime line falls day by day with the
/// real spending, the dotted line is an even pace, and below ₹0 (spent extra) the area
/// is striped. Tap a card to open Budgets.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../services/budget_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/icon_mapper.dart';

class BudgetWatchDeck extends StatefulWidget {
  final List<BudgetInfo> items;
  final String symbol;
  final VoidCallback onOpen;

  /// The month shown (today's month: the chart runs up to today).
  final DateTime today;

  const BudgetWatchDeck({
    super.key,
    required this.items,
    required this.symbol,
    required this.onOpen,
    required this.today,
  });

  @override
  State<BudgetWatchDeck> createState() => _BudgetWatchDeckState();
}

class _BudgetWatchDeckState extends State<BudgetWatchDeck> with TickerProviderStateMixin {
  static const _spring = AppMotion.move;

  int _i = 0;
  double _width = 320;
  bool _flying = false;
  bool _passed = false;

  /// The front card's sideways offset; only the card transforms listen to it.
  late final AnimationController _dx = AnimationController.unbounded(vsync: this);

  /// The front card springs from a little smaller when it comes forward.
  late final AnimationController _land = AnimationController.unbounded(vsync: this, value: 1);

  /// Fills the front card's ring when it comes to the front.
  late final AnimationController _draw = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..forward();

  int get _n => widget.items.length;

  @override
  void didUpdateWidget(BudgetWatchDeck old) {
    super.didUpdateWidget(old);
    if (_i >= _n) _i = 0;
  }

  @override
  void dispose() {
    _dx.dispose();
    _land.dispose();
    _draw.dispose();
    super.dispose();
  }

  double get _t => (_dx.value.abs() / (_width * 0.9)).clamp(0.0, 1.0);

  void _dragUpdate(DragUpdateDetails d) {
    if (_flying) return;
    _dx.stop();
    _dx.value += _n < 2 ? d.delta.dx * 0.25 : d.delta.dx;
    final past = _dx.value.abs() > _width * 0.28;
    if (past != _passed) {
      _passed = past;
      if (past) AppHaptics.tap();
    }
  }

  void _dragEnd(DragEndDetails d) {
    if (_flying) return;
    final v = d.primaryVelocity ?? 0;
    final x = _dx.value;
    _passed = false;
    if (_n >= 2 && (x.abs() > _width * 0.28 || (v.abs() > 700 && v.sign == x.sign))) {
      _flyOut(x < 0 ? 1 : -1, v);
    } else {
      _dx.animateWith(SpringSimulation(_spring, x, 0, v));
    }
  }

  Future<void> _flyOut(int dir, [double velocity = 0]) async {
    _flying = true;
    final target = -dir * _width * 1.15;
    final speed = math.max(velocity.abs(), 1600.0);
    final ms = ((target - _dx.value).abs() / speed * 1000).clamp(120, 320).round();
    await _dx.animateTo(target, duration: Duration(milliseconds: ms), curve: Curves.easeOutCubic);
    if (!mounted) return;
    setState(() => _i = (_i + dir + _n) % _n);
    _dx.value = 0;
    _land.value = 0.97;
    _land.animateWith(SpringSimulation(_spring, 0.97, 1, 0.6));
    _draw.forward(from: 0);
    _flying = false;
  }

  Future<void> _go(int dir) async {
    if (_n < 2 || _flying) return;
    AppHaptics.tap();
    await _flyOut(dir);
  }

  /// The first time the deck shows (once per app run) the front card slides a little to
  /// the left and springs back, so it's clear the cards swipe.
  static bool _nudged = false;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    if (!_nudged && widget.items.length > 1) {
      _nudged = true;
      Future.delayed(const Duration(milliseconds: 900), () async {
        if (!mounted || _touched || _flying) return;
        await _dx.animateTo(-64, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
        if (!mounted || _touched || _flying) return;
        await _dx.animateWith(SpringSimulation(_spring, _dx.value, 0, 0));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_n == 0) return const SizedBox.shrink();
    final i = _i.clamp(0, _n - 1);
    final front = RepaintBoundary(child: _card(widget.items[i], front: true));
    Widget? behind(int k) => _n > k ? RepaintBoundary(child: _card(widget.items[(i + k) % _n])) : null;
    Widget? before(int k) => _n > k ? RepaintBoundary(child: _card(widget.items[(i - k + _n) % _n])) : null;
    final next = behind(1), next2 = behind(2), prev = before(1), prev2 = before(2);
    final pad = _n > 1 ? 18.0 : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            _width = box.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onOpen,
              onHorizontalDragStart: (_) => _touched = true,
              onHorizontalDragUpdate: _dragUpdate,
              onHorizontalDragEnd: _dragEnd,
              child: AnimatedBuilder(
                animation: Listenable.merge([_dx, _land]),
                builder: (context, _) {
                  final x = _dx.value;
                  final t = _t;
                  final b1 = x > 0 ? prev : next;
                  final b2 = x > 0 ? prev2 : next2;
                  // The front card sets the height; the ones behind take the same size.
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (b2 != null) _behind(b2, 2 - t, pad),
                      if (b1 != null) _behind(b1, 1 - t, pad),
                      Padding(
                        padding: EdgeInsets.only(top: pad),
                        child: Transform.translate(
                          offset: Offset(x, x.abs() * 0.04),
                          child: Transform.rotate(
                            angle: x / (_width * 6),
                            child: Transform.scale(scale: _land.value, child: front),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
        if (_n > 1) ...[const SizedBox(height: 10), _pager(i)],
      ],
    );
  }

  /// A card behind the front one: higher, smaller and darker the deeper it sits (depth 1
  /// or 2, less while the front card is swiped away).
  Widget _behind(Widget card, double depth, double pad) {
    final d = depth.clamp(0.0, 2.0);
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      bottom: 0,
      child: Transform.translate(
        offset: Offset(0, pad - 9.0 * d),
        child: Transform.scale(
          scale: 1 - 0.06 * d,
          alignment: Alignment.topCenter,
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.12 * d), BlendMode.srcATop),
            child: Padding(
              padding: EdgeInsets.only(bottom: pad),
              child: ClipRect(
                child: OverflowBox(alignment: Alignment.topCenter, maxHeight: double.infinity, child: card),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pager(int i) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _go(-1),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.chevron_left_rounded, size: 20, color: AppColors.muted),
          ),
        ),
        for (var k = 0; k < _n; k++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: k == i ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: k == i ? AppColors.dark : const Color(0xFFD5D7CF),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _go(1),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.muted),
          ),
        ),
        // Says the cards swipe, like the category carousel.
        const SizedBox(width: 6),
        const Icon(Icons.swipe_rounded, size: 16, color: AppColors.muted),
        const SizedBox(width: 5),
        Text('Swipe', style: AppText.rowSub.copyWith(fontSize: 11.5)),
      ],
    );
  }

  String _m(double v) =>
      '${widget.symbol}${NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0).format(v.round())}';

  static const _under = Color(0xFF5D6A2A);

  /// One budget: name, a chip saying whether it's fine, the ring (spent of the limit,
  /// with a white tick for how much of the month has gone) beside the numbers, the month
  /// as dated day dots, and one line of advice.
  Widget _card(BudgetInfo b, {bool front = false}) {
    final today = widget.today;
    final days = DateUtils.getDaysInMonth(today.year, today.month);
    final day = today.day.clamp(1, days);
    final daysLeft = days - day;
    final month = DateFormat('MMM').format(today);
    final over = b.spent > b.limit;
    final left = b.limit - b.spent;
    final share = b.limit / days;
    final pace = b.spent / day * days; // where this pace ends the month

    // The chip: over, will go over, close, or fine.
    final (IconData chipIcon, String chipText, bool chipLit) =
        over
            ? (Icons.error_rounded, '${_m(-left)} over', true)
            : pace > b.limit
            ? (Icons.trending_up_rounded, 'Will go over by $days $month', true)
            : b.fraction >= day / days - 0.05
            ? (Icons.speed_rounded, 'Close to the limit', false)
            : (Icons.check_circle_rounded, 'On track', false);

    final String tip;
    if (over) {
      tip =
          b.ranOutDay != null
              ? 'Limit hit on ${b.ranOutDay} $month. Spending nothing more here keeps it at +${_m(-left)}.'
              : 'Spending nothing more here keeps it at +${_m(-left)}.';
    } else if (daysLeft > 0) {
      tip =
          'Keep it under ${_m(left / daysLeft)}/day for the last ${daysLeft == 1 ? 'day' : '$daysLeft days'} to stay on budget.';
    } else {
      tip = 'Last day of the month: ${_m(left)} still left.';
    }
    const tipStyle = TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600, color: AppColors.darkMuted);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: front ? AppShadows.elevated : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: AppColors.darkCardRaised, shape: BoxShape.circle),
                child: Icon(IconMapper.map(b.icon), size: 18, color: AppColors.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  b.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
              Text(
                b.entries == 1 ? '1 entry' : '${b.entries} entries',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.darkMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
            decoration: BoxDecoration(
              color: chipLit ? AppColors.accent : AppColors.darkCardRaised,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(chipIcon, size: 14, color: chipLit ? AppColors.dark : Colors.white),
                const SizedBox(width: 5),
                Text(
                  chipText,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: chipLit ? AppColors.dark : Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: AnimatedBuilder(
                  animation: _draw,
                  builder: (context, _) {
                    final p = front ? Curves.easeOutCubic.transform(_draw.value) : 1.0;
                    return CustomPaint(
                      painter: _RingPainter(fraction: b.fraction * p, month: day / days),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  over ? '+${_m(-left * p)}' : _m(left + b.spent * (1 - p)),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                    color: Colors.white,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                              Text(
                                over ? 'spent extra' : 'left',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.darkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fact(AppColors.accent, 'Spent', _m(b.spent)),
                    const SizedBox(height: 10),
                    _fact(AppColors.darkCardRaised, 'Budget', _m(b.limit), ring: true),
                    const SizedBox(height: 10),
                    _fact(Colors.white, 'Month gone', '$day of $days days'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _MonthDots(budget: b, day: day, days: days, month: month, share: share, money: _m),
          const SizedBox(height: 8),
          Row(
            children: [
              _legend(AppColors.accent, 'over ${_m(share)}'),
              const SizedBox(width: 10),
              _legend(_under, 'under'),
              const SizedBox(width: 10),
              _legend(AppColors.darkCardRaised, 'none'),
              const Spacer(),
              const Text(
                'Tap a day',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.darkFaint),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.lightbulb_rounded, size: 16, color: AppColors.accent),
              ),
              const SizedBox(width: 8),
              // Always two lines tall, so every card in the deck has the same height.
              Expanded(
                child: Stack(
                  children: [
                    const Opacity(opacity: 0, child: Text('.\n.', style: tipStyle)),
                    Text(tip, maxLines: 2, overflow: TextOverflow.ellipsis, style: tipStyle),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fact(Color dot, String label, String value, {bool ring = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 3),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: dot,
            shape: BoxShape.circle,
            border: ring ? Border.all(color: AppColors.darkFaint, width: 1.5) : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkMuted),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legend(Color c, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.darkFaint)),
    ],
  );
}

/// The budget ring: lime for what's spent of the limit, a thinner inner ring for what
/// went past it (striped), and a white tick at how much of the month has gone.
class _RingPainter extends CustomPainter {
  final double fraction;
  final double month;

  _RingPainter({required this.fraction, required this.month});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const stroke = 13.0;
    final r = size.shortestSide / 2 - stroke / 2 - 4;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = AppColors.darkCardRaised
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    final main = fraction.clamp(0.0, 1.0);
    if (main > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * main,
        false,
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
    // Spent past the limit: an inner ring of short stripes, as far round as it went.
    final extra = (fraction - 1).clamp(0.0, 1.0);
    if (extra > 0) {
      final ri = r - stroke - 3;
      final paint =
          Paint()
            ..color = AppColors.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7;
      const step = 0.16, dash = 0.08;
      for (var a = 0.0; a < 2 * math.pi * extra; a += step) {
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: ri),
          -math.pi / 2 + a,
          math.min(dash, 2 * math.pi * extra - a),
          false,
          paint,
        );
      }
    }
    // How far the month has gone.
    final ang = -math.pi / 2 + 2 * math.pi * month.clamp(0.0, 1.0);
    final dir = Offset(math.cos(ang), math.sin(ang));
    canvas.drawLine(
      c + dir * (r - 10),
      c + dir * (r + 10),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.month != month;
}

/// The month as dated dots, one per day: lime when that day went over the daily share,
/// olive when something was spent, dark when nothing was, outlined for days still to
/// come, a white ring on today. Press a dot (or slide along them) to read that day.
class _MonthDots extends StatefulWidget {
  final BudgetInfo budget;
  final int day;
  final int days;
  final String month;
  final double share;
  final String Function(double) money;

  const _MonthDots({
    required this.budget,
    required this.day,
    required this.days,
    required this.month,
    required this.share,
    required this.money,
  });

  @override
  State<_MonthDots> createState() => _MonthDotsState();
}

class _MonthDotsState extends State<_MonthDots> {
  int? _picked;
  int get _cols => (widget.days / 2).ceil();
  static const _gap = 4.0;

  int? _dayAt(Offset p, double width) {
    final size = (width - _gap * (_cols - 1)) / _cols;
    final col = (p.dx / (size + _gap)).floor().clamp(0, _cols - 1);
    final row = (p.dy / (size + _gap)).floor().clamp(0, 1);
    final d = row * _cols + col + 1;
    return d <= widget.days ? d : null;
  }

  void _pick(Offset p, double width) {
    final d = _dayAt(p, width);
    if (d == null || d == _picked) return;
    HapticFeedback.selectionClick();
    setState(() => _picked = d);
  }

  void _clear() {
    if (_picked != null) setState(() => _picked = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final size = (w - _gap * (_cols - 1)) / _cols;
        final h = size * 2 + _gap;
        final picked = _picked;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Pressing and sliding here reads the days; it doesn't swipe the card or open
          // Budgets.
          onTapDown: (d) => _pick(d.localPosition, w),
          onTapUp:
              (_) => Future.delayed(const Duration(milliseconds: 1400), () {
                if (mounted) _clear();
              }),
          onTap: () {},
          onHorizontalDragStart: (d) => _pick(d.localPosition, w),
          onHorizontalDragUpdate: (d) => _pick(d.localPosition, w),
          onHorizontalDragEnd: (_) => _clear(),
          onHorizontalDragCancel: _clear,
          child: SizedBox(
            height: h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var d = 1; d <= widget.days; d++)
                  Positioned(
                    left: ((d - 1) % _cols) * (size + _gap),
                    top: ((d - 1) ~/ _cols) * (size + _gap),
                    width: size,
                    height: size,
                    child: _dot(d, size),
                  ),
                if (picked != null) _bubble(picked, size, w),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dot(int d, double size) {
    final v = widget.budget.daily[d] ?? 0;
    final future = d > widget.day;
    final overShare = !future && v > widget.share;
    final Color fill;
    final Color ink;
    if (future) {
      fill = Colors.transparent;
      ink = AppColors.darkFaint;
    } else if (overShare) {
      fill = AppColors.accent;
      ink = AppColors.dark;
    } else if (v > 0) {
      fill = _BudgetWatchDeckState._under;
      ink = const Color(0xFFE2E6DA);
    } else {
      fill = AppColors.darkCardRaised;
      ink = AppColors.darkMuted;
    }
    final picked = _picked == d;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: _picked == null || picked ? 1 : 0.45,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border:
              future
                  ? Border.all(color: AppColors.darkCardRaised, width: 1.5)
                  : (picked || d == widget.day)
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
        ),
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Text('$d', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: ink)),
          ),
        ),
      ),
    );
  }

  Widget _bubble(int d, double size, double width) {
    final v = widget.budget.daily[d] ?? 0;
    final String text;
    if (d > widget.day) {
      text = '$d ${widget.month} · still to come';
    } else if (v <= 0) {
      text = '$d ${widget.month} · nothing spent';
    } else {
      text =
          '$d ${widget.month} · ${widget.money(v)}${v > widget.share ? ' · over ${widget.money(widget.share)}' : ''}';
    }
    final cx = ((d - 1) % widget.days % _cols) * (size + _gap) + size / 2;
    const bw = 190.0;
    final left = (cx - bw / 2).clamp(0.0, math.max(0.0, width - bw)).toDouble();
    return Positioned(
      left: left,
      width: bw,
      bottom: size * 2 + _gap + 6 - ((d - 1) ~/ _cols) * (size + _gap),
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: Text(
              text,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.dark),
            ),
          ),
        ),
      ),
    );
  }
}

/// What "Budgets to watch" shows when there is nothing to watch: with no budgets, a dark
/// card that invites setting one (a faint chart shows what it will look like); with
/// budgets all well within their limits, one calm line saying so.
class BudgetWatchEmpty extends StatelessWidget {
  /// How many budgets this month (0: none set yet).
  final int budgets;
  final VoidCallback onSet;

  const BudgetWatchEmpty({super.key, required this.budgets, required this.onSet});

  @override
  Widget build(BuildContext context) {
    if (budgets > 0) {
      return SpringPress(
        haptic: HapticKind.tap,
        scale: 0.98,
        onTap: onSet,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            boxShadow: AppShadows.soft,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 22, color: AppColors.dark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      budgets == 1 ? 'Your budget is on track' : 'All $budgets budgets are on track',
                      style: AppText.rowTitle,
                    ),
                    const Text('None is close to its limit this month', style: AppText.rowSub),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: AppShadows.elevated,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(color: AppColors.darkCardRaised, shape: BoxShape.circle),
                child: Icon(Icons.savings_rounded, size: 19, color: AppColors.accent),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'No budgets yet',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Set a monthly limit for food, travel or anything else. Here you\'ll see how fast the money '
            'goes, and how much you spend extra.',
            style: TextStyle(fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w500, color: AppColors.darkMuted),
          ),
          const SizedBox(height: 12),
          // A faint example of the chart each budget gets.
          SizedBox(height: 74, width: double.infinity, child: CustomPaint(painter: _SamplePainter())),
          const SizedBox(height: 14),
          SpringPress(
            haptic: HapticKind.tap,
            onTap: onSet,
            child: Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(23)),
              child: const Text(
                'Set a budget',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SamplePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const pts = [1.0, .94, .9, .82, .79, .7, .66, .58, .52, .47, .4, .36];
    final line = Path()..moveTo(0, h - pts[0] * (h - 6));
    for (var i = 1; i < pts.length; i++) {
      line.lineTo(w * i / (pts.length + 3), h - pts[i] * (h - 6));
    }
    final pace =
        Paint()
          ..color = AppColors.darkCardRaised
          ..strokeWidth = 1.4;
    for (var s = 0.0; s < 1; s += 0.03) {
      canvas.drawLine(Offset(w * s, 6 + (h - 6) * s), Offset(w * (s + .012), 6 + (h - 6) * (s + .012)), pace);
    }
    canvas.drawLine(
      Offset(0, h - 1),
      Offset(w, h - 1),
      Paint()
        ..color = AppColors.darkCardRaised
        ..strokeWidth = 1.5,
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SamplePainter old) => false;
}
