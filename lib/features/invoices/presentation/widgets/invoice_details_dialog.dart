import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../customers/data/services/customer_ledger_service.dart';
import '../../../returns/presentation/screens/return_screen.dart';
import '../../domain/entities/invoice_details_entity.dart';
import '../services/receipt_pdf_service.dart';

class InvoiceDetailsDialog extends StatelessWidget {
  final InvoiceDetailsEntity invoice;
  final void Function(String invoiceRef)? onRequestReturn;

  const InvoiceDetailsDialog({
    super.key,
    required this.invoice,
    this.onRequestReturn,
  });

  String _formatPaymentLabel(String method) {
    switch (method.toLowerCase().trim()) {
      case 'cash':
        return 'نقدي';
      case 'card':
      case 'visa':
        return 'بطاقة / فيزا';
      case 'split':
      case 'mixed':
        return 'مجزأ';
      case 'installment':
        return 'تقسيط';
      case 'credit':
        return 'آجل على الحساب';
      default:
        return method;
    }
  }

  void _sendWhatsApp(BuildContext context) async {
    final phone = invoice.customerPhone;
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد رقم هاتف مسجل لهذا العميل لإرسال الفاتورة عبر واتساب'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    final itemsSummary = invoice.items
        .map((i) =>
            '• ${i.productName} (${i.color}/${i.size}) × ${i.qty} = ${Money(i.lineTotal).toDisplay()} ج.م')
        .join('\n');

    final message = 'مرحباً ${invoice.customerName ?? 'عزيزنا العميل'}،\n'
        'شكراً لتسوقكم من متجرنا!\n'
        'إليك تفاصيل فاتورة الشراء #${invoice.shortRef}:\n'
        'التاريخ: ${dateFormat.format(invoice.date)}\n'
        'الأصناف (${invoice.totalItemsCount} قطعة):\n$itemsSummary\n'
        'الإجمالي: ${Money(invoice.total).toDisplay()} ج.م\n'
        'طريقة الدفع: ${_formatPaymentLabel(invoice.paymentMethod)}\n\n'
        'نسعد دائماً بخدمتكم!';

    final uri = CustomerLedgerService.buildWhatsAppUri(phone);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رقم هاتف العميل غير صالح لإرسال واتساب'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final chatUri =
        Uri.parse('${uri.toString()}?text=${Uri.encodeComponent(message)}');
    try {
      await launchUrl(chatUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح تطبيق واتساب على هذا الجهاز'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _startReturn(BuildContext context) {
    if (invoice.status == 'returned') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إرجاع جميع أصناف هذه الفاتورة بالكامل مسبقاً'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).pop();
    if (onRequestReturn != null) {
      onRequestReturn!(invoice.shortRef);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReturnScreen(initialInvoiceRef: invoice.shortRef),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Exact date format with seconds as specified in blueprint
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm:ss a');

    // Manager / Admin permission check
    final authState = context.watch<AuthCubit>().state;
    final isManager = authState is! AuthAuthenticated ||
        authState.user.role == 'admin' ||
        authState.user.role == 'manager';

    Color statusBorderColor;
    Color statusTextColor;
    String statusLabel;

    if (invoice.status == 'returned') {
      statusBorderColor = AppColors.error.withValues(alpha: 0.3);
      statusTextColor = AppColors.error;
      statusLabel = 'مرتجعة بالكامل';
    } else if (invoice.status == 'partially_returned') {
      statusBorderColor = AppColors.warning.withValues(alpha: 0.3);
      statusTextColor = AppColors.warning;
      statusLabel = 'مرتجع جزئي';
    } else {
      statusBorderColor = AppColors.success.withValues(alpha: 0.3);
      statusTextColor = AppColors.success;
      statusLabel = 'مكتملة';
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 820),
        child: Padding(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
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
                        Row(
                          children: [
                            Text(
                              'تفاصيل فاتورة البيع #${invoice.shortRef}',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: statusBorderColor),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: statusTextColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dateFormat.format(invoice.date),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Metadata Info Card (Inspection Hub)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _infoCol(
                            label: 'رقم الفاتورة والباركود',
                            value: '#${invoice.shortRef}',
                            icon: Icons.qr_code_2_rounded,
                          ),
                        ),
                        Expanded(
                          child: _infoCol(
                            label: 'الكاشير',
                            value: invoice.cashierName.isNotEmpty
                                ? invoice.cashierName
                                : invoice.cashierId,
                            icon: Icons.badge_outlined,
                          ),
                        ),
                        Expanded(
                          child: _infoCol(
                            label: 'تاريخ ووقت البيع',
                            value: dateFormat.format(invoice.date),
                            icon: Icons.access_time_rounded,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    Row(
                      children: [
                        Expanded(
                          child: _infoCol(
                            label: 'العميل',
                            value: invoice.customerName ?? 'عميل نقدي',
                            subtitle: invoice.customerPhone != null &&
                                    invoice.customerPhone!.isNotEmpty
                                ? invoice.customerPhone
                                : null,
                            icon: Icons.person_outline_rounded,
                          ),
                        ),
                        Expanded(
                          child: _infoCol(
                            label: 'الفرع والوردية',
                            value: invoice.shiftId != null
                                ? 'وردية #${invoice.shiftId}'
                                : 'الوردية الحالية',
                            icon: Icons.storefront_outlined,
                          ),
                        ),
                        Expanded(
                          child: _infoCol(
                            label: 'طريقة الدفع',
                            value: _formatPaymentLabel(invoice.paymentMethod),
                            icon: Icons.payments_outlined,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Items Breakdown Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'الأصناف المباعة (${invoice.totalItemsCount} قطعة):',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  if (isManager && invoice.totalProfitPiasters > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        'إجمالي الربح: +${Money(invoice.totalProfitPiasters).toDisplay()} ج.م (${invoice.totalProfitMarginPercent.toStringAsFixed(1)}%)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Items Breakdown Table
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: ListView.separated(
                    itemCount: invoice.items.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, idx) {
                      final item = invoice.items[idx];
                      final hasDiscount =
                          item.lineDiscount > 0 || item.promotionDiscount > 0;
                      final totalDiscount =
                          item.lineDiscount + item.promotionDiscount;

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.08),
                              child: Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Item Details
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: AppColors.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'اللون: ${item.color} | المقاس: ${item.size}',
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Qty & Price Snapshot
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item.qty} × ${Money(item.price).toDisplay()} ج.م',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                  if (hasDiscount)
                                    Text(
                                      '- ${Money(totalDiscount).toDisplay()} ج.م خصم',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.success,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Profit Margin (Visible only for Manager/Admin)
                            if (isManager)
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: item.profitPiasters >= 0
                                            ? const Color(0xFFECFDF5)
                                            : const Color(0xFFFEF2F2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: item.profitPiasters >= 0
                                              ? AppColors.success
                                                  .withValues(alpha: 0.3)
                                              : AppColors.error
                                                  .withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Text(
                                        'ربح: ${item.profitPiasters >= 0 ? '+' : ''}${Money(item.profitPiasters).toDisplay()} (${item.profitMarginPercent.toStringAsFixed(0)}%)',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: item.profitPiasters >= 0
                                              ? AppColors.success
                                              : AppColors.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            // Line Total
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${Money(item.lineTotal).toDisplay()} ج.م',
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13.5,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Summary Box (Subtotal, Discount, Net Total, Profit)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'المجموع الفرعي: ${Money(invoice.subtotal).toDisplay()} ج.م'
                          '${invoice.discountAmount > 0 ? '  |  الخصم: -${Money(invoice.discountAmount).toDisplay()} ج.م' : ''}',
                          style: const TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'الإجمالي النهائي: ${Money(invoice.total).toDisplay()} ج.م',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    if (isManager && invoice.totalProfitPiasters != 0) ...[
                      const Divider(height: 12, color: Color(0xFFE2E8F0)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.auto_graph_rounded,
                                size: 14,
                                color: AppColors.success,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'صافي هامش الربح التجاري للمحل:',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '+${Money(invoice.totalProfitPiasters).toDisplay()} ج.م (نسبة الربح ${invoice.totalProfitMarginPercent.toStringAsFixed(1)}%)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Action Buttons (Action Footer: 4 Strategic Buttons)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Button 4: Direct Return from Invoice
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onPressed: () => _startReturn(context),
                    icon: const Icon(Icons.assignment_return_rounded, size: 16),
                    label: const Text(
                      'إجراء مرتجع من الفاتورة',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                  ),

                  // Button 3: WhatsApp Share
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF25D366),
                      side: const BorderSide(color: Color(0xFF25D366)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onPressed: () => _sendWhatsApp(context),
                    icon: const Icon(Icons.chat_rounded, size: 16),
                    label: const Text(
                      'إرسال واتساب',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                  ),

                  // Button 2: Export PDF
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      side: const BorderSide(color: AppColors.outlineVariant),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final path =
                          await ReceiptPdfService.saveReceiptAsPdf(invoice);
                      if (path != null) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('تم تنزيل الفاتورة كملف PDF:\n$path'),
                            backgroundColor: AppColors.success,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    icon: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Color(0xFFEF4444),
                      size: 16,
                    ),
                    label: const Text(
                      'تحميل A4 / PDF',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                  ),

                  // Button 1: Print Thermal Receipt
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onPressed: () => ReceiptPdfService.printReceipt(invoice),
                    icon: const Icon(Icons.print_rounded, size: 16),
                    label: const Text(
                      'طباعة إيصال حراري',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCol({
    required String label,
    required String value,
    String? subtitle,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF94A3B8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
