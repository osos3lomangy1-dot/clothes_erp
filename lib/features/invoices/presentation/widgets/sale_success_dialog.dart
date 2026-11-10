import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/invoice_details_entity.dart';
import '../services/receipt_pdf_service.dart';

class SaleSuccessDialog extends StatelessWidget {
  final InvoiceDetailsEntity invoice;

  const SaleSuccessDialog({super.key, required this.invoice});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 54),
              ),
              const SizedBox(height: 18),
              const Text(
                'تم حفظ وإصدار الفاتورة بنجاح!',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppColors.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                'رقم الفاتورة: #${invoice.shortRef}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('المبلغ المطلوب:', style: TextStyle(fontSize: 14)),
                    Text(
                      '${Money(invoice.total).toDisplay()} ج.م',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey.shade400),
                      ),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final path = await ReceiptPdfService.saveReceiptAsPdf(invoice);
                        if (path != null) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('تم حفظ ملف PDF:\n$path'),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 20),
                      label: const Text('تنزيل PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        await ReceiptPdfService.printReceipt(invoice);
                      },
                      icon: const Icon(Icons.print_rounded, color: Colors.white, size: 20),
                      label: const Text(
                        'طباعة الفاتورة',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('فاتورة جديدة (متابعة البيع)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

