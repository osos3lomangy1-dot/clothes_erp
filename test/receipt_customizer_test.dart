import 'dart:typed_data';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/invoice_item_details_entity.dart';
import 'package:clothes_erp/features/invoices/domain/entities/receipt_config.dart';
import 'package:clothes_erp/features/invoices/presentation/services/receipt_pdf_service.dart';
import 'package:clothes_erp/features/invoices/presentation/widgets/thermal_receipt_live_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReceiptConfig Entity Tests', () {
    test('Default values are initialized properly', () {
      const def = ReceiptConfig.defaults;
      expect(def.storeName, 'بيعة');
      expect(def.paperWidthMm, 80);
      expect(def.showCashierName, true);
      expect(def.showCustomerInfo, true);
      expect(def.showPaymentMethod, true);
      expect(def.showBarcode, true);
      expect(def.showItemDetails, true);
      expect(def.returnPolicy.contains('14 يوماً'), true);
      expect(def.footerGreeting.contains('شكراً لزيارتكم'), true);
    });

    test('copyWith updates specified fields only', () {
      const original = ReceiptConfig.defaults;
      final updated = original.copyWith(
        storeName: 'بوتيك الأناقة',
        storePhone: '01122334455',
        paperWidthMm: 58,
        showBarcode: false,
      );

      expect(updated.storeName, 'بوتيك الأناقة');
      expect(updated.storePhone, '01122334455');
      expect(updated.paperWidthMm, 58);
      expect(updated.showBarcode, false);
      expect(updated.showCashierName, original.showCashierName);
      expect(updated.returnPolicy, original.returnPolicy);
    });
  });

  group('ReceiptPdfService & Formatting Tests', () {
    final sampleInvoice = InvoiceDetailsEntity(
      id: 'inv-test-1',
      shortRef: 'INV-1001',
      date: DateTime(2026, 11, 20, 16, 30),
      cashierId: 'cashier-1',
      cashierName: 'محمد أحمد',
      customerName: 'عمرو دياب',
      customerPhone: '01099887766',
      subtotal: 50000,
      discountAmount: 5000,
      total: 45000,
      paymentMethod: 'نقدي (كاش)',
      items: const [
        InvoiceItemDetailsEntity(
          id: 'item-1',
          variantId: 'var-1',
          productName: 'تيشيرت بولو سادة',
          color: 'أبيض',
          size: 'XL',
          qty: 2,
          price: 25000,
          lineTotal: 50000,
        ),
      ],
    );

    test('generateReceiptPdf produces valid non-empty 80mm PDF byte array', () async {
      final config = ReceiptConfig.defaults.copyWith(
        storeName: 'محل الفخامة',
        storeAddress: 'شارع الهرم - الجيزة',
        storePhone: '01234567890',
        paperWidthMm: 80,
      );

      final pdfBytes = await ReceiptPdfService.generateReceiptPdf(
        sampleInvoice,
        config: config,
      );

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.isNotEmpty, true);
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('generateReceiptPdf produces valid 58mm PDF format without error', () async {
      final config = ReceiptConfig.defaults.copyWith(
        storeName: 'سوبر ماركت السلام',
        paperWidthMm: 58,
        showBarcode: false,
        showCashierName: false,
      );

      final pdfBytes = await ReceiptPdfService.generateReceiptPdf(
        sampleInvoice,
        config: config,
      );

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.isNotEmpty, true);
      expect(pdfBytes.length, greaterThan(1000));
    });
  });

  group('ThermalReceiptLivePreview UI Tests', () {
    testWidgets('Live preview renders store header, policy, and items cleanly', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const config = ReceiptConfig(
        storeName: 'رويال فاشون',
        storeActivity: 'أرقى الموديلات الرجالي والحريمي',
        storePhone: '01011223344',
        storeAddress: 'وسط البلد - القاهرة',
        paperWidthMm: 80,
        returnPolicy: 'الاسترجاع خلال 7 أيام فقط بالفاتورة',
        footerGreeting: 'أهلاً بكم دائماً',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: Center(
                  child: ThermalReceiptLivePreview(config: config),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('رويال فاشون'), findsOneWidget);
      expect(find.text('أرقى الموديلات الرجالي والحريمي'), findsOneWidget);
      expect(find.text('هاتف: 01011223344'), findsOneWidget);
      expect(find.text('وسط البلد - القاهرة'), findsOneWidget);
      expect(find.text('الاسترجاع خلال 7 أيام فقط بالفاتورة'), findsOneWidget);
      expect(find.text('أهلاً بكم دائماً'), findsOneWidget);
      expect(find.text('قميص كاجوال رجالي (كحلي - L)'), findsOneWidget);
    });
  });
}
