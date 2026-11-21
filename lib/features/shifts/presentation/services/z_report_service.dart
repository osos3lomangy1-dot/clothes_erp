import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_branding.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/shift_summary_entity.dart';

class ZReportService {
  static Future<pw.Font> _loadArabicFont() async {
    try {
      final localFont = File('assets/fonts/static/Cairo-Regular.ttf');
      if (await localFont.exists()) {
        final bytes = await localFont.readAsBytes();
        return pw.Font.ttf(bytes.buffer.asByteData());
      }
    } catch (_) {}

    try {
      final winArial = File('C:\\Windows\\Fonts\\arial.ttf');
      if (await winArial.exists()) {
        final bytes = await winArial.readAsBytes();
        return pw.Font.ttf(bytes.buffer.asByteData());
      }
    } catch (_) {}

    return pw.Font.helvetica();
  }

  static Future<pw.Font> _loadArabicBoldFont() async {
    try {
      final localFont = File('assets/fonts/static/Cairo-Bold.ttf');
      if (await localFont.exists()) {
        final bytes = await localFont.readAsBytes();
        return pw.Font.ttf(bytes.buffer.asByteData());
      }
    } catch (_) {}

    try {
      final winArialBd = File('C:\\Windows\\Fonts\\arialbd.ttf');
      if (await winArialBd.exists()) {
        final bytes = await winArialBd.readAsBytes();
        return pw.Font.ttf(bytes.buffer.asByteData());
      }
    } catch (_) {}

    return pw.Font.helveticaBold();
  }

  /// Generates a thermal roll 80mm ESC/POS PDF for the Z-Report.
  static Future<Uint8List> generateThermalPdf(ShiftSummaryEntity summary) async {
    final doc = pw.Document();
    final font = await _loadArabicFont();
    final boldFont = await _loadArabicBoldFont();
    final storeName = AppBranding.current.appName;
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    const roll80 = PdfPageFormat(
      80 * PdfPageFormat.mm,
      double.infinity,
      marginAll: 4 * PdfPageFormat.mm,
    );

    final shift = summary.shift;
    final counted = shift.countedBalance ?? summary.expectedCashInDrawer;
    final diff = shift.difference ?? (counted - summary.expectedCashInDrawer);

    String diffStatusText;
    if (diff == 0) {
      diffStatusText = 'مطابق تماماً (0.00 ج.م)';
    } else if (diff > 0) {
      diffStatusText = '+${Money(diff).toDisplay()} ج.م (زيادة)';
    } else {
      diffStatusText = '${Money(diff).toDisplay()} ج.م (عجز)';
    }

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
                pw.Text(
                  storeName,
                  style: pw.TextStyle(font: boldFont, fontSize: 16, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'تقرير إغلاق الوردية (Z-Report)',
                  style: pw.TextStyle(font: boldFont, fontSize: 13, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 1),

                // Shift Metadata
                _pdfKeyValue('رقم الوردية:', '#${shift.id.length > 8 ? shift.id.substring(0, 8) : shift.id}'),
                _pdfKeyValue('الكاشير:', shift.cashierName.isNotEmpty ? shift.cashierName : shift.cashierId),
                _pdfKeyValue('وقت الفتح:', dateFormat.format(shift.openedAt)),
                _pdfKeyValue('وقت الإغلاق:', dateFormat.format(shift.closedAt ?? DateTime.now())),
                pw.Divider(thickness: 0.5),

                // Sales Section
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('ملخص المبيعات:', style: pw.TextStyle(font: boldFont, fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ),
                pw.SizedBox(height: 3),
                _pdfKeyValue('مبيعات كاش:', '${Money(summary.cashSales).toDisplay()} ج.م'),
                _pdfKeyValue('مبيعات فيزا:', '${Money(summary.cardSales).toDisplay()} ج.م'),
                if (summary.otherSales > 0)
                  _pdfKeyValue('مبيعات أخرى / مجزأة:', '${Money(summary.otherSales).toDisplay()} ج.م'),
                _pdfKeyValue('إجمالي المبيعات:', '${Money(summary.totalRevenue).toDisplay()} ج.م', isBold: true),
                _pdfKeyValue('عدد الفواتير المنفذة:', '${summary.totalSalesCount} فاتورة'),
                pw.Divider(thickness: 0.5),

                // Cash Drawer Flow Section
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('حركات درج النقدية (الكاش):', style: pw.TextStyle(font: boldFont, fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ),
                pw.SizedBox(height: 3),
                _pdfKeyValue('الرصيد الافتتاحي (الفكة):', '${Money(shift.openingBalance).toDisplay()} ج.م'),
                _pdfKeyValue('إجمالي المقبوضات النقدية:', '+${Money(summary.cashSales + summary.cashInstallments).toDisplay()} ج.م'),
                _pdfKeyValue('مرتجعات نقدية:', '-${Money(summary.cashReturns).toDisplay()} ج.م'),
                _pdfKeyValue('مصروفات نقدية:', '-${Money(summary.cashExpenses).toDisplay()} ج.م'),
                pw.Divider(thickness: 1),

                // Reconciliation Section
                _pdfKeyValue('المتوقع في الدرج:', '${Money(summary.expectedCashInDrawer).toDisplay()} ج.م', isBold: true),
                _pdfKeyValue('الفعلي المعدود:', '${Money(counted).toDisplay()} ج.م', isBold: true),
                _pdfKeyValue('الفارق (العجز/الزيادة):', diffStatusText, isBold: true),
                pw.SizedBox(height: 8),

                // Signatures
                pw.Divider(thickness: 0.5),
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('توقيع الكاشير:\n\n.....................', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
                    pw.Text('توقيع المستلم:\n\n.....................', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'تم استخراج التقرير بواسطة Bay3ah ERP',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  /// Generates a standard A4 format PDF for archiving and accounting.
  static Future<Uint8List> generateA4Pdf(ShiftSummaryEntity summary) async {
    final doc = pw.Document();
    final font = await _loadArabicFont();
    final boldFont = await _loadArabicBoldFont();
    final storeName = AppBranding.current.appName;
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    final shift = summary.shift;
    final counted = shift.countedBalance ?? summary.expectedCashInDrawer;
    final diff = shift.difference ?? (counted - summary.expectedCashInDrawer);

    String diffStatusText;
    if (diff == 0) {
      diffStatusText = 'مطابق تماماً (0.00 ج.م)';
    } else if (diff > 0) {
      diffStatusText = '+${Money(diff).toDisplay()} ج.م (زيادة)';
    } else {
      diffStatusText = '${Money(diff).toDisplay()} ج.م (عجز)';
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Header
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(storeName, style: pw.TextStyle(font: boldFont, fontSize: 20, fontWeight: pw.FontWeight.bold)),
                        pw.Text('تقرير الإغلاق المالي للوردية (Z-Report)', style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('رقم الوردية: #${shift.id.length > 8 ? shift.id.substring(0, 8) : shift.id}', style: pw.TextStyle(font: boldFont, fontSize: 12)),
                        pw.Text('تاريخ التقرير: ${dateFormat.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 1.5, height: 24),

                // Shift Details Box
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                    color: PdfColors.grey50,
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('الكاشير المسؤول: ${shift.cashierName.isNotEmpty ? shift.cashierName : shift.cashierId}', style: const pw.TextStyle(fontSize: 11)),
                      pw.Text('وقت الفتح: ${dateFormat.format(shift.openedAt)}', style: const pw.TextStyle(fontSize: 11)),
                      pw.Text('وقت الإغلاق: ${dateFormat.format(shift.closedAt ?? DateTime.now())}', style: const pw.TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),

                // Financial Breakdown Table
                pw.Text('1. بيان المبيعات التشغيلية:', style: pw.TextStyle(font: boldFont, fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  headerStyle: pw.TextStyle(font: boldFont, fontSize: 10, fontWeight: pw.FontWeight.bold),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  cellAlignment: pw.Alignment.centerRight,
                  headers: ['البند', 'القيمة بالجنيه'],
                  data: [
                    ['مبيعات النقدية (كاش)', '${Money(summary.cashSales).toDisplay()} ج.م'],
                    ['مبيعات البطاقات (فيزا / إلكتروني)', '${Money(summary.cardSales).toDisplay()} ج.م'],
                    if (summary.otherSales > 0) ['مبيعات مجزأة / أخرى', '${Money(summary.otherSales).toDisplay()} ج.م'],
                    ['إجمالي الإيرادات الإجمالية', '${Money(summary.totalRevenue).toDisplay()} ج.م'],
                    ['إجمالي عدد الفواتير المنفذة', '${summary.totalSalesCount} فاتورة'],
                  ],
                ),
                pw.SizedBox(height: 20),

                // Cash Flow Table
                pw.Text('2. بيان حركة الدرج والمطابقة المالية (Cash Reconciliation):', style: pw.TextStyle(font: boldFont, fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  headerStyle: pw.TextStyle(font: boldFont, fontSize: 10, fontWeight: pw.FontWeight.bold),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  cellAlignment: pw.Alignment.centerRight,
                  headers: ['بيان حركة الخزينة', 'القيمة بالجنيه'],
                  data: [
                    ['الرصيد الافتتاحي للدرج (عهدة الفكة)', '${Money(shift.openingBalance).toDisplay()} ج.م'],
                    ['المقبوضات النقدية (مبيعات + أقساط كاش)', '+${Money(summary.cashSales + summary.cashInstallments).toDisplay()} ج.م'],
                    ['المرتجعات النقدية للمبيعات', '-${Money(summary.cashReturns).toDisplay()} ج.م'],
                    ['المصروفات النثرية وسلف الموظفين', '-${Money(summary.cashExpenses).toDisplay()} ج.م'],
                    ['المبلغ المتوقع في الدرج', '${Money(summary.expectedCashInDrawer).toDisplay()} ج.م'],
                    ['المبلغ الفعلي الموجود في الدرج (المعدود)', '${Money(counted).toDisplay()} ج.م'],
                    ['الفارق المحاسبي (العجز / الزيادة)', diffStatusText],
                  ],
                ),
                pw.Spacer(),

                // Signatures
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      children: [
                        pw.Text('توقيع الكاشير المسلم:', style: const pw.TextStyle(fontSize: 11)),
                        pw.SizedBox(height: 35),
                        pw.Text('_______________________', style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Text('توقيع الإدارة المستلمة:', style: const pw.TextStyle(fontSize: 11)),
                        pw.SizedBox(height: 35),
                        pw.Text('_______________________', style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Center(
                  child: pw.Text('Bay3ah ERP — نظام إدارة المتاجر ونقاط البيع المتكامل', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                ),
              ],
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  /// Prints the thermal slip directly to default/chosen printer.
  static Future<void> printThermalSlip(ShiftSummaryEntity summary) async {
    final bytes = await generateThermalPdf(summary);
    await Printing.layoutPdf(
      name: 'Z_Report_Shift_${summary.shift.id.length > 8 ? summary.shift.id.substring(0, 8) : summary.shift.id}',
      onLayout: (PdfPageFormat format) async => bytes,
    );
  }

  /// Prints or exports the A4 PDF report.
  static Future<void> printA4Report(ShiftSummaryEntity summary) async {
    final bytes = await generateA4Pdf(summary);
    await Printing.layoutPdf(
      name: 'Z_Report_A4_${summary.shift.id.length > 8 ? summary.shift.id.substring(0, 8) : summary.shift.id}',
      onLayout: (PdfPageFormat format) async => bytes,
    );
  }

  /// Generates pre-formatted Arabic WhatsApp summary text.
  static String generateWhatsAppText(ShiftSummaryEntity summary) {
    final storeName = AppBranding.current.appName;
    final shift = summary.shift;
    final dateFormat = DateFormat('yyyy/MM/dd hh:mm a');
    final counted = shift.countedBalance ?? summary.expectedCashInDrawer;
    final diff = shift.difference ?? (counted - summary.expectedCashInDrawer);

    String diffStatusText = 'مطابق تماماً 100%';
    if (diff > 0) {
      diffStatusText = '+${Money(diff).toDisplay()} ج.م (زيادة)';
    } else if (diff < 0) {
      diffStatusText = '${Money(diff).toDisplay()} ج.م (عجز)';
    }

    return '''
*تقرير إغلاق الوردية (Z-Report) — بيعة ERP*
*المتجر:* $storeName
*الكاشير:* ${shift.cashierName.isNotEmpty ? shift.cashierName : shift.cashierId}
*رقم الوردية:* #${shift.id.length > 8 ? shift.id.substring(0, 8) : shift.id}
*الفترة:* من ${dateFormat.format(shift.openedAt)} إلى ${dateFormat.format(shift.closedAt ?? DateTime.now())}
─────────────────
*مبيعات كاش:* ${Money(summary.cashSales).toDisplay()} ج.م
*مبيعات فيزا:* ${Money(summary.cardSales).toDisplay()} ج.م
${summary.otherSales > 0 ? "*مبيعات مجزأة:* ${Money(summary.otherSales).toDisplay()} ج.م\n" : ""}*إجمالي الإيرادات:* ${Money(summary.totalRevenue).toDisplay()} ج.م
*عدد الفواتير:* ${summary.totalSalesCount} فاتورة
─────────────────
*رصيد الفكة الافتتاحي:* ${Money(shift.openingBalance).toDisplay()} ج.م
*مصروفات نقدية:* -${Money(summary.cashExpenses).toDisplay()} ج.م
*مرتجعات نقدية:* -${Money(summary.cashReturns).toDisplay()} ج.م
─────────────────
*المتوقع في الدرج:* ${Money(summary.expectedCashInDrawer).toDisplay()} ج.م
*الفعلي المعدود:* ${Money(counted).toDisplay()} ج.م
*حالة الدرج:* $diffStatusText
''';
  }

  /// Opens WhatsApp web or desktop application with the pre-formatted Z-report summary.
  static Future<bool> shareViaWhatsApp(ShiftSummaryEntity summary, {String? phoneNumber}) async {
    final text = generateWhatsAppText(summary);
    final cleanPhone = phoneNumber?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    final encodedText = Uri.encodeComponent(text);
    
    // Construct WhatsApp URI
    final String urlStr = cleanPhone.isNotEmpty
        ? 'https://wa.me/$cleanPhone?text=$encodedText'
        : 'https://wa.me/?text=$encodedText';

    final uri = Uri.parse(urlStr);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static pw.Widget _pdfKeyValue(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: isBold ? 9.5 : 8.5, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value, style: pw.TextStyle(fontSize: isBold ? 9.5 : 8.5, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }
}

