import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/shift_summary_entity.dart';
import '../services/z_report_service.dart';

class ZReportDialog extends StatelessWidget {
  final ShiftSummaryEntity summary;

  const ZReportDialog({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    final shift = summary.shift;
    final counted = shift.countedBalance ?? summary.expectedCashInDrawer;
    final diff = shift.difference ?? (counted - summary.expectedCashInDrawer);

    Color diffColor;
    String diffLabel;
    IconData diffIcon;
    if (diff == 0) {
      diffColor = Colors.green.shade700;
      diffLabel = 'مطابق تماماً 100% (لا يوجد عجز أو زيادة)';
      diffIcon = Icons.check_circle_rounded;
    } else if (diff > 0) {
      diffColor = Colors.blue.shade700;
      diffLabel = 'يوجد زيادة في الدرج: +${Money(diff).toDisplay()} ج.م';
      diffIcon = Icons.arrow_upward_rounded;
    } else {
      diffColor = AppColors.error;
      diffLabel = 'يوجد عجز في الدرج: ${Money(diff).toDisplay()} ج.م';
      diffIcon = Icons.warning_rounded;
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.receipt_long_rounded,
                              color: AppColors.primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'تقرير إغلاق الوردية (Z-Report)',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                Text(
                                  'وردية #${shift.id.length > 8 ? shift.id.substring(0, 8) : shift.id} • الكاشير: ${shift.cashierName.isNotEmpty ? shift.cashierName : shift.cashierId}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Timing Info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _infoText(
                          'وقت الفتح:',
                          dateFormat.format(shift.openedAt),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _infoText(
                          'وقت الإغلاق:',
                          dateFormat.format(shift.closedAt ?? DateTime.now()),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Sales Metric Grid
                const Text(
                  'مبيعات الوردية:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _metricCard(
                        'مبيعات كاش',
                        '${Money(summary.cashSales).toDisplay()} ج.م',
                        Icons.money_rounded,
                        Colors.green.shade700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricCard(
                        'مبيعات فيزا',
                        '${Money(summary.cardSales).toDisplay()} ج.م',
                        Icons.credit_card_rounded,
                        Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricCard(
                        'إجمالي المبيعات',
                        '${Money(summary.totalRevenue).toDisplay()} ج.م',
                        Icons.payments_rounded,
                        AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Cash Reconciliation Details
                const Text(
                  'مطابقة حركة الدرج (الكاش):',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      _rowDetail(
                        'الرصيد الافتتاحي (الفكة):',
                        '${Money(shift.openingBalance).toDisplay()} ج.م',
                      ),
                      const Divider(height: 12),
                      _rowDetail(
                        'المقبوضات النقدية (مبيعات + أقساط كاش):',
                        '+${Money(summary.cashSales + summary.cashInstallments).toDisplay()} ج.م',
                        color: Colors.green.shade700,
                      ),
                      if (summary.cashReturns > 0) ...[
                        const SizedBox(height: 6),
                        _rowDetail(
                          'مرتجعات نقدية للعملاء:',
                          '-${Money(summary.cashReturns).toDisplay()} ج.م',
                          color: Colors.red.shade600,
                        ),
                      ],
                      if (summary.cashExpenses > 0) ...[
                        const SizedBox(height: 6),
                        _rowDetail(
                          'مصروفات نقدية وسلف:',
                          '-${Money(summary.cashExpenses).toDisplay()} ج.م',
                          color: Colors.red.shade600,
                        ),
                      ],
                      const Divider(height: 16, thickness: 1.2),
                      _rowDetail(
                        'المبلغ المتوقع في الدرج:',
                        '${Money(summary.expectedCashInDrawer).toDisplay()} ج.م',
                        isBold: true,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 6),
                      _rowDetail(
                        'المبلغ الفعلي (المعدود):',
                        '${Money(counted).toDisplay()} ج.م',
                        isBold: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Reconciliation Result Banner
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: diffColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: diffColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(diffIcon, color: diffColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          diffLabel,
                          style: TextStyle(
                            color: diffColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    // Thermal Slip Print Button
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () =>
                            ZReportService.printThermalSlip(summary),
                        icon: const Icon(Icons.print_rounded, size: 18),
                        label: const Text(
                          'بون حراري',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // A4 PDF Export Button
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => ZReportService.printA4Report(summary),
                        icon: const Icon(
                          Icons.picture_as_pdf_rounded,
                          size: 18,
                        ),
                        label: const Text(
                          'تقرير A4',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // WhatsApp Share Button
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () =>
                            ZReportService.shareViaWhatsApp(summary),
                        icon: const Icon(Icons.chat_rounded, size: 18),
                        label: const Text(
                          'واتساب',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoText(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
              Icon(icon, size: 16, color: color),
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
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowDetail(
    String label,
    String value, {
    Color? color,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color ?? AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}
