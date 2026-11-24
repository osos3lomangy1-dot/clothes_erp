import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';

class PaymentMethodPieChart extends StatefulWidget {
  final Map<String, int> breakdown;

  const PaymentMethodPieChart({super.key, required this.breakdown});

  @override
  State<PaymentMethodPieChart> createState() => _PaymentMethodPieChartState();
}

class _PaymentMethodPieChartState extends State<PaymentMethodPieChart> {
  int _touchedIndex = -1;

  Color _getColorForMethod(String method, int index) {
    final lower = method.toLowerCase();
    if (lower.contains('cash') || lower.contains('نقدي') || lower.contains('كاش')) {
      return Colors.green.shade600;
    }
    if (lower.contains('card') || lower.contains('visa') || lower.contains('فيزا') || lower.contains('بطاقة')) {
      return AppColors.primary;
    }
    if (lower.contains('insta') || lower.contains('انستا') || lower.contains('محفظة') || lower.contains('فودافون')) {
      return Colors.teal.shade600;
    }
    final palette = [
      Colors.indigo.shade600,
      Colors.amber.shade700,
      Colors.purple.shade600,
      Colors.cyan.shade700,
    ];
    return palette[index % palette.length];
  }

  String _formatName(String method) {
    final lower = method.toLowerCase();
    if (lower == 'cash' || lower == 'نقدي') return 'كاش (نقدي)';
    if (lower == 'card' || lower == 'visa' || lower == 'فيزا') return 'بطاقة / فيزا';
    if (lower.contains('insta') || lower.contains('انستاباي')) return 'انستاباي (InstaPay)';
    if (lower.contains('فودافون') || lower.contains('محفظة')) return 'محفظة إلكترونية';
    return method;
  }

  @override
  Widget build(BuildContext context) {
    final validEntries = widget.breakdown.entries.where((e) => e.value > 0).toList();
    final total = validEntries.fold<int>(0, (sum, e) => sum + e.value);

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
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.pie_chart_rounded, color: Colors.green.shade700, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'توزيع طرق الدفع',
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
                height: 180,
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
                      Icon(Icons.payments_outlined, size: 36, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text(
                        'لا توجد عمليات دفع مسجلة بالفترة المحددة',
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 620;
                  final chartWidget = SizedBox(
                    width: isCompact ? 140 : 160,
                    height: isCompact ? 140 : 160,
                    child: PieChart(
                      PieChartData(
                        pieTouchData: PieTouchData(
                          touchCallback: (event, pieTouchResponse) {
                            setState(() {
                              if (!event.isInterestedForInteractions ||
                                  pieTouchResponse == null ||
                                  pieTouchResponse.touchedSection == null) {
                                _touchedIndex = -1;
                                return;
                              }
                              _touchedIndex =
                                  pieTouchResponse.touchedSection!.touchedSectionIndex;
                            });
                          },
                        ),
                        borderData: FlBorderData(show: false),
                        sectionsSpace: 3,
                        centerSpaceRadius: isCompact ? 30 : 36,
                        sections: List.generate(validEntries.length, (i) {
                          final isTouched = i == _touchedIndex;
                          final e = validEntries[i];
                          final percent = (e.value / total) * 100.0;
                          final radius = isTouched ? (isCompact ? 36.0 : 42.0) : (isCompact ? 30.0 : 36.0);
                          final color = _getColorForMethod(e.key, i);

                          return PieChartSectionData(
                            color: color,
                            value: e.value.toDouble(),
                            title: percent >= 8 ? '${percent.toStringAsFixed(0)}%' : '',
                            radius: radius,
                            titleStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        }),
                      ),
                    ),
                  );

                  final legendList = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(validEntries.length, (i) {
                      final e = validEntries[i];
                      final color = _getColorForMethod(e.key, i);
                      final percent = (e.value / total) * 100.0;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _formatName(e.key),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              fit: FlexFit.loose,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${percent.toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '(${Money(e.value).toDisplay()} ج.م)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  );

                  if (isCompact) {
                    return Column(
                      children: [
                        Center(child: chartWidget),
                        const SizedBox(height: 16),
                        legendList,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      chartWidget,
                      const SizedBox(width: 16),
                      Expanded(child: legendList),
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

