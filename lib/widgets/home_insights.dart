/// Home charts, built from the transactions saved on the phone (work offline):
/// [CategoryBreakdownCard] — where the month's money went, as a donut and a ranked list;
/// [MonthlyTrendCard] — spending for the last 6 months; tap a bar to open that month.
library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/transaction.dart';
import '../theme/app_theme.dart';
import '../utils/icon_mapper.dart';

String _money(num v, String symbol) {
  final whole = v == v.roundToDouble();
  final f = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: whole ? 0 : 2);
  return '${v < 0 ? '−' : ''}$symbol${f.format(v.abs())}';
}

/// Short form for chart labels: ₹950, ₹12.4k, ₹1.2L.
String _short(double v, String symbol) {
  if (v >= 100000) return '$symbol${(v / 100000).toStringAsFixed(v >= 1000000 ? 0 : 1)}L';
  if (v >= 1000) return '$symbol${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k';
  return '$symbol${v.round()}';
}

class _Slice {
  final String name;
  final String icon;
  final double total;
  final int count;
  const _Slice(this.name, this.icon, this.total, this.count);
}

class CategoryBreakdownCard extends StatefulWidget {
  final DateTime month;
  final List<TransactionModel> transactions;
  final String symbol;
  final ValueChanged<String>? onCategoryTap;

  const CategoryBreakdownCard({
    super.key,
    required this.month,
    required this.transactions,
    required this.symbol,
    this.onCategoryTap,
  });

  @override
  State<CategoryBreakdownCard> createState() => _CategoryBreakdownCardState();
}

class _CategoryBreakdownCardState extends State<CategoryBreakdownCard> {
  int? _touched;

  List<_Slice> _slices() {
    final totals = <String, (String, double, int)>{};
    for (final t in widget.transactions) {
      if (t.isIncome) continue;
      final d = t.date.toLocal();
      if (d.year != widget.month.year || d.month != widget.month.month) continue;
      final v = double.tryParse(t.amount) ?? 0;
      final prev = totals[t.category.name];
      totals[t.category.name] = (t.category.icon, (prev?.$2 ?? 0) + v, (prev?.$3 ?? 0) + 1);
    }
    final list = totals.entries.map((e) => _Slice(e.key, e.value.$1, e.value.$2, e.value.$3)).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    if (list.length <= 6) return list;
    final rest = list.skip(5);
    return [
      ...list.take(5),
      _Slice('Everything else', 'more_horiz', rest.fold(0, (s, x) => s + x.total), rest.fold(0, (s, x) => s + x.count)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final slices = _slices();
    final total = slices.fold<double>(0, (s, x) => s + x.total);
    final touched = _touched != null && _touched! < slices.length ? slices[_touched!] : null;

    return _Card(
      title: 'Where it went',
      subtitle: DateFormat('MMMM yyyy').format(widget.month),
      child: slices.isEmpty
          ? const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: Text('No spending this month yet.', style: AppText.rowSub),
            )
          : Column(
              children: [
                SizedBox(
                  height: 190,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 3,
                          centerSpaceRadius: 58,
                          startDegreeOffset: -90,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, resp) {
                              if (!event.isInterestedForInteractions) return;
                              final i = resp?.touchedSection?.touchedSectionIndex;
                              if (i != null && i >= 0 && i != _touched) {
                                HapticFeedback.selectionClick();
                                setState(() => _touched = i);
                              }
                            },
                          ),
                          sections: [
                            for (var i = 0; i < slices.length; i++)
                              PieChartSectionData(
                                value: slices[i].total,
                                color: AppColors.chartAt(i),
                                radius: i == _touched ? 30 : 24,
                                showTitle: false,
                              ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(touched?.name ?? 'Spent', style: AppText.rowSub, maxLines: 1),
                          const SizedBox(height: 2),
                          Text(
                            _money(touched?.total ?? total, widget.symbol),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text),
                          ),
                          if (touched != null)
                            Text('${(touched.total / total * 100).round()}%',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                for (var i = 0; i < slices.length; i++) _row(i, slices[i], total),
                const SizedBox(height: 6),
              ],
            ),
    );
  }

  Widget _row(int i, _Slice s, double total) {
    final pct = total <= 0 ? 0.0 : s.total / total;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _touched = _touched == i ? null : i);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: AppColors.categoryFill, shape: BoxShape.circle),
              child: Icon(IconMapper.map(s.icon), size: 20, color: AppColors.categoryInk),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: AppColors.chartAt(i), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(s.name,
                            style: AppText.rowTitle.copyWith(fontWeight: i == _touched ? FontWeight.w800 : FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(_money(s.total, widget.symbol), style: AppText.amount),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 6,
                            backgroundColor: AppColors.surface,
                            valueColor: AlwaysStoppedAnimation(AppColors.chartAt(i)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 78,
                        child: Text(
                          '${(pct * 100).round()}% · ${s.count} ${s.count == 1 ? 'entry' : 'entries'}',
                          textAlign: TextAlign.right,
                          style: AppText.rowSub.copyWith(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MonthlyTrendCard extends StatelessWidget {
  final DateTime selected;
  final List<TransactionModel> transactions;
  final String symbol;
  final ValueChanged<DateTime> onSelect;

  const MonthlyTrendCard({
    super.key,
    required this.selected,
    required this.transactions,
    required this.symbol,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = List.generate(6, (i) => DateTime(now.year, now.month - 5 + i));
    final spent = List<double>.filled(6, 0);
    final income = List<double>.filled(6, 0);
    for (final t in transactions) {
      final d = t.date.toLocal();
      final i = (d.year - months.first.year) * 12 + d.month - months.first.month;
      if (i < 0 || i > 5) continue;
      final v = double.tryParse(t.amount) ?? 0;
      if (t.isIncome) {
        income[i] += v;
      } else {
        spent[i] += v;
      }
    }
    final sel = months.indexWhere((m) => m.year == selected.year && m.month == selected.month);
    final maxY = math.max(1.0, spent.fold<double>(0, math.max)) * 1.25;
    final used = spent.where((v) => v > 0).toList();
    final avg = used.isEmpty ? 0.0 : used.reduce((a, b) => a + b) / used.length;
    final prevIdx = sel > 0 ? sel - 1 : -1;
    final change = sel >= 0 && prevIdx >= 0 && spent[prevIdx] > 0 ? (spent[sel] - spent[prevIdx]) / spent[prevIdx] : null;

    return _Card(
      title: 'Month by month',
      subtitle: 'Tap a month to see it',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
        child: Column(
          children: [
            SizedBox(
              height: 170,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    handleBuiltInTouches: false,
                    touchCallback: (event, resp) {
                      if (event is! FlTapUpEvent) return;
                      final i = resp?.spot?.touchedBarGroupIndex;
                      if (i == null || i < 0 || i > 5 || i == sel) return;
                      HapticFeedback.selectionClick();
                      onSelect(months[i]);
                    },
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i > 5 || spent[i] <= 0) return const SizedBox();
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              _short(spent[i], symbol),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: i == sel ? FontWeight.w800 : FontWeight.w600,
                                color: i == sel ? AppColors.text : AppColors.muted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i > 5) return const SizedBox();
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              DateFormat('MMM').format(months[i]),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: i == sel ? FontWeight.w800 : FontWeight.w600,
                                color: i == sel ? AppColors.text : AppColors.muted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < 6; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: math.max(spent[i], maxY * 0.02),
                            width: 26,
                            color: i == sel ? AppColors.accent : AppColors.dark,
                            borderRadius: BorderRadius.circular(8),
                            backDrawRodData: BackgroundBarChartRodData(
                              show: true,
                              toY: maxY,
                              color: AppColors.surface,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _stat('Average month', _money(avg.roundToDouble(), symbol))),
                const SizedBox(width: 8),
                Expanded(
                  child: _stat(
                    sel >= 0 ? 'vs ${prevIdx >= 0 ? DateFormat('MMM').format(months[prevIdx]) : 'before'}' : 'Change',
                    change == null ? '—' : '${change > 0 ? '↑' : '↓'} ${(change.abs() * 100).round()}%',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _stat('Money in', sel >= 0 ? '+${_money(income[sel], symbol)}' : '—')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowSub.copyWith(fontSize: 11)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text)),
            ),
          ],
        ),
      );
}

class _Card extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _Card({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          boxShadow: AppShadows.soft,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: Text(title, style: AppText.section)),
                  Text(subtitle, style: AppText.rowSub),
                ],
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
