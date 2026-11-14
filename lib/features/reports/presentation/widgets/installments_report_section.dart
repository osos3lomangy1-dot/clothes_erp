import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../cubits/installments_report_cubit.dart';

class InstallmentsReportSection extends StatelessWidget {
  const InstallmentsReportSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<InstallmentsReportCubit>()..load(now: DateTime.now()),
      child: const _InstallmentsReportView(),
    );
  }
}

class _InstallmentsReportView extends StatelessWidget {
  const _InstallmentsReportView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InstallmentsReportCubit, InstallmentsReportState>(
      builder: (context, state) {
        if (state.status == InstallmentsReportStatus.loading) {
          return const Card(
            margin: EdgeInsets.all(16),
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (state.status == InstallmentsReportStatus.error) {
          return Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('خطأ: ${state.errorMessage ?? "حدث خطأ"}'),
            ),
          );
        }
        final summary = state.summary;
        if (summary == null) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.payments_rounded, color: Color(0xFF6A1B9A)),
                    SizedBox(width: 8),
                    Text(
                      'التقسيط',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricCard(
                      title: 'إجمالي المتبقي',
                      value: Money(summary.totalOutstanding).toDisplay(),
                      icon: Icons.account_balance_wallet_rounded,
                      color: const Color(0xFF1976D2),
                    ),
                    _MetricCard(
                      title: 'المحصل هذا الشهر',
                      value: Money(summary.monthlyCollected).toDisplay(),
                      icon: Icons.trending_up_rounded,
                      color: const Color(0xFF388E3C),
                    ),
                    _MetricCard(
                      title: 'إجمالي المتأخرات',
                      value: Money(summary.overdueTotal).toDisplay(),
                      icon: Icons.warning_amber_rounded,
                      color: const Color(0xFFF57C00),
                    ),
                    _MetricCard(
                      title: 'عدد العقود المتأخرة',
                      value: '${summary.overdueCount}',
                      icon: Icons.receipt_long_rounded,
                      color: const Color(0xFFD32F2F),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (state.monthlyTrend.isNotEmpty) ...[
                  const Text(
                    'التحصيل خلال 6 أشهر',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: _maxY(state.monthlyTrend),
                        barGroups: state.monthlyTrend.asMap().entries.map((e) {
                          final point = e.value;
                          return BarChartGroupData(
                            x: e.key,
                            barRods: [
                              BarChartRodData(
                                toY: point.collected / 100.0,
                                color: const Color(0xFF6A1B9A),
                                width: 20,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx < 0 || idx >= state.monthlyTrend.length) {
                                  return const SizedBox.shrink();
                                }
                                final m = state.monthlyTrend[idx].month;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '${m.month}/${m.year % 100}',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  double _maxY(List<MonthlyTrendPoint> trend) {
    final maxVal = trend
        .map((p) => p.collected / 100.0)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return maxVal == 0 ? 100 : maxVal * 1.2;
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
