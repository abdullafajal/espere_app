/// The Budgets screen's card stack: one big dark card for the picked budget with two
/// cards peeking behind it. Swipe the card (or use ‹ ›) to move through the budgets; tap
/// it to open the budget. Each card shows what is left (or how much over), spent of the
/// limit, and the month's days as a strip: green while the budget lasted, white today.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:intl/intl.dart';

import '../services/budget_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/icon_mapper.dart';
import 'morph_text.dart';
import 'spring_menu.dart';
import 'block_bar.dart';
import 'thanos_snap_widget.dart';

class BudgetDeck extends StatefulWidget {
  final List<BudgetInfo> items;
  final int index;
  final ValueChanged<int> onIndex;
  final DateTime month;
  final String symbol;
  final ValueChanged<BudgetInfo> onOpen;
  final ValueChanged<BudgetInfo> onEdit;
  final ValueChanged<BudgetInfo> onDelete;

  /// Key of the delete animation around the front card (so Delete plays it).
  final GlobalKey<ThanosSnapWidgetState> Function(BudgetInfo)? snapKeyFor;

  const BudgetDeck({
    super.key,
    required this.items,
    required this.index,
    required this.onIndex,
    required this.month,
    required this.symbol,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    this.snapKeyFor,
  });

  static const double height = 252;

  @override
  State<BudgetDeck> createState() => _BudgetDeckState();
}

class _BudgetDeckState extends State<BudgetDeck> with TickerProviderStateMixin {
  /// The front card's sideways offset in pixels. Driven by the finger while dragging and
  /// by a spring after letting go. Only the card transforms listen to it, so dragging
  /// does not rebuild the cards (or the screen).
  late final AnimationController _dx = AnimationController.unbounded(
    vsync: this,
  );
  double _width = 300;
  bool _flying = false;
  bool _passed =
      false; // the drag has gone far enough to change card (one tick when it does)
  bool _touched =
      false; // the user has dragged the deck (then no hint animation)

  /// The day under the finger while pressing and sliding along the front card's strip
  /// (null otherwise). Only the strip and the line under it listen to it.
  final ValueNotifier<int?> _scrub = ValueNotifier<int?>(null);

  /// The first time the deck is shown (once per app run), the card slides a little to
  /// the left and back, to show that it can be swiped.
  static bool _nudged = false;

  /// The app's spring (the nav pill's): arrives with one soft overshoot.
  static const _spring = AppMotion.move;

  /// The front card's size: springs from a little smaller to full when a new budget comes
  /// to the front (after a swipe, or a tap in the list), like the nav pill landing.
  late final AnimationController _land = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  bool _ownChange = false; // the index change came from this deck's swipe

  void _landSpring({double from = 0.94, double velocity = 0}) {
    _land.value = from;
    _land.animateWith(SpringSimulation(_spring, from, 1, velocity));
  }

  @override
  void didUpdateWidget(BudgetDeck old) {
    super.didUpdateWidget(old);
    // Picked from the list (not swiped): the new card springs in.
    if (old.index != widget.index && !_ownChange) _landSpring(from: 0.9);
    _ownChange = false;
  }

  @override
  void initState() {
    super.initState();
    if (!_nudged && widget.items.length > 1) {
      _nudged = true;
      Future.delayed(const Duration(milliseconds: 700), () async {
        if (!mounted || _touched || _flying || _dx.isAnimating) return;
        await _dx.animateTo(
          -54,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
        if (!mounted || _touched || _flying) return;
        await _dx.animateWith(SpringSimulation(_spring, _dx.value, 0, 0));
      });
    }
  }

  @override
  void dispose() {
    _dx.dispose();
    _land.dispose();
    _scrub.dispose();
    super.dispose();
  }

  int get _n => widget.items.length;
  int get _i => widget.index.clamp(0, _n - 1);

  /// How far the card behind has come forward (0 at rest, 1 when the front card is gone).
  double get _t => (_dx.value.abs() / (_width * 0.9)).clamp(0.0, 1.0);

  void _dragUpdate(DragUpdateDetails d) {
    if (_flying) return;
    _touched = true;
    _dx.stop();
    // A single budget only gives a little, like a rubber band.
    final delta = _n < 2 ? d.delta.dx * 0.25 : d.delta.dx;
    _dx.value += delta;
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
    if (_n >= 2 &&
        (x.abs() > _width * 0.28 || (v.abs() > 700 && v.sign == x.sign))) {
      _flyOut(x < 0 ? 1 : -1, v);
    } else {
      _dx.animateWith(SpringSimulation(_spring, x, 0, v));
    }
  }

  /// The front card flies off ([dir] 1: to the left, next budget; -1: to the right,
  /// previous). The card behind is already in front by then, so the swap does not jump.
  Future<void> _flyOut(int dir, [double velocity = 0]) async {
    _flying = true;
    final target = -dir * _width * 1.15;
    final speed = math.max(velocity.abs(), 1600.0);
    final ms =
        ((target - _dx.value).abs() / speed * 1000).clamp(120, 320).round();
    await _dx.animateTo(
      target,
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    _ownChange = true;
    widget.onIndex((_i + dir + _n) % _n);
    _dx.value = 0;
    // The card that came forward settles with the app's spring (a small overshoot).
    _landSpring(from: 0.97, velocity: 0.6);
    _flying = false;
  }

  /// Moves to the next (1) or previous (-1) budget, as if swiped (used by the dots).
  Future<void> go(int dir) async {
    if (_n < 2 || _flying) return;
    AppHaptics.tap();
    await _flyOut(dir);
  }

  String _m(double v) =>
      '${widget.symbol}${NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0).format(v.round())}';

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final n = _n;
    final i = _i;
    // Built once per index change; dragging only moves them.
    final frontCard = _card(items[i], front: true);
    final front = RepaintBoundary(
      // Delete plays the dust animation on the front card.
      child:
          widget.snapKeyFor == null
              ? frontCard
              : ThanosSnapWidget(
                key: widget.snapKeyFor!(items[i]),
                child: frontCard,
              ),
    );
    final next =
        n > 1
            ? RepaintBoundary(child: _card(items[(i + 1) % n], front: false))
            : null;
    final prev =
        n > 1
            ? RepaintBoundary(
              child: _card(items[(i - 1 + n) % n], front: false),
            )
            : null;
    final next2 =
        n > 2
            ? RepaintBoundary(child: _card(items[(i + 2) % n], front: false))
            : null;
    final prev2 =
        n > 2
            ? RepaintBoundary(
              child: _card(items[(i - 2 + n) % n], front: false),
            )
            : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            _width = box.maxWidth;
            return SizedBox(
              height: BudgetDeck.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onOpen(items[i]),
                onHorizontalDragUpdate: _dragUpdate,
                onHorizontalDragEnd: _dragEnd,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_dx, _land]),
                  builder: (context, _) {
                    final x = _dx.value;
                    final t = _t;
                    // Dragging right shows the previous budgets behind, left the next ones.
                    final b1 = x > 0 ? prev : next;
                    final b2 = x > 0 ? prev2 : next2;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (b2 != null) _placed(b2, depth: 2 - t),
                        if (b1 != null) _placed(b1, depth: 1 - t),
                        _placed(
                          Transform.translate(
                            offset: Offset(x, x.abs() * 0.04),
                            child: Transform.rotate(
                              angle: x / (_width * 6),
                              child: Transform.scale(
                                scale: _land.value,
                                child: front,
                              ),
                            ),
                          ),
                          depth: 0,
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        _indicator(n, i),
      ],
    );
  }

  /// Puts a card in the stack: depth 0 is the front, 1 and 2 peek behind (higher,
  /// smaller, fainter). In between while a card is being swiped away.
  Widget _placed(Widget card, {required double depth}) {
    final d = depth.clamp(0.0, 2.0);
    return Positioned(
      left: 0,
      right: 0,
      top: 18 - 9.0 * d,
      child: Transform.scale(
        scale: 1 - 0.06 * d,
        alignment: Alignment.topCenter,
        child: Opacity(opacity: (1 - 0.28 * d).clamp(0.0, 1.0), child: card),
      ),
    );
  }

  /// Where you are and that the cards swipe: dots (a count when there are many) with a
  /// small swipe icon. Tapping a side of it moves one card that way.
  Widget _indicator(int n, int i) {
    if (n < 2) return const SizedBox(height: 4);
    final dots = n <= 8;
    return Semantics(
      label: 'Budget ${i + 1} of $n. Swipe the card for the next one.',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swipe_rounded, size: 16, color: AppColors.muted),
          const SizedBox(width: 6),
          if (dots)
            for (var k = 0; k < n; k++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: k == i ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: k == i ? AppColors.dark : AppColors.mutedLight,
                  borderRadius: BorderRadius.circular(3),
                ),
              )
          else
            Text(
              '${i + 1} of $n',
              style: AppText.rowSub.copyWith(fontWeight: FontWeight.w700),
            ),
          const SizedBox(width: 8),
          Text('Swipe', style: AppText.rowSub.copyWith(fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _card(BudgetInfo b, {required bool front}) {
    final over = b.spent > b.limit && b.limit > 0;
    final now = DateTime.now();
    final daysIn = DateTime(widget.month.year, widget.month.month + 1, 0).day;
    final isThisMonth =
        widget.month.year == now.year && widget.month.month == now.month;
    final today = isThisMonth ? now.day : daysIn + 1;
    final daysLeft = isThisMonth ? daysIn - now.day + 1 : 0;
    final pct = (b.fraction * 100).round();
    final repeatLine = [
      b.repeat ? 'Every month' : 'This month only',
      if (b.carried > 0) '+${_m(b.carried)} carried',
    ].join(' · ');
    final String footLeft;
    final String footRight;
    if (over) {
      footLeft =
          b.ranOutDay != null
              ? 'Ran out on ${b.ranOutDay} ${DateFormat('MMM').format(widget.month)}'
              : 'Over the limit';
      footRight =
          isThisMonth
              ? '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} to go'
              : '';
    } else if (isThisMonth && daysLeft > 0) {
      footLeft =
          '${_m(b.left / daysLeft)} a day for $daysLeft ${daysLeft == 1 ? 'day' : 'days'}';
      footRight = '$pct% used';
    } else {
      footLeft = '${_m(b.left)} was left';
      footRight = '$pct% used';
    }

    final maxDay = b.daily.values.fold<double>(0, math.max);
    return Container(
      height: BudgetDeck.height - 22,
      padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(26),
        boxShadow:
            front
                ? const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ]
                : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.darkCardRaised,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  IconMapper.map(b.icon),
                  size: 20,
                  color: AppColors.accent,
                ),
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
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      repeatLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.darkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: over ? AppColors.accent : AppColors.darkCardRaised,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$pct%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: over ? AppColors.dark : AppColors.accent,
                  ),
                ),
              ),
              if (front)
                SpringMenuButton<String>(
                  items: SpringMenuButton.editDelete(),
                  onSelected: (v) {
                    if (v == 'edit') widget.onEdit(b);
                    if (v == 'delete') widget.onDelete(b);
                  },
                  child: const SizedBox(
                    width: 36,
                    height: 40,
                    child: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: AppColors.darkMuted,
                    ),
                  ),
                )
              else
                const SizedBox(width: 10),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MorphText(
              id: 'deck-${b.categoryId}',
              over ? '${_m(b.spent - b.limit)} over' : '${_m(b.left)} left',
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.4,
                color: Colors.white,
              ),
            ),
          ),
          MorphText(
            id: 'deck-${b.categoryId}',
            '${_m(b.spent)} spent of ${_m(b.limit)}',
            style: const TextStyle(fontSize: 12, color: AppColors.darkMuted),
          ),
          const SizedBox(height: 12),
          // On the front card, press and hold the strip, then slide: the line under it shows
          // that day's date and spending, and its bar lights up.
          ValueListenableBuilder<int?>(
            valueListenable: front ? _scrub : ValueNotifier<int?>(null),
            builder:
                (context, scrub, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, box) {
                        final stripW = box.maxWidth - 10;
                        int dayAt(double x) =>
                            (x / stripW * daysIn).floor().clamp(0, daysIn - 1) +
                            1;
                        void pick(double x) {
                          final d = dayAt(x);
                          if (d != _scrub.value) {
                            _scrub.value = d;
                            AppHaptics.tap();
                          }
                        }

                        return GestureDetector(
                          // The whole strip takes the press, not only the bars.
                          behavior: HitTestBehavior.opaque,
                          onLongPressStart:
                              front ? (e) => pick(e.localPosition.dx) : null,
                          onLongPressMoveUpdate:
                              front ? (e) => pick(e.localPosition.dx) : null,
                          onLongPressEnd:
                              front ? (_) => _scrub.value = null : null,
                          onLongPressCancel:
                              front ? () => _scrub.value = null : null,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            // This budget's spending by day: each day's bar as tall as that day's spending
                            // (a dot when nothing). Green while within the budget, white after it ran out;
                            // the days still to come are faint; a white line marks today.
                            child: SizedBox(
                              height: 50,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  for (var d = 1; d <= daysIn; d++) ...[
                                    if (d > 1) const SizedBox(width: 2.5),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Container(
                                            height:
                                                (b.daily[d] ?? 0) <= 0
                                                    ? 4
                                                    : 8 +
                                                        34 *
                                                            ((b.daily[d] ?? 0) /
                                                                    maxDay)
                                                                .clamp(
                                                                  0.0,
                                                                  1.0,
                                                                ),
                                            decoration: BoxDecoration(
                                              color:
                                                  d == scrub
                                                      ? Colors.white
                                                      : d > today
                                                      ? AppColors.darkCard
                                                      : (b.daily[d] ?? 0) <= 0
                                                      ? AppColors.darkCardRaised
                                                      : (b.ranOutDay != null &&
                                                          d > b.ranOutDay!)
                                                      ? Colors.white
                                                      : AppColors.accent,
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Container(
                                            height: 2,
                                            decoration: BoxDecoration(
                                              color:
                                                  d == today
                                                      ? Colors.white
                                                      : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(1),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    if (scrub != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                DateFormat('EEE, d MMM').format(
                                  DateTime(
                                    widget.month.year,
                                    widget.month.month,
                                    scrub,
                                  ),
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            Text(
                              (b.daily[scrub] ?? 0) > 0
                                  ? _m(b.daily[scrub]!)
                                  : 'Nothing spent',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                footLeft,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.darkMuted,
                                ),
                              ),
                            ),
                            Text(
                              footRight,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.darkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
          ),
        ],
      ),
    );
  }
}

/// One budget in the "All budgets" list: icon, name (with an OVER tag when over), a bar
/// of ten blocks (each 10% of the limit; dark from 80%), and on the right what is left
/// or over with the limit under it. The picked one is tinted. Tap to bring it to the
/// front of the deck.
class BudgetListRow extends StatelessWidget {
  final BudgetInfo budget;
  final bool current;
  final String symbol;
  final VoidCallback onTap;

  const BudgetListRow({
    super.key,
    required this.budget,
    required this.current,
    required this.symbol,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = budget;
    final over = b.spent > b.limit && b.limit > 0;
    final near = !over && b.fraction >= 0.8;
    final m = NumberFormat.decimalPatternDigits(
      locale: 'en_IN',
      decimalDigits: 0,
    );
    final amount =
        '$symbol${m.format((over ? b.spent - b.limit : b.left).round())}';
    final under =
        over
            ? 'over $symbol${m.format(b.limit.round())}'
            : 'left of $symbol${m.format(b.limit.round())}';
    // Ten blocks of 10% each, filled to the exact share used: 61% is six full blocks
    // and a tenth of the seventh. All ten when over.
    final tenths = over ? 10.0 : (b.fraction * 10).clamp(0.0, 10.0);
    final blockColor = over || near ? AppColors.dark : AppColors.accent;
    return Semantics(
      button: true,
      selected: current,
      label: '${b.name}: $amount ${over ? 'over' : 'left'}',
      excludeSemantics: true,
      // Pressed, the row sinks and springs back like every button in the app.
      child: SpringPress(
        haptic: HapticKind.tap,
        scale: 0.97,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          color: current ? AppColors.accentSoft : AppColors.card,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: over ? AppColors.dark : AppColors.surface,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    IconMapper.map(b.icon),
                    size: 20,
                    color: over ? AppColors.accent : AppColors.dark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              b.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.rowTitle.copyWith(fontSize: 14),
                            ),
                          ),
                          if (over) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.dark,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'OVER',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                  color: AppColors.accent,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 7),
                      BlockBar(value: over ? 2 : tenths / 10, color: blockColor),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // A fixed width, so every row's bar is the same length.
                SizedBox(
                  width: 104,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      MorphText(
                        id: 'brow-${b.categoryId}',
                        amount,
                        style: AppText.amount.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      MorphText(
                        id: 'brow-${b.categoryId}',
                        under,
                        maxLines: 1,
                        style: AppText.rowSub.copyWith(fontSize: 10.5),
                      ),
                    ],
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
