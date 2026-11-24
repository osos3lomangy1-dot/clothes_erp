import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../cubits/promotions_report_cubit.dart';

class PromotionsReportSection extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;

  const PromotionsReportSection({
    super.key,
    this.startDate,
    this.endDate,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<PromotionsReportCubit>()
        ..load(startDate: startDate, endDate: endDate),
      child: _PromotionsReportView(
        startDate: startDate,
        endDate: endDate,
      ),
    );
  }
}

class _PromotionsReportView extends StatefulWidget {
  final DateTime? startDate;
  final DateTime? endDate;

  const _PromotionsReportView({
    this.startDate,
    this.endDate,
  });

  @override
  State<_PromotionsReportView> createState() => _PromotionsReportViewState();
}

class _PromotionsReportViewState extends State<_PromotionsReportView> {
  @override
  void didUpdateWidget(covariant _PromotionsReportView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate ||
        oldWidget.endDate != widget.endDate) {
      context.read<PromotionsReportCubit>().load(
            startDate: widget.startDate,
            endDate: widget.endDate,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PromotionsReportCubit, PromotionsReportState>(
      builder: (context, state) {
        if (state.status == PromotionsReportStatus.loading) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (state.status == PromotionsReportStatus.error) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'خطأ في تحميل تقرير العروض: ${state.errorMessage ?? "حدث خطأ"}',
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          );
        }

        final report = state.report;
        if (report == null) return const SizedBox.shrink();

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.local_offer_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'تقرير العروض والخصومات الترويجية',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        title: 'إجمالي خصومات العروض',
                        value: '${Money(report.totalDiscountPiasters).toDisplay()} ج.م',
                        color: AppColors.primary,
                        icon: Icons.savings_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        title: 'فواتير استفادت من العروض',
                        value: '${report.totalSalesWithPromotions}',
                        color: AppColors.secondary,
                        icon: Icons.receipt_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        title: 'مرات تطبيق العروض',
                        value: '${report.totalApplications}',
                        color: AppColors.success,
                        icon: Icons.check_circle_outline_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (report.topPromotions.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    alignment: Alignment.center,
                    child: Text(
                      'لا توجد خصومات ترويجية مطبقة في هذه الفترة',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  )
                else ...[
                  const Text(
                    'أكثر العروض استخداماً في هذه الفترة',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(4),
                        1: FlexColumnWidth(2),
                        2: FlexColumnWidth(3),
                      },
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color: Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                          ),
                          children: const [
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              child: Text(
                                'اسم العرض',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                              child: Text(
                                'مرات الاستخدام',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              child: Text(
                                'إجمالي الخصم',
                                textAlign: TextAlign.end,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        ...report.topPromotions.map((p) => TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 12,
                                  ),
                                  child: Text(
                                    p.promotionName,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 8,
                                  ),
                                  child: Text(
                                    '${p.count}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 12,
                                  ),
                                  child: Text(
                                    '${Money(p.totalDiscountPiasters).toDisplay()} ج.م',
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            )),
                      ],
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
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
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
                    fontSize: 11,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
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
          ),
        ],
      ),
    );
  }
}

