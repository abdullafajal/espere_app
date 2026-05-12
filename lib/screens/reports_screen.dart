import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../utils/icon_mapper.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map<String, dynamic>? _reportData;
  bool _isLoading = true;
  String? _error;
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final result = await ApiService.getReports(year: _selectedYear);
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result.isSuccess) {
        _reportData = result.data;
      } else {
        _error = result.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Custom Fixed Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.maybePop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        boxShadow: AppShadows.soft,
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Financial Reports',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  const Spacer(),
                  _buildYearPicker(),
                ],
              ),
            ),

            // Content
            Expanded(
              child:
                  _isLoading
                      ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accent,
                        ),
                      )
                      : _error != null
                      ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _error!,
                              style: const TextStyle(color: AppColors.muted),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadData,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                      : RefreshIndicator(
                        onRefresh: _loadData,
                        color: AppColors.accent,
                        child: _buildContent(),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYearPicker() {
    final years = List.generate(5, (index) => DateTime.now().year - index);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.soft,
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedYear,
          items:
              years
                  .map(
                    (y) => DropdownMenuItem(
                      value: y,
                      child: Text(
                        y.toString(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  )
                  .toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedYear = val);
              _loadData();
            }
          },
          icon: const Icon(
            Icons.keyboard_arrow_down,
            size: 16,
            color: AppColors.text,
          ),
          dropdownColor: AppColors.card,
        ),
      ),
    );
  }

  Widget _buildContent() {
    final data = _reportData!;
    final symbol = data['currency_symbol'] ?? '₹';
    final formatCurrency = NumberFormat.currency(
      symbol: symbol,
      decimalDigits: 0,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Annual Stats
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Income',
                  formatCurrency.format(
                    double.tryParse(data['annual_income'].toString()) ?? 0,
                  ),
                  AppColors.income,
                  Icons.arrow_upward,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Expenses',
                  formatCurrency.format(
                    double.tryParse(data['annual_expenses'].toString()) ?? 0,
                  ),
                  AppColors.expense,
                  Icons.arrow_downward,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Net',
                  formatCurrency.format(
                    double.tryParse(data['annual_net'].toString()) ?? 0,
                  ),
                  AppColors.accent,
                  Icons.account_balance_wallet_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Bar Chart: Monthly Income vs Expense
          _ChartCard(
            icon: Icons.insert_chart_outlined,
            title: 'Income vs Expenses Trend',
            child: _buildBarChart(data),
          ),
          const SizedBox(height: 24),

          // Savings Trend Line Chart
          _ChartCard(
            icon: Icons.show_chart,
            title: 'Accumulated Savings',
            child: _buildLineChart(data),
          ),
          const SizedBox(height: 24),

          // Pie Chart: Categories
          _ChartCard(
            icon: Icons.pie_chart_outline,
            title: 'Category Breakdown',
            child: _buildPieChart(data),
          ),
          const SizedBox(height: 24),

          // Monthly Summary List
          const Text(
            'Monthly Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          _buildMonthlyList(data),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String amount,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 18, color: AppColors.dark),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(
              amount,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(Map<String, dynamic> data) {
    final labels = List<String>.from(data['bar_labels']);
    final income = List<double>.from(
      data['bar_income'].map((v) => double.tryParse(v.toString()) ?? 0.0),
    );
    final expense = List<double>.from(
      data['bar_expense'].map((v) => double.tryParse(v.toString()) ?? 0.0),
    );

    double maxVal = 100;
    for (var v in income) {
      if (v > maxVal) maxVal = v;
    }
    for (var v in expense) {
      if (v > maxVal) maxVal = v;
    }
    maxVal = (maxVal * 1.2).ceilToDouble();

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: maxVal,
          barTouchData: BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx >= 0 && idx < labels.length && idx % 2 == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        labels[idx],
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.muted,
                        ),
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
                reservedSize: 35,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const SizedBox.shrink();
                  return Text(
                    NumberFormat.compact().format(value),
                    style: const TextStyle(fontSize: 9, color: AppColors.muted),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine:
                (_) => FlLine(
                  color: Colors.black.withOpacity(0.04),
                  strokeWidth: 1,
                ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(labels.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: income[i],
                  color: AppColors.accent,
                  width: 6,
                  borderRadius: BorderRadius.circular(2),
                ),
                BarChartRodData(
                  toY: expense[i],
                  color: AppColors.dark,
                  width: 6,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildLineChart(Map<String, dynamic> data) {
    final values = List<double>.from(
      data['savings_trend'].map((v) => double.tryParse(v.toString()) ?? 0.0),
    );
    final labels = List<String>.from(data['bar_labels']);

    double minVal = 0;
    double maxVal = 100;
    for (var v in values) {
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
    }
    maxVal = (maxVal * 1.2);
    minVal = (minVal * 1.2);

    return SizedBox(
      height: 160,
      child: LineChart(
        LineChartData(
          maxY: maxVal,
          minY: minVal,
          lineTouchData: const LineTouchData(enabled: true),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine:
                (_) => FlLine(
                  color: Colors.black.withOpacity(0.04),
                  strokeWidth: 1,
                ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx >= 0 && idx < labels.length && idx % 3 == 0) {
                    return Text(
                      labels[idx],
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.muted,
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
                reservedSize: 35,
                getTitlesWidget: (value, meta) {
                  return Text(
                    NumberFormat.compact().format(value),
                    style: const TextStyle(fontSize: 9, color: AppColors.muted),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(
                values.length,
                (i) => FlSpot(i.toDouble(), values[i]),
              ),
              isCurved: true,
              color: AppColors.accent,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.accent.withOpacity(0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart(Map<String, dynamic> data) {
    final List<dynamic> topCategories = data['top_categories'] ?? [];
    
    if (topCategories.isEmpty) {
      return const Center(
        child: Text(
          'No expense data for this year',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }

    final labels = topCategories.map((c) => c['name'].toString()).toList();
    final values = topCategories.map((c) => double.tryParse(c['total'].toString()) ?? 0.0).toList();
    final colors = topCategories.map((c) => c['color'].toString()).toList();
    final icons = topCategories.map((c) => c['icon'].toString()).toList();

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: List.generate(topCategories.length, (i) {
                final colorHex = colors[i].replaceFirst('#', '');
                final color = Color(int.parse('FF$colorHex', radix: 16));
                return PieChartSectionData(
                  color: color,
                  value: values[i],
                  title: '',
                  radius: 50,
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 20),
        ...List.generate(topCategories.length, (i) {
          final colorHex = colors[i].replaceFirst('#', '');
          final color = Color(int.parse('FF$colorHex', radix: 16));
          final total = values.reduce((a, b) => a + b);
          final pct = (values[i] / total * 100).toStringAsFixed(1);
          final iconData = IconMapper.map(icons[i]);

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color, // Use category color
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(iconData, size: 16, color: AppColors.dark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    labels[i],
                    style: const TextStyle(fontSize: 13, color: AppColors.text),
                  ),
                ),
                Text(
                  '$pct%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  NumberFormat.compact().format(values[i]),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMonthlyList(Map<String, dynamic> data) {
    final summary = List<Map<String, dynamic>>.from(data['monthly_summary']);
    final symbol = data['currency_symbol'] ?? '₹';
    final formatCurrency = NumberFormat.compactCurrency(
      symbol: symbol,
      decimalDigits: 0,
    );

    return Column(
      children:
          summary.map((m) {
            final net = double.tryParse(m['net'].toString()) ?? 0.0;
            final income = double.tryParse(m['income'].toString()) ?? 0.0;
            final expense = double.tryParse(m['expense'].toString()) ?? 0.0;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.xxl),
                boxShadow: AppShadows.card,
              ),
              child: Row(
                children: [
                  // Month Badge (Transaction Icon style)
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(
                      m['month'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.dark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Stats
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monthly Summary',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Inc: ${formatCurrency.format(income)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Exp: ${formatCurrency.format(expense)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Net Amount
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        (net >= 0 ? '+' : '') + formatCurrency.format(net),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: net >= 0 ? AppColors.text : AppColors.text,
                        ),
                      ),
                      const Text(
                        'Net Balance',
                        style: TextStyle(fontSize: 10, color: AppColors.muted),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _ChartCard({
    required this.icon,
    required this.title,
    required this.child,
  });

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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, size: 18, color: AppColors.dark),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}
