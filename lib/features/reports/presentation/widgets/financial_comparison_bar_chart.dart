import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';

class FinancialComparisonBarChart extends StatelessWidget {
  final int totalRevenue;
  final int totalCost;
  final int totalExpenses;
  final int netProfit;

  const FinancialComparisonBarChart({
    super.key,
    required this.totalRevenue,
    required this.totalCost,
    required this.totalExpenses,
    required this.netProfit,
  });

  bool get _hasData =>
      totalRevenue > 0 || totalCost > 0 || totalExpenses > 0 || netProfit != 0;

  @override
  Widget build(BuildContext context) {
    final bars = [
      (
        label: 'المبيعات',
        amount: totalRevenue,
        color: Colors.green.shade700,
        icon: Icons.monetization_on_rounded,
      ),
      (
        label: 'تكلفة البضاعة',
        amount: totalCost,
        color: Colors.orange.shade800,
        icon: Icons.shopping_bag_outlined,
      ),
      (
        label: 'المصروفات',
        amount: totalExpenses,
        color: AppColors.error,
        icon: Icons.outbox_rounded,
      ),
      (
        label: 'صافي الربح',
        amount: netProfit,
        color: netProfit >= 0 ? AppColors.primary : AppColors.error,
        icon: Icons.trending_up_rounded,
      ),
    ];

    double maxVal = 0;
    for (final b in bars) {
      final p = (b.amount / 100.0).abs();
      if (p > maxVal) maxVal = p;
    }
    final maxY = maxVal == 0 ? 100.0 : maxVal * 1.25;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.bar_chart_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Text(
                  'المقارنة المالية (إيرادات / تكاليف / مصروفات / أرباح)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (!_hasData)
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.analytics_outlined, size: 36, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text(
                        'لا توجد بيانات مالية مسجلة بالفترة المحددة',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxY,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          if (groupIndex < 0 || groupIndex >= bars.length) return null;
                          final b = bars[groupIndex];
                          return BarTooltipItem(
                            '${b.label}\n${Money(b.amount).toDisplay()} ج.م',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 45,
                          getTitlesWidget: (value, meta) {
                            if (value == 0 || value == meta.max) return const SizedBox.shrink();
                            final pounds = value.toInt();
                            String label;
                            if (pounds >= 1000) {
                              label = '${(pounds / 1000).toStringAsFixed(1)}k';
                            } else {
                              label = '$pounds';
                            }
                            return Text(
                              label,
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= bars.length) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                bars[idx].label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: bars[idx].color,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: Colors.grey.shade200,
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: List.generate(bars.length, (idx) {
                      final b = bars[idx];
                      final pounds = (b.amount / 100.0).clamp(0.0, double.infinity);
                      return BarChartGroupData(
                        x: idx,
                        barRods: [
                          BarChartRodData(
                            toY: pounds,
                            color: b.color,
                            width: 28,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

