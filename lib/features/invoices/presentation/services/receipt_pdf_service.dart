import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../../core/theme/app_branding.dart';
import '../../../../core/utils/money.dart';
import '../../../customers/domain/entities/customer_entity.dart';
import '../../../installments/domain/entities/customer_installment_entity.dart';
import '../../../installments/domain/entities/installment_schedule_entry.dart';
import '../../data/services/receipt_settings_service.dart';
import '../../domain/entities/invoice_details_entity.dart';
import '../../domain/entities/receipt_config.dart';

class ReceiptPdfService {
  static Future<pw.Font> _loadArabicFont() async {
    // 1. Try local project asset Cairo (works 100% offline everywhere: Windows, Linux CI, macOS)
    try {
      final localFont = File('assets/fonts/static/Cairo-Regular.ttf');
      if (await localFont.exists()) {
        final bytes = await localFont.readAsBytes();
        return pw.Font.ttf(bytes.buffer.asByteData());
      }
    } catch (_) {}

    // 2. Try Windows system font (instant offline fallback)
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
    // 1. Try local project asset Cairo Bold
    try {
      final localFont = File('assets/fonts/static/Cairo-Bold.ttf');
      if (await localFont.exists()) {
        final bytes = await localFont.readAsBytes();
        return pw.Font.ttf(bytes.buffer.asByteData());
      }
    } catch (_) {}

    // 2. Try Windows system font
    try {
      final winArialBd = File('C:\\Windows\\Fonts\\arialbd.ttf');
      if (await winArialBd.exists()) {
        final bytes = await winArialBd.readAsBytes();
        return pw.Font.ttf(bytes.buffer.asByteData());
      }
    } catch (_) {}

    return pw.Font.helveticaBold();
  }

  static Future<Uint8List> generateReceiptPdf(
    InvoiceDetailsEntity invoice, {
    ReceiptConfig? config,
    String? storeName,
    String? storePhone,
    String? storeAddress,
    String? returnPolicy,
  }) async {
    final cfg = config ?? ReceiptSettingsService.current;
    final effectiveStoreName =
        storeName ??
        (cfg.storeName.isNotEmpty
            ? cfg.storeName
            : AppBranding.current.appName);
    final effectiveStorePhone = storePhone ?? cfg.storePhone;
    final effectiveStoreAddress = storeAddress ?? cfg.storeAddress;
    final effectiveReturnPolicy = returnPolicy ?? cfg.returnPolicy;
    final effectiveFooterGreeting = cfg.footerGreeting;

    final doc = pw.Document();
    final font = await _loadArabicFont();
    final boldFont = await _loadArabicBoldFont();

    final rollFormat = PdfPageFormat(
      (cfg.paperWidthMm == 58 ? 58 : 80) * PdfPageFormat.mm,
      double.infinity,
      marginAll: (cfg.paperWidthMm == 58 ? 2 : 4) * PdfPageFormat.mm,
    );

    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    doc.addPage(
      pw.Page(
        pageFormat: rollFormat,
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
                  effectiveStoreName,
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                if (cfg.storeActivity.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    cfg.storeActivity,
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                if (effectiveStoreAddress.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    effectiveStoreAddress,
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                if (effectiveStorePhone.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'هاتف: $effectiveStorePhone',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                if (cfg.storePhoneSecondary.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'هاتف إضافي: ${cfg.storePhoneSecondary}',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                if (cfg.taxNumber.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'س.ت / ضريبي: ${cfg.taxNumber}',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
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
                    pw.Text(
                      'رقم الفاتورة:',
                      style: pw.TextStyle(fontSize: 9, font: boldFont),
                    ),
                    pw.Text(
                      '#${invoice.shortRef}',
                      style: pw.TextStyle(fontSize: 10, font: boldFont),
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('التاريخ:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(
                      dateFormat.format(invoice.date),
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
                if (cfg.showCashierName) ...[
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'الكاشير:',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                      pw.Text(
                        invoice.cashierName.isNotEmpty
                            ? invoice.cashierName
                            : invoice.cashierId,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ],
                if (cfg.showCustomerInfo &&
                    invoice.customerName != null &&
                    invoice.customerName!.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'العميل:',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                      pw.Text(
                        invoice.customerName!,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ],
                if (cfg.showPaymentMethod) ...[
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'طريقة الدفع:',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                      pw.Text(
                        invoice.paymentMethod,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ],

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 6),

                // Table Header
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 5,
                      child: pw.Text(
                        'الصنف',
                        style: pw.TextStyle(font: boldFont, fontSize: 8),
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(
                        'ك',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(font: boldFont, fontSize: 8),
                      ),
                    ),
                    pw.Expanded(
                      flex: 3,
                      child: pw.Text(
                        'السعر',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(font: boldFont, fontSize: 8),
                      ),
                    ),
                    pw.Expanded(
                      flex: 3,
                      child: pw.Text(
                        'الإجمالي',
                        textAlign: pw.TextAlign.left,
                        style: pw.TextStyle(font: boldFont, fontSize: 8),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                _dottedLine(),
                pw.SizedBox(height: 4),

                // Items Rows
                ...invoice.items.map((it) {
                  final itemLabel =
                      cfg.showItemDetails &&
                          (it.color.isNotEmpty || it.size.isNotEmpty)
                      ? '${it.productName} (${it.color} - ${it.size})'
                      : it.productName;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          itemLabel,
                          style: pw.TextStyle(fontSize: 8, font: boldFont),
                        ),
                        pw.Row(
                          children: [
                            pw.Expanded(flex: 5, child: pw.SizedBox()),
                            pw.Expanded(
                              flex: 2,
                              child: pw.Text(
                                '${it.qty}',
                                textAlign: pw.TextAlign.center,
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                            ),
                            pw.Expanded(
                              flex: 3,
                              child: pw.Text(
                                Money(it.price).toDisplay(),
                                textAlign: pw.TextAlign.center,
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                            ),
                            pw.Expanded(
                              flex: 3,
                              child: pw.Text(
                                Money(it.lineTotal).toDisplay(),
                                textAlign: pw.TextAlign.left,
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                            ),
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
                    pw.Text(
                      'المجموع الفرعي:',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      '${Money(invoice.subtotal).toDisplay()} ج.م',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
                if (invoice.totalPromotionDiscount > 0) ...[
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'خصم العروض:',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.green700,
                        ),
                      ),
                      pw.Text(
                        '-${Money(invoice.totalPromotionDiscount).toDisplay()} ج.م',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.green700,
                        ),
                      ),
                    ],
                  ),
                ],
                if (invoice.discountAmount > 0) ...[
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'خصم:',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.red700,
                        ),
                      ),
                      pw.Text(
                        '-${Money(invoice.discountAmount).toDisplay()} ج.م',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.red700,
                        ),
                      ),
                    ],
                  ),
                ],
                pw.SizedBox(height: 4),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'الإجمالي المطلوب:',
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        '${Money(invoice.total).toDisplay()} ج.م',
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                if (cfg.showBarcode) ...[
                  pw.SizedBox(height: 10),
                  pw.Container(
                    height: 35,
                    child: pw.BarcodeWidget(
                      data: invoice.shortRef,
                      barcode: pw.Barcode.code128(),
                      drawText: false,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    invoice.shortRef,
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                ],

                pw.SizedBox(height: 8),
                _dashedLine(),
                pw.SizedBox(height: 6),

                // Footer Policy & Greeting
                if (effectiveReturnPolicy.isNotEmpty) ...[
                  pw.Text(
                    effectiveReturnPolicy,
                    style: const pw.TextStyle(
                      fontSize: 7,
                      color: PdfColors.grey700,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 4),
                ],
                if (effectiveFooterGreeting.isNotEmpty) ...[
                  pw.Text(
                    effectiveFooterGreeting,
                    style: pw.TextStyle(font: boldFont, fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 8),
                ],
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
      final finalPath = savePath.toLowerCase().endsWith('.pdf')
          ? savePath
          : '$savePath.pdf';
      final file = File(finalPath);
      await file.writeAsBytes(pdfBytes);
      return file.path;
    }
    return null;
  }

  /// Generate complete Installment Contract & Schedule PDF (80mm thermal roll)
  static Future<Uint8List> generateInstallmentContractPdf({
    required InvoiceDetailsEntity invoice,
    required CustomerInstallmentEntity contract,
    required List<InstallmentScheduleEntry> schedule,
    CustomerEntity? customer,
    ReceiptConfig? config,
    String? storeName,
    String? storePhone,
    String? storeAddress,
    String? returnPolicy,
  }) async {
    final cfg = config ?? ReceiptSettingsService.current;
    final effectiveStoreName = storeName ??
        (cfg.storeName.isNotEmpty ? cfg.storeName : AppBranding.current.appName);
    final effectiveStorePhone = storePhone ?? cfg.storePhone;
    final effectiveStoreAddress = storeAddress ?? cfg.storeAddress;
    final effectiveReturnPolicy = returnPolicy ?? cfg.returnPolicy;
    final effectiveFooterGreeting = cfg.footerGreeting;

    final doc = pw.Document();
    final font = await _loadArabicFont();
    final boldFont = await _loadArabicBoldFont();

    final rollFormat = PdfPageFormat(
      (cfg.paperWidthMm == 58 ? 58 : 80) * PdfPageFormat.mm,
      double.infinity,
      marginAll: (cfg.paperWidthMm == 58 ? 2 : 4) * PdfPageFormat.mm,
    );

    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    final shortContractId = contract.id.length >= 8
        ? contract.id.substring(0, 8).toUpperCase()
        : contract.id.toUpperCase();

    final totalFinancedWithInterest =
        contract.monthlyAmountPiasters * contract.durationMonths;
    final totalClientObligation =
        totalFinancedWithInterest + contract.downPaymentPiasters;
    final totalInterestPiasters =
        (totalFinancedWithInterest - contract.principalPiasters).clamp(0, 999999999);

    doc.addPage(
      pw.Page(
        pageFormat: rollFormat,
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
                  effectiveStoreName,
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                if (cfg.storeActivity.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    cfg.storeActivity,
                    style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                if (effectiveStoreAddress.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    effectiveStoreAddress,
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
                if (effectiveStorePhone.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'هاتف: $effectiveStorePhone',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                    textAlign: pw.TextAlign.center,
                  ),
                ],

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 4),

                // Contract & Invoice Title Banner
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  child: pw.Text(
                    'فاتورة وعقد بيع بالتقسيط',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 4),

                // Metadata Rows
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('رقم الفاتورة:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('#${invoice.shortRef}', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('رقم عقد التقسيط:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('#$shortContractId', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('التاريخ والوقت:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(dateFormat.format(invoice.date), style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('الكاشير / المحرر:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(
                      invoice.cashierName.isNotEmpty ? invoice.cashierName : invoice.cashierId,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),

                // Customer Info
                pw.SizedBox(height: 4),
                _dottedLine(),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('العميل / المدين:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(
                      customer?.name ?? invoice.customerName ?? 'عميل مسجل',
                      style: pw.TextStyle(font: boldFont, fontSize: 8),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('رقم الهاتف:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(
                      customer?.phone ?? invoice.customerPhone ?? '-',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 4),

                // Items Table Header
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 5,
                      child: pw.Text('الصنف', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text('ك', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: boldFont, fontSize: 8)),
                    ),
                    pw.Expanded(
                      flex: 3,
                      child: pw.Text('السعر', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: boldFont, fontSize: 8)),
                    ),
                    pw.Expanded(
                      flex: 3,
                      child: pw.Text('الإجمالي', textAlign: pw.TextAlign.left, style: pw.TextStyle(font: boldFont, fontSize: 8)),
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                _dottedLine(),
                pw.SizedBox(height: 3),

                // Items List
                ...invoice.items.map((it) {
                  final itemLabel = (it.color.isNotEmpty || it.size.isNotEmpty)
                      ? '${it.productName} (${it.color} - ${it.size})'
                      : it.productName;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          flex: 5,
                          child: pw.Text(itemLabel, style: pw.TextStyle(fontSize: 8, font: boldFont)),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text('${it.qty}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8)),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(Money(it.price).toDisplay(), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8)),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(Money(it.lineTotal).toDisplay(), textAlign: pw.TextAlign.left, style: const pw.TextStyle(fontSize: 8)),
                        ),
                      ],
                    ),
                  );
                }),

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 4),

                // Installment Financial Statement Box
                pw.Container(
                  padding: const pw.EdgeInsets.all(5),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'البيان المالي للتقسيط',
                        style: pw.TextStyle(font: boldFont, fontSize: 9, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('إجمالي المشتريات (أصل الفاتورة):', style: const pw.TextStyle(fontSize: 8)),
                          pw.Text('${Money(invoice.total).toDisplay()} ج.م', style: const pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('الدفعة المقدمة (المسددة نقداً):', style: const pw.TextStyle(fontSize: 8)),
                          pw.Text('${Money(contract.downPaymentPiasters).toDisplay()} ج.م', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('المبلغ الممول (أصل الدين):', style: const pw.TextStyle(fontSize: 8)),
                          pw.Text('${Money(contract.principalPiasters).toDisplay()} ج.م', style: const pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('نسبة الفائدة المقررة:', style: const pw.TextStyle(fontSize: 8)),
                          pw.Text('${contract.interestBp / 100}%', style: const pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                      if (totalInterestPiasters > 0) ...[
                        pw.SizedBox(height: 2),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('إجمالي الفائدة المحسوبة:', style: const pw.TextStyle(fontSize: 8)),
                            pw.Text('${Money(totalInterestPiasters).toDisplay()} ج.م', style: const pw.TextStyle(fontSize: 8)),
                          ],
                        ),
                      ],
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('مدة التقسيط:', style: const pw.TextStyle(fontSize: 8)),
                          pw.Text('${contract.durationMonths} شهراً', style: const pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('قيمة القسط الشهري:', style: pw.TextStyle(font: boldFont, fontSize: 8.5)),
                          pw.Text(
                            '${Money(contract.monthlyAmountPiasters).toDisplay()} ج.م / شهر',
                            style: pw.TextStyle(font: boldFont, fontSize: 9),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 3),
                      _dottedLine(),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('إجمالي التزام العميل (مقدم + أقساط):', style: pw.TextStyle(font: boldFont, fontSize: 8.5)),
                          pw.Text(
                            '${Money(totalClientObligation).toDisplay()} ج.م',
                            style: pw.TextStyle(font: boldFont, fontSize: 9.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Schedule Table (جدول استحقاق الأقساط)
                if (schedule.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  _dashedLine(),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'جدول استحقاق الأقساط الشهرية',
                    style: pw.TextStyle(font: boldFont, fontSize: 9),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text('م', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: boldFont, fontSize: 7.5)),
                      ),
                      pw.Expanded(
                        flex: 5,
                        child: pw.Text('تاريخ الاستحقاق', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: boldFont, fontSize: 7.5)),
                      ),
                      pw.Expanded(
                        flex: 4,
                        child: pw.Text('المبلغ', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: boldFont, fontSize: 7.5)),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text('الحالة', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: boldFont, fontSize: 7.5)),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  _dottedLine(),
                  ...schedule.map((entry) {
                    final dueStr = DateFormat('yyyy/MM/dd').format(entry.dueDate);
                    return pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text('${entry.installmentNumber}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7.5)),
                          ),
                          pw.Expanded(
                            flex: 5,
                            child: pw.Text(dueStr, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7.5)),
                          ),
                          pw.Expanded(
                            flex: 4,
                            child: pw.Text(Money(entry.amountPiasters).toDisplay(), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7.5)),
                          ),
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text('مستحق', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7)),
                          ),
                        ],
                      ),
                    );
                  }),
                ],

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 4),

                // Customer Legal Acknowledgment & Commitment
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Center(
                        child: pw.Text(
                          'إقرار استلام السلع وتعهد بالسداد',
                          style: pw.TextStyle(font: boldFont, fontSize: 8.5),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'أقر أنا الموقع أدناه باستلام السلع الموضحة أعلاه بحالة جيدة وسليمة ومطابقة للمواصفات، وأتعهد بالتزامي الكامل بسداد الأقساط الشهرية الموضحة في جدول الاستحقاق في مواعيدها دون أي تأخير، ويُعد هذا الإيصال سندا تنفيذيا وقانونيا ملزما.',
                        style: const pw.TextStyle(fontSize: 7, height: 1.3),
                        textAlign: pw.TextAlign.justify,
                      ),
                      pw.SizedBox(height: 8),
                      pw.Row(
                        children: [
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('اسم العميل: _____________________', style: const pw.TextStyle(fontSize: 7)),
                                pw.SizedBox(height: 4),
                                pw.Text('الرقم القومي: ___________________', style: const pw.TextStyle(fontSize: 7)),
                              ],
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('التوقيع: _______________________', style: const pw.TextStyle(fontSize: 7)),
                                pw.SizedBox(height: 4),
                                pw.Text('البصمة: [                     ]', style: const pw.TextStyle(fontSize: 7)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 6),
                _dashedLine(),
                pw.SizedBox(height: 4),

                // Footer Return Policy & Greeting
                if (effectiveReturnPolicy.isNotEmpty) ...[
                  pw.Text(
                    effectiveReturnPolicy,
                    style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 3),
                ],
                if (effectiveFooterGreeting.isNotEmpty) ...[
                  pw.Text(
                    effectiveFooterGreeting,
                    style: pw.TextStyle(font: boldFont, fontSize: 7.5),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 6),
                ],
              ],
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  /// Print installment contract & payment schedule to thermal printer
  static Future<void> printInstallmentContractReceipt({
    required InvoiceDetailsEntity invoice,
    required CustomerInstallmentEntity contract,
    required List<InstallmentScheduleEntry> schedule,
    CustomerEntity? customer,
  }) async {
    final pdfBytes = await generateInstallmentContractPdf(
      invoice: invoice,
      contract: contract,
      schedule: schedule,
      customer: customer,
    );
    await Printing.layoutPdf(
      name: 'عقد_تقسيط_${invoice.shortRef}',
      onLayout: (PdfPageFormat format) async => pdfBytes,
    );
  }

  /// Save installment contract & payment schedule as PDF
  static Future<String?> saveInstallmentContractReceiptAsPdf({
    required InvoiceDetailsEntity invoice,
    required CustomerInstallmentEntity contract,
    required List<InstallmentScheduleEntry> schedule,
    CustomerEntity? customer,
  }) async {
    final pdfBytes = await generateInstallmentContractPdf(
      invoice: invoice,
      contract: contract,
      schedule: schedule,
      customer: customer,
    );

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'تنزيل عقد التقسيط كملف PDF',
      fileName: 'عقد_تقسيط_${invoice.shortRef}.pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (savePath != null) {
      final finalPath = savePath.toLowerCase().endsWith('.pdf')
          ? savePath
          : '$savePath.pdf';
      final file = File(finalPath);
      await file.writeAsBytes(pdfBytes);
      return file.path;
    }
    return null;
  }
}
