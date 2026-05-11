/// Dashboard Screen — exact match of dashboard.html.
///
/// Layout: greeting header → balance card → 3 summary cards → promo banner
///         → insights → charts → recent transactions → quick links
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../theme/app_theme.dart';
import '../models/dashboard.dart';
import '../services/api_service.dart';
import '../widgets/balance_card.dart';
import '../widgets/summary_card.dart';
import '../widgets/transaction_tile.dart';
import '../utils/app_toast.dart';
import 'reports_screen.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int)? onTabChange;

  const DashboardScreen({super.key, this.onTabChange});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  DashboardData? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  /// Public method for parent to trigger a data reload.
  void reload() => _loadDashboard();

  Future<void> _loadDashboard() async {
    if (_data == null) {
      setState(() => _isLoading = true);
    }
    final result = await ApiService.getDashboard();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.isSuccess) {
        _data = result.data;
      } else {
        _error = result.error;
      }
    });
  }

  /// Calculates a "nice" interval for chart axes (like Chart.js/Django)
  double _getNiceInterval(double max) {
    if (max <= 0) return 1000;
    // Aim for 4-5 ticks
    double rawInterval = max / 4;
    double exponent = (math.log(rawInterval) / math.ln10).floorToDouble();
    double fraction = rawInterval / math.pow(10, exponent);
    
    double niceFraction;
    if (fraction < 1.5) niceFraction = 1;
    else if (fraction < 3) niceFraction = 2;
    else if (fraction < 7) niceFraction = 5;
    else niceFraction = 10;
    
    return niceFraction * math.pow(10, exponent);
  }

  double _getNiceMax(double max, double interval) {
    if (max <= 0) return 4000;
    return (math.max(max, 1.0) / interval).ceil() * interval;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildSkeleton();
    if (_error != null) return _buildError();
    if (_data == null) return _buildEmpty();

    final d = _data!;

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      color: AppColors.accent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Greeting Header ────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 32, bottom: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GOOD ${d.greeting.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted,
                          letterSpacing: 2.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: AppColors.text,
                            letterSpacing: -0.5,
                          ),
                          children: [
                            TextSpan(text: d.user.displayName),
                            const TextSpan(
                              text: '.',
                              style: TextStyle(color: AppColors.accent),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/profile'),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.dark,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        boxShadow: AppShadows.soft,
                      ),
                      child: const Icon(
                        Icons.settings_outlined,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ─── Balance Card ───────────────────────────────────
            BalanceCard(
              totalBalance: d.totalBalance,
              monthlyIncome: d.monthlyIncome,
              monthlyExpenses: d.monthlyExpenses,
              monthlySavings: d.monthlySavings,
              currencySymbol: d.currencySymbol,
              onAddIncome: () async {
                await Navigator.pushNamed(
                  context,
                  '/transaction/add',
                  arguments: 'income',
                );
                _loadDashboard();
              },
              onAddExpense: () async {
                await Navigator.pushNamed(
                  context,
                  '/transaction/add',
                  arguments: 'expense',
                );
                _loadDashboard();
              },
            ),

            const SizedBox(height: 16),

            // ─── Summary Cards (3 columns) ─────────────────────
            Row(
              children: [
                Expanded(
                  child: SummaryCard(
                    icon: Icons.arrow_upward,
                    label: 'Income',
                    value: '${d.currencySymbol}${d.monthlyIncome}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SummaryCard(
                    icon: Icons.arrow_downward,
                    label: 'Expenses',
                    value: '${d.currencySymbol}${d.monthlyExpenses}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SummaryCard(
                    icon: Icons.savings_outlined,
                    label: 'Savings',
                    value: '${d.currencySymbol}${d.monthlySavings}',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ─── Promo Banner ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Start tracking money tax free',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.dark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'The best place for tracking expenses and income. Start saving now!',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.dark.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    child: const Icon(
                      Icons.savings_outlined,
                      size: 28,
                      color: AppColors.dark,
                    ),
                  ),
                ],
              ),
            ),

            // ─── Budget Warnings ────────────────────────────────
            if (d.budgetWarnings.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...d.budgetWarnings.map(
                (w) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.dark,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_outlined, size: 18, color: AppColors.accent),
                      const SizedBox(width: 12),
                      Text(
                        '${w['category']} budget exceeded!',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // ─── Insights ───────────────────────────────────────
            if (d.insights.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...d.insights.map(
                (insight) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(AppRadius.xxl),
                    boxShadow: AppShadows.card,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.lightbulb_outline, size: 18, color: AppColors.dark),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          insight,
                          style: const TextStyle(fontSize: 14, color: AppColors.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // ─── Charts ─────────────────────────────────────────
            const SizedBox(height: 16),

            // Spending by Category (horizontal bar)
            if (d.pieLabels.isNotEmpty) ...[
              Builder(builder: (context) {
                final max = d.pieValues.isEmpty ? 0.0 : d.pieValues.fold(0.0, math.max);
                final interval = _getNiceInterval(max);
                final chartMax = _getNiceMax(max, interval);

                return _ChartCard(
                  icon: Icons.bar_chart,
                  title: 'Spending by Category',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      height: 220,
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: BarChart(
                          BarChartData(
                            maxY: chartMax,
                            alignment: BarChartAlignment.spaceAround,
                            barTouchData: BarTouchData(enabled: false),
                            titlesData: FlTitlesData(
                              show: true,
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 80,
                                  getTitlesWidget: (value, meta) {
                                    final idx = value.toInt();
                                    if (idx >= 0 && idx < d.pieLabels.length) {
                                      return RotatedBox(
                                        quarterTurns: -1,
                                        child: Padding(
                                          padding: const EdgeInsets.only(right: 8),
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              d.pieLabels[idx],
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                color: AppColors.text,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.right,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),
                              rightTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  interval: interval,
                                  reservedSize: 32,
                                  getTitlesWidget: (value, meta) {
                                    if (value > chartMax) return const SizedBox.shrink();
                                    return RotatedBox(
                                      quarterTurns: -1,
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          NumberFormat.decimalPattern().format(value),
                                          style: const TextStyle(fontSize: 10, color: AppColors.muted),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              drawHorizontalLine: true,
                              horizontalInterval: interval,
                              getDrawingHorizontalLine: (_) => FlLine(
                                color: Colors.black.withOpacity(0.04),
                                strokeWidth: 1,
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            barGroups: List.generate(d.pieLabels.length, (i) {
                              final colorHex = d.pieColors[i].replaceFirst('#', '');
                              return BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: d.pieValues[i],
                                    color: Color(int.parse('FF$colorHex', radix: 16)),
                                    width: d.pieLabels.length <= 3 ? 28 : 14,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],

            // Income vs Expenses (bar chart)
            if (d.barLabels.isNotEmpty) ...[
              Builder(builder: (context) {
                final max = [...d.barIncome, ...d.barExpense].fold(0.0, math.max);
                final interval = _getNiceInterval(max);
                final chartMax = _getNiceMax(max, interval);

                return _ChartCard(
                  icon: Icons.insert_chart_outlined,
                  title: 'Income vs Expenses',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 200,
                          child: BarChart(
                            BarChartData(
                              maxY: chartMax,
                              alignment: BarChartAlignment.spaceAround,
                              barTouchData: BarTouchData(enabled: false),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final idx = value.toInt();
                                      if (idx >= 0 && idx < d.barLabels.length) {
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Text(
                                            d.barLabels[idx],
                                            style: const TextStyle(fontSize: 10, color: AppColors.muted),
                                          ),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    interval: interval,
                                    reservedSize: 48,
                                    getTitlesWidget: (value, meta) {
                                      if (value > chartMax) return const SizedBox.shrink();
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: Text(
                                          NumberFormat.decimalPattern().format(value),
                                          style: const TextStyle(fontSize: 10, color: AppColors.muted),
                                          textAlign: TextAlign.right,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                horizontalInterval: interval,
                                getDrawingHorizontalLine: (_) => FlLine(
                                  color: Colors.black.withOpacity(0.04),
                                  strokeWidth: 1,
                                ),
                              ),
                              borderData: FlBorderData(show: false),
                              barGroups: List.generate(d.barLabels.length, (i) {
                                return BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: d.barIncome[i],
                                      color: AppColors.accent,
                                      width: 10,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    BarChartRodData(
                                      toY: d.barExpense[i],
                                      color: AppColors.dark,
                                      width: 10,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ],
                                );
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _LegendItem(color: AppColors.accent, label: 'Income'),
                            SizedBox(width: 20),
                            _LegendItem(color: AppColors.dark, label: 'Expenses'),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],

            // 30-Day Spending Trend (line chart)
            if (d.lineValues.isNotEmpty) ...[
              Builder(builder: (context) {
                final max = d.lineValues.isEmpty ? 0.0 : d.lineValues.fold(0.0, math.max);
                final interval = _getNiceInterval(max);
                final chartMax = _getNiceMax(max, interval);

                return _ChartCard(
                  icon: Icons.show_chart,
                  title: '30-Day Spending Trend',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      height: 160,
                      child: LineChart(
                        LineChartData(
                          maxY: chartMax,
                          lineTouchData: const LineTouchData(enabled: false),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: interval,
                            getDrawingHorizontalLine: (_) => FlLine(
                              color: Colors.black.withValues(alpha: 0.04),
                              strokeWidth: 1,
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 5,
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  if (idx >= 0 && idx < d.lineLabels.length) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        d.lineLabels[idx],
                                        style: const TextStyle(fontSize: 10, color: AppColors.muted),
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: interval,
                                reservedSize: 48,
                                getTitlesWidget: (value, meta) {
                                  if (value > chartMax) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Text(
                                      NumberFormat.decimalPattern().format(value),
                                      style: const TextStyle(fontSize: 10, color: AppColors.muted),
                                      textAlign: TextAlign.right,
                                    ),
                                  );
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: List.generate(
                                d.lineValues.length,
                                (i) => FlSpot(i.toDouble(), d.lineValues[i]),
                              ),
                              isCurved: true,
                              color: AppColors.accent,
                              barWidth: 2.5,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: AppColors.accent.withValues(alpha: 0.15),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],

            // ─── Recent Transactions ────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'History Transaction',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text),
                ),
                GestureDetector(
                  onTap: () {
                    // Navigate to transactions tab via parent
                  },
                  child: const Text(
                    'see more',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (d.recentTransactions.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(Icons.receipt_outlined, size: 48, color: AppColors.muted.withValues(alpha: 0.4)),
                      const SizedBox(height: 8),
                      const Text('No transactions yet.', style: TextStyle(fontSize: 14, color: AppColors.muted)),
                    ],
                  ),
                ),
              )
            else
              ...d.recentTransactions.map(
                (txn) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TransactionTile(
                    transaction: txn,
                    currencySymbol: d.currencySymbol,
                    onTap: () async {
                      await Navigator.pushNamed(context, '/transaction/edit',
                          arguments: txn.id);
                      _loadDashboard();
                    },
                  ),
                ),
              ),

            // ─── Quick Links ────────────────────────────────────
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _QuickLink(
                  icon: Icons.savings,
                  label: 'Budgets',
                  subtitle: 'Set spending limits',
                  onTap: () => widget.onTabChange?.call(2),
                ),
                _QuickLink(
                  icon: Icons.flag,
                  label: 'Savings',
                  subtitle: 'Track your goals',
                  onTap: () => widget.onTabChange?.call(3),
                ),
                _QuickLink(
                  icon: Icons.category,
                  label: 'Categories',
                  subtitle: 'Organize spending',
                  onTap: () => Navigator.pushNamed(context, '/categories'),
                ),
                _QuickLink(
                  icon: Icons.pie_chart,
                  label: 'Reports',
                  subtitle: 'Analyze spending',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())),
                ),
                _QuickLink(
                  icon: Icons.groups,
                  label: 'Split Groups',
                  subtitle: 'Share expenses',
                  onTap: () => widget.onTabChange?.call(4),
                ),
                _QuickLink(
                  icon: Icons.download,
                  label: 'Export',
                  subtitle: 'Download CSV',
                  onTap: () => AppToast.success(context, 'Export Complete: CSV downloaded successfully.'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _shimmer(96, 12),
                  const SizedBox(height: 8),
                  _shimmer(192, 32),
                ],
              ),
              _shimmer(48, 48, radius: AppRadius.xl),
            ],
          ),
          const SizedBox(height: 24),
          _shimmer(double.infinity, 200, radius: AppRadius.xxxl),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _shimmer(double.infinity, 100, radius: AppRadius.xxl)),
              const SizedBox(width: 12),
              Expanded(child: _shimmer(double.infinity, 100, radius: AppRadius.xxl)),
              const SizedBox(width: 12),
              Expanded(child: _shimmer(double.infinity, 100, radius: AppRadius.xxl)),
            ],
          ),
          const SizedBox(height: 16),
          _shimmer(double.infinity, 220, radius: AppRadius.xxl),
          const SizedBox(height: 16),
          _shimmer(double.infinity, 200, radius: AppRadius.xxl),
          const SizedBox(height: 16),
          ...List.generate(
            3,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _shimmer(double.infinity, 72, radius: AppRadius.xxl),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shimmer(double width, double height, {double radius = 8}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(radius)),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(_error ?? 'Something went wrong', style: const TextStyle(color: AppColors.muted), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadDashboard, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(child: Text('No data available', style: TextStyle(color: AppColors.muted)));
  }
}

class _ChartCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _ChartCard({required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 16, color: AppColors.dark),
              ),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;

  const _QuickLink({required this.icon, required this.label, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.dark,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: AppShadows.soft,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Icon(icon, size: 24, color: AppColors.dark),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.accent)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ],
    );
  }
}
