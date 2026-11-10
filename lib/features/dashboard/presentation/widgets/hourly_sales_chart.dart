import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/sales_chart_point_entity.dart';

class HourlySalesChart extends StatelessWidget {
  final List<HourlySalesPointEntity> hourlyPoints;

  const HourlySalesChart({super.key, required this.hourlyPoints});

  bool get _hasSales => hourlyPoints.any((p) => p.totalAmount > 0);

  @override
  Widget build(BuildContext context) {
    // Show hours from 9 AM (9) to 11 PM (23) by default, or include any hour with sales
    final relevantHours = hourlyPoints.where((p) {
      if (p.totalAmount > 0) return true;
      return p.hour >= 9 && p.hour <= 23;
    }).toList();

    // Find peak hour
    int maxAmount = 0;
    int? peakHour;
    for (final p in relevantHours) {
      if (p.totalAmount > maxAmount) {
        maxAmount = p.totalAmount;
        peakHour = p.hour;
      }
    }

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
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.access_time_filled_rounded, color: Colors.blue.shade700, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'توزيع مبيعات اليوم بالساعات',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text(
                        peakHour != null
                            ? 'ساعة الذروة: ${_formatHour(peakHour)} (${Money(maxAmount).toDisplay()} ج.م)'
                            : 'توزيع حركة البيع خلال ساعات اليوم',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (!_hasSales)
              Container(
                height: 220,
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
                      Icon(Icons.schedule_rounded, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 10),
                      Text(
                        'لم يتم تسجيل فواتير بيع اليوم حتى الآن',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ستظهر ساعات الذروة وتوزيع المبيعات فور إجراء عمليات بيع',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 220,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxAmount == 0 ? 100 : (maxAmount / 100.0) * 1.25,
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          if (groupIndex < 0 || groupIndex >= relevantHours.length) return null;
                          final p = relevantHours[groupIndex];
                          return BarTooltipItem(
                            '${p.hourLabel}\n${Money(p.totalAmount).toDisplay()} ج.م\n${p.transactionsCount} فواتير',
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
                          reservedSize: 40,
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
                          reservedSize: 30,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= relevantHours.length) return const SizedBox.shrink();
                            // Show label every 2 hours or on active hours to avoid crowding
                            if (relevantHours.length > 8 && idx % 2 != 0) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(
                                relevantHours[idx].hourLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
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
                    barGroups: List.generate(relevantHours.length, (idx) {
                      final p = relevantHours[idx];
                      final isPeak = p.hour == peakHour && p.totalAmount > 0;
                      final pounds = p.totalAmount / 100.0;

                      return BarChartGroupData(
                        x: idx,
                        barRods: [
                          BarChartRodData(
                            toY: pounds,
                            color: isPeak ? AppColors.primary : AppColors.primary.withValues(alpha: 0.45),
                            width: 14,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
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

  String _formatHour(int h) {
    if (h == 0) return '12 منتصف الليل';
    if (h < 12) return '$h صباحاً';
    if (h == 12) return '12 ظهراً';
    return '${h - 12} مساءً';
  }
}

