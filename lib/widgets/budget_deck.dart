/// The Budgets screen's card stack: one big dark card for the picked budget with two
/// cards peeking behind it. Swipe the card (or use ‹ ›) to move through the budgets; tap
/// it to open the budget. Each card shows what is left (or how much over), spent of the
/// limit, and the month's days as a strip: green while the budget lasted, white today.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/budget_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/icon_mapper.dart';
import 'morph_text.dart';
import 'spring_menu.dart';
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

  static const double height = 230;

  @override
  State<BudgetDeck> createState() => _BudgetDeckState();
}

class _BudgetDeckState extends State<BudgetDeck> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))
    ..addListener(() => setState(() => _dx = _from + (_to - _from) * Curves.easeOutCubic.transform(_c.value)));
  double _dx = 0, _from = 0, _to = 0;
  double _width = 300;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _animate(double to) {
    _from = _dx;
    _to = to;
    return _c.forward(from: 0);
  }

  /// Moves to the next (dir 1) or previous (-1) budget: the card flies out, the next one
  /// slides in.
  Future<void> go(int dir) async {
    final n = widget.items.length;
    if (n < 2 || _c.isAnimating) return;
    AppHaptics.tap();
    await _animate(-dir * _width * 1.2);
    widget.onIndex((widget.index + dir + n) % n);
    _dx = dir * 50.0;
    await _animate(0);
  }

  String _m(double v) =>
      '${widget.symbol}${NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0).format(v.round())}';

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final n = items.length;
    final i = widget.index.clamp(0, n - 1);
    return Column(
      children: [
        LayoutBuilder(builder: (context, box) {
          _width = box.maxWidth;
          return SizedBox(
            height: BudgetDeck.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (n > 2) _back(items[(i + 2) % n], 2),
                if (n > 1) _back(items[(i + 1) % n], 1),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 18,
                  child: GestureDetector(
                    onTap: () => widget.onOpen(items[i]),
                    onHorizontalDragUpdate: n < 2
                        ? null
                        : (d) {
                            _c.stop();
                            setState(() => _dx += d.delta.dx);
                          },
                    onHorizontalDragEnd: n < 2
                        ? null
                        : (d) {
                            final v = d.primaryVelocity ?? 0;
                            if (_dx.abs() > 70 || v.abs() > 600) {
                              go(_dx < 0 || v < -600 ? 1 : -1);
                            } else {
                              _animate(0);
                            }
                          },
                    child: Transform.translate(
                      offset: Offset(_dx, 0),
                      child: Transform.rotate(
                        angle: _dx / 1400,
                        child: widget.snapKeyFor == null
                            ? _card(items[i], front: true)
                            : ThanosSnapWidget(key: widget.snapKeyFor!(items[i]), child: _card(items[i], front: true)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        Row(
          children: [
            _arrow(Icons.chevron_left_rounded, 'Previous budget', n > 1 ? () => go(-1) : null),
            Expanded(
              child: Text('${i + 1} of $n',
                  textAlign: TextAlign.center, style: AppText.rowSub.copyWith(fontWeight: FontWeight.w600)),
            ),
            _arrow(Icons.chevron_right_rounded, 'Next budget', n > 1 ? () => go(1) : null),
          ],
        ),
      ],
    );
  }

  Widget _arrow(IconData icon, String label, VoidCallback? onTap) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: SpringPress(
          haptic: HapticKind.none,
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: AppColors.card, shape: BoxShape.circle, boxShadow: AppShadows.soft),
            child: Icon(icon, color: onTap == null ? AppColors.mutedLight : AppColors.dark),
          ),
        ),
      );

  /// A card peeking behind the front one: a little higher, smaller and fainter.
  Widget _back(BudgetInfo b, int depth) => Positioned(
        left: 0,
        right: 0,
        top: 18 - 9.0 * depth,
        child: IgnorePointer(
          child: Transform.scale(
            scale: 1 - 0.06 * depth,
            alignment: Alignment.topCenter,
            child: Opacity(opacity: depth == 1 ? 0.7 : 0.45, child: _card(b, front: false)),
          ),
        ),
      );

  Widget _card(BudgetInfo b, {required bool front}) {
    final over = b.spent > b.limit && b.limit > 0;
    final now = DateTime.now();
    final daysIn = DateTime(widget.month.year, widget.month.month + 1, 0).day;
    final isThisMonth = widget.month.year == now.year && widget.month.month == now.month;
    final today = isThisMonth ? now.day : daysIn + 1;
    final lasted = over ? (b.ranOutDay ?? today) : today;
    final daysLeft = isThisMonth ? daysIn - now.day + 1 : 0;
    final pct = (b.fraction * 100).round();
    final repeatLine = [
      b.repeat ? 'Every month' : 'This month only',
      if (b.carried > 0) '+${_m(b.carried)} carried',
    ].join(' · ');
    final String footLeft;
    final String footRight;
    if (over) {
      footLeft = b.ranOutDay != null ? 'Ran out on ${b.ranOutDay} ${DateFormat('MMM').format(widget.month)}' : 'Over the limit';
      footRight = isThisMonth ? '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} to go' : '';
    } else if (isThisMonth && daysLeft > 0) {
      footLeft = '${_m(b.left / daysLeft)} a day for $daysLeft ${daysLeft == 1 ? 'day' : 'days'}';
      footRight = '$pct% used';
    } else {
      footLeft = '${_m(b.left)} was left';
      footRight = '$pct% used';
    }

    return Container(
      height: BudgetDeck.height - 22,
      padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(26),
        boxShadow: front ? const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 12))] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: AppColors.darkCardRaised, shape: BoxShape.circle),
                child: Icon(IconMapper.map(b.icon), size: 20, color: AppColors.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                    Text(repeatLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.darkMuted)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: over ? AppColors.accent : AppColors.darkCardRaised,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text('$pct%',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, color: over ? AppColors.dark : AppColors.accent)),
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
                    child: Icon(Icons.more_vert_rounded, size: 20, color: AppColors.darkMuted),
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
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.4, color: Colors.white),
            ),
          ),
          MorphText(
            id: 'deck-${b.categoryId}',
            '${_m(b.spent)} spent of ${_m(b.limit)}',
            style: const TextStyle(fontSize: 12, color: AppColors.darkMuted),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              children: [
                for (var d = 1; d <= daysIn; d++) ...[
                  if (d > 1) const SizedBox(width: 2),
                  Expanded(
                    child: Container(
                      height: 18,
                      decoration: BoxDecoration(
                        color: d == today
                            ? Colors.white
                            : d < math.min(lasted, today) || (!over && d < today)
                                ? AppColors.accent
                                : AppColors.darkCardRaised,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(footLeft,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.darkMuted)),
                ),
                Text(footRight, style: const TextStyle(fontSize: 11, color: AppColors.darkMuted)),
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
    final m = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0);
    final amount = '$symbol${m.format((over ? b.spent - b.limit : b.left).round())}';
    final under = over ? 'over $symbol${m.format(b.limit.round())}' : 'left of $symbol${m.format(b.limit.round())}';
    // Blocks filled: one per 10% (a started block counts), all ten when over.
    final filled = over ? 10 : (b.fraction * 10).ceil().clamp(b.spent > 0 ? 1 : 0, 10);
    final blockColor = over || near ? AppColors.dark : AppColors.accent;
    return Semantics(
      button: true,
      selected: current,
      label: '${b.name}: $amount ${over ? 'over' : 'left'}',
      excludeSemantics: true,
      child: Material(
        color: current ? AppColors.accentSoft : AppColors.card,
        child: InkWell(
          onTap: () {
            AppHaptics.tap();
            onTap();
          },
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
                  child: Icon(IconMapper.map(b.icon), size: 20, color: over ? AppColors.accent : AppColors.dark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(b.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle.copyWith(fontSize: 14)),
                          ),
                          if (over) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(6)),
                              child: Text('OVER',
                                  style: TextStyle(
                                      fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: AppColors.accent)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          for (var k = 0; k < 10; k++) ...[
                            if (k > 0) const SizedBox(width: 2.5),
                            Expanded(
                              child: AnimatedContainer(
                                duration: Duration(milliseconds: 200 + 40 * k),
                                height: 7,
                                decoration: BoxDecoration(
                                  color: k < filled ? blockColor : AppColors.surface,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MorphText(id: 'brow-${b.categoryId}', amount, style: AppText.amount.copyWith(fontSize: 15)),
                    const SizedBox(height: 2),
                    MorphText(id: 'brow-${b.categoryId}', under, style: AppText.rowSub.copyWith(fontSize: 10.5)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
