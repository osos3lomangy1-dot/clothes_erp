import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../core/utils/money.dart';
import '../domain/models/barcode_label_item.dart';

class BarcodeLabelService {
  static pw.Font? _cairoRegular;
  static pw.Font? _cairoBold;

  static Future<void> _loadFonts() async {
    if (_cairoRegular != null && _cairoBold != null) return;
    try {
      final regData = await rootBundle.load('assets/fonts/static/Cairo-Regular.ttf');
      _cairoRegular = pw.Font.ttf(regData);

      final boldData = await rootBundle.load('assets/fonts/static/Cairo-Bold.ttf');
      _cairoBold = pw.Font.ttf(boldData);
    } catch (_) {
      // Fallback to default sans
      _cairoRegular = pw.Font.helvetica();
      _cairoBold = pw.Font.helveticaBold();
    }
  }

  static Future<Uint8List> generatePdf({
    required List<BarcodeLabelItem> items,
    required BarcodeLabelSize size,
    String storeName = 'أوركيد للملابس',
    bool showStoreName = true,
    bool showPrice = true,
    bool showColorAndSize = true,
    bool showProductName = true,
    bool showBarcodeText = true,
  }) async {
    await _loadFonts();

    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: _cairoRegular,
      bold: _cairoBold,
    );

    // Expand items by copies
    final List<BarcodeLabelItem> flatLabels = [];
    for (final item in items) {
      for (int i = 0; i < item.copies; i++) {
        flatLabels.add(item);
      }
    }

    if (flatLabels.isEmpty) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.Center(child: pw.Text('لا توجد ملصقات للطباعة')),
        ),
      );
      return doc.save();
    }

    if (size == BarcodeLabelSize.sheetA4) {
      // A4 Grid Layout: 3 columns x 8 rows = 24 stickers per page
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          theme: theme,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
          build: (ctx) => [
            pw.GridView(
              crossAxisCount: 3,
              childAspectRatio: 1.8,
              crossAxisSpacing: 6 * PdfPageFormat.mm,
              mainAxisSpacing: 6 * PdfPageFormat.mm,
              children: flatLabels.map((lbl) => _buildSingleLabelContent(
                item: lbl,
                storeName: storeName,
                showStoreName: showStoreName,
                showPrice: showPrice,
                showColorAndSize: showColorAndSize,
                showProductName: showProductName,
                showBarcodeText: showBarcodeText,
                isSheet: true,
              )).toList(),
            ),
          ],
        ),
      );
    } else {
      // Single Label Roll (50x30 or 38x25)
      final format = PdfPageFormat(
        size.widthMm * PdfPageFormat.mm,
        size.heightMm * PdfPageFormat.mm,
        marginAll: 1.5 * PdfPageFormat.mm,
      );

      for (final lbl in flatLabels) {
        doc.addPage(
          pw.Page(
            pageFormat: format,
            theme: theme,
            textDirection: pw.TextDirection.rtl,
            build: (ctx) => pw.Center(
              child: _buildSingleLabelContent(
                item: lbl,
                storeName: storeName,
                showStoreName: showStoreName,
                showPrice: showPrice,
                showColorAndSize: showColorAndSize,
                showProductName: showProductName,
                showBarcodeText: showBarcodeText,
                isSheet: false,
              ),
            ),
          ),
        );
      }
    }

    return doc.save();
  }

  static pw.Widget _buildSingleLabelContent({
    required BarcodeLabelItem item,
    required String storeName,
    required bool showStoreName,
    required bool showPrice,
    required bool showColorAndSize,
    required bool isSheet,
    bool showProductName = true,
    bool showBarcodeText = true,
  }) {
    final priceStr = '${Money(item.salePricePiasters).toDisplay()} ج.م';
    final colorSizeStr = '${item.color} - مقاس ${item.size}';

    return pw.Container(
      decoration: isSheet
          ? pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            )
          : null,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (showStoreName && storeName.isNotEmpty) ...[
            pw.Text(
              storeName,
              style: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
              maxLines: 1,
            ),
            pw.SizedBox(height: 1),
          ],
          if (showProductName) ...[
            pw.Text(
              item.productName,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
            ),
          ],
          if (showColorAndSize && (item.color.isNotEmpty || item.size.isNotEmpty)) ...[
            pw.Text(
              colorSizeStr,
              style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
              maxLines: 1,
            ),
          ],
          pw.SizedBox(height: 2),
          // Barcode (Code128)
          pw.Expanded(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: item.sku.isNotEmpty ? item.sku : '000000000000',
              drawText: showBarcodeText,
              textStyle: const pw.TextStyle(fontSize: 6.5),
            ),
          ),
          if (showPrice) ...[
            pw.SizedBox(height: 1),
            pw.Text(
              priceStr,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Future<void> printLabels({
    required List<BarcodeLabelItem> items,
    required BarcodeLabelSize size,
    String storeName = 'أوركيد للملابس',
    bool showStoreName = true,
    bool showPrice = true,
    bool showColorAndSize = true,
    bool showProductName = true,
    bool showBarcodeText = true,
  }) async {
    final pdfBytes = await generatePdf(
      items: items,
      size: size,
      storeName: storeName,
      showStoreName: showStoreName,
      showPrice: showPrice,
      showColorAndSize: showColorAndSize,
      showProductName: showProductName,
      showBarcodeText: showBarcodeText,
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdfBytes,
      name: 'barcode_labels_${DateTime.now().millisecondsSinceEpoch}',
    );
  }
}

