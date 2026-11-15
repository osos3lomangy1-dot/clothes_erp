import 'package:clothes_erp/features/invoices/domain/entities/invoice_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_item_details_entity.dart';
import 'package:clothes_erp/features/invoices/presentation/services/receipt_pdf_service.dart';
import 'package:clothes_erp/features/invoices/presentation/widgets/sale_success_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 16, 12, 0);

  final invoiceWithPromo = InvoiceDetailsEntity(
    id: 'inv-promo',
    shortRef: 'PROMO01',
    date: now,
    cashierId: 'user-1',
    cashierName: 'أحمد',
    subtotal: 20000, // 200.00 EGP
    discountAmount: 0,
    total: 15000, // 150.00 EGP
    paymentMethod: 'cash',
    items: const [
      InvoiceItemDetailsEntity(
        id: 'item-1',
        variantId: 'v-1',
        productName: 'تيشيرت بولو',
        color: 'كحلي',
        size: 'XL',
        qty: 1,
        price: 20000,
        lineDiscount: 5000,
        promotionDiscount: 5000,
        lineTotal: 15000,
      ),
    ],
  );

  final invoiceWithoutPromo = InvoiceDetailsEntity(
    id: 'inv-regular',
    shortRef: 'REG01',
    date: now,
    cashierId: 'user-1',
    cashierName: 'أحمد',
    subtotal: 20000,
    discountAmount: 0,
    total: 20000,
    paymentMethod: 'cash',
    items: const [
      InvoiceItemDetailsEntity(
        id: 'item-1',
        variantId: 'v-1',
        productName: 'تيشيرت بولو',
        color: 'كحلي',
        size: 'XL',
        qty: 1,
        price: 20000,
        lineDiscount: 0,
        promotionDiscount: 0,
        lineTotal: 20000,
      ),
    ],
  );

  test('PDF receipt generates bytes successfully when promotion discount > 0', () async {
    final bytes = await ReceiptPdfService.generateReceiptPdf(invoiceWithPromo);
    expect(bytes, isNotEmpty);
    expect(invoiceWithPromo.totalPromotionDiscount, 5000);
  });

  test('PDF receipt generates bytes successfully when promotion discount == 0', () async {
    final bytes = await ReceiptPdfService.generateReceiptPdf(invoiceWithoutPromo);
    expect(bytes, isNotEmpty);
    expect(invoiceWithoutPromo.totalPromotionDiscount, 0);
  });

  testWidgets('SaleSuccessDialog renders breakdown widget tree when totalPromotionDiscount > 0',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: SaleSuccessDialog(invoice: invoiceWithPromo),
          ),
        ),
      ),
    );

    expect(find.text('المجموع الفرعي:'), findsOneWidget);
    expect(find.text('خصم العروض:'), findsOneWidget);
    expect(find.text('-50.00 ج.م'), findsOneWidget);
    expect(find.text('150.00 ج.م'), findsOneWidget);
  });

  testWidgets('SaleSuccessDialog renders only total when totalPromotionDiscount == 0 and discountAmount == 0',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: SaleSuccessDialog(invoice: invoiceWithoutPromo),
          ),
        ),
      ),
    );

    expect(find.text('المجموع الفرعي:'), findsNothing);
    expect(find.text('خصم العروض:'), findsNothing);
    expect(find.text('200.00 ج.م'), findsOneWidget);
  });
}
