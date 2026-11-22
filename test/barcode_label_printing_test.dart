import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/features/barcode_printing/domain/models/barcode_label_item.dart';
import 'package:clothes_erp/features/barcode_printing/services/barcode_label_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BarcodeLabelItem & BarcodeLabelSize', () {
    test('BarcodeLabelItem equality and copyWith', () {
      const item1 = BarcodeLabelItem(
        variantId: 'var-1',
        productName: 'قميص رجالي كلاسيك',
        sku: '123456789012',
        color: 'أزرق',
        size: 'L',
        salePricePiasters: 35000,
        copies: 2,
      );

      final item2 = item1.copyWith(copies: 5);
      expect(item2.copies, 5);
      expect(item2.productName, 'قميص رجالي كلاسيك');
      expect(item1.copies, 2);
      expect(item1.props, contains('var-1'));
    });

    test('BarcodeLabelSize dimensions check', () {
      expect(BarcodeLabelSize.roll50x30.widthMm, 50);
      expect(BarcodeLabelSize.roll50x30.heightMm, 30);
      expect(BarcodeLabelSize.roll38x25.widthMm, 38);
      expect(BarcodeLabelSize.roll38x25.heightMm, 25);
      expect(BarcodeLabelSize.sheetA4.widthMm, 210);
      expect(BarcodeLabelSize.sheetA4.heightMm, 297);
    });
  });

  group('BarcodeLabelService PDF Generation', () {
    test('generatePdf with empty list generates fallback valid PDF', () async {
      final pdfBytes = await BarcodeLabelService.generatePdf(
        items: [],
        size: BarcodeLabelSize.roll50x30,
      );

      expect(pdfBytes, isNotEmpty);
      // PDF header check
      final header = String.fromCharCodes(pdfBytes.take(5));
      expect(header, '%PDF-');
    });

    test('generatePdf generates single-page rolls per copy', () async {
      final items = [
        const BarcodeLabelItem(
          variantId: 'var-1',
          productName: 'تيشرت بولو',
          sku: '1000101',
          color: 'أبيض',
          size: 'XL',
          salePricePiasters: 25000,
          copies: 2,
        ),
        const BarcodeLabelItem(
          variantId: 'var-2',
          productName: 'بنطلون جينز',
          sku: '1000102',
          color: 'كحلي',
          size: '34',
          salePricePiasters: 40000,
          copies: 1,
        ),
      ];

      final pdfBytes = await BarcodeLabelService.generatePdf(
        items: items,
        size: BarcodeLabelSize.roll50x30,
        storeName: 'بيعة فاشون',
        showStoreName: true,
        showPrice: true,
        showColorAndSize: true,
      );

      expect(pdfBytes, isA<Uint8List>());
      expect(pdfBytes.length, greaterThan(100));
      final header = String.fromCharCodes(pdfBytes.take(5));
      expect(header, '%PDF-');
    });

    test('generatePdf generates A4 sheet layout', () async {
      final items = [
        const BarcodeLabelItem(
          variantId: 'var-1',
          productName: 'فستان صيفي',
          sku: '2000201',
          color: 'زهري',
          size: 'M',
          salePricePiasters: 55000,
          copies: 6,
        ),
      ];

      final pdfBytes = await BarcodeLabelService.generatePdf(
        items: items,
        size: BarcodeLabelSize.sheetA4,
        storeName: 'بوتيك راقي',
        showStoreName: true,
        showPrice: true,
        showColorAndSize: true,
      );

      expect(pdfBytes, isNotEmpty);
      final header = String.fromCharCodes(pdfBytes.take(5));
      expect(header, '%PDF-');
    });
  });
}

