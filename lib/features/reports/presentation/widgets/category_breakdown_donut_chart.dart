import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';

class CategoryBreakdownDonutChart extends StatefulWidget {
  final Map<String, int> categoryBreakdown;

  const CategoryBreakdownDonutChart({
    super.key,
    required this.categoryBreakdown,
  });

  @override
  State<CategoryBreakdownDonutChart> createState() =>
      _CategoryBreakdownDonutChartState();
}

class _CategoryBreakdownDonutChartState
    extends State<CategoryBreakdownDonutChart> {
  int _touchedIndex = -1;

  static const List<Color> _palette = [
    Color(0xFF0A2E5C), // Royal Navy
    Color(0xFF1FB5A8), // Calm Teal
    Color(0xFF2B5B84), // Slate Navy
    Color(0xFF168A80), // Deep Teal
    Color(0xFF4F6D8A), // Cool Slate
    Color(0xFF64748B), // Neutral Slate
  ];

  @override
  Widget build(BuildContext context) {
    final entries = widget.categoryBreakdown.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

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
                    color: const Color(0xFF1FB5A8).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.donut_large_rounded,
                    color: Color(0xFF1FB5A8),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'المبيعات حسب التصنيف والأقسام',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (total == 0)
              Container(
                height: 170,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Center(
                  child: Text(
                    'لا توجد مبيعات مصنفة خلال الفترة المحددة',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 520;
                  final chart = SizedBox(
                    width: isCompact ? 150 : 170,
                    height: isCompact ? 150 : 170,
                    child: PieChart(
                      PieChartData(
                        pieTouchData: PieTouchData(
                          touchCallback: (event, response) {
                            setState(() {
                              if (!event.isInterestedForInteractions ||
                                  response == null ||
                                  response.touchedSection == null) {
                                _touchedIndex = -1;
                                return;
                              }
                              _touchedIndex = response
                                  .touchedSection!.touchedSectionIndex;
                            });
                          },
                        ),
                        borderData: FlBorderData(show: false),
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: [
                          for (int i = 0; i < entries.length; i++)
                            PieChartSectionData(
                              color: _palette[i % _palette.length],
                              value: entries[i].value.toDouble(),
                              title:
                                  '${((entries[i].value / total) * 100).toStringAsFixed(0)}%',
                              radius: i == _touchedIndex ? 46 : 38,
                              titleStyle: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );

                  final legend = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < entries.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _palette[i % _palette.length],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  entries[i].key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${Money(entries[i].value).toDisplay()} ج.م (${((entries[i].value / total) * 100).toStringAsFixed(1)}%)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );

                  if (isCompact) {
                    return Column(
                      children: [
                        Center(child: chart),
                        const SizedBox(height: 16),
                        legend,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      chart,
                      const SizedBox(width: 24),
                      Expanded(child: legend),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

