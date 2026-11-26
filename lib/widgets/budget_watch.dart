/// Home's "Budgets to watch": the budgets that are over or close to their limit, as a
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

  static const double cardHeight = 292;

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

  /// Draws the front card's line from the start of the month to today.
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

  @override
  Widget build(BuildContext context) {
    if (_n == 0) return const SizedBox.shrink();
    final i = _i.clamp(0, _n - 1);
    final front = RepaintBoundary(child: _card(widget.items[i], front: true));
    Widget? behind(int k) => _n > k ? RepaintBoundary(child: _card(widget.items[(i + k) % _n])) : null;
    Widget? before(int k) => _n > k ? RepaintBoundary(child: _card(widget.items[(i - k + _n) % _n])) : null;
    final next = behind(1), next2 = behind(2), prev = before(1), prev2 = before(2);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            _width = box.maxWidth;
            return SizedBox(
              height: BudgetWatchDeck.cardHeight + (_n > 1 ? 18 : 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpen,
                onHorizontalDragUpdate: _dragUpdate,
                onHorizontalDragEnd: _dragEnd,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_dx, _land]),
                  builder: (context, _) {
                    final x = _dx.value;
                    final t = _t;
                    final b1 = x > 0 ? prev : next;
                    final b2 = x > 0 ? prev2 : next2;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (b2 != null) _placed(b2, 2 - t),
                        if (b1 != null) _placed(b1, 1 - t),
                        _placed(
                          Transform.translate(
                            offset: Offset(x, x.abs() * 0.04),
                            child: Transform.rotate(
                              angle: x / (_width * 6),
                              child: Transform.scale(scale: _land.value, child: front),
                            ),
                          ),
                          0,
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
        if (_n > 1) ...[const SizedBox(height: 10), _dots(i)],
      ],
    );
  }

  Widget _placed(Widget card, double depth) {
    final d = depth.clamp(0.0, 2.0);
    return Positioned(
      left: 0,
      right: 0,
      top: (_n > 1 ? 18 : 0) - 9.0 * d,
      child: Transform.scale(
        scale: 1 - 0.06 * d,
        alignment: Alignment.topCenter,
        child: Opacity(opacity: (1 - 0.28 * d).clamp(0.0, 1.0), child: card),
      ),
    );
  }

  Widget _dots(int i) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _go(-1),
          child: const Padding(padding: EdgeInsets.all(6), child: SizedBox(width: 8)),
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
        const SizedBox(width: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _go(1),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.swipe_rounded, size: 16, color: AppColors.muted),
          ),
        ),
      ],
    );
  }

  String _m(double v) =>
      '${widget.symbol}${NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0).format(v.round())}';

  Widget _card(BudgetInfo b, {bool front = false}) {
    final over = b.spent > b.limit;
    final extra = b.spent - b.limit;
    final today = widget.today;
    final days = DateUtils.getDaysInMonth(today.year, today.month);
    final daysLeft = days - today.day;
    final month = DateFormat('MMM').format(today);

    final String note;
    if (over) {
      note = b.ranOutDay != null ? 'Ran out on ${b.ranOutDay} $month' : 'Past the limit';
    } else if (daysLeft > 0) {
      note = '${_m((b.limit - b.spent) / daysLeft)}/day keeps you on budget';
    } else {
      note = 'Last day of the month';
    }

    return Container(
      height: BudgetWatchDeck.cardHeight,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: front ? AppShadows.elevated : null,
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
                child: Icon(IconMapper.map(b.icon), size: 19, color: AppColors.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    Text(
                      '${_m(b.spent)} spent of ${_m(b.limit)}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.darkMuted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: over ? AppColors.accent : AppColors.darkCardRaised,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  over ? 'OVER' : '${b.percent}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: over ? AppColors.dark : Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  over ? '+${_m(extra)}' : _m(b.limit - b.spent),
                  style: AppText.hero.copyWith(color: Colors.white, fontSize: 30, letterSpacing: -1),
                ),
                const SizedBox(width: 8),
                Text(
                  over ? 'spent extra' : 'left',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.darkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: AnimatedBuilder(
              animation: _draw,
              builder:
                  (context, _) => CustomPaint(
                    size: Size.infinite,
                    painter: MoneyLeftPainter(
                      budget: b,
                      day: today.day,
                      days: days,
                      progress: front ? Curves.easeOutCubic.transform(_draw.value) : 1,
                      ranOutLabel: over && b.ranOutDay != null ? 'ran out ${b.ranOutDay} $month' : null,
                      zeroLabel: '${widget.symbol}0',
                    ),
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.darkMuted),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                daysLeft == 1 ? '1 day left' : '$daysLeft days left',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Money left in a budget through the month: a lime line from the limit (day 0) down to
/// today, a dotted even pace from the limit to ₹0 on the last day, and the part spent
/// extra (below ₹0) striped.
class MoneyLeftPainter extends CustomPainter {
  final BudgetInfo budget;
  final int day;
  final int days;
  final double progress;
  final String? ranOutLabel;
  final String zeroLabel;

  MoneyLeftPainter({
    required this.budget,
    required this.day,
    required this.days,
    required this.progress,
    required this.zeroLabel,
    this.ranOutLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0 || budget.limit <= 0) return;
    const top = 6.0;
    final floorY = h - 4;

    // Money left at the end of each day up to today, from the real daily spending.
    final left = <double>[budget.limit];
    var sum = 0.0;
    for (var d = 1; d <= day; d++) {
      sum += budget.daily[d] ?? 0;
      left.add(budget.limit - sum);
    }
    // Spending saved without a day (or rounding) still lands on today's total.
    left[day] = budget.limit - budget.spent;
    final minV = math.min(0.0, left.reduce(math.min));
    // Room under ₹0 only when something was spent extra.
    final zeroY = minV < 0 ? h * 0.64 : h - 12;
    double y(double v) =>
        v >= 0 ? zeroY - v / budget.limit * (zeroY - top) : zeroY + (minV == 0 ? 0 : v / minV) * (floorY - zeroY);
    double x(num d) => d / days * w;

    final line = Path()..moveTo(0, y(left[0]));
    for (var d = 1; d <= day; d++) {
      line.lineTo(x(d), y(left[d]));
    }

    // Even pace: from the limit to ₹0 on the last day.
    final pace =
        Paint()
          ..color = AppColors.darkFaint
          ..strokeWidth = 1.4;
    const dash = 3.0, gap = 5.0;
    final len = math.sqrt(w * w + (zeroY - top) * (zeroY - top));
    for (var s = 0.0; s < len; s += dash + gap) {
      final a = s / len, b = math.min(1.0, (s + dash) / len);
      canvas.drawLine(Offset(w * a, top + (zeroY - top) * a), Offset(w * b, top + (zeroY - top) * b), pace);
    }

    // ₹0
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(w, zeroY),
      Paint()
        ..color = AppColors.darkCardRaised
        ..strokeWidth = 1.5,
    );

    final reveal = x(day) * progress;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, reveal + 1, h));
    final area =
        Path.from(line)
          ..lineTo(x(day), zeroY)
          ..lineTo(0, zeroY)
          ..close();
    // Above ₹0: a soft lime wash.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, zeroY));
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.accent.withValues(alpha: 0.32), AppColors.accent.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, top, w, zeroY - top)),
    );
    canvas.restore();
    // Below ₹0 (spent extra): stripes.
    if (minV < 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, zeroY, w, h - zeroY));
      canvas.clipPath(area);
      final stripe =
          Paint()
            ..color = AppColors.accent.withValues(alpha: 0.5)
            ..strokeWidth = 3;
      for (var s = -h; s < w + h; s += 8) {
        canvas.drawLine(Offset(s, h), Offset(s + h, 0), stripe);
      }
      canvas.restore();
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    // Today: a faint line and a dot at the end.
    canvas.drawLine(Offset(x(day), top), Offset(x(day), floorY), Paint()..color = Colors.white.withValues(alpha: 0.16));
    if (progress > 0.95) {
      final end = Offset(x(day), y(left[day]));
      canvas.drawCircle(end, 7, Paint()..color = AppColors.dark);
      canvas.drawCircle(end, 4.5, Paint()..color = AppColors.accent);
    }

    _label(canvas, 'today', Offset(x(day) - 5, top - 2), AppColors.darkFaint, alignRight: true);
    _label(canvas, zeroLabel, Offset(w, zeroY - 15), AppColors.darkFaint, alignRight: true);
    if (ranOutLabel != null && budget.ranOutDay != null && progress > 0.6) {
      // Early in the month: above ₹0 to the right (the line is under ₹0 there by then).
      // Late: under ₹0 to the left (that part is still above ₹0).
      final rx = x(budget.ranOutDay!);
      final early = day - budget.ranOutDay! > 8;
      _label(
        canvas,
        ranOutLabel!,
        Offset(early ? rx + 7 : rx - 12, early ? zeroY - 17 : zeroY + 5),
        AppColors.accent,
        alignRight: !early,
        bold: true,
      );
    }
  }

  void _label(Canvas canvas, String text, Offset at, Color color, {bool alignRight = false, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 10.5,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(alignRight ? at.dx - tp.width : at.dx, at.dy));
  }

  @override
  bool shouldRepaint(MoneyLeftPainter old) =>
      old.progress != progress || old.budget != budget || old.day != day || old.days != days;
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
