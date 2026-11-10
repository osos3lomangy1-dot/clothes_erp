import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/invoice_details_entity.dart';

class ReceiptPdfService {
  static Future<pw.Font> _loadArabicFont() async {
    // 1. Try Windows system font (instant offline fallback)
    try {
      final winArial = File('C:\\Windows\\Fonts\\arial.ttf');
      if (await winArial.exists()) {
        final bytes = await winArial.readAsBytes();
        return pw.Font.ttf(bytes.buffer.asByteData());
      }
    } catch (_) {}

    // 2. Try Google Fonts Cairo
    try {
      return await PdfGoogleFonts.cairoRegular();
    } catch (_) {
      return pw.Font.helvetica();
    }
  }

  static Future<pw.Font> _loadArabicBoldFont() async {
    try {
      final winArialBd = File('C:\\Windows\\Fonts\\arialbd.ttf');
      if (await winArialBd.exists()) {
        final bytes = await winArialBd.readAsBytes();
        return pw.Font.ttf(bytes.buffer.asByteData());
      }
    } catch (_) {}

    try {
      return await PdfGoogleFonts.cairoBold();
    } catch (_) {
      return pw.Font.helveticaBold();
    }
  }

  static Future<Uint8List> generateReceiptPdf(
    InvoiceDetailsEntity invoice, {
    String storeName = 'محل أوركيد للملابس',
    String storePhone = '01000000000',
    String storeAddress = 'القاهرة - مصر',
    String returnPolicy = 'الاستبدال والاسترجاع خلال 14 يوماً بالفاتورة وأصل التكت',
  }) async {
    final doc = pw.Document();
    final font = await _loadArabicFont();
    final boldFont = await _loadArabicBoldFont();

    const roll80 = PdfPageFormat(
      80 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 4 * PdfPageFormat.mm,
    );

    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    doc.addPage(
      pw.Page(
        pageFormat: roll80,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                // Store Header
                pw.Text(
                  storeName,
                  style: pw.TextStyle(font: boldFont, fontSize: 16, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'أحدث صيحات الملابس الجاهزة',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  textAlign: pw.TextAlign.center,
                ),
                if (storeAddress.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    storeAddress,
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                if (storePhone.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'هاتف: $storePhone',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                    textAlign: pw.TextAlign.center,
                  ),
                ],

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 6),

                // Invoice Meta
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('رقم الفاتورة:', style: pw.TextStyle(fontSize: 9, font: boldFont)),
                    pw.Text('#${invoice.shortRef}', style: pw.TextStyle(fontSize: 10, font: boldFont)),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('التاريخ:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(dateFormat.format(invoice.date), style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('الكاشير:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(invoice.cashierName.isNotEmpty ? invoice.cashierName : invoice.cashierId, style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                if (invoice.customerName != null && invoice.customerName!.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('العميل:', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text(invoice.customerName!, style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ],
                pw.SizedBox(height: 3),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('طريقة الدفع:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(invoice.paymentMethod, style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 6),

                // Table Header
                pw.Row(
                  children: [
                    pw.Expanded(flex: 5, child: pw.Text('الصنف', style: pw.TextStyle(font: boldFont, fontSize: 8))),
                    pw.Expanded(flex: 2, child: pw.Text('ك', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: boldFont, fontSize: 8))),
                    pw.Expanded(flex: 3, child: pw.Text('السعر', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: boldFont, fontSize: 8))),
                    pw.Expanded(flex: 3, child: pw.Text('الإجمالي', textAlign: pw.TextAlign.left, style: pw.TextStyle(font: boldFont, fontSize: 8))),
                  ],
                ),
                pw.SizedBox(height: 4),
                _dottedLine(),
                pw.SizedBox(height: 4),

                // Items Rows
                ...invoice.items.map((it) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          '${it.productName} (${it.color} - ${it.size})',
                          style: pw.TextStyle(fontSize: 8, font: boldFont),
                        ),
                        pw.Row(
                          children: [
                            pw.Expanded(flex: 5, child: pw.SizedBox()),
                            pw.Expanded(flex: 2, child: pw.Text('${it.qty}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8))),
                            pw.Expanded(flex: 3, child: pw.Text('${Money(it.price).toDisplay()}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8))),
                            pw.Expanded(flex: 3, child: pw.Text('${Money(it.lineTotal).toDisplay()}', textAlign: pw.TextAlign.left, style: const pw.TextStyle(fontSize: 8))),
                          ],
                        ),
                      ],
                    ),
                  );
                }),

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 6),

                // Financial Summary
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('المجموع الفرعي:', style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('${Money(invoice.subtotal).toDisplay()} ج.م', style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
                if (invoice.discountAmount > 0) ...[
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('خصم:', style: const pw.TextStyle(fontSize: 9, color: PdfColors.red700)),
                      pw.Text('-${Money(invoice.discountAmount).toDisplay()} ج.م', style: const pw.TextStyle(fontSize: 9, color: PdfColors.red700)),
                    ],
                  ),
                ],
                pw.SizedBox(height: 4),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('الإجمالي المطلوب:', style: pw.TextStyle(font: boldFont, fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text('${Money(invoice.total).toDisplay()} ج.م', style: pw.TextStyle(font: boldFont, fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),

                pw.SizedBox(height: 10),

                // Barcode of invoice shortRef
                pw.Container(
                  height: 35,
                  child: pw.BarcodeWidget(
                    data: invoice.shortRef,
                    barcode: pw.Barcode.code128(),
                    drawText: false,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(invoice.shortRef, style: const pw.TextStyle(fontSize: 7)),

                pw.SizedBox(height: 8),
                _dashedLine(),
                pw.SizedBox(height: 6),

                // Footer Policy & Greeting
                pw.Text(
                  returnPolicy,
                  style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'شكراً لزيارتكم ونتمنى لكم يوماً سعيداً',
                  style: pw.TextStyle(font: boldFont, fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _dashedLine() {
    return pw.Text(
      '------------------------------------------------',
      style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
      maxLines: 1,
    );
  }

  static pw.Widget _dottedLine() {
    return pw.Text(
      '- - - - - - - - - - - - - - - - - - - - - - - - -',
      style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey400),
      maxLines: 1,
    );
  }

  /// Direct print to physical printer or Windows print dialog
  static Future<void> printReceipt(InvoiceDetailsEntity invoice) async {
    final pdfBytes = await generateReceiptPdf(invoice);
    await Printing.layoutPdf(
      name: 'فاتورة_${invoice.shortRef}',
      onLayout: (PdfPageFormat format) async => pdfBytes,
    );
  }

  /// Save invoice as a PDF file to user-chosen location
  static Future<String?> saveReceiptAsPdf(InvoiceDetailsEntity invoice) async {
    final pdfBytes = await generateReceiptPdf(invoice);

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'تنزيل الفاتورة كملف PDF',
      fileName: 'فاتورة_${invoice.shortRef}.pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (savePath != null) {
      final finalPath = savePath.toLowerCase().endsWith('.pdf') ? savePath : '$savePath.pdf';
      final file = File(finalPath);
      await file.writeAsBytes(pdfBytes);
      return file.path;
    }
    return null;
  }
}

