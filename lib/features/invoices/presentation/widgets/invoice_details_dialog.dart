import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/invoice_details_entity.dart';
import '../services/receipt_pdf_service.dart';

class InvoiceDetailsDialog extends StatelessWidget {
  final InvoiceDetailsEntity invoice;

  const InvoiceDetailsDialog({super.key, required this.invoice});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650, maxHeight: 750),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تفاصيل فاتورة البيع #${invoice.shortRef}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          dateFormat.format(invoice.date),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Metadata info row
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _infoCol('الكاشير', invoice.cashierName.isNotEmpty ? invoice.cashierName : invoice.cashierId),
                    _infoCol('العميل', invoice.customerName ?? 'عميل نقدي'),
                    _infoCol('طريقة الدفع', invoice.paymentMethod),
                    _infoCol('إجمالي القطع', '${invoice.totalItemsCount} قطعة'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'الأصناف المشتراة:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              // Items Table
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: ListView.separated(
                    itemCount: invoice.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final item = invoice.items[idx];
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${item.productName} (${item.color} - مقاس ${item.size})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${item.qty} × ${Money(item.price).toDisplay()} ج.م',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        ),
                        trailing: Text(
                          '${Money(item.lineTotal).toDisplay()} ج.م',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Totals
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'المجموع: ${Money(invoice.subtotal).toDisplay()} ج.م'
                      '${invoice.discountAmount > 0 ? '  |  الخصم: -${Money(invoice.discountAmount).toDisplay()} ج.م' : ''}',
                      style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
                    ),
                    Text(
                      'الإجمالي الصافي: ${Money(invoice.total).toDisplay()} ج.م',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      side: BorderSide(color: Colors.grey.shade400),
                    ),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final path = await ReceiptPdfService.saveReceiptAsPdf(invoice);
                      if (path != null) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('تم تنزيل الفاتورة كملف PDF:\n$path'),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 18),
                    label: const Text('تنزيل كملف PDF'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: () async {
                      await ReceiptPdfService.printReceipt(invoice);
                    },
                    icon: const Icon(Icons.print_rounded, color: Colors.white, size: 18),
                    label: const Text(
                      'طباعة الفاتورة',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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

  Widget _infoCol(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

