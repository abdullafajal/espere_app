/// Picking a category by swiping: the picked one is a big dark card in the middle, the
/// next and previous ones peek at the sides. It goes round: left of the first category
/// is the last one, so the first (most used) never sits next to an empty space. Drag (or flick) to move; it settles on the
/// app's spring. Tap a side card to bring it to the middle, tap the middle card (or
/// "All") to see every category in a searchable list. Used on Add expense, Edit and the
/// Split "new expense" screen, so picking a category feels the same everywhere.
library;

import 'block_bar.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';

class CarouselCategory {
  final String label;
  final IconData icon;

  /// A line under the name, e.g. "₹2,653 left" (null: none).
  final String? note;

  /// How much of its budget is used (0-1+), for the list's bar (null: no budget).
  final double? used;

  /// The "New category" card (tap opens [CategoryCarousel.onNew]).
  final bool isNew;

  const CarouselCategory({
    required this.label,
    required this.icon,
    this.note,
    this.used,
    this.isNew = false,
  });
}

class CategoryCarousel extends StatefulWidget {
  final List<CarouselCategory> items;
  final int index;
  final ValueChanged<int> onChanged;
  final VoidCallback? onNew;

  /// Dark cards on a dark background (inside a dark sheet) instead of the light sheet.
  final bool onDark;

  const CategoryCarousel({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.onNew,
    this.onDark = false,
  });

  @override
  State<CategoryCarousel> createState() => _CategoryCarouselState();
}

class _CategoryCarouselState extends State<CategoryCarousel> with SingleTickerProviderStateMixin {
  static const double _gap = 92; // between card centres
  static const double _stageH = 186;

  late final AnimationController _pos =
      AnimationController.unbounded(vsync: this, value: widget.index.toDouble())..addListener(_onMove);
  int _shown = 0; // the index last reported

  @override
  void initState() {
    super.initState();
    _shown = widget.index;
  }

  @override
  void didUpdateWidget(CategoryCarousel old) {
    super.didUpdateWidget(old);
    // Picked elsewhere (the list, or the screen chose a default): glide there.
    if (widget.index != _shown && !_pos.isAnimating) {
      _shown = widget.index;
      _settle(_nearest(widget.index), 0);
    }
  }

  /// The scroll position for [index] closest to where the carousel is now (it goes round).
  int _nearest(int index) {
    if (!_loops) return index;
    final base = _pos.value.round();
    var diff = (index - _wrap(base)) % _n;
    if (diff > _n / 2) diff -= _n;
    return base + diff;
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  int get _n => widget.items.length;

  /// Goes round when there are enough categories to fill both sides.
  bool get _loops => _n >= 4;
  int _wrap(int k) => _loops ? ((k % _n) + _n) % _n : k.clamp(0, _n - 1);

  void _onMove() {
    final i = _wrap(_pos.value.round());
    if (i != _shown) {
      _shown = i;
      AppHaptics.tap();
      widget.onChanged(i);
    }
  }

  void _settle(int target, double velocity) {
    _pos.animateWith(SpringSimulation(AppMotion.move, _pos.value, target.toDouble(), velocity));
  }

  void _dragStart(DragStartDetails d) => _pos.stop();

  void _dragUpdate(DragUpdateDetails d) {
    var p = _pos.value - d.delta.dx / _gap;
    // Without going round, past either end it gives like a rubber band.
    if (!_loops && (p < 0 || p > _n - 1)) p = _pos.value - d.delta.dx / _gap * 0.3;
    _pos.value = p;
  }

  void _dragEnd(DragEndDetails d) {
    final v = -(d.primaryVelocity ?? 0) / _gap; // cards per second
    final projected = _pos.value + v * 0.18; // a flick carries on a little
    final target = _loops ? projected.round() : projected.round().clamp(0, _n - 1);
    _settle(target, v);
  }

  void _tapAt(double dx, double width) {
    var hit = (_pos.value + (dx - width / 2) / _gap).round();
    if (!_loops) hit = hit.clamp(0, _n - 1);
    if (hit == _pos.value.round()) {
      final item = widget.items[_wrap(hit)];
      if (item.isNew) {
        widget.onNew?.call();
      } else {
        _openAll();
      }
    } else {
      AppHaptics.tap();
      _settle(hit, 0);
    }
  }

  Future<void> _openAll() async {
    AppHaptics.tap();
    final picked = await showCategoryList(context, widget.items, _wrap(_pos.value.round()));
    if (picked != null && mounted) {
      _settle(_nearest(picked), 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_n == 0) return const SizedBox(height: 150);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _dragStart,
            onHorizontalDragUpdate: _dragUpdate,
            onHorizontalDragEnd: _dragEnd,
            onTapUp: (d) => _tapAt(d.localPosition.dx, w),
            child: SizedBox(
              height: _stageH,
              child: AnimatedBuilder(
                animation: _pos,
                builder: (context, _) {
                  final p = _pos.value;
                  final c = p.round();
                  // Positions around the middle (each shows the category it wraps to);
                  // never so many that one category shows twice.
                  final reach = _loops ? math.min(3, (_n - 1) ~/ 2) : 3;
                  final order = <int>[
                    for (var k = c - reach; k <= c + reach; k++)
                      if (_loops || (k >= 0 && k < _n)) k
                  ]..sort((a, b) => (b - p).abs().compareTo((a - p).abs()));
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [for (final i in order) _placed(i, p, w)],
                  );
                },
              ),
            ),
          );
        }),
        // The picked category, large: its name and what its budget says.
        AnimatedBuilder(
          animation: _pos,
          builder: (context, _) {
            final item = widget.items[_wrap(_pos.value.round())];
            return Column(
              children: [
                Text(
                  item.isNew ? 'New category' : item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: widget.onDark ? Colors.white : AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 17,
                  child: Text(
                    item.isNew ? 'Tap to add one' : (item.note ?? 'No budget'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: item.note != null ? FontWeight.w700 : FontWeight.w500,
                      color: item.note != null ? const Color(0xFF1D6B45) : AppColors.muted,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.swipe_rounded, size: 15, color: widget.onDark ? AppColors.darkMuted : AppColors.muted),
            const SizedBox(width: 6),
            Text('Swipe', style: AppText.rowSub.copyWith(fontSize: 11.5, color: widget.onDark ? AppColors.darkMuted : null)),
            const SizedBox(width: 10),
            SpringPress(
              haptic: HapticKind.none,
              onTap: _openAll,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.onDark ? AppColors.darkCard : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'All ${widget.items.where((e) => !e.isNew).length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: widget.onDark ? Colors.white : AppColors.text,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// One card at its place for scroll position [p], cover-flow style: the middle card
  /// faces you, the others turn away in 3D, step back and fade further out.
  Widget _placed(int i, double p, double width) {
    final d = i - p;
    final a = d.abs();
    final s = d.clamp(-1.0, 1.0);
    final x = d * _gap + s * math.min(a, 1) * 6;
    final opacity = (1 - math.max(0.0, a - 1.6) * 0.8).clamp(0.0, 1.0);
    const cw = 120.0, ch = 150.0;
    final m = Matrix4.identity()
      ..setEntry(3, 2, 0.0014) // perspective
      ..translateByDouble(x, 0, -math.min(a, 2) * 70, 1)
      ..rotateY(-s * 0.84); // up to 48°
    return Positioned(
      left: width / 2 - cw / 2,
      top: (_stageH - ch) / 2,
      child: Opacity(
        opacity: opacity,
        child: Transform(
          transform: m,
          alignment: Alignment.center,
          child: _card(widget.items[_wrap(i)], a < 0.5, cw, ch,
              Color.lerp(AppColors.accent, AppColors.surface, a.clamp(0.0, 1.0))!),
        ),
      ),
    );
  }

  Widget _card(CarouselCategory item, bool mid, double w, double h, Color bg) {
    return Container(
      width: w,
      height: h,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(28),
        border: mid ? Border.all(color: AppColors.dark, width: 2) : null,
        boxShadow: mid ? const [BoxShadow(color: Color(0x2E000000), blurRadius: 24, offset: Offset(0, 12))] : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: item.isNew ? Colors.transparent : Colors.white.withValues(alpha: 0.6),
              shape: BoxShape.circle,
              border: item.isNew ? Border.all(color: AppColors.mutedLight, width: 1.5) : null,
            ),
            child: Icon(item.icon, size: 28, color: AppColors.dark),
          ),
          const SizedBox(height: 8),
          Text(
            item.label,
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text),
          ),
        ],
      ),
    );
  }
}

/// Every category in a sheet: a search box, those with a budget first (with what is
/// left and a bar), then the rest. Resolves to the picked index, or null.
Future<int?> showCategoryList(BuildContext context, List<CarouselCategory> items, int current) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CategoryListSheet(items: items, current: current),
  );
}

class _CategoryListSheet extends StatefulWidget {
  final List<CarouselCategory> items;
  final int current;
  const _CategoryListSheet({required this.items, required this.current});

  @override
  State<_CategoryListSheet> createState() => _CategoryListSheetState();
}

class _CategoryListSheetState extends State<_CategoryListSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final match = [
      for (final (i, c) in widget.items.indexed)
        if (!c.isNew && c.label.toLowerCase().contains(_q.toLowerCase())) (i, c)
    ];
    final withBudget = match.where((e) => e.$2.used != null).toList();
    final others = match.where((e) => e.$2.used == null).toList();
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, size: 20, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    autofocus: false,
                    onChanged: (v) => setState(() => _q = v.trim()),
                    decoration: const InputDecoration(
                      hintText: 'Search categories',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 24),
              children: [
                if (withBudget.isNotEmpty) _label('WITH A BUDGET'),
                for (final (i, c) in withBudget) _row(i, c),
                if (others.isNotEmpty) _label(withBudget.isEmpty ? 'CATEGORIES' : 'OTHERS'),
                for (final (i, c) in others) _row(i, c),
                if (match.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No category called "$_q"', textAlign: TextAlign.center, style: AppText.rowSub),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
        child: Text(t, style: AppText.label),
      );

  Widget _row(int i, CarouselCategory c) {
    final current = i == widget.current;
    return SpringPress(
      haptic: HapticKind.tap,
      scale: 0.97,
      onTap: () => Navigator.pop(context, i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: current ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(color: AppColors.categoryFill, shape: BoxShape.circle),
              child: Icon(c.icon, size: 21, color: AppColors.categoryInk),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.label, style: AppText.rowTitle),
                  if (c.note != null) Text(c.note!, style: AppText.rowSub),
                ],
              ),
            ),
            if (c.used != null)
              SizedBox(
                width: 64,
                child: BlockBar(value: c.used!, height: 5),
              ),
          ],
        ),
      ),
    );
  }
}
